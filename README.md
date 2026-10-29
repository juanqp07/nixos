# ❄️ Configuración NixOS de Juan (Flakes)

Este repositorio contiene la configuración centralizada de cinco equipos, gestionada mediante **Nix Flakes**.

## 📂 Estructura del Repositorio

* **flake.nix**: Punto de entrada que define los hosts y las versiones de los paquetes.
* **hosts/**: Configuraciones específicas de hardware.
    * `portatil/` (elytra): Laptop i5-13450HX (Raptor Lake HX) + NVIDIA RTX 5050 Max-Q / UHD integrada (PRIME offload).
    * `torre/` (titan): PC Ryzen 5 5600X + RX 6700 XT 12GB + 32GB RAM (AMD nativo).
    * `servidor/` (atlas): i5-1250P + 32GB RAM (Docker, sin entorno gráfico).
    * `zimablade/` (pico): Intel Celeron N3450 (Apollo Lake) (ZimaBlade, Docker/Dockge).
    * `rpi4-bt/` (palco): Raspberry Pi 4B 8GB headless, receptor Bluetooth A2DP → jack 3.5mm (aarch64).
* **modules/**: Módulos compartidos.
    * `common-system.nix`: Configuración base, idioma, herramientas CLI y mantenimiento.
    * `desktop-gaming.nix`: Entorno Plasma 6, Steam, audio, virtualización y aplicaciones de escritorio.
    * `server-system.nix`: Ajustes comunes de kernel y memoria para los servidores.
    * `palco-audio.nix`: BlueZ + PipeWire/WirePlumber y DSP para la Raspberry Pi.

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

Primera puesta en marcha: entra por la consola local y ejecuta `passwd` para
establecer una contraseña propia antes de usar SSH. SSH sigue admitiendo
contraseñas; no se exige una clave SSH. La contraseña inicial no se almacena en
este repositorio público. Si ya tenías la Pi configurada, quitar el valor inicial
de la configuración no cambia una contraseña existente.

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

### Actualizar el sistema de forma controlada

1. Comprueba que no tienes cambios ajenos a la configuración y actualiza las dependencias:
   ```bash
   git status --short
   nix flake update
   git diff -- flake.lock
   ```
2. Evalúa las cinco configuraciones antes de desplegar:
   ```bash
   for host in elytra titan atlas pico palco; do
     nix eval --show-trace --raw ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null || exit 1
   done
   ```
3. Construye primero la configuración del equipo que vayas a actualizar y revisa el resultado:
   ```bash
   sudo nixos-rebuild build --flake .#elytra
   ```
   Cambia `elytra` por el host correspondiente. La compilación de la configuración de escritorio no sustituye las pruebas de hardware en el equipo real.
4. Aplica el cambio solo cuando hayas revisado las diferencias:
   ```bash
   sudo nixos-rebuild switch --flake .#elytra
   ```

Los hosts `atlas` y `pico` tienen `system.autoUpgrade` activado con `operation = "boot"`: se prepara una generación nueva usando las revisiones fijadas en `flake.lock`, pero no se activa en caliente ni se reinicia automáticamente. Las actualizaciones de paquetes requieren actualizar y revisar el lockfile de forma deliberada; después, despliega la configuración actualizada en la copia local del repositorio de cada servidor. Comprueba los registros con `journalctl -u nixos-upgrade.service` y mantén copias de seguridad de los datos persistentes.
---

## 🧹 Mantenimiento y Limpieza

Para liberar espacio sin eliminar todas las generaciones anteriores:

* **Eliminar generaciones antiguas de más de 30 días** (coincide con la política general de `common-system.nix`):
    `sudo nix-collect-garbage --delete-older-than 30d`
* **Optimizar el almacenamiento compartido**:
    `sudo nix-store --optimise`

Nota: `nix-collect-garbage -d` elimina todas las generaciones antiguas, no solo las que tienen más de siete días, y reduce las posibilidades de volver a una generación anterior. En `pico`, la recolección automática del sistema está configurada con un umbral de 7 días.

---

## ✅ Validación automática

GitHub Actions evalúa el `system.build.toplevel` de los cinco hosts y ejecuta `nix flake check --no-build --show-trace` en cada pull request y en los cambios que llegan a `main`. Son comprobaciones de evaluación; no sustituyen la compilación completa ni las pruebas de hardware, Bluetooth, audio, GPU o contenedores.

La auditoría de decisiones, compromisos y pruebas recomendadas por equipo está en [`docs/performance-stability-audit.md`](docs/performance-stability-audit.md).

## ⚠️ Notas de configuración
* **Git y Flakes**: los archivos nuevos deben estar añadidos a Git para que un flake basado en Git pueda verlos. Añade solo los archivos necesarios (por ejemplo, `git add modules/nuevo-modulo.nix`); los alias `nix-up` y `nix-update` no deben preparar automáticamente todos tus cambios.
* **NVIDIA**: `elytra` usa una RTX 5050 con PRIME offload; comprueba los controladores y el kernel en el hardware real antes de cambiar de rama.
* **Contenedores**: `elytra` y `titan` habilitan Docker para uso local; `atlas` y `pico` lo utilizan para sus servicios. `palco` es un appliance de audio Bluetooth y no necesita el stack de escritorio.
