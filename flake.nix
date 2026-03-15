{
  description = "Configuracion Flake de Juan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
  };

  outputs = { self, nixpkgs, nix-flatpak, ... }@inputs: {
    nixosConfigurations = {
      
      # 1. PORTÁTIL
      elytra = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; }; # <--- AÑADIR ESTO
        modules = [
          ./modules/common-system.nix
          ./hosts/portatil/configuration.nix
          ./modules/desktop-gaming.nix
          nix-flatpak.nixosModules.nix-flatpak
        ];
      };

      # 2. ORDENADOR
      titan = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; }; # <--- AÑADIR ESTO
        modules = [
          ./modules/common-system.nix
          ./hosts/torre/configuration.nix
          ./modules/desktop-gaming.nix
          nix-flatpak.nixosModules.nix-flatpak
        ];
      };

      # 3. SERVIDOR
      atlas = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; }; # <--- AÑADIR ESTO
        modules = [
          ./modules/common-system.nix
          ./hosts/servidor/configuration.nix
        ];
      };

      # 4. ZIMABLADE
      pico = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; }; # <--- AÑADIR ESTO
        modules = [
          ./modules/common-system.nix
          ./hosts/zimablade/configuration.nix
        ];
      };

    };
    
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
  };
}