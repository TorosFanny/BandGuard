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

### 方法一：使用Nix Flake（推荐）

如果你使用Nix包管理器，可以直接使用flake构建项目：

1. 确保已安装Nix并启用flakes功能
2. 克隆项目：
   ```bash
   git clone <项目地址>
   cd notify
   ```

3. 使用Nix构建：
   ```bash
   nix build path:.
   ```

4. 运行程序：
   ```bash
   ./result/bin/notify
   ```

   或者直接运行（无需先构建）：
   ```bash
   nix run path:.
   ```

### 方法二：传统Rust构建

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

### 使用Nix构建的版本：
```bash
./result/bin/notify
```

### 使用Cargo构建的版本：
```bash
./target/release/notify
```

或者直接使用Cargo运行：
```bash
cargo run
```

## systemd 集成（用户级）

本项目在安装包中自带用户级 systemd 单元文件（随包安装到 $out/share/systemd/user）：
- notify.service：Type=oneshot，ExecStart 运行该程序，默认低优先级（Nice=19，IOSchedulingClass=idle）
- notify.timer：OnCalendar=daily，RandomizedDelaySec=1h，Persistent=true

方案 A：在系统 flake（NixOS）中声明式启用（推荐）
- 假设此项目作为 flake input（根据你的环境替换 URL）：
  ```nix
  # flake.nix (system)
  {
    inputs.notify.url = "path:/path/to/notify"; # 或者 git+https://... 等
    outputs = { self, nixpkgs, notify, ... }: {
      nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          notify.nixosModules.notify
          {
            services.notify = {
              enable = true;
              users = [ "qs" ];       # 需要启用的用户
              onCalendar = "daily";   # 也可用 "03:00" 等
              randomizedDelaySec = "1h";
              lowPriority = true;
            };
          }
        ];
      };
    };
  }
  ```
- 重建系统后，该用户的 notify.timer（用户级）将自动启用，并通过 services.logind.lingerUsers 让用户登出后也能运行。

方案 B：不使用模块，手动启用（用户级）
- 让系统或用户路径里有该包（例如 NixOS 上：`systemd.user.packages = [ inputs.notify.packages.${pkgs.system}.default ];`）
- 以目标用户执行：
  ```bash
  systemctl --user daemon-reload
  systemctl --user enable --now notify.timer
  # 确保登出后仍能运行（按需）：
  loginctl enable-linger <username>
  ```
- 查看状态与日志：
  ```bash
  systemctl --user status notify.timer
  journalctl --user -u notify.service
  ```

提示
- 若在本地直接运行 Nix 命令，建议使用 `path:.` 前缀（如 `nix build path:.`、`nix develop path:.`），以避免 `.` 触发 git+file 解析导致的 libgit2 兼容性问题。
- 进入目录后也可使用 direnv（`.envrc` 使用 `use flake path:.`）自动加载开发环境。

## 开发环境

### 使用Nix开发环境

进入包含所有必要依赖的开发环境：
```bash
nix develop path:.
```

这将提供：
- Rust编译器和Cargo
- pkg-config
- DBus开发库
- speedtest-cli

### 传统开发环境

确保系统已安装：
- Rust和Cargo
- pkg-config
- DBus开发库
- speedtest-cli

## 配置

如果需要修改速度阈值，可以编辑`src/main.rs`文件中的`main`函数，修改`if result.download < 300.0`这一行中的300.0为其他值。

## 许可证

MIT
