{ lowPrio, newScope, pkgs, lib, stdenv, cmake, ninja, preLibcCrossHeaders
, libxml2, python3, fetchFromGitHub, substituteAll, overrideCC, wrapCCWith
, wrapBintoolsWith
, buildLlvmTools # tools, but from the previous stage, for cross
, targetLlvmLibraries # libraries, but from the next stage, for cross
, targetLlvm
# This is the default binutils, but with *this* version of LLD rather
# than the default LLVM verion's, if LLD is the choice. We use these for
# the `useLLVM` bootstrapping below.
, bootBintoolsNoLibc ?
  if stdenv.targetPlatform.linker == "lld" then null else pkgs.bintoolsNoLibc
, bootBintools ?
  if stdenv.targetPlatform.linker == "lld" then null else pkgs.bintools, darwin
# LLVM release information; specify one of these but not both:
, gitRelease ? {
  version = "19.0.0-git";
  rev = "cebf77fb936a7270c7e3fa5c4a7e76216321d385";
  rev-version = "19.0.0-unstable-2024-04-07";
  sha256 = "sha256-616tscgsiFgHQcXW4KzK5srrudYizQFnJVM6K0qRf+I=";
}
# i.e.:
# {
#   version = /* i.e. "15.0.0" */;
#   rev = /* commit SHA */;
#   rev-version = /* human readable version; i.e. "15.0.0-unstable-2022-07-26" */;
#   sha256 = /* checksum for this release, can omit if specifying your own `monorepoSrc` */;
# }
, officialRelease ? null
  # i.e.:
  # {
  #   version = /* i.e. "15.0.0" */;
  #   candidate = /* optional; if specified, should be: "rcN" */
  #   sha256 = /* checksum for this release, can omit if specifying your own `monorepoSrc` */;
  # }
  # By default, we'll try to fetch a release from `github:llvm/llvm-project`
  # corresponding to the `gitRelease` or `officialRelease` specified.
  #
  # You can provide your own LLVM source by specifying this arg but then it's up
  # to you to make sure that the LLVM repo given matches the release configuration
  # specified.
, monorepoSrc ? null }:

assert lib.assertMsg (lib.xor (gitRelease != null) (officialRelease != null))
  ("must specify `gitRelease` or `officialRelease`"
    + (lib.optionalString (gitRelease != null) " — not both"));
