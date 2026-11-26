# ❄️ Configuración NixOS de Juan (Flakes)

Este repositorio contiene la configuración centralizada de cinco equipos, gestionada mediante **Nix Flakes**. Incluye dos servidores del homelab (`atlas` y `pico`), dos equipos de escritorio (`elytra` y `titan`) y una Raspberry Pi dedicada a audio (`palco`).

## 📂 Estructura del Repositorio

* **flake.nix / flake.lock**: punto de entrada, hosts, dependencias fijadas, devShells y despliegues remotos.
* **hosts/**: ajustes específicos de cada equipo y su hardware.
    * `portatil/` (elytra): portátil Intel + NVIDIA RTX 5050.
    * `torre/` (titan): torre Ryzen + Radeon RX 6700 XT.
    * `servidor/` (atlas): servidor principal del homelab.
    * `zimablade/` (pico): servidor secundario del homelab.
    * `rpi4-bt/` (palco): Raspberry Pi dedicada a audio Bluetooth.
* **modules/**: configuración compartida agrupada por responsabilidad.
    * `common/`: base del sistema y herramientas de desarrollo.
    * `desktop/`: base, Plasma, audio/Bluetooth, virtualización, gaming, aplicaciones y compatibilidad binaria.
    * `server/`: base común y política SSH/Fail2ban compartida por Atlas y Pico.
    * `atlas/`: motor Docker, Arcane, firewall de contenedores y runners de GitHub Actions.
    * `palco/`: Bluetooth, PipeWire/DSP y mantenimiento del appliance.
    * `home-manager.nix`: integración de Home Manager con NixOS.
* **home/juan/**: preferencias personales, Fish, alias y configuración de Plasma mediante Home Manager.
* **packages/** y **nixpkgs/**: paquetes propios y expresiones preparadas para Nixpkgs.
* **scripts/** y **tests/**: mantenimiento, automatización y pruebas offline.
* **docs/**: procedimientos de despliegue, seguridad, mantenimiento y decisiones técnicas.
* **.github/**: CI, actualización de dependencias y reglas de automatización.

---

## 📦 Preparación para Nixpkgs

Las recetas candidatas de Nori están en `nixpkgs/pkgs/by-name/no/` y son las mismas que usan Elytra y Titan. Ambas incluyen `passthru.updateScript = nix-update-script { };`, para que el actualizador comunitario de Nixpkgs pueda proponer nuevas versiones una vez fusionado el paquete oficial.

El primer envío requiere una PR a `NixOS/nixpkgs` con las dos recetas y una entrada de mantenedor. Este repositorio prepara y compila los paquetes, pero no publica directamente dentro de Nixpkgs. Los artefactos oficiales actuales son binarios precompilados, por lo que sus metadatos indican `binaryNativeCode`.

Validación local:

```bash
nix build --no-link .#nori
nix build --no-link .#nori-cli
```

## 🧰 Herramientas y entornos de desarrollo

Elytra y Titan tienen disponibles globalmente los básicos de Python y Rust:
`python3`, `pip`, `uv`, `ruff`, `rustc`, `cargo`, `rust-analyzer`,
`rustfmt` y `clippy`. También incluyen `gcc`, `clang`, `mold`,
`pkg-config`, `cmake` y `gnumake` para compilar dependencias nativas.
La versión de Rust procede del `nixpkgs` fijado en `flake.lock` (actualmente
1.99.1) y el módulo comprueba que sea al menos 1.95.

Los devShells siguen ofreciendo entornos aislados y reproducibles por proyecto.
Node/Bun, Go y Java continúan activándose bajo demanda desde la raíz del
repositorio con los devShells del flake:

```bash
nix develop .#python  # Python, uv, Ruff y MkDocs
nix develop .#node    # Node.js 24, pnpm y Bun
nix develop .#go      # Go
nix develop .#rust    # Rust, Cargo, rust-analyzer, rustfmt y Clippy
nix develop .#java    # JDK 21, Gradle y Kotlin
```

Al salir del shell con `exit`, el entorno del proyecto deja de estar activo.
Para trabajar automáticamente al entrar en el directorio, el repositorio ya
incluye direnv + nix-direnv en el módulo común; puedes usar `direnv allow`
cuando el proyecto tenga un archivo `.envrc` con `use flake .#python`,
`use flake .#node`, etc.

## 🤖 OpenCode en los escritorios

**Elytra y Titan instalan tanto OpenCode CLI como OpenCode Desktop** desde el módulo compartido `modules/desktop/`. No hay diferencias por host: puedes trabajar desde Fish/terminal o abrir la interfaz gráfica en cualquiera de los dos equipos.

- `opencode`: CLI para terminal, scripts y sesiones rápidas.
- `opencode-desktop`: aplicación gráfica para gestionar sesiones, revisar cambios y trabajar con proyectos mediante su interfaz.

Los dos paquetes pueden coexistir: usan ejecutables distintos y Nixpkgs construye Desktop reutilizando la misma versión fijada del paquete `opencode`. Instalar Desktop no mantiene Electron ejecutándose en segundo plano; el consumo adicional de memoria aparece cuando abres la interfaz.

El módulo compartido activa `NIXOS_OZONE_WL` para que Electron utilice Ozone nativo en las sesiones Plasma Wayland de ambos equipos. No se añaden inputs ni repositorios externos.

## 🖥️ RustDesk en los escritorios

El cliente estándar `rustdesk-flutter` de Nixpkgs se instala en Elytra y Titan desde `modules/desktop/`. No se configura un servicio de sistema para acceso previo al inicio de sesión, ni la variante unattended/DRM. El relay autoalojado `hbbs`/`hbbr` de Atlas permanece independiente y sin cambios.

## 🏠 Home Manager

Home Manager está integrado como módulo de NixOS: los cambios del entorno personal se aplican junto con `nixos-rebuild switch`.

- `elytra`, `titan` y `palco` utilizan Home Manager `master`, siguiendo `nixpkgs-unstable`.
- `atlas` y `pico` utilizan `release-26.05`, siguiendo `nixpkgs-stable`.
- Las preferencias comunes de Fish y los alias personales se mantienen en `home/juan/`; Fastfetch y los alias de despliegue solo se cargan en los equipos de escritorio.
- Hardware, servicios, permisos, aplicaciones de sistema y configuración de Plasma continúan en los módulos de NixOS.

Después de incorporar los nuevos inputs por primera vez, ejecuta `nix flake lock` desde la raíz del repositorio y revisa/añade el `flake.lock` resultante antes de desplegar:

```bash
nix flake lock
git diff -- flake.lock
git add flake.lock
git commit -m "chore: lock Home Manager inputs"
```

## 🚀 Despliegue remoto del homelab

Atlas y Pico se pueden desplegar desde Elytra o Titan mediante **deploy-rs
1.0.0**. La herramienta construye localmente la configuración y transfiere la
clausura por SSH; los servidores no se utilizan como máquinas de compilación.

Tras fusionar la PR y sincronizar el repositorio, activa primero una vez el
cambio de Home Manager en Elytra o Titan con:

```bash
sudo nixos-rebuild switch --flake .#elytra
```

Cambia `elytra` por `titan` si corresponde. Los alias de despliegue verifican
que `~/nixos` sea un repositorio limpio (incluidos archivos sin seguimiento) y
muestran la rama y el commit exacto antes de ejecutar deploy-rs. No hacen
`fetch`, `pull`, `checkout` ni `commit` automáticos: comprueba tú que estás en el
commit que quieres desplegar.

Comandos disponibles en Fish:

- `nix-deploy-atlas`: despliega Atlas por LAN.
- `nix-deploy-pico`: despliega Pico por LAN.
- `nix-deploy-servers`: despliega por LAN solo los nodos del grupo `homelab` (Atlas y Pico); otros nodos quedan fuera salvo que se asignen expresamente a ese grupo.
- `nix-deploy-atlas --netbird`: resuelve la IP del peer conectado Atlas y
  despliega por NetBird.
- `nix-deploy-pico --netbird`: resuelve la IP del peer conectado Pico y
  despliega por NetBird.

El modo NetBird requiere los comandos `netbird` y `jq`, un peer conectado con
el hostname esperado (`atlas` o `pico`) y una política que permita SSH entrante.
Exige una única IP conectada y cancela si no puede resolverla; no hace
fallback automático a LAN. El comando conjunto sigue usando LAN: despliega
cada servidor por separado para usar NetBird.

Los comandos piden confirmación y sudo para activar el sistema. Se conservan
`nix-up-atlas` y `nix-up-pico` como alternativas con `nixos-rebuild --target-host`.

El despliegue conjunto no es transaccional: si un servidor falla después de
que el otro se haya actualizado, no se revierte automáticamente el que tuvo
éxito. Despliega primero cada servidor por separado.

Los rollbacks automáticos de deploy-rs están desactivados de forma deliberada:
`system.autoUpgrade` puede crear generaciones con `nixos-rebuild` que no incluyen
el helper requerido por Magic Rollback. Consulta [`docs/deploy-rs.md`](docs/deploy-rs.md)
antes de desplegar.

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

### 🗄️ Servidor principal · Atlas (Minisforum UN1250)
```bash
sudo nixos-rebuild switch --flake .#atlas
```

### 🧊 Servidor secundario · Pico (ZimaBlade)
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

Los hosts `atlas` y `pico` tienen `system.autoUpgrade` activado con `operation = "boot"`: se prepara una generación nueva usando las revisiones fijadas en `flake.lock`, pero no se activa en caliente ni se reinicia automáticamente. El flake apunta a `path:/home/juan/nixos`: el timer no ejecuta `git pull` ni sincroniza ese checkout con GitHub. Actualiza la copia local de forma explícita y revisada antes de esperar una nueva generación. Comprueba los registros con `journalctl -u nixos-upgrade.service` y mantén copias de seguridad de los datos persistentes.
---

## 🧹 Mantenimiento y Limpieza

Para liberar espacio sin eliminar todas las generaciones anteriores:

* **Eliminar generaciones antiguas de más de 30 días** (coincide con la política general de `modules/common/system.nix`):
    `sudo nix-collect-garbage --delete-older-than 30d`
* **Optimizar el almacenamiento compartido**:
    `sudo nix-store --optimise`

Nota: `nix-collect-garbage -d` elimina todas las generaciones antiguas, no solo las que tienen más de siete días, y reduce las posibilidades de volver a una generación anterior. En `pico`, la recolección automática del sistema está configurada con un umbral de 7 días.

---

## ✅ Validación automática

GitHub Actions evalúa el `system.build.toplevel` de los cinco hosts, construye las clausuras completas de Atlas y Pico y ejecuta `nix flake check --no-build --show-trace`. También construye las comprobaciones de esquema y activación de deploy-rs. El mismo workflow ejecuta primero formato, análisis estático, tests unitarios del actualizador de Nori, validación de workflows y detección de secretos; solo si todo pasa inicia las cinco evaluaciones NixOS, limitadas a tres trabajos simultáneos. Las recetas Nori se construyen cuando hay una actualización pendiente. Las clausuras completas de los escritorios se evalúan, pero no se construyen en cada PR por su tamaño. Estas comprobaciones no sustituyen las pruebas de hardware, Bluetooth, audio, GPU o contenedores. Consulta [docs/ci-security.md](docs/ci-security.md) para la configuración y protección recomendadas.

La auditoría de decisiones, compromisos y pruebas recomendadas por equipo está en [`docs/performance-stability-audit.md`](docs/performance-stability-audit.md).

La revisión de exposición de red, privilegios Docker y modularización de Atlas está en [`docs/security-review.md`](docs/security-review.md).

## 🔄 Actualización controlada de dependencias

El workflow `Update Flake inputs and container digests` revisa semanalmente los inputs de `flake.lock` y fija mediante SHA-256 las imágenes OCI declaradas en los módulos de Atlas y Pico. Cuando encuentra cambios, abre o actualiza una PR y solicita la validación completa de los cinco hosts. No despliega cambios automáticamente. Consulta [docs/dependency-updates.md](docs/dependency-updates.md) para ejecutarlo manualmente y revisar los cambios.

En Atlas, `nix-maintain` comprueba las releases estables de Arcane Manager y acepta actualizaciones de la misma versión principal tras hacer una copia de seguridad. En Pico, mantiene Arcane Agent alineado con la versión fijada del Manager, también con copia de seguridad local. El agente v3 inicia conexiones salientes hacia Atlas por TCP/3552; no escucha ni publica TCP/3553. Las migraciones mayores se detienen para revisión manual. Consulta [docs/arcane-updates.md](docs/arcane-updates.md) y [docs/arcane-v3-pico.md](docs/arcane-v3-pico.md).

## ⚠️ Notas de configuración
* **Git y Flakes**: los archivos nuevos deben estar añadidos a Git para que un flake basado en Git pueda verlos. Añade solo los archivos necesarios (por ejemplo, `git add modules/nuevo-modulo.nix`); los alias `nix-up` y `nix-update` no deben preparar automáticamente todos tus cambios.
* **NVIDIA**: `elytra` usa una RTX 5050 con PRIME offload; comprueba los controladores y el kernel en el hardware real antes de cambiar de rama.
* **Contenedores**: `elytra` y `titan` habilitan Docker para uso local; `atlas` y `pico` lo utilizan para sus servicios. `palco` es un appliance de audio Bluetooth y no necesita el stack de escritorio.
