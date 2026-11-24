{
  lib,
  pkgs,
  config,
}:

lib.makeScope pkgs.newScope (
  self:
  let
    inherit (self) callPackage;
  in
  {
    glibc = callPackage ./glibc { };
    lcc = callPackage ./lcc { };
  }
)
