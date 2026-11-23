{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapCCWith,
  wrapBintoolsWith,
  bison,
  flex,
  breakpointHook,
}:

assert stdenv.targetPlatform.system == "e2k-linux";
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

    preFixup = ''
      rm -rf $out/gdb
      rm -rf $out/binutils
      rm -rf $out/bin.toolchain
      rm -rf $out/fs
    '';

    postFixup = ''
      for prog in $out/bin/{lcc,cpp,l++,lfortran}; do
        wrapProgram $prog \
          --add-flags "--sysroot=${libc}" \
          --add-flags "-B $(echo -n $out/lcc-home/*/*/bin/)" \
          --add-flags "-B $(echo -n $out/lcc-home/*/*/lib64/)" \
          --add-flags "-B ${bintools}/bin/e2k-unknown-linux-gnu-"
      done
    '';

    passthru = {
      hardeningUnsupportedFlags = [
        "zerocallusedregs"
        "strictflexarrays1"
      ];
    };

    meta.mainProgram = "lcc";
  };
  bintools-unwrapped = stdenv.mkDerivation {
    pname = "mcst-lcc-bintools";
    version = "2.41";
    src = fetchurl {
      url = "https://dev.mcst.ru/downloads/2026-11-03/binutils-2.41-29.024.tar.gz";
      hash = "sha256-cXoDlxoAjTzQj4YWXCK7QbYf3oGf0VyA1E/yK7mdFhQ=";
    };

    nativeBuildInputs = [
      makeWrapper
    ];

    buildInputs = [
      flex
      bison
    ];

    configureFlags = [
      "--disable-gprofng"
      "--target=e2k-mcst-linux-gnu"
    ];

    hardeningDisable = [ "format" ];

    env = {
      NIX_CFLAGS_COMPILE = "-std=gnu17";
    };

    postFixup = ''
      for ld in $out/bin/e2k-mcst-linux-gnu-ld{,.bfd}; do
        wrapProgram "$ld" --add-flags "--sysroot=${libc}"
      done

      for f in "$out/bin/e2k-mcst-linux-"*; do
        base=$(basename "$f")
        f2="$out/bin/e2k-unknown-''${base#e2k-mcst-}"
        ln -s $f $f2
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
      mkdir -p $out/lib $out/usr
      cp -rL mcst/*/fs/lib64/* $out/lib/
      cp -rL mcst/*/fs/usr/lib64/* $out/lib/
      ln -s $out/lib/libgcc_s.so.1 $out/lib/libgcc_s.so

      ln -s $out/lib $out/lib64
      ln -s $out/lib $out/usr/lib64

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
