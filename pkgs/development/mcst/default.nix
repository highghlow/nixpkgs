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
    lcc = callPackage ./lcc { };
  }
)
