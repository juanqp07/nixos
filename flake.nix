{
  description = "Configuracion Flake de Juan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      
      # 1. PORTÁTIL
      portatil = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/portatil/configuration.nix
          ./modules/common-system.nix
          ./modules/desktop-gaming.nix
        ];
      };

      # 2. ORDENADOR
      torre = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/torre/configuration.nix
          ./modules/common-system.nix
          ./modules/desktop-gaming.nix
        ];
      };

      # 3. SERVIDOR
      servidor = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/servidor/configuration.nix
          ./modules/common-system.nix
        ];
      };

    };
  };
}
