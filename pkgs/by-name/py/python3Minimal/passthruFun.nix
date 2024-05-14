{ lib, stdenv, callPackage, config, makeScopeWithSplicing', ... }:

{ implementation, libPrefix, executable, sourceVersion, pythonVersion
, packageOverrides, sitePackages, hasDistutilsCxxPatch, pythonOnBuildForBuild
, pythonOnBuildForHost, pythonOnBuildForTarget, pythonOnHostForHost
, pythonOnTargetForTarget, pythonAttr ? null, self # is pythonOnHostForTarget
}:
let
  pythonOnBuildForHost_overridden = pythonOnBuildForHost.override {
    inherit packageOverrides;
    self = pythonOnBuildForHost_overridden;
  };
in rec {
  isPy27 = pythonVersion == "2.7";
  isPy37 = pythonVersion == "3.7";
  isPy38 = pythonVersion == "3.8";
  isPy39 = pythonVersion == "3.9";
  isPy310 = pythonVersion == "3.10";
  isPy311 = pythonVersion == "3.11";
  isPy312 = pythonVersion == "3.12";
  isPy2 = lib.strings.substring 0 1 pythonVersion == "2";
  isPy3 = lib.strings.substring 0 1 pythonVersion == "3";
  isPy3k = isPy3;
  isPyPy = lib.hasInfix "pypy" interpreter;

  interpreter = "${self}/bin/${executable}";
  inherit executable implementation libPrefix pythonVersion sitePackages;
  inherit sourceVersion;
  pythonAtLeast = lib.versionAtLeast pythonVersion;
  pythonOlder = lib.versionOlder pythonVersion;
  inherit hasDistutilsCxxPatch;
  pythonOnBuildForHost = pythonOnBuildForHost_overridden;

  inherit pythonAttr;
}
