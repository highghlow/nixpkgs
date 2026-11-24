{
  lib,
  pkgs,
  config,
}:

lib.makeScope pkgs.newScope (
  self:
  let
    inherit (self) callPackage;

    bootstrapStdenv = pkgs.overrideCC pkgs.stdenv pkgs.mcst.lcc-bootstrap;

    glibc = callPackage ./glibc {
      stdenv = bootstrapStdenv;
    };
    linuxPackages = callPackage ./linux {
      inherit bootstrapStdenv;
    };
    lccPackages = callPackage ./lcc { };
  in
  {
    inherit glibc;
    inherit (linuxPackages) linux linux-headers;
    inherit (lccPackages) lcc-base bintools-unwrapped lcc-libs-bin
            bintools-bootstrap lcc-bootstrap
            lcc-libs lcc-unwrapped bintools
            lcc;
  }
)
