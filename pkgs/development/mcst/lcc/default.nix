{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapCCWith,
  wrapBintoolsWith,
  runtimeShell,
  buildPackages,
  xz,
  bzip2,
  libgcc,
  xxhash,
  zlib,
  ncurses,
  libuuid,
  libffi,
  sqlite,
  gdbm,
  readline,
  flex,
  gcc,
  libxcrypt-legacy,
  breakpointHook
}:

assert stdenv.targetPlatform.system == "e2kv6-linux";
let
  version = "1.31.05";
  # TODO: native
  src = fetchurl {
    url = "https://dev.mcst.ru/downloads/2026-09-09/cross/cross-sp-public-osl-1.31.05.e2k-v6.linux-6.1_64.tgz";
    hash = "sha256-vRg10c20Kn6Ga0E2B3qbxJR/8qTYlX8yp2x6SnrPasg=";
  };
  cc = stdenv.mkDerivation {
    pname = "mcst-lcc";
    inherit version src;

    installPhase = ''
      cp -r mcst/* $out
    '';

    nativeBuildInputs = [
      makeWrapper
      autoPatchelfHook
    ];

    buildInputs = [
    # gcc.cc.lib
    # xz
    # bzip2
    # libgcc
    # xxhash
    # ncurses
    # zlib
    # libuuid
    # libffi
    # sqlite
    # gdbm
    # readline
    # flex
    # libxcrypt-legacy
    ];

    preFixup = ''
      rm -rf $out/gdb
      rm -rf $out/binutils
      rm -rf $out/bin.toolchain
    '';

    postFixup = ''
      for prog in $out/bin/{lcc,cpp,l++,lfortran}; do
        wrapProgram $prog \
          --add-flags "-B $(echo -n $out/lcc-home/*/*/bin/)" \
          --add-flags "-B $(echo -n $out/lcc-home/*/*/lib64/)" \
          --add-flags "-B ${bintools}/bin/e2kv6-unknown-linux-gnu-" \
          --add-flags "-B $out/fs/usr/lib64/"
      done
    '';

    passthru = {
      hardeningUnsupportedFlags = [
        "zerocallusedregs"
        "strictflexarrays1"
        # Add any other flags lcc doesn't support here later, e.g.:
        # "stackclashprotection"
        # "shadowcallstack"
      ];
    };

    meta.mainProgram = "lcc";
  };
  bintools-fhs = buildPackages.buildFHSEnv {
    name = "mcst-lcc-bintools-fhs";

    targetPkgs = p: [
      libc
    ];

    extraBuildCommands = ''
      rm -rf $out/{,usr/}lib64
      ln -sf ${libc}/lib $out/lib64
      ln -sf ${libc}/lib $out/usr/lib64
    '';

    runScript = "";
  };
  bintools-unwrapped = stdenv.mkDerivation {
    pname = "mcst-lcc-bintools";
    inherit version src;

    installPhase = ''
      cp -r mcst/*/binutils $out
      cp -r mcst/*/fs $out
    '';

    nativeBuildInputs = [
      makeWrapper
      autoPatchelfHook
    ];

    buildInputs = [
      flex
    ];

    postFixup = ''
      rm -rf $out/e2k-linux/bin

      for f in "$out/bin/e2k-linux-"*; do
        base=$(basename "$f")
        f2="$out/bin/e2kv6-unknown-linux-gnu-''${base#e2k-linux-}"
        f2_unwrapped="$out/bin/.e2kv6-unknown-linux-gnu-''${base#e2k-linux-}"
        mv "$f" "$f2_unwrapped"
        cat > "$f2" <<EOF
#!${runtimeShell}
exec ${lib.getExe bintools-fhs} "$f2_unwrapped" "\$@"
EOF
        chmod +x "$f2"
      done
    '';
  };
  libc = stdenv.mkDerivation {
    pname = "mcst-lcc-libc";
    inherit version src;
    nativeBuildInputs = [
      breakpointHook
    ];

    installPhase = ''
      mkdir $out
      cp -rL mcst/*/fs/lib64 $out/lib
      cp -rL mcst/*/fs/usr/lib64/* $out/lib
      ln -s $out/lib/libgcc_s.so.1 $out/lib/libgcc_s.so
      cp -rL mcst/*/lcc-home/*/*/include $out/include
      cp -rL mcst/*/fs/usr/include $out/include2
    '';
  };

  bintools = wrapBintoolsWith {
    inherit libc;
    bintools = bintools-unwrapped;
  };
in
  wrapCCWith {
    inherit cc bintools;
    nixSupport = {
      cc-cflags = [
        "-idirafter"
        "${libc}/include2"
      ];
    };
  }
