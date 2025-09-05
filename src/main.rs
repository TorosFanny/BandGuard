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

// 执行speedtest-cli命令并返回结果
async fn run_speed_test() -> Result<SpeedTestResult> {
    let output = TokioCommand::new("speedtest-cli")
        .arg("--json")
        .output()
        .await
        .context("Failed to execute speedtest-cli command")?;

    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("speedtest-cli command failed: {}", error);
    }

    let stdout = String::from_utf8(output.stdout)?;
    let result: SpeedTestResult = serde_json::from_str(&stdout)?;
    
    // speedtest-cli返回的下载/上传速度单位是bit/s，转换为Mbit/s
    Ok(SpeedTestResult {
        download: result.download / 1_000_000.0,
        upload: result.upload / 1_000_000.0,
        ping: result.ping,
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

    // 检查speedtest-cli是否已安装
    let check = Command::new("which").arg("speedtest-cli").output()?;
    if !check.status.success() {
        eprintln!("Error: speedtest-cli is not installed.");
        eprintln!("Please install it using: pip install speedtest-cli");
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
