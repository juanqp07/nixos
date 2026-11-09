# Keep the NixOS package and the expression prepared for Nixpkgs identical.
{ lib, stdenv, appimageTools, fetchurl, nix-update-script }:

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
import ../nixpkgs/pkgs/by-name/no/nori/package.nix {
  inherit stdenv appimageTools fetchurl nix-update-script;
  lib = nixpkgsLib;
}