let monorepoSrc' = monorepoSrc;
in let
  inherit (import ../common/common-let.nix {
    inherit lib gitRelease officialRelease;
  })
    releaseInfo;

  inherit (releaseInfo) release_version version;

  inherit (import ../common/common-let.nix {
    inherit lib fetchFromGitHub release_version gitRelease officialRelease
      monorepoSrc';
  })
    llvm_meta monorepoSrc;

  tools = lib.makeExtensible (tools:
    let
      callPackage = newScope (tools // {
        inherit stdenv cmake ninja libxml2 python3 release_version version
          monorepoSrc buildLlvmTools;
      });
      major = lib.versions.major release_version;
      mkExtraBuildCommands0 = cc: ''
        rsrc="$out/resource-root"
        mkdir "$rsrc"
        ln -s "${cc.lib}/lib/clang/${major}/include" "$rsrc"
        echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
      '';
      mkExtraBuildCommands = cc:
        mkExtraBuildCommands0 cc + ''
          ln -s "${targetLlvmLibraries.compiler-rt.out}/lib" "$rsrc/lib"
          ln -s "${targetLlvmLibraries.compiler-rt.out}/share" "$rsrc/share"
        '';

      bintoolsNoLibc' = if bootBintoolsNoLibc == null then
        tools.bintoolsNoLibc
      else
        bootBintoolsNoLibc;
      bintools' = if bootBintools == null then tools.bintools else bootBintools;

    in {

      libllvm = callPackage ./llvm { inherit llvm_meta; };

      # `llvm` historically had the binaries.  When choosing an output explicitly,
      # we need to reintroduce `outputSpecified` to get the expected behavior e.g. of lib.get*
      llvm = tools.libllvm;

      libclang = callPackage ../common/clang {
        patches = [
          ./clang/purity.patch
          # https://reviews.llvm.org/D51899
          ./clang/gnu-install-dirs.patch
          ../common/clang/add-nostdlibinc-flag.patch
          (substituteAll {
            src = ../common/clang/clang-at-least-16-LLVMgold-path.patch;
            libllvmLibdir = "${tools.libllvm.lib}/lib";
          })
        ];
        inherit llvm_meta;
      };

      clang-unwrapped = tools.libclang;

      llvm-manpages = lowPrio (tools.libllvm.override {
        enableManpages = true;
        python3 = pkgs.python3; # don't use python-boot
      });

      clang-manpages = lowPrio (tools.libclang.override {
        enableManpages = true;
        python3 = pkgs.python3; # don't use python-boot
      });

      lldb-manpages = lowPrio (tools.lldb.override {
        enableManpages = true;
        python3 = pkgs.python3; # don't use python-boot
      });

      # pick clang appropriate for package set we are targeting
      clang = if stdenv.targetPlatform.useLLVM or false then
        tools.clangUseLLVM
      else if (pkgs.targetPackages.stdenv or stdenv).cc.isGNU then
        tools.libstdcxxClang
      else
        tools.libcxxClang;

      libstdcxxClang = wrapCCWith rec {
        cc = tools.clang-unwrapped;
        # libstdcxx is taken from gcc in an ad-hoc way in cc-wrapper.
        libcxx = null;
        extraPackages = [ targetLlvmLibraries.compiler-rt ];
        extraBuildCommands = mkExtraBuildCommands cc;
      };

      libcxxClang = wrapCCWith rec {
        cc = tools.clang-unwrapped;
        libcxx = targetLlvmLibraries.libcxx;
        extraPackages = [ targetLlvmLibraries.compiler-rt ];
        extraBuildCommands = mkExtraBuildCommands cc;
      };

      lld = callPackage ../common/lld {
        patches = [ ./lld/gnu-install-dirs.patch ];
        inherit llvm_meta;
      };

      mlir = callPackage ../common/mlir { inherit llvm_meta; };

      lldb = callPackage ../common/lldb.nix {
        src = callPackage ({ runCommand }:
          runCommand "lldb-src-${version}" { } ''
            mkdir -p "$out"
            cp -r ${monorepoSrc}/cmake "$out"
            cp -r ${monorepoSrc}/lldb "$out"
          '') { };
        patches = [
          # FIXME: do we need this? ./procfs.patch
          ../common/lldb/gnu-install-dirs.patch
        ]
        # This is a stopgap solution if/until the macOS SDK used for x86_64 is
        # updated.
        #
        # The older 10.12 SDK used on x86_64 as of this writing has a `mach/machine.h`
        # header that does not define `CPU_SUBTYPE_ARM64E` so we replace the one use
        # of this preprocessor symbol in `lldb` with its expansion.
        #
        # See here for some context:
        # https://github.com/NixOS/nixpkgs/pull/194634#issuecomment-1272129132
          ++ lib.optional (stdenv.targetPlatform.isDarwin
            && !stdenv.targetPlatform.isAarch64
            && (lib.versionOlder darwin.apple_sdk.sdk.version "11.0"))
          ./lldb/cpu_subtype_arm64e_replacement.patch;
        inherit llvm_meta;
      };

      # Below, is the LLVM bootstrapping logic. It handles building a
      # fully LLVM toolchain from scratch. No GCC toolchain should be
      # pulled in. As a consequence, it is very quick to build different
      # targets provided by LLVM and we can also build for what GCC
      # doesn’t support like LLVM. Probably we should move to some other
      # file.

      bintools-unwrapped = callPackage ../common/bintools.nix { };

      bintoolsNoLibc = wrapBintoolsWith {
        bintools = tools.bintools-unwrapped;
        libc = preLibcCrossHeaders;
      };

      bintools = wrapBintoolsWith { bintools = tools.bintools-unwrapped; };

      clangUseLLVM = wrapCCWith rec {
        cc = tools.clang-unwrapped;
        libcxx = targetLlvmLibraries.libcxx;
        bintools = bintools';
        extraPackages = [ targetLlvmLibraries.compiler-rt ]
          ++ lib.optionals (!stdenv.targetPlatform.isWasm)
          [ targetLlvmLibraries.libunwind ];
        extraBuildCommands = mkExtraBuildCommands cc;
        nixSupport.cc-cflags = [
          "-rtlib=compiler-rt"
          "-Wno-unused-command-line-argument"
          "-B${targetLlvmLibraries.compiler-rt}/lib"
        ] ++ lib.optional (!stdenv.targetPlatform.isWasm)
          "--unwindlib=libunwind" ++ lib.optional (!stdenv.targetPlatform.isWasm
            && stdenv.targetPlatform.useLLVM or false) "-lunwind"
          ++ lib.optional stdenv.targetPlatform.isWasm "-fno-exceptions";
        nixSupport.cc-ldflags = lib.optionals (!stdenv.targetPlatform.isWasm)
          [ "-L${targetLlvmLibraries.libunwind}/lib" ];
      };

      clangNoLibcxx = wrapCCWith rec {
        cc = tools.clang-unwrapped;
        libcxx = null;
        bintools = bintools';
        extraPackages = [ targetLlvmLibraries.compiler-rt ];
        extraBuildCommands = mkExtraBuildCommands cc;
        nixSupport.cc-cflags = [
          "-rtlib=compiler-rt"
          "-B${targetLlvmLibraries.compiler-rt}/lib"
          "-nostdlib++"
        ] ++ lib.optional stdenv.targetPlatform.isWasm "-fno-exceptions";
      };

      clangNoLibc = wrapCCWith rec {
        cc = tools.clang-unwrapped;
        libcxx = null;
        bintools = bintoolsNoLibc';
        extraPackages = [ targetLlvmLibraries.compiler-rt ];
        extraBuildCommands = mkExtraBuildCommands cc;
        nixSupport.cc-cflags =
          [ "-rtlib=compiler-rt" "-B${targetLlvmLibraries.compiler-rt}/lib" ]
          ++ lib.optional stdenv.targetPlatform.isWasm "-fno-exceptions";
      };

      clangNoCompilerRt = wrapCCWith rec {
        cc = tools.clang-unwrapped;
        libcxx = null;
        bintools = bintoolsNoLibc';
        extraPackages = [ ];
        extraBuildCommands = mkExtraBuildCommands0 cc;
        nixSupport.cc-cflags = [ "-nostartfiles" ]
          ++ lib.optional stdenv.targetPlatform.isWasm "-fno-exceptions";
      };

      clangNoCompilerRtWithLibc = wrapCCWith (rec {
        cc = tools.clang-unwrapped;
        libcxx = null;
        bintools = bintools';
        extraPackages = [ ];
        extraBuildCommands = mkExtraBuildCommands0 cc;
      } // lib.optionalAttrs stdenv.targetPlatform.isWasm {
        nixSupport.cc-cflags = [ "-fno-exceptions" ];
      });

      # Has to be in tools despite mostly being a library,
      # because we use a native helper executable from a
      # non-cross build in cross builds.
      libclc = callPackage ../common/libclc.nix { inherit buildLlvmTools; };
    });

  libraries = lib.makeExtensible (libraries:
    let
      callPackage = newScope (libraries // buildLlvmTools // {
        inherit stdenv cmake ninja libxml2 python3 release_version version
          monorepoSrc;
      });
    in {

      compiler-rt-libc = callPackage ../common/compiler-rt {
        patches = [
          ./compiler-rt/X86-support-extension.patch # Add support for i486 i586 i686 by reusing i386 config
          # ld-wrapper dislikes `-rpath-link //nix/store`, so we normalize away the
          # extra `/`.
          ./compiler-rt/normalize-var.patch
          # See: https://github.com/NixOS/nixpkgs/pull/186575
          ../common/compiler-rt/darwin-plistbuddy-workaround.patch
          # See: https://github.com/NixOS/nixpkgs/pull/194634#discussion_r999829893
          # ../common/compiler-rt/armv7l-15.patch
        ];
        inherit llvm_meta;
        stdenv = if stdenv.hostPlatform.useLLVM or false
        || (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isStatic) then
          overrideCC stdenv buildLlvmTools.clangNoCompilerRtWithLibc
        else
          stdenv;
      };

      compiler-rt-no-libc = callPackage ../common/compiler-rt {
        patches = [
          ./compiler-rt/X86-support-extension.patch # Add support for i486 i586 i686 by reusing i386 config
          # ld-wrapper dislikes `-rpath-link //nix/store`, so we normalize away the
          # extra `/`.
          ./compiler-rt/normalize-var.patch
          # See: https://github.com/NixOS/nixpkgs/pull/186575
          ../common/compiler-rt/darwin-plistbuddy-workaround.patch
          # See: https://github.com/NixOS/nixpkgs/pull/194634#discussion_r999829893
          # ../common/compiler-rt/armv7l-15.patch
        ];
        inherit llvm_meta;
        stdenv = if stdenv.hostPlatform.useLLVM or false then
          overrideCC stdenv buildLlvmTools.clangNoCompilerRt
        else
          stdenv;
      };

      # N.B. condition is safe because without useLLVM both are the same.
      compiler-rt =
        if stdenv.hostPlatform.isAndroid || stdenv.hostPlatform.isDarwin then
          libraries.compiler-rt-libc
        else
          libraries.compiler-rt-no-libc;

      stdenv = overrideCC stdenv buildLlvmTools.clang;

      libcxxStdenv = overrideCC stdenv buildLlvmTools.libcxxClang;

      # `libcxx` requires a fairly modern C++ compiler,
      # so: we use the clang from this LLVM package set instead of the regular
      # stdenv's compiler.
      libcxx = callPackage ../common/libcxx {
        patches = lib.optionals (stdenv.isDarwin
          && lib.versionOlder stdenv.hostPlatform.darwinMinVersion "10.13") [
            # https://github.com/llvm/llvm-project/issues/64226
            ./libcxx/0001-darwin-10.12-mbstate_t-fix.patch
          ];
        inherit llvm_meta;
        stdenv = overrideCC stdenv buildLlvmTools.clangNoLibcxx;
      };

      libunwind = callPackage ../common/libunwind {
        inherit llvm_meta;
        stdenv = overrideCC stdenv buildLlvmTools.clangNoLibcxx;
      };

      openmp = callPackage ../common/openmp {
        patches =
          [ ./openmp/fix-find-tool.patch ./openmp/run-lit-directly.patch ];
        inherit llvm_meta targetLlvm;
      };
    });
  noExtend = extensible: lib.attrsets.removeAttrs extensible [ "extend" ];

in {
  inherit tools libraries release_version;
} // (noExtend libraries) // (noExtend tools)
