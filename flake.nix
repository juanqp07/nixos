{
  description = "Configuracion Flake de Juan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs = { self, nixpkgs, nix-flatpak, ... }@inputs: {
    nixosConfigurations = {
      
      # 1. PORTÁTIL
      portatil = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; }; # <--- ESTO ES IMPORTANTE
        modules = [
          ./hosts/portatil/configuration.nix
          ./modules/common-system.nix
          ./modules/desktop-gaming.nix
          nix-flatpak.nixosModules.nix-flatpak
        ];
      };

      # 2. ORDENADOR
      torre = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/torre/configuration.nix
          ./modules/common-system.nix
          ./modules/desktop-gaming.nix
          nix-flatpak.nixosModules.nix-flatpak
        ];
      };

      # 3. SERVIDOR
      servidor = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/servidor/configuration.nix
          ./modules/common-system.nix
        ];
      };

    };
    
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
  };
}