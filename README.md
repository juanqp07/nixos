# ❄️ Configuración NixOS de Juan (Flakes)

Este repositorio contiene la configuración centralizada de cinco equipos, gestionada mediante **Nix Flakes**. Incluye dos servidores del homelab (`atlas` y `pico`), dos equipos de escritorio (`elytra` y `titan`) y una Raspberry Pi dedicada a audio (`palco`).

## 📂 Estructura del Repositorio

* **flake.nix**: Punto de entrada que define los hosts, las dependencias fijadas y los despliegues remotos de Atlas y Pico.
* **hosts/**: Configuraciones específicas de hardware.
    * `portatil/` (elytra): Laptop i5-13450HX (Raptor Lake HX) + NVIDIA RTX 5050 Max-Q / UHD integrada (PRIME offload).
    * `torre/` (titan): PC Ryzen 5 5600X + RX 6700 XT 12GB + 32GB RAM (AMD nativo).
    * `servidor/` (**atlas · servidor principal**): Minisforum UN1250 con Intel Core i5-1250P y 32GB RAM; servidor headless para Docker y servicios del homelab.
    * `zimablade/` (**pico · servidor secundario**): ZimaBlade con Intel Celeron N3450 (Apollo Lake); servidor headless para Docker y Arcane Edge Agent, administrado desde Atlas.
    * `rpi4-bt/` (palco): Raspberry Pi 4B 8GB headless, receptor Bluetooth A2DP → jack 3.5mm (aarch64).
**Atlas y Pico son los dos servidores del homelab.** Ambos ejecutan NixOS sin entorno gráfico, usan Docker y tienen NetBird (interfaz `wt0`) y OpenSSH para administración remota. Atlas es el servidor principal (Minisforum UN1250); Pico es el servidor secundario (ZimaBlade).

* **modules/**: Módulos reutilizables y módulos específicos de host.
    * `common-system.nix`: Configuración base, idioma, herramientas CLI y mantenimiento.
    * `desktop-gaming.nix`: Entorno Plasma 6, Steam, audio, virtualización y aplicaciones de escritorio.
    * `server-system.nix`: Ajustes comunes de kernel y memoria para los servidores.
    * `atlas-docker.nix`: Docker, Arcane, proxy de socket y política DOCKER-USER exclusivos de Atlas.
    * `palco-audio.nix`: BlueZ + PipeWire/WirePlumber y DSP para la Raspberry Pi.
    * `home-manager.nix`: Integración de Home Manager con NixOS.
* **packages/**: accesos a los paquetes externos preparados para NixOS.
    * `nori.nix` y `nori-cli.nix`: reutilizan las expresiones candidatas para Nixpkgs, evitando mantener dos recetas distintas.
* **nixpkgs/pkgs/by-name/no/**: expresiones listas para proponer en Nixpkgs.
    * `nori/package.nix`: Nori Desktop 0.9.0 desde el AppImage oficial y con WebKitGTK 4.1.
    * `nori-cli/package.nix`: Nori CLI 0.9.0 desde el tarball oficial y con ALSA/WebKitGTK.
* **home/juan/**: Configuración personal compartida con Home Manager.
    * `default.nix`: Versión inicial de estado y módulos comunes del usuario.
    * `fish.nix`: Fish, saludo y alias personales de mantenimiento.
    * `desktop.nix`: Fastfetch, comandos de deploy-rs y alternativas de despliegue remoto exclusivas de Elytra y Titan.

---

## 📦 Preparación para Nixpkgs

Las recetas candidatas de Nori están en `nixpkgs/pkgs/by-name/no/` y son las mismas que usan Elytra y Titan. Ambas incluyen `passthru.updateScript = nix-update-script { };`, para que el actualizador comunitario de Nixpkgs pueda proponer nuevas versiones una vez fusionado el paquete oficial.

El primer envío requiere una PR a `NixOS/nixpkgs` con las dos recetas y una entrada de mantenedor. Este repositorio prepara y compila los paquetes, pero no publica directamente dentro de Nixpkgs. Los artefactos oficiales actuales son binarios precompilados, por lo que sus metadatos indican `binaryNativeCode`.

Validación local:

```bash
nix build --no-link .#nori
nix build --no-link .#nori-cli
```

## 🧰 Entornos de desarrollo

Los toolchains de los proyectos no se instalan globalmente en los escritorios.
Se activan bajo demanda desde la raíz del repositorio con los devShells del
flake, que usan las versiones fijadas en `flake.lock`:

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

## 🖥️ RustDesk en los escritorios

El cliente estándar `rustdesk-flutter` de Nixpkgs se instala en Elytra y Titan desde `modules/desktop-gaming.nix`. No se configura un servicio de sistema para acceso previo al inicio de sesión, ni la variante unattended/DRM. El relay autoalojado `hbbs`/`hbbr` de Atlas permanece independiente y sin cambios.

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
- `nix-deploy-servers`: despliega ambos servidores por LAN.
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

* **Eliminar generaciones antiguas de más de 30 días** (coincide con la política general de `common-system.nix`):
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

## ⚠️ Notas de configuración
* **Git y Flakes**: los archivos nuevos deben estar añadidos a Git para que un flake basado en Git pueda verlos. Añade solo los archivos necesarios (por ejemplo, `git add modules/nuevo-modulo.nix`); los alias `nix-up` y `nix-update` no deben preparar automáticamente todos tus cambios.
* **NVIDIA**: `elytra` usa una RTX 5050 con PRIME offload; comprueba los controladores y el kernel en el hardware real antes de cambiar de rama.
* **Contenedores**: `elytra` y `titan` habilitan Docker para uso local; `atlas` y `pico` lo utilizan para sus servicios. `palco` es un appliance de audio Bluetooth y no necesita el stack de escritorio.
