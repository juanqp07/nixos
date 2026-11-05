{
  description = "Configuracion Flake de Juan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Canal estable para los servidores (atlas, pico): solo correcciones y seguridad.
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    # Home Manager para hosts que siguen nixpkgs-unstable.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager alineado con nixos-26.05 para los servidores.
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nix-flatpak.url =
      "github:gmodena/nix-flatpak/?ref=latest";

    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";    
  };

  outputs = { self, nixpkgs, nixpkgs-stable, nix-flatpak, nixos-hardware, home-manager, home-manager-stable, ... }@inputs:
    let
      # pkgsInput: nixpkgs (unstable) o nixpkgs-stable según el equipo.
      mkHost = pkgsInput: homeManagerInput: hostName: system: extraModules:
        pkgsInput.lib.nixosSystem {
          inherit system;

          specialArgs = {
            inherit inputs;
          };

          modules = [
            ./modules/common-system.nix
            homeManagerInput.nixosModules.home-manager
            ./modules/home-manager.nix
            ./hosts/${hostName}/configuration.nix
          ] ++ extraModules;
        };
    in
    {
  nixosConfigurations = {
    elytra = mkHost nixpkgs home-manager "portatil" "x86_64-linux" [
      ./modules/desktop-gaming.nix
      nix-flatpak.nixosModules.nix-flatpak
    ];

    titan = mkHost nixpkgs home-manager "torre" "x86_64-linux" [
      ./modules/desktop-gaming.nix
      nix-flatpak.nixosModules.nix-flatpak
    ];

    atlas = mkHost nixpkgs-stable home-manager-stable "servidor" "x86_64-linux" [
      ./modules/server-system.nix
    ];

    pico = mkHost nixpkgs-stable home-manager-stable "zimablade" "x86_64-linux" [
      ./modules/server-system.nix
    ];

    palco = mkHost nixpkgs home-manager "rpi4-bt" "aarch64-linux" [
      nixos-hardware.nixosModules.raspberry-pi-4
      "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
      ./modules/palco-audio.nix
    ];
  };

      formatter.x86_64-linux =
        nixpkgs.legacyPackages.x86_64-linux.nixfmt;

      formatter.aarch64-linux =
        nixpkgs.legacyPackages.aarch64-linux.nixfmt;

      # devShells por proyecto: `nix develop .#python` etc. o auto con direnv.
      # Evitan meter toolchains globales en systemPackages.
      devShells.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        {
          python = pkgs.mkShell {
            packages = with pkgs; [
              python3
              uv
              ruff
            ];
          };
          node = pkgs.mkShell {
            packages = with pkgs; [
              nodejs_24
              pnpm
            ];
          };
          # Java/Kotlin para DAM: ajusta el JDK a la versión que pida el curso.
          java = pkgs.mkShell {
            packages = with pkgs; [
              jdk21
              gradle
              kotlin
            ];
          };
          rust = pkgs.mkShell {
            packages = with pkgs; [
              rustc
              cargo
              rust-analyzer
              gcc
              pkg-config
            ];
          };
        };
    };
}