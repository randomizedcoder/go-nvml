{
  lib,
  src,
  constants,
  buildGoModule,
}:

buildGoModule {
  pname = "go-nvml";
  version = constants.goNvml.version;
  inherit src;

  vendorHash = "sha256-U5ap/6tNdeaQkxp5etapDONYd1527tla8vDLoDoWsWM=";

  env.CGO_ENABLED = "1";

  ldflags = constants.goNvml.ldflags;

  doCheck = false;

  meta = with lib; {
    description = "Go bindings for NVIDIA Management Library (NVML)";
    homepage = "https://github.com/NVIDIA/go-nvml";
    license = licenses.asl20;
  };
}
