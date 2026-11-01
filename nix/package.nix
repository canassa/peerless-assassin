{
  lib,
  stdenv,
  zig_0_17,
}:

stdenv.mkDerivation {
  pname = "peerless-assassin";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../build.zig
      ../build.zig.zon
      ../src
    ];
  };

  nativeBuildInputs = [ zig_0_17.hook ];

  meta = {
    description = "Drives the Thermalright Peerless Assassin cooler's segment display";
    homepage = "https://github.com/canassa/peerless-assassin";
    platforms = lib.platforms.linux;
    mainProgram = "peerless_assassin";
  };
}
