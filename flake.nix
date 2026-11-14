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

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    # Despliegue remoto de Atlas y Pico; fijado a la versión estable 1.0.0.
    deploy-rs = {
      url = "github:serokell/deploy-rs/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      nix-flatpak,
      nixos-hardware,
      deploy-rs,
      home-manager,
      home-manager-stable,
      ...
    }@inputs:
    let
      # pkgsInput: nixpkgs (unstable) o nixpkgs-stable según el equipo.
      mkHost =
        pkgsInput: homeManagerInput: hostName: system: extraModules:
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
          ]
          ++ extraModules;
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
          ./modules/titan-interactive.nix
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

      # Despliegue remoto: las compilaciones se realizan en el equipo de control,
      # nunca en los servidores de baja potencia.
      deploy = {
        remoteBuild = false;
        activationTimeout = 600;

        # No activar estos rollbacks mientras system.autoUpgrade pueda crear
        # generaciones sin deploy-rs-activate. Véase docs/deploy-rs.md.
        autoRollback = false;
        magicRollback = false;

        nodes = {
          atlas = {
            hostname = "192.168.1.143";
            profiles.system = {
              user = "root";
              sshUser = "juan";
              interactiveSudo = true;
              path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.atlas;
            };
          };

          pico = {
            hostname = "192.168.1.147";
            profiles.system = {
              user = "root";
              sshUser = "juan";
              interactiveSudo = true;
              path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.pico;
            };
          };
        };
      };

      # Comprueba el esquema de despliegue y que cada perfil incluya sus
      # scripts de activación antes de permitir un despliegue real.
      checks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

      # CLI de deploy-rs y paquetes propios del Flake.
      # Agrupados en un único conjunto para evitar asignaciones anidadas duplicadas.
      packages.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        {
          deploy-rs = deploy-rs.packages.x86_64-linux.deploy-rs;
          nori = pkgs.callPackage ./packages/nori.nix { };
          nori-cli = pkgs.callPackage ./packages/nori-cli.nix { };
        };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;

      formatter.aarch64-linux = nixpkgs.legacyPackages.aarch64-linux.nixfmt;

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
              python3Packages.pip
              uv
              ruff
              mkdocs
            ];
          };
          node = pkgs.mkShell {
            packages = with pkgs; [
              nodejs_24
              pnpm
              bun
            ];
          };
          go = pkgs.mkShell {
            packages = with pkgs; [
              go
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
              rustfmt
              clippy
              gcc
              pkg-config
            ];
          };
        };
    };
}
