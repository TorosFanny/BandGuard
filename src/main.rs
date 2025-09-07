use anyhow::{Context, Result};
use clap::Parser;
use dbus::blocking::Connection;
use serde::Deserialize;
use std::process::Command;
use tokio::process::Command as TokioCommand;

/// BandGuard - 宽带速度监控工具
#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Args {
    /// 下载速度阈值 (Mbits/s)，低于此值时发送通知
    #[arg(short, long, value_name = "MBITS", required = true)]
    threshold: f64,

}

// Speedtest结果结构体
#[derive(Deserialize, Debug)]
struct SpeedTestResult {
    download: f64,
    upload: f64,
    ping: f64,
}

 // 执行speedtest-go命令并返回结果（通过 BANDGUARD_SPEEDTEST_ARGS 追加自定义参数）
async fn run_speed_test() -> Result<SpeedTestResult> {
    let mut cmd = TokioCommand::new("speedtest-go");

    // 通过环境变量追加 speedtest-go 参数
    if let Ok(extra) = std::env::var("BANDGUARD_SPEEDTEST_ARGS") {
        if let Some(a) = shlex::split(&extra) {
            cmd.args(a);
        }
    }

    let output = cmd
        .arg("--json")
        .output()
        .await
        .context("Failed to execute speedtest-go command")?;

    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("speedtest-go command failed: {}", error);
    }

    let stdout_raw = String::from_utf8(output.stdout)?;
    let stderr_raw = String::from_utf8(output.stderr).unwrap_or_else(|_| String::new());

    // 从 stdout/stderr 中提取纯 JSON（某些实现会在 JSON 前后输出日志）
    fn extract_json_slice(s: &str) -> Option<&str> {
        if s.is_empty() {
            return None;
        }
        let bytes = s.as_bytes();
        let mut start = None;
        let mut end = None;
        for (i, &b) in bytes.iter().enumerate() {
            if start.is_none() && (b == b'{' || b == b'[') {
                start = Some(i);
                break;
            }
        }
        if let Some(s0) = start {
            for (i, &b) in bytes.iter().enumerate().rev() {
                if b == b'}' || b == b']' {
                    end = Some(i);
                    break;
                }
            }
            if let Some(e0) = end {
                if e0 >= s0 {
                    return Some(&s[s0..=e0]);
                }
            }
        }
        None
    }

    let json_str = extract_json_slice(&stdout_raw)
        .or_else(|| extract_json_slice(&stderr_raw))
        .ok_or_else(|| anyhow::anyhow!("No JSON found in speedtest-go output"))?;

    // 仅解析 speedtest-go 的 JSON 结构
    let v: serde_json::Value = serde_json::from_str(json_str)
        .with_context(|| format!("Failed to parse JSON. stdout: {}, stderr: {}", stdout_raw, stderr_raw))?;

    let mut download_bps: Option<f64> = None;
    let mut upload_bps: Option<f64> = None;
    let mut ping_ms: Option<f64> = None;

    // 仅解析 speedtest-go 风格：{"servers":[{...,"dl_speed": bytes/s, "ul_speed": bytes/s, "latency": ns,...}]}
    if let Some(servers) = v.get("servers").and_then(|x| x.as_array()) {
        if let Some(best) = servers.iter().max_by(|a, b| {
            let ad = a.get("dl_speed").and_then(|x| x.as_f64()).unwrap_or(0.0);
            let bd = b.get("dl_speed").and_then(|x| x.as_f64()).unwrap_or(0.0);
            ad.partial_cmp(&bd).unwrap_or(std::cmp::Ordering::Equal)
        }) {
            download_bps = best.get("dl_speed").and_then(|x| x.as_f64()).map(|v| v * 8.0);
            upload_bps = best.get("ul_speed").and_then(|x| x.as_f64()).map(|v| v * 8.0);
            ping_ms = best.get("latency").and_then(|x| x.as_f64()).map(|v| v / 1_000_000.0);
        }
    }

    let (download_bps, upload_bps, ping_ms) = match (download_bps, upload_bps, ping_ms) {
        (Some(d), Some(u), Some(p)) => (d, u, p),
        _ => anyhow::bail!("Unrecognized JSON output from speedtest-go: {}", json_str),
    };

    // 转换为 Mbit/s
    Ok(SpeedTestResult {
        download: download_bps / 1_000_000.0,
        upload: upload_bps / 1_000_000.0,
        ping: ping_ms,
    })
}

// 通过DBus发送GNOME通知
fn send_notification(title: &str, body: &str) -> Result<()> {
    // 连接到session bus
    let conn = Connection::new_session()
        .context("Failed to connect to DBus session")?;

    // 创建通知代理
    let proxy = conn.with_proxy(
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        std::time::Duration::from_secs(5),
    );

    // 发送通知
    let _: () = proxy.method_call(
        "org.freedesktop.Notifications",
        "Notify",
        (
            "BandGuard", // 应用名称
            0u32, // 替换ID (0表示新通知)
            "", // 图标 (留空)
            title, // 标题
            body, // 正文
            Vec::<String>::new(), // 动作列表
            std::collections::HashMap::<String, dbus::arg::Variant<Box<dyn dbus::arg::RefArg>>>::new(), // 提示
            -1i32, // 超时时间 (毫秒, -1表示默认)
        ),
    )
    .context("Failed to send notification")?;

    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args = Args::parse();

    println!("Running speed test...");

    // 检查speedtest-go是否已安装
    let check = Command::new("which").arg("speedtest-go").output()?;
    if !check.status.success() {
        eprintln!("Error: speedtest-go is not installed.");
        eprintln!("Please install it, e.g.: nix profile install nixpkgs#speedtest-go");
        std::process::exit(1);
    }
    
    let result = run_speed_test().await?;
    println!("Download speed: {:.2} Mbits/s", result.download);
    println!("Upload speed: {:.2} Mbits/s", result.upload);
    println!("Ping: {:.2} ms", result.ping);

    // 如果下载速度低于阈值，发送通知
    if result.download < args.threshold {
        send_notification(
            "宽带下载速度低于阈值",
            &format!("下载速度: {:.2} Mbits/s (阈值: {:.0} Mbits/s)\n上传速度: {:.2} Mbits/s\nPing: {:.2} ms", result.download, args.threshold, result.upload, result.ping),
        )?;
        println!("Notification sent");
    }

    Ok(())
}
