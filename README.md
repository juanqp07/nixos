# ❄️ Configuración NixOS de Juan (Flakes)

Este repositorio contiene mi configuración centralizada para 4 máquinas, gestionada mediante **Nix Flakes**.

## 📂 Estructura del Repositorio

* **flake.nix**: Punto de entrada que define los hosts y las versiones de los paquetes.
* **hosts/**: Configuraciones específicas de hardware.
    * `portatil/` (elytra): Laptop i5-13450HX (Raptor Lake HX) + NVIDIA RTX 5050 Max-Q / UHD integrada (PRIME offload).
    * `torre/` (titan): PC Ryzen 5 5600X + RX 6700 XT 12GB + 32GB RAM (AMD nativo).
    * `servidor/` (atlas): i5-1250P + 32GB RAM (Docker, sin entorno gráfico).
    * `zimablade/` (pico): Intel Celeron N3450 (Apollo Lake) (ZimaBlade, Docker/Dockge).
    * `rpi4-bt/` (palco): Raspberry Pi 4B 8GB headless, receptor Bluetooth A2DP → jack 3.5mm (aarch64).
* **modules/**: Módulos compartidos.
    * `common-system.nix`: Configuración base (Usuario, Idioma, Herramientas CLI).
    * `desktop-gaming.nix`: Entorno Plasma 6, Steam, Audio y Apps de escritorio.
    * `palco-audio.nix`: BlueZ sink + PipeWire/WirePlumber + auto-pairing para la Pi (solo palco).

---

## 🚀 Cómo aplicar cambios

Desde la carpeta `~/nixos`, ejecuta el comando según la máquina en la que estés:

### 💻 Portátil (elytra)
```bash
sudo nixos-rebuild switch --flake .#elytra
```

### 🖥️ PC Torre (titan)
```bash
sudo nixos-rebuild switch --flake .#titan
```

### ☁️ Servidor (atlas)
```bash
sudo nixos-rebuild switch --flake .#atlas
```

### 🧊 ZimaBlade (pico)
```bash
sudo nixos-rebuild switch --flake .#pico
```

### 🔊 Raspberry Pi 4B (palco) — receptor Bluetooth → jack
```bash
# 1. Construir la imagen SD desde la torre (titan tiene binfmt aarch64):
nix build .#nixosConfigurations.palco.config.system.build.sdImage
# 2. Grabarla (sustituye /dev/mmcblk0 por tu lector SD):
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/mmcblk0 bs=4M status=progress conv=fsync
# 3. Arrancar la Pi, generar su hardware real y aplicarlo:
sudo nixos-generate-config --show-hardware-config > ~/nixos/hosts/rpi4-bt/hardware-configuration.nix
git add hosts/rpi4-bt/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#palco
```

Uso en bolo (sin internet): la Pi arranca como `palco` visible por Bluetooth,
se empareja una vez desde el móvil y reconecta sola. Alias útiles en la Pi:
`palco-bolo` (apaga WiFi para estabilizar BT), `palco-config` (enciende WiFi
para mantenimiento), `palco-estado` (diagnóstico BT + audio).

---

## 🛠️ Instalación en una máquina nueva

1.  Instala NixOS con la ISO (Plasma o Mínima).
2.  Clona este repositorio: `git clone <URL_DEL_REPO> ~/nixos`.
3.  **Importante**: Copia el hardware generado por el instalador:
    `cp /etc/nixos/hardware-configuration.nix ~/nixos/hosts/<nombre-maquina>/`
4.  Si los Flakes no están activos:
    `export NIX_CONFIG="experimental-features = nix-command flakes"`
5.  Aplica la configuración con el comando de "rebuild" correspondiente.

---

## 🔄 Actualización y Mantenimiento

### Actualizar el Sistema (Software)
1. **Actualizar el catálogo de paquetes** (modifica el flake.lock):
   ```bash
   nix flake update
   ```
2. **Aplicar la actualización**:
   ```bash
   sudo nixos-rebuild switch --flake .#nombre-maquina
   ```
---

## 🧹 Mantenimiento y Limpieza

Para evitar que el disco se llene con versiones antiguas del sistema:

* **Eliminar versiones de más de 7 días**:
    `sudo nix-collect-garbage -d`
* **Optimizar el almacenamiento (eliminar duplicados)**:
    `nix-store --optimise`

---

## ⚠️ Notas de Configuración
* **Git**: Antes de aplicar un cambio con el comando `switch`, debes añadir los archivos nuevos a git (`git add .`), de lo contrario Nix los ignorará.
* **NVIDIA**: El portátil usa el driver propietario estable.
* **Docker/Podman**: 
    * `atlas` y `pico` usan **Docker** y **Dockge** para gestión de contenedores.
    * El resto usa **Podman** o no tiene entorno de contenedores habilitado por defecto.
