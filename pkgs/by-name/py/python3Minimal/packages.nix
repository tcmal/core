{ ... }:
res: pkgs: super:

with pkgs; {
  pythonInterpreters = callPackage ./. { };
  inherit (pythonInterpreters) python3Minimal;

  python3 = python3Minimal;

  # Should eventually be moved inside Python interpreters.
  python-setup-hook = buildPackages.callPackage ./setup-hook.nix { };
}
