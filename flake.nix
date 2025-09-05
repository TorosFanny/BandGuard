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
  in
  {
    packages = forAllSystems (system:
    let
      pkgs = pkgsFor system;
    in
    {
      default = pkgs.rustPlatform.buildRustPackage {
        pname = "notify";
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
        
        meta = with pkgs.lib; {
          description = "A Rust application that monitors bandwidth and sends notifications";
          homepage = "https://github.com/user/notify";
          license = licenses.mit;
          mainProgram = "notify";
        };
      };
    });
    
    devShells = forAllSystems (system:
    let
      pkgs = pkgsFor system;
    in
    {
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
  };
}
