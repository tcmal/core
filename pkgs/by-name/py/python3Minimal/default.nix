{ __splicedPackages, callPackage, config, darwin, lib, libffiBoot
, makeScopeWithSplicing', stdenv }@args:
let
  passthruFun = import ./passthruFun.nix args;
  sources = {
    python311 = {
      sourceVersion = {
        major = "3";
        minor = "11";
        patch = "9";
        suffix = "";
      };
      hash = "sha256-mx6JZSP8UQaREmyGRAbZNgo9Hphqy9pZzaV7Wr2kW4c=";
    };
  };

in {
  # Minimal versions of Python (built without optional dependencies)
  python3Minimal = (callPackage ./cpython ({
    self = __splicedPackages.python3Minimal;
    inherit passthruFun;
    pythonAttr = "python3Minimal";
    # strip down that python version as much as possible
    openssl = null;
    readline = null;
    ncurses = null;
    gdbm = null;
    configd = null;
    sqlite = null;
    tzdata = null;
    libX11 = null;
    xorgproto = null;
    bluez = null;
    bzip2 = null;
    mailcap = null;
    tcl = null;
    tix = null;
    tk = null;
    windows = null;
    libffi = libffiBoot; # without test suite
    stripConfig = true;
    stripIdlelib = true;
    stripTests = true;
    stripTkinter = true;
    rebuildBytecode = false;
    stripBytecode = true;
    includeSiteCustomize = false;
    enableOptimizations = false;
    enableLTO = false;
    mimetypesSupport = false;
  } // sources.python311)).overrideAttrs (old: {
    # TODO(@Artturin): Add this to the main cpython expr
    strictDeps = true;
    pname = "python3-minimal";
  });
}
