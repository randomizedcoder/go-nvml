{
  pkgs,
  src,
  goNvmlPkg,
}:

let
  goPkg = pkgs.go_1_26 or pkgs.go;

  goEnv = ''
    export HOME=$TMPDIR
    export CGO_ENABLED=1
    export GOCACHE=$TMPDIR/go-cache
    export GOLANGCI_LINT_CACHE=$TMPDIR/golangci-cache
    mkdir -p "$GOCACHE" "$GOLANGCI_LINT_CACHE"
  '';

  withVendor = ''
    cp -r $src go-nvml-src
    chmod -R u+w go-nvml-src
    cd go-nvml-src
    cp -r --no-preserve=mode,ownership ${goNvmlPkg.goModules}/ vendor
  '';

  mkGolangciCheck =
    { name, config }:
    pkgs.runCommand "go-nvml-${name}"
      {
        nativeBuildInputs = [
          goPkg
          pkgs.golangci-lint
          pkgs.cacert
          pkgs.gcc
        ];
        inherit src;
      }
      ''
        ${withVendor}
        ${goEnv}
        export GOFLAGS="-mod=vendor"
        golangci-lint run --config ${config} --timeout 30m ./...
        touch $out
      '';

  go-vet =
    pkgs.runCommand "go-nvml-go-vet"
      {
        nativeBuildInputs = [
          goPkg
          pkgs.cacert
          pkgs.gcc
        ];
        inherit src;
      }
      ''
        ${withVendor}
        ${goEnv}
        export GOFLAGS="-mod=vendor"
        go vet -v ./...
        touch $out
      '';

  staticcheck =
    pkgs.runCommand "go-nvml-staticcheck"
      {
        nativeBuildInputs = [
          goPkg
          pkgs.go-tools
          pkgs.cacert
          pkgs.gcc
        ];
        inherit src;
      }
      ''
        ${withVendor}
        ${goEnv}
        export GOFLAGS="-mod=vendor"
        staticcheck ./...
        touch $out
      '';

  # govulncheck needs network access (vuln.go.dev). Ship as an app, not a
  # check. Source mode (./...) — go-nvml is a library, no binary to scan.
  # Run with: nix run .#govulncheck-go-nvml
  govulncheck-app = pkgs.writeShellApplication {
    name = "govulncheck-go-nvml";
    runtimeInputs = [
      goPkg
      pkgs.govulncheck
      pkgs.cacert
      pkgs.gcc
    ];
    text = ''
      set -e
      tmp=$(mktemp -d)
      cp -r ${src}/. "$tmp/"
      chmod -R u+w "$tmp"
      cp -r --no-preserve=mode,ownership ${goNvmlPkg.goModules}/ "$tmp/vendor"
      cd "$tmp"
      export CGO_ENABLED=1
      export GOFLAGS="-mod=vendor"
      echo "=== govulncheck (source mode) against go-nvml ==="
      exec govulncheck ./...
    '';
  };

  # gosec exclusions match nebula's baseline; tune per findings.
  gosec =
    pkgs.runCommand "go-nvml-gosec"
      {
        nativeBuildInputs = [
          goPkg
          pkgs.gosec
          pkgs.cacert
          pkgs.gcc
        ];
        inherit src;
      }
      ''
        ${withVendor}
        ${goEnv}
        export GOFLAGS="-mod=vendor"
        gosec -exclude=G101,G115,G204,G304,G306,G401,G501 -quiet \
          -exclude-generated ./...
        touch $out
      '';

  nix-fmt =
    pkgs.runCommand "go-nvml-nix-fmt"
      {
        nativeBuildInputs = [
          pkgs.nixfmt
          pkgs.findutils
        ];
        inherit src;
      }
      ''
        cp -r $src go-nvml-src
        cd go-nvml-src
        find . -type f -name '*.nix' | xargs nixfmt --check
        touch $out
      '';

  statix =
    pkgs.runCommand "go-nvml-statix"
      {
        nativeBuildInputs = [ pkgs.statix ];
        inherit src;
      }
      ''
        cp -r $src go-nvml-src
        cd go-nvml-src
        statix check .
        touch $out
      '';

  deadnix =
    pkgs.runCommand "go-nvml-deadnix"
      {
        nativeBuildInputs = [ pkgs.deadnix ];
        inherit src;
      }
      ''
        cp -r $src go-nvml-src
        cd go-nvml-src
        deadnix --fail nix/ flake.nix
        touch $out
      '';

in
{
  golangci-lint-quick = mkGolangciCheck {
    name = "golangci-lint-quick";
    config = ./golangci/golangci-quick.yml;
  };

  golangci-lint = mkGolangciCheck {
    name = "golangci-lint";
    config = ./golangci/golangci.yml;
  };

  golangci-lint-comprehensive = mkGolangciCheck {
    name = "golangci-lint-comprehensive";
    config = ./golangci/golangci-comprehensive.yml;
  };

  inherit
    go-vet
    staticcheck
    gosec
    ;
  inherit
    nix-fmt
    statix
    deadnix
    ;
}
// {
  # not exported under `checks` (network-impure); see flake.nix.
  inherit govulncheck-app;
}
