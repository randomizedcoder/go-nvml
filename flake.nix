{
  description = "go-nvml - Go bindings for NVIDIA Management Library (modular nix flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        packagesAttrs = import ./nix/packages {
          inherit pkgs lib;
          src = ./.;
        };

        checksAttrs = import ./nix/checks.nix {
          inherit pkgs;
          src = ./.;
          goNvmlPkg = packagesAttrs.go-nvml;
        };

        appsAttrs = import ./nix/apps {
          inherit lib;
          checks = checksAttrs;
        };
      in
      {
        packages = packagesAttrs // {
          default = packagesAttrs.go-nvml;
        };

        apps = appsAttrs;

        checks = lib.filterAttrs (n: _: n != "govulncheck-app") checksAttrs;

        devShells.default = import ./nix/shell.nix { inherit pkgs; };
      }
    );
}
