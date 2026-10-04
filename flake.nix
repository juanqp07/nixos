{
  description = "Configuracion Flake de Juan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nix-flatpak.url =
      "github:gmodena/nix-flatpak/?ref=latest";

    nix-software-center.url =
      "github:snowfallorg/nix-software-center";

    nix-software-center.inputs.nixpkgs.follows =
      "nixpkgs";

    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-flatpak, nixos-hardware, ... }@inputs:
    let
      mkHost = hostName: system: extraModules:
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = {
            inherit inputs;
          };

          modules = [
            ./modules/common-system.nix
            ./hosts/${hostName}/configuration.nix
          ] ++ extraModules;
        };
    in
    {
  nixosConfigurations = {
    elytra = mkHost "portatil" "x86_64-linux" [
      ./modules/desktop-gaming.nix
      nix-flatpak.nixosModules.nix-flatpak
    ];

    titan = mkHost "torre" "x86_64-linux" [
      ./modules/desktop-gaming.nix
      nix-flatpak.nixosModules.nix-flatpak
    ];

    atlas = mkHost "servidor" "x86_64-linux" [ ];

    pico = mkHost "zimablade" "x86_64-linux" [ ];

    palco = mkHost "rpi4-bt" "aarch64-linux" [
      nixos-hardware.nixosModules.raspberry-pi-4
      "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
      ./modules/palco-audio.nix
    ];
  };

      formatter.x86_64-linux =
        nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;

      formatter.aarch64-linux =
        nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
    };
}