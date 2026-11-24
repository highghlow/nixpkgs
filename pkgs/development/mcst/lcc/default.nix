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
  symlinkJoin,
  cmake,
  runtimeShell,
  python3,
}:

assert stdenv.targetPlatform.system == "e2k-linux";
let
  # The source of proprietary components. Open-source
  # components have their owns sources. This is used for:
  # - LCC compiler and libraries
  # - The dynalic linker
  # - Glibc (only for bootstrapping)
  src = fetchurl {
    url = "https://dev.mcst.ru/downloads/2026-09-09/cross/cross-sp-public-osl-1.31.05.e2k-v6.linux-6.1_64.tgz";
    hash = "sha256-FA26rkJH0htyQhli56fXoO5mUUUkvQKSkP7XOS9EwdQ=";
    downloadToTemp = true;
    recursiveHash = true;
    postFetch = ''
      mkdir -p $out
      tar -xzf $downloadedFile -C $out --strip-components=1
    '';
  };

  # This derivation contains the lcc and all proprietary
  # libraries distributed with it. The open-source libs
  # are built from source in separate derivations
  lcc-unwrapped-nolib = stdenv.mkDerivation {
    pname = "mcst-lcc-nolib";
    version = "1.31.05";
    inherit src;

    installPhase = ''
      mkdir -p $out/include
      mkdir -p $out/lib
      mkdir -p $out/bin2
      mkdir -p $out/bin
      base=$(echo -n mcst/*)
      lcc_home=$(echo -n $base/lcc-home/*/*)

      cp $base/bin/* $out/bin

      # LCC intrinsic headers (like limits.h)
      cp -rL $base/lcc-home/*/*/include/* $out/include

      cp -rL $lcc_home/lib64/*.a $out/lib
      cp -rL $lcc_home/lib64/*.o $out/lib
      # .so files in this directory are actually absolute
      # symlinks, which are broken in nix
      cp -rL $base/fs/usr/lib64/*.so $out/lib
      # This is actually a linker script pointing to /lib64
      rm $out/lib/libc.so

      # Required utilities of the compiler (but not bintools)
      cp $lcc_home/bin/* $out/bin2
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
          --append-flags "--sysroot=${libc}" \
          --append-flags "-B ${bintools}/bin/e2k-unknown-linux-gnu-" \
          --append-flags "-B $out/bin2/" \
          --append-flags "-B $out/lib/" \
          --append-flags "-I$out/include" \
          --append-flags "-L$out/lib"
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

  lcc-unwrapped-vendor-glibc = symlinkJoin {
    name = "mcst-lcc";
    paths = [ lcc-unwrapped-nolib ];
    nativeBuildInputs = [ makeWrapper ];
    postBuild = ''
      mkdir $out/include2

      # The vendored version of glibc is required for
      # configure to work when building lcc-libs.
      # Hovewer, we only need the headers.
      cp -rL ${src}/mcst/*/fs/usr/include/* $out/include2

      for prog in $out/bin/{lcc,cpp,l++,lfortran}; do
        wrapProgram $prog \
          --append-flags "-I$out/include2"
      done
    '';
  };

  lcc-libs = stdenv.mkDerivation {
    pname = "mcst-lcc-libs";
    version = "1.29.16";

    src = fetchurl {
      url = "https://dev.mcst.ru/downloads/2026-05-27/lcc-libs-1.29.16.tar.gz";
      hash = "sha256-XDUD96dHC7T64iQKrxC6A7sLVpNTbNSoH+q1UGgq3eg=";
    };

    patches = [
      ./lcc-libs-add-cpp.patch
    ];

    nativeBuildInputs = [
      cmake
      python3
    ];

    dontUseCmakeConfigure = true;
    dontUseCmakeBuild = true;
    dontUseCmakeInstall = true;
    CMAKE_POLICY_VERSION_MINIMUM = "3.5";

    buildPhase = let
      args =
         "INSTALL_DIR_LIB=$out/lib "
       + "INSTALL_DIR_INCLUDE=$out/include "
       + "LCC=${lcc-unwrapped-vendor-glibc}/bin/lcc "
       + "LXX=${lcc-unwrapped-vendor-glibc}/bin/l++ "
       + "CPP=${lcc-unwrapped-vendor-glibc}/bin/cpp "
       + ''CFLAGS="-Wno-bad-macro-redef" CXXFLAGS="-Wno-bad-macro-redef"'';
    in /* bash */ ''
      # To add always-present options to the compiler passed
      # to CMake, the script generates a small wrapper script.
      # This script has a bash shebang

      substituteInPlace lib/compiler_rt-11.1.0/build.sh \
        --replace-fail "/bin/bash" "${runtimeShell}"

      mkdir -p $out/lib
      bash lib/compiler_rt-11.1.0/build.sh ${args}
      bash lib/GNU/build_libgcc.sh STAGE=1 ${args}
      bash lib/GNU/build_libgcc.sh STAGE=2 ${args}
      bash lib/GNU/build_libgcc.sh STAGE=3 ${args}
      #bash lib/GNU/build_libquadmath.sh ${args}
      #bash lib/GNU/build_libstdc++.sh ${args}
    '';
  };

  # Here we include lcc-libs, but it is still "unwrapped"
  # as it doesn't have the bintools or glibc
  lcc-unwrapped = symlinkJoin {
    name = "mcst-lcc";
    paths = [ lcc-unwrapped-nolib ];
    nativeBuildInputs = [ makeWrapper ];
    postBuild = ''
      for prog in $out/bin/{lcc,cpp,l++,lfortran}; do
        wrapProgram $prog \
          --add-flags "-L${lcc-libs}/lib/" \
          --add-flags "-I${lcc-libs}/include/"
      done
    '';
    passthru = {
      hardeningUnsupportedFlags = lcc-unwrapped-nolib.hardeningUnsupportedFlags;
    };
  };

  bintools-unwrapped = stdenv.mkDerivation {
    pname = "mcst-lcc-bintools";
    version = "2.41-29.024";
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
    version = "1.31.05";
    inherit src;

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
  /*lcc-libs*/
  wrapCCWith {
    inherit bintools libc;
    cc = lcc-unwrapped;
    nixSupport = {
      cc-cflags = [
        "-idirafter"
        "${libc}/include2"
      ];
    };
  }
