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

### Rust 相对于 Python 项目的依赖优点

- **编译时依赖检查**：Rust 在编译时进行严格的依赖检查，可以提前发现潜在的依赖冲突和版本不兼容问题，而 Python 项目在运行时才进行依赖检查，可能导致运行时错误。
- **依赖管理工具**：Rust 使用 Cargo 进行依赖管理，Cargo 提供了强大的依赖解析和版本管理功能，可以自动处理依赖关系，而 Python 项目通常需要手动管理依赖或使用 pip 工具。
- **系统依赖**：Rust 项目在编译时会静态链接所需的库，减少了对系统库的依赖，而 Python 项目可能需要安装额外的系统库（如 libgirepository）才能正常运行。

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