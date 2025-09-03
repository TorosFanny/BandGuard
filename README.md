# 宽带测速通知工具

这是一个使用Rust编写的宽带测速工具，当下载速度低于300Mbits/s时，会通过D-Bus向GNOME桌面发送通知。

## 功能

- 使用speedtest-cli进行标准的网络速度测试
- 测试下载速度、上传速度和Ping延迟
- 当下载速度低于阈值（300Mbits/s）时，自动发送桌面通知

## 依赖

- Rust 1.5+ 和 Cargo
- `speedtest-cli` Python包
- GNOME桌面环境（用于发送通知）

## 安装

1. 安装Rust和Cargo（如果尚未安装）：
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. 安装speedtest-cli：
   ```bash
   pip install speedtest-cli
   ```

3. 克隆项目并构建：
   ```bash
   git clone <项目地址>
   cd notify
   cargo build --release
   ```

## 使用方法

运行程序：
```bash
./target/release/notify
```

或者直接使用Cargo运行：
```bash
cargo run
```

## 配置

如果需要修改速度阈值，可以编辑`src/main.rs`文件中的`main`函数，修改`if result.download < 300.0`这一行中的300.0为其他值。

## 许可证

MIT