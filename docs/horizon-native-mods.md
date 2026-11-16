# Horizon en Elytra

Horizon se instala de forma declarativa desde el remoto firmado de FlatPark. La instalación está limitada a Elytra; no añade el launcher ni su SDK al otro equipo de escritorio.

## Uso normal

Abre **Horizon** desde el menú de KDE. Ese acceso inicia el Flatpak en su modo normal.

## Compilar mods nativos

Abre **Horizon (compilar mods nativos)** desde el menú de KDE. Este acceso ejecuta:

```bash
flatpak run --devel dev.playhorizon.Horizon
```

La compilación de mods nativos se realiza dentro del sandbox de Flatpak. Para ello, Horizon necesita el Freedesktop SDK de la misma rama que su runtime: `org.freedesktop.Sdk//26.08`. El SDK aporta el compilador C, `pkg-config` y los archivos de desarrollo de ALSA y libudev. El launcher descarga y administra su propio toolchain de Rust.

NixOS instala o actualiza el SDK mediante `horizon-native-mod-sdk.service`, después de registrar los remotos e instalar Horizon. Un temporizador semanal mantiene el SDK actualizado. No es necesario añadir `pkg-config`, `alsa-lib.dev` ni `udev.dev` a los paquetes globales del anfitrión.

Para comprobar el SDK o iniciar su instalación manualmente:

```bash
flatpak info --system org.freedesktop.Sdk//26.08
sudo systemctl start horizon-native-mod-sdk.service
```

Cierra cualquier instancia normal de Horizon antes de abrir el acceso de compilación.

> **Seguridad:** los mods nativos se ejecutan con los permisos de tu usuario. Compila únicamente mods y dependencias cuyo código y procedencia consideres fiables.
