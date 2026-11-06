{
  lib,
  rustPlatform,
  fetchurl,

  libzip,
  openssl,
  pkg-config,

  berryVersion,
  berryCacheVersion,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "yarn-berry-${toString berryVersion}-fetcher";
  version = "1.3.1";

  __structuredAttrs = true;

  src = fetchurl {
    url = "https://github.com/highghlow/m/raw/refs/heads/main/yarn-berry-fetcher-${finalAttrs.version}.tar.gz";
    hash = "sha256-aSeVPmEUen4v1tO5h60+MpyisiNrE/RGRxoeH4FtORw=";
  };

  cargoHash = "sha256-l8zTzr2y8i2ENb8iadIBz59YLmNwfDZcrbUqIUibFqg=";

  env.YARN_ZIP_SUPPORTED_CACHE_VERSION = berryCacheVersion;
  env.LIBZIP_SYS_USE_PKG_CONFIG = 1;

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  nativeBuildInputs = [
    rustPlatform.bindgenHook
    pkg-config
  ];
  buildInputs = [
    libzip
    openssl
  ];

  meta = {
    homepage = "https://cyberchaos.dev/yuka/yarn-berry-fetcher";
    license = lib.licenses.mit;
    mainProgram = "yarn-berry-fetcher";
    maintainers = with lib.maintainers; [
      flokli
    ];
  };
})
