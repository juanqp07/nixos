# Paquetes de Nori preparados para Nixpkgs

Esta carpeta conserva las expresiones con la estructura que Nixpkgs espera. Las mismas recetas se usan directamente en Elytra y Titan mediante los pequeños adaptadores de `packages/nori.nix` y `packages/nori-cli.nix`, de modo que no hay una receta local distinta de la candidata a upstream.

## Paquetes

- `pkgs/by-name/no/nori/package.nix`: AppImage oficial de Nori Desktop.
- `pkgs/by-name/no/nori-cli/package.nix`: tarball oficial de Nori CLI.

Los dos paquetes declaran AGPL-3.0-or-later, x86_64-linux y `sourceProvenance = binaryNativeCode`, porque la release distribuye estos ejecutables precompilados. No se deben presentar como compilaciones reproducibles desde código fuente.

El AppImage de escritorio no incluye WebKitGTK: Nori upstream espera usar la biblioteca del sistema. La receta añade `webkitgtk_4_1` al entorno FHS. El CLI también se ejecuta en un entorno FHS con WebKitGTK y ALSA.

## Actualizaciones automáticas

Cada receta incorpora:

```nix
passthru.updateScript = nix-update-script { };
```

Al incorporar los paquetes a Nixpkgs, el bot comunitario `r-ryantm` / `nixpkgs-update` podrá ejecutar el updateScript, detectar una nueva versión de GitHub Releases, actualizar el número de versión y recalcular el hash. La actualización seguirá siendo una PR revisable; no se fusiona directamente ni publica una generación del sistema sin revisión.

El primer alta en Nixpkgs es manual. Este repositorio no puede hacer que Nixpkgs importe paquetes desde aquí: los dos archivos tienen que copiarse a un fork de `NixOS/nixpkgs` y proponerse mediante una PR.

## Envío inicial

Desde un checkout de un fork actualizado de Nixpkgs:

1. Copiar `nixpkgs/pkgs/by-name/no/nori/package.nix` a `pkgs/by-name/no/nori/package.nix`.
2. Copiar `nixpkgs/pkgs/by-name/no/nori-cli/package.nix` a `pkgs/by-name/no/nori-cli/package.nix`.
3. Añadir una entrada de mantenedor a `maintainers/maintainer-list.nix` y asignarla a ambos paquetes cuando esté aceptada.
4. Ejecutar `nix build -f . nori` y `nix build -f . nori-cli` o los equivalentes con Flakes.
5. Ejecutar `nixpkgs-review pr` sobre la rama y abrir la PR contra `NixOS/nixpkgs`.

Los paquetes usan los nombres `nori` y `nori-cli`; no existe actualmente un paquete de Nori Music con esos nombres en Nixpkgs. La búsqueda debe repetirse justo antes de abrir la PR por si el repositorio ha cambiado.

## Validación desde este repositorio

Las salidas `.#nori` y `.#nori-cli` llaman a estas mismas expresiones:

```bash
nix build --no-link --show-trace .#nori
nix build --no-link --show-trace .#nori-cli
```

GitHub Actions ejecuta ambas compilaciones en la comprobación Nori de Elytra y evalúa las configuraciones de los cinco hosts.
