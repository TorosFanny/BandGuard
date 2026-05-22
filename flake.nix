{
  description = "A Rust project with dbus notifications";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    pkgsFor = system: import nixpkgs {
      inherit system;
    };
  in {
    packages = forAllSystems (system:
    let
      pkgs = pkgsFor system;
    in {
      default = pkgs.rustPlatform.buildRustPackage {
        pname = "bandguard";
        version = "0.1.0";
        src = pkgs.lib.cleanSource ./.;
        
        cargoLock = { lockFile = ./Cargo.lock; };
        
        nativeBuildInputs = [
          pkgs.pkg-config
          pkgs.makeWrapper
        ];
        
        buildInputs = [
          pkgs.dbus
        ];
        
        # Add runtime dependencies
        propagatedBuildInputs = [
          pkgs.speedtest-go
        ];

        postInstall = ''
          install -Dm644 ${./systemd/user/bandguard.service} $out/share/systemd/user/bandguard.service
          install -Dm644 ${./systemd/user/bandguard.timer} $out/share/systemd/user/bandguard.timer
          substituteInPlace $out/share/systemd/user/bandguard.service \
            --replace @bandguard_bin@ "$out/bin/bandguard"

          # Ensure runtime PATH in user systemd for required tools
          wrapProgram "$out/bin/bandguard" \
            --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.speedtest-go pkgs.which ]}
        '';

        meta = with pkgs.lib; {
          description = "A Rust application that monitors bandwidth and sends notifications";
          homepage = "https://github.com/TorosFanny/BandGuard";
          license = licenses.mit;
          mainProgram = "bandguard";
        };
      };
    });
    
    devShells = forAllSystems (system:
    let
      pkgs = pkgsFor system;
    in {
      default = pkgs.mkShell {
        buildInputs = [
          pkgs.rustc
          pkgs.cargo
          pkgs.pkg-config
          pkgs.dbus
          pkgs.speedtest-go
        ];
      };
    });

    apps = forAllSystems (system:
    let
      pkgs = pkgsFor system;
      pkg = self.packages.${system}.default;
    in {
      # 默认 app：提供可直接运行（带默认阈值）的包装器
      default = {
        type = "app";
        program = "${pkgs.writeShellScriptBin "bandguard-default" ''
          exec ${pkg}/bin/bandguard --threshold 200 "$@"
        ''}/bin/bandguard-default";
      };

      # 原始可执行（不注入默认参数），可用来自定义全部参数：
      # nix run .#bandguard -- --threshold 300 ...
      bandguard = {
        type = "app";
        program = "${pkg}/bin/bandguard";
      };
    });

    nixosModules.bandguard = { lib, pkgs, config, ... }:
    let
      inherit (lib) mkOption mkEnableOption types mkIf genAttrs;
      cfg = config.services.bandguard;
      pkg = cfg.package or self.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in {
      options.services.bandguard = {
        enable = mkEnableOption "bandguard user timer";
        users = mkOption {
          type = types.listOf types.str;
          default = [];
              description = "Users to enable the bandguard user timer for";
        };
        onCalendar = mkOption {
          type = types.str;
          default = "daily";
          description = "systemd OnCalendar expression.";
        };
        randomizedDelaySec = mkOption {
          type = types.str;
          default = "1h";
          description = "RandomizedDelaySec for the timer.";
        };
        lowPriority = mkOption {
          type = types.bool;
          default = true;
          description = "Run with Nice=19 and IOSchedulingClass=idle.";
        };
        threshold = mkOption {
          type = types.number;
          default = 200;
          description = "Required: download speed threshold in Mbits/s (passed as --threshold).";
        };
        speedtestArgs = mkOption {
          type = types.str;
          default = "";
          description = "Extra arguments for speedtest-go, will be exported via BANDGUARD_SPEEDTEST_ARGS.";
        };
        package = mkOption {
          type = types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          description = "Package providing the bandguard binary.";
        };
      };
      config = mkIf cfg.enable {
        # Ensure specified users have the package
        users.users = genAttrs cfg.users (u: {
          packages = [ pkg ];
        });
        systemd.user.services.bandguard = {
          description = "BandGuard bandwidth monitor";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkg}/bin/bandguard --threshold ${toString cfg.threshold}";
            Environment = "\"BANDGUARD_SPEEDTEST_ARGS=" + cfg.speedtestArgs + "\"";
          } // (if cfg.lowPriority then {
            Nice = 19;
            IOSchedulingClass = "idle";
          } else { });
        };
        systemd.user.timers.bandguard = {
          description = "BandGuard bandwidth monitor (daily)";
          timerConfig = {
            OnCalendar = cfg.onCalendar;
            RandomizedDelaySec = cfg.randomizedDelaySec;
            Persistent = true;
          };
          wantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
