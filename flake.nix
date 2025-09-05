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
        ];
        
        buildInputs = [
          pkgs.dbus
        ];
        
        # Add runtime dependencies
        propagatedBuildInputs = [
          pkgs.python3Packages.speedtest-cli
        ];

        postInstall = ''
          install -Dm644 ${./systemd/user/bandguard.service} $out/share/systemd/user/bandguard.service
          install -Dm644 ${./systemd/user/bandguard.timer} $out/share/systemd/user/bandguard.timer
          substituteInPlace $out/share/systemd/user/bandguard.service \
            --replace @bandguard_bin@ "$out/bin/bandguard"
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
          pkgs.python3Packages.speedtest-cli
        ];
      };
    });

    nixosModules.bandguard = { lib, pkgs, config, ... }:
    let
      inherit (lib) mkOption mkEnableOption types mkIf genAttrs;
      cfg = config.services.bandguard;
      pkg = cfg.package or self.packages.${pkgs.system}.default;
    in {
      options.services.bandguard = {
        enable = mkEnableOption "bandguard user timer";
        users = mkOption {
          type = types.listOf types.str;
          default = [];
              description = "Users to enable the bandguard user timer for (linger will be enabled).";
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
        package = mkOption {
          type = types.package;
          default = self.packages.${pkgs.system}.default;
          description = "Package providing the bandguard binary.";
        };
      };
      config = mkIf cfg.enable {
        # Ensure specified users have the package and keep user systemd running even when not logged in
        users.users = genAttrs cfg.users (u: {
          packages = [ pkg ];
        });
        services.logind.lingerUsers = cfg.users;
        systemd.user.services.bandguard = {
          Unit = {
            Description = "BandGuard bandwidth monitor";
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkg}/bin/bandguard";
          } // (if cfg.lowPriority then {
            Nice = 19;
            IOSchedulingClass = "idle";
          } else { });
        };
        systemd.user.timers.bandguard = {
          Unit = {
            Description = "BandGuard bandwidth monitor (daily)";
          };
          Timer = {
            OnCalendar = cfg.onCalendar;
            RandomizedDelaySec = cfg.randomizedDelaySec;
            Persistent = true;
          };
          Install = {
            WantedBy = [ "timers.target" ];
          };
        };
      };
    };
  };
}
