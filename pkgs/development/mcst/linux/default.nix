{
  stdenv,
  bootstrapStdenv,
  buildLinux,
  fetchurl,
  makeLinuxHeaders,
}:

let
  version = "6.1.0";
  src = fetchurl {
    url = "https://dev.mcst.ru/downloads/2026-09-30/linux-6.1.0-1.19-open.tgz";
    hash = "sha256-p47xdhBfDRITn99FLZIHio7cMrJcLWK2k1dRfrDiVT0=";
  };
in
  {
    linux = buildLinux {
      inherit stdenv version src;
      modDirVersion = version;
      defconfig = "mcst_release";
      enableCommonConfig = false;
      ignoreConfigErrors = true;
    };
    linux-headers = makeLinuxHeaders {
      inherit src version;
    };
  }
