# Keep the NixOS package and the expression prepared for Nixpkgs identical.
# The local nixpkgs input does not contain our new maintainer entry yet.
{ lib, ... }@args:

let
  nixpkgsLib = lib // {
    maintainers = lib.maintainers // {
      juanqp07 = {
        name = "JuanQ";
        github = "juanqp07";
        githubId = 87898162;
      };
    };
  };
in
import ../nixpkgs/pkgs/by-name/no/nori-cli/package.nix (args // {
  lib = nixpkgsLib;
})
