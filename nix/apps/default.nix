{
  lib,
  checks ? null,
}:

let
  mkApp = drv: program: {
    type = "app";
    program = "${drv}/bin/${program}";
  };

  auditApps = lib.optionalAttrs (checks != null && checks ? govulncheck-app) {
    govulncheck-go-nvml = mkApp checks.govulncheck-app "govulncheck-go-nvml";
  };

in
auditApps
