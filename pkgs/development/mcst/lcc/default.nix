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
  targetPackages,
  mcst,
  buildPackages,
  breakpointHook
}:

# To make the compiler work you need some libraries (lcc-libs and glibc), but those
# need a compiler to compile. To solve this we use the precompiled libraries
# distributed with lcc.
#
# The compiler is built as follows:
# - lcc-base      -- Contains only the compiler itself and it's proprietary libraries
# - bintools-unwrapped
#                 -- The bintools, also built from MCST's sources. They don't need an
#                    Elbrus compiler, so can by compiled at this early stage. Hovewer,
#                    the ld utility needs it's sysroot to a library directory, and those
#                    do need lcc, and so two bintools exist: one with the precompiled
#                    libraries, and the other with ones built from source
# - lcc-libs-bin  -- All the precompiled libraries. This has more libraries than the
#                    `lcc-libs` derivation described below. This includes glibc
# - bintools-bootstrap
#                 -- bintools with the precompiled libraries
# - lcc-bootstrap
#                 -- A fully working compiler that uses the precompiled libraries
# - lcc-libs      -- compiler_rt and libgcc
# - lcc-unwrapped -- The compiler with the lcc-libs which were built from source. It
#                    doesn't include the libraries from lcc-bootstrap
# - mcst.glibc    -- glibc built from MCST's sources
# - bintools
#                 -- bintools with the libraries compiled from source
# - lcc           -- The final compiler with lcc, bintools and glibc

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
  lcc-base = stdenv.mkDerivation {
    pname = "mcst-lcc";
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

      # LCC intrinsic headers
      cp -rL $lcc_home/include/* $out/include
      cp -rL $base/fs/usr/include/asm $out/include

      cp -rL $lcc_home/lib64/*.a $out/lib
      cp -rL $lcc_home/lib64/*.o $out/lib
      # .so files in lcc-home are actually absolute
      # symlinks, which are broken in nix
      cp -rL $base/fs/usr/lib64/*.so $out/lib
      # This is actually a linker script pointing to /lib64.
      # This derivation doesn't have a real libc.
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

          #--append-flags "-B ${bintools}/bin/e2k-unknown-linux-gnu-" \
    postFixup = ''
      for prog in $out/bin/{lcc,cpp,l++,lfortran}; do
        wrapProgram $prog \
          --append-flags "-B $out/bin2/" \
          --append-flags "-B $out/lib/" \
          --add-flags "-isystem $out/include" \
          --add-flags "-L$out/lib"
      done
    '';

    passthru = {
      hardeningUnsupportedFlags = [
        "zerocallusedregs"
        "strictflexarrays1"
      ];
      targetPrefix = "e2k-unknown-linux-gnu-";
    };

    meta.mainProgram = "lcc";
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

      #for ld in $out/bin/e2k-mcst-linux-gnu-ld{,.bfd}; do
      #  wrapProgram "$ld" --add-flags "--sysroot=${libc}"
      #done
    postFixup = ''
      for f in "$out/bin/e2k-mcst-linux-"*; do
        base=$(basename "$f")
        f2="$out/bin/e2k-unknown-''${base#e2k-mcst-}"
        ln -s $f $f2
      done
    '';
  };

  lcc-libs-bin = stdenv.mkDerivation {
    pname = "mcst-lcc-libs-bin";
    version = "1.31.05";
    inherit src;

    installPhase = ''
      mkdir -p $out/lib $out/usr

      cp -rL mcst/*/fs/lib64/* $out/lib/
      cp -rL mcst/*/fs/usr/lib64/* $out/lib/
      ln -s $out/lib/libgcc_s.so.1 $out/lib/libgcc_s.so

      ln -s $out/lib $out/lib64
      ln -s $out/lib $out/usr/lib64

      cp -rL mcst/*/fs/usr/include $out/include
    '';
  };

  # For some reason you just can't set `ld` flags directly
  # in wrapBintoolsWith, so we're doing it here.
  bintools-bootstrap-unwrapped = symlinkJoin {
    name = "${bintools-unwrapped.name}-bootstrap-unwrapped";
    paths = [ bintools-unwrapped ];
    nativeBuildInputs = [ makeWrapper ];
    postBuild = ''
      for prog in $out/bin/e2k-unknown-linux-gnu-ld{,.bfd}; do
        wrapProgram $prog \
          --append-flags "--sysroot=${lcc-libs-bin}"
      done
    '';
  };

  bintools-bootstrap = wrapBintoolsWith {
    libc = lcc-libs-bin;
    bintools = bintools-bootstrap-unwrapped;
  };

  lcc-bootstrap = wrapCCWith {
    cc = lcc-base;
    bintools = bintools-bootstrap;
    libc = lcc-libs-bin;

    extraBuildCommands = ''
      echo "-B ${bintools-bootstrap}/bin/e2k-unknown-linux-gnu-" >> $out/nix-support/cc-cflags
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
      breakpointHook
    ];

    dontUseCmakeConfigure = true;
    dontUseCmakeBuild = true;
    dontUseCmakeInstall = true;
    CMAKE_POLICY_VERSION_MINIMUM = "3.5";

    buildPhase = let
      args =
         "INSTALL_DIR_LIB=$out/lib "
       + "INSTALL_DIR_INCLUDE=$out/include "
       + "LCC=${lcc-bootstrap}/bin/e2k-unknown-linux-gnu-lcc "
       + "LXX=${lcc-bootstrap}/bin/e2k-unknown-linux-gnu-l++ "
       + "CPP=${lcc-bootstrap}/bin/e2k-unknown-linux-gnu-cpp "
       + "LD=${lcc-bootstrap}/bin/e2k-unknown-linux-gnu-ld "
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
      bash lib/GNU/build_libquadmath.sh ${args}
      bash lib/GNU/build_libstdc++.sh ${args}
    '';
  };

  # Here we include lcc-libs, but it is still "unwrapped"
  # as it doesn't have the bintools or glibc
  lcc-unwrapped = symlinkJoin {
    name = "mcst-lcc";
    paths = [ lcc-base ];
    nativeBuildInputs = [ makeWrapper ];
    postBuild = ''
      for prog in $out/bin/{lcc,cpp,l++,lfortran}; do
        wrapProgram $prog \
          --add-flags "-L${lcc-libs}/lib/" \
          --add-flags "-I${lcc-libs}/include/"
      done
    '';
    passthru = {
      hardeningUnsupportedFlags = lcc-base.hardeningUnsupportedFlags;
    };
  };

  libc = mcst.glibc;

  bintools = wrapBintoolsWith {
    inherit libc;
    bintools = bintools-unwrapped;
  };

  lcc = wrapCCWith {
    inherit bintools libc;
    cc = lcc-unwrapped;
    extraBuildCommands = ''
      echo "-B ${bintools}/bin/e2k-unknown-linux-gnu-" >> $out/nix-support/cc-cflags
    '';
    /*nixSupport = {
      cc-cflags = [
        "-idirafter"
        "${}/include2"
      ];
    };*/
  };
in
  { inherit lcc-base bintools-unwrapped lcc-libs-bin
            bintools-bootstrap lcc-bootstrap
            lcc-libs lcc-unwrapped bintools
            lcc; }
