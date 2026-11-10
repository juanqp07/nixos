# Keep the NixOS package and the expression prepared for Nixpkgs identical.
{ lib
, stdenv
, stdenvNoCC
, fetchurl
, gnutar
, gzip
, buildFHSEnv
, appimageTools
, alsa-lib
, webkitgtk_4_1
, cacert
, nix-update-script
}:

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
import ../nixpkgs/pkgs/by-name/no/nori-cli/package.nix {
  inherit
    stdenv
    stdenvNoCC
    fetchurl
    gnutar
    gzip
    buildFHSEnv
    appimageTools
    alsa-lib
    webkitgtk_4_1
    cacert
    nix-update-script
    ;
  lib = nixpkgsLib;
}
