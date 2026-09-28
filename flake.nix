{
  description = "Configuracion Flake de Juan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-flatpak.url =
      "github:gmodena/nix-flatpak/?ref=latest";

    nix-software-center.url =
      "github:snowfallorg/nix-software-center";

    nix-software-center.inputs.nixpkgs.follows =
      "nixpkgs";

    subtui = {
      url = "github:MattiaPun/SubTUI";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-flatpak, ... }@inputs:
    let
      mkHost = hostName: extraModules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

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

        # ======================================================
        # PORTÁTIL
        # ======================================================

        elytra = mkHost "portatil" [
          ./modules/desktop-gaming.nix
          nix-flatpak.nixosModules.nix-flatpak
        ];

        # ======================================================
        # TORRE
        # ======================================================

        titan = mkHost "torre" [
          ./modules/desktop-gaming.nix
          nix-flatpak.nixosModules.nix-flatpak
        ];

        # ======================================================
        # SERVIDOR
        # ======================================================

        atlas = mkHost "servidor" [
          ./modules/server-system.nix
        ];

        # ======================================================
        # ZIMABLADE
        # ======================================================

        pico = mkHost "zimablade" [
          ./modules/server-system.nix
        ];
      };

      formatter.x86_64-linux =
        nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
    };
}