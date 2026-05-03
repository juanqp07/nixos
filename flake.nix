{
  description = "Configuracion Flake de Juan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    nix-software-center.url = "github:snowfallorg/nix-software-center";
    nix-software-center.inputs.nixpkgs.follows = "nixpkgs";
    subtui = {
       url = "github:MattiaPun/SubTUI";
       inputs.nixpkgs.follows = "nixpkgs"; # Para que use tu misma versión de nixpkgs
    };
  };

  outputs = { self, nixpkgs, nix-flatpak, ... }@inputs: 
  let
    # 1. Creamos una función auxiliar para no repetir código
    mkHost = hostName: extraModules: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./modules/common-system.nix
        ./hosts/${hostName}/configuration.nix

      ] ++ extraModules;
    };
  in
  {
    nixosConfigurations = {
      
      # 2. Definimos los hosts usando la función
      # mkHost "nombre_carpeta" [ lista_de_modulos_extra ]

      elytra = mkHost "portatil" [ 
        ./modules/desktop-gaming.nix 
        nix-flatpak.nixosModules.nix-flatpak 
      ];

      titan = mkHost "torre" [ 
        ./modules/desktop-gaming.nix 
        nix-flatpak.nixosModules.nix-flatpak 
      ];

      atlas = mkHost "servidor" [ ];

      pico = mkHost "zimablade" [ ];

    };
    
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
  };
}
