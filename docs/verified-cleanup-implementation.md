# Limpieza verificada y cambios que requieren validación en hardware

Este documento acompaña la rama `chore/verified-nixos-cleanup-2026-11`.
Los cambios se limitan a duplicidades o inconsistencias comprobables en el
repositorio. No se despliega ninguna generación desde GitHub.

## Cambios implementados

- Elytra: se retiran las aperturas TCP 1701/9001 de Weylus. No existe paquete,
  servicio ni declaración de Weylus en los módulos/hosts del repositorio; el
  firewall sigue habilitado por el default `networking.firewall.enable = true`
  del pin NixOS, así que se elimina la asignación redundante. Sunshine y los
  demás servicios mantienen sus reglas actuales hasta poder definir una política
  por interfaz que preserve el acceso LAN doméstico.
- Escritorios: los toolchains de Python, Node/Bun, Go y Rust dejan de instalarse
  globalmente en `desktop-gaming.nix`. Se ofrecen en devShells declarados en
  `flake.nix`; Rust añade rustfmt/clippy y Go dispone de un shell propio.
  Los runtimes que aparecen en `programs.nix-ld.libraries` se conservan: esa
  lista sirve a bibliotecas compartidas de binarios externos, no equivale a
  instalar toolchains en el PATH de todos los proyectos.
- Elytra: se eliminan de su lista local `btop`, `lm_sensors`, `pciutils` y
  `usbutils`, ya heredados de `common-system.nix`.
- Escritorios: se elimina `services.pipewire.jack.enable`, deprecado en el pin
  de nixpkgs porque inyecta `LD_LIBRARY_PATH` globalmente. Se conserva la
  compatibilidad JACK instalando el output `pipewire.jack`, que aporta
  `pw-jack`; lanzar clientes JACK como `pw-jack aplicación` limita el entorno
  de bibliotecas al proceso que lo necesita. Así se evita una variable global
  de sesión que afecta a aplicaciones no relacionadas.
  Referencia: [módulo PipeWire del pin](https://github.com/NixOS/nixpkgs/blob/f4a03c008967841f2a0b3cb7c436fc6fc31671f6/nixos/modules/services/desktops/pipewire/pipewire.nix)
  y [salida JACK de PipeWire](https://github.com/NixOS/nixpkgs/blob/f4a03c008967841f2a0b3cb7c436fc6fc31671f6/pkgs/by-name/pi/pipewire/package.nix).
- Elytra y Titan: se retiran declaraciones de microcódigo duplicadas en
  `configuration.nix`; sus `hardware-configuration.nix` ya declaran
  `updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware`.
  Elytra, Atlas y Titan activan `hardware.enableRedistributableFirmware = true`;
  en Titan esto habilita además el microcódigo AMD que hereda del archivo hardware.
  Pico conserva su ajuste explícito porque es distinto del valor heredado.
  Referencia del pin: [all-firmware.nix](https://github.com/NixOS/nixpkgs/blob/f4a03c008967841f2a0b3cb7c436fc6fc31671f6/nixos/modules/hardware/all-firmware.nix).
- Atlas: se corrige el comentario de CPU (el governor declarado es
  `powersave`, no `performance`), se retira la segunda declaración redundante
  de NetworkManager, `LC_ALL` (el locale común ya configura `LANG`) y los
  tmpfiles que recreaban directorios antiguos de Dockge. No se borra ningún
  directorio/dato existente de `/mnt/datos`.
- Atlas y Pico: se deja explícito en los comentarios de `system.autoUpgrade`
  que `path:/home/juan/nixos` apunta a un checkout local y no hace `git pull`.
  El timer no mantiene sincronizado el repositorio con GitHub.
- Atlas y Pico: Technitium DNS se ejecuta como contenedor Docker, no como
  servicio DNS nativo declarado en NixOS. En ambos hosts, INPUT no abre DNS
  porque el Compose compartido publica los puertos mediante Docker bridge.
  Atlas protege en `ATLAS-DOCKER-PRIVATE` DNS 53/tcp+udp y las consolas
  8665/tcp y 53443/tcp. Pico añade la unidad
  `pico-technitium-docker-firewall`, que instala la cadena
  `PICO-TECHNITIUM-PRIVATE` para proteger los mismos puertos desde redes no
  confiables y mantener acceso desde LAN/NetBird. Los Compose no están
  versionados en el flake: el modo bridge se confirmó mediante `docker inspect`
  en Atlas y debe comprobarse en Pico después del despliegue. Si se cambia a
  `network_mode: host`, revisar INPUT porque DOCKER-USER no filtra ese tráfico.
- Atlas y Pico: se quita la asignación sysctl duplicada de `kernel.panic=10`;
  el parámetro de arranque `panic=10` permanece en `server-system.nix`.
- Pico: se elimina la declaración explícita de `nix.settings.trusted-users`.
  El pin de NixOS ya define `[ "root" ]` como valor predeterminado; antes el
  host añadía `juan`, que habría concedido privilegios equivalentes a root.
  La cuenta conserva `wheel` y la administración mediante `sudo`.
- La configuración compartida expresa los umbrales base de earlyoom como
  `lib.mkDefault`; Elytra mantiene 10 % sin recurrir a `mkForce`. El modo
  Gaming de scx-loader es también un default, para que Elytra establezca Auto
  sin prioridad forzada. `vm.max_map_count` ya tiene default `1048576` en el
  módulo sysctl del nixpkgs fijado; se eliminan sus redefiniciones comunes y de
  escritorio. El valor específico heredado del host excluido se preserva en una
  condición de compatibilidad para no modificarlo. La capacidad ZRAM de Titan
  usa asignación normal.
- Atlas deja de pasar `intel_pstate=active`: en el Alder Lake el modo activo
  es el modo predeterminado del driver cuando HWP está disponible; se conserva
  `powersave` como governor solicitado y se verifica HWP/EPP en runtime.
- fastfetch y nix-output-monitor se trasladan del módulo común al de escritorio.
  Fish deja de declararse como paquete explícito porque `programs.fish.enable`
  ya lo añade a `environment.systemPackages`.
- La CI construye las clausuras de Atlas y Pico además de evaluarlas; las
  clausuras de escritorio continúan siendo evaluadas (y las recetas Nori se
  construyen en el job existente) para no forzar builds grandes de IDEs y
  multimedia en cada PR.
- Atlas y Pico: se eliminan de las listas locales algunos paquetes ya heredados
  de `common-system.nix`; también se quita `lm_sensors` de `desktop-gaming.nix`
  porque los escritorios ya lo reciben del módulo común.
- El devShell Python incluye `pip` además de uv, Ruff y MkDocs, para conservar
  el flujo de trabajo disponible anteriormente sin instalarlo globalmente.
- Se elimina el archivo raíz `.conf`, que estaba vacío.
- Se retiran los overlays de OpenCode (el hash que fijaba era idéntico al del
  pin) y Gear Lever. El overlay de Gear Lever copiaba exactamente el
  `makeWrapperArgs` y el `preFixup` de la receta upstream incluida en
  `f4a03c008967841f2a0b3cb7c436fc6fc31671f6`, por lo que no alteraba el paquete.


## Elementos preservados deliberadamente

- No se cambia PPD, thermald, GameMode, scx_cosmos, governor/EPP, turbo ni
  límites de potencia del i5-13450HX. No se implementa un cambio AC/batería
  automático sin confirmar el nombre y los eventos reales del dispositivo de
  alimentación del LOQ, ni el comportamiento de PowerDevil/PPD en la sesión
  Plasma actual.
- Se conservan `hardware.nvidia.powerManagement.finegrained`,
  Dynamic Boost, PRIME offload y la preservación de memoria de vídeo. Se eliminan
  los parámetros de kernel duplicados `nvidia-drm.fbdev=1` y
  `NVreg_PreserveVideoMemoryAllocations=1`: el driver del pin para la rama
  `latest` es 615.78.08, y el módulo NixOS declara modeset/fbdev al habilitar
  PRIME offload y modesetting (driver >=545), además de PreserveVideoMemoryAllocations
  al habilitar powerManagement. La configuración del módulo se traduce a
  `boot.extraModprobeConfig`; no hace falta repetirlos en `boot.kernelParams`.
  Se mantiene `kernelSuspendNotifier`. El dato de RTD3/S0ix no soportado y el
  consumo de reposo previamente medido requieren comprobar el estado del
  controlador y la GPU de nuevo antes de cambiar parámetros de energía.
  Fuente: [versión latest y criterio de selección del driver en el pin](https://github.com/NixOS/nixpkgs/blob/f4a03c008967841f2a0b3cb7c436fc6fc31671f6/pkgs/os-specific/linux/nvidia-x11/default.nix#L25-L42),
  [módulo NVIDIA del nixpkgs fijado](https://github.com/NixOS/nixpkgs/blob/f4a03c008967841f2a0b3cb7c436fc6fc31671f6/nixos/modules/hardware/video/nvidia.nix#L799-L806)
  y [generación de modprobe config](https://github.com/NixOS/nixpkgs/blob/f4a03c008967841f2a0b3cb7c436fc6fc31671f6/nixos/modules/hardware/video/nvidia.nix#L828-L833).
- Se conservan `wifi.powersave = false` y los parámetros rtw89 que desactivan
  PS/ASPM. Se añadieron por estabilidad; habilitar ahorro en batería o cambiar
  ASPM sin una prueba repetible podría reintroducir cortes o latencia.
- No se cambia FastConnectable/Experimental de BlueZ sin medir el consumo ni
  los dispositivos que utilizan ese modo.
- No se cambia el tratamiento de tapa, suspensión, hibernación, brillo,
  refresco, USB/NVMe/PCIe ASPM ni límites de carga. Primero hay que descubrir
  las interfaces disponibles en el firmware/hardware real del LOQ.
- `libz` y `zlib` no son alias ni el mismo paquete en el pin actual:
  `libz` es el fork Sortix libz 1.2.8.2025.03.07 y `zlib` es zlib 1.3.2.
  Se conservan ambos en nix-ld hasta comprobar con `ldd`/ejecución de los
  binarios externos qué SONAME y símbolos necesita cada uno; quitarlos como
  si fueran duplicados sería una suposición incorrecta.
- No se migra NetworkManager a systemd-networkd en Atlas/Pico: ambos dependen
  de perfiles de red existentes, NetBird y redes Docker. Una migración necesita
  el inventario de direcciones, rutas, DNS, bridges y método de recuperación
  fuera de banda.
- No se altera todavía la política de firewall de los escritorios. Los servicios
  declarados usan `openFirewall`/puertos globales (Sunshine, Syncthing,
  Avahi, Steam Remote Play, Stremio y KDE Connect). Restringirlos por interfaz
  requiere conocer las interfaces y la conexión/perfil doméstico real; usar
  nombres de interfaz supuestos puede dejar Moonlight, Chromecast o Syncthing
  sin acceso.
- Cloudflare WARP y NetBird siguen habilitados. Hay un informe de NetBird que
  considera no soportado el uso simultáneo por competir por rutas/DNS:
  https://github.com/netbirdio/netbird/issues/672. No se desactiva ninguno sin
  conocer qué tráfico debe ir por cada túnel. Revisar `ip rule`, tablas de
  rutas y DNS antes de tomar una decisión.
- Se conserva SSH por contraseña. El propio módulo común declara que es
  deliberado y el repositorio no contiene una declaración de claves
  `authorized_keys` que permita demostrar que todos los accesos remotos están
  preparados para autenticación por clave. Deshabilitar password auth a ciegas
  puede bloquear el acceso a Atlas/Pico.
- Se conserva `services.earlyoom` en el módulo común. Elytra mantiene umbral
  10 %; Atlas y Pico conservan 5 %. Su impacto en procesos
  de contenedores depende de los `oom_score_adj` y de la carga real; no se
  debe deshabilitar ni cambiar el umbral de Atlas sin capturar eventos bajo
  presión de memoria.
- Atlas mantiene journald limitado por `SystemMaxUse=1G`; Pico mantiene
  `json-file` con rotación. No se unifican drivers sin comparar retención,
  almacenamiento, consulta de logs y consumo real.
- Atlas y Pico fijan Arcane Manager y Edge Agent a `v2.17.3` en vez de
  `:latest`. El `.goreleaser.yaml` de la propia release `v2.17.3` confirma los
  nombres de imagen GHCR y que ambas se etiquetan como `v<versión>`; los builds
  `BUILD_NEXT` usan la etiqueta `next` separada. Se elige la misma release para
  ambos componentes y se evita que una referencia móvil introduzca una versión
  distinta sin revisar el flake. Próximas actualizaciones: copia de seguridad de
  base de datos/volúmenes y datos Arcane; cambiar Manager y Agent juntos, revisar
  changelog/migraciones, construir la generación y desplegar primero Atlas y
  después Pico. No usar `:latest` ni `:next` en estos servicios persistentes.

  Fuentes upstream: [release v2.17.3](https://github.com/getarcaneapp/arcane/releases/tag/v2.17.3),
  [Changelog](https://getarcane.app/changelog) y
  [manifiesto de publicación de imágenes de esa versión](https://github.com/getarcaneapp/arcane/blob/v2.17.3/.goreleaser.yaml).
- Se conserva `postgres:17-alpine`: fija la versión mayor 17 y permite recibir
  revisiones de seguridad dentro de esa rama; cambiar la versión mayor requiere
  una migración separada.
- No se modifican `containerd-snapshotter`, el socket Docker del agente de Pico
  ni los mapeos de puertos de Technitium DNS: sus Compose externos no forman
  parte del flake. El firewall se limita a los puertos publicados conocidos y
  debe revisarse si cambia el Compose. En Pico se elimina `docker0` de
  `trustedInterfaces`: el módulo
  de firewall de NixOS acepta incondicionalmente el tráfico recibido por una
  interfaz marcada como confiable. El agente usa el socket Docker y establece
  una conexión saliente con Atlas, así que no necesita esa excepción; se
  mantiene `wt0` como interfaz confiable para la administración por NetBird.
  Fuente: [opción trustedInterfaces en el módulo NixOS 26.05 fijado](https://github.com/NixOS/nixpkgs/blob/ac588ef1c914865dad517b337ea0eb9694a4021c/nixos/modules/services/networking/firewall.nix#L164-L172). Un bind mount de socket con `:ro` no convierte
  la API Docker en una API de solo lectura; reducir ese permiso requiere un
  proxy con allowlist validada contra las operaciones reales del agente.
- Se conserva el overlay de DwarFS: la receta del pin todavía activa tests y
  el workaround desactiva pruebas que fallaban en el entorno descrito.
- Se conserva el overlay de CardWire: la receta del pin aún no contiene la
  dependencia SQLite añadida por el override local.
- El overlay de Gear Lever se elimina porque la receta upstream del pin ya
  contiene el mismo wrapper y los mismos argumentos.
- Se conserva `rustdesk-privacy.nix`, sus scripts y su documentación: aunque
  el módulo no se importa, el workflow valida la sintaxis de los scripts y el
  README declara expresamente que se mantienen para posible reactivación.
- Se conservan las recetas de Nori en `nixpkgs/pkgs/by-name/no`: son la fuente
  única de receta; `packages/nori*.nix` son adaptadores del flake que las
  importan, no copias divergentes.
- No se cambia la lista de aplicaciones compartida entre Elytra y Titan:
  dos clientes/editores/reproductores pueden ser alternativas intencionales.
  El uso real no se deduce del hecho de que sus paquetes se solapen.

## Elytra: selección declarativa de perfiles AC/batería

Elytra mantiene una sola pila de energía: `power-profiles-daemon` con
`thermald`, ambos declarados en `desktop-gaming.nix`. Home Manager importa
`home/juan/laptop-power.nix` solo desde `hosts/portatil/configuration.nix`,
y configura `powerdevilrc` con estas asignaciones:

- AC: `performance`, para permitir el presupuesto completo del equipo cuando
  está conectado.
- Battery: `power-saver`, para priorizar autonomía.
- LowBattery: `power-saver`, para no aumentar consumo cuando queda poca carga.

PowerDevil detecta la fuente de alimentación y selecciona el perfil PPD por
estado. No hace falta añadir TLP, auto-cpufreq, reglas udev ni un servicio
systemd adicional. La configuración usa `qt.kde.settings` del Home Manager
fijado y los grupos KConfig `[AC][Performance]`, `[Battery][Performance]` y
`[LowBattery][Performance]` definidos por KDE.

GameMode continúa separado: al ejecutar un juego puede solicitar el governor
`performance`; al salir vuelve a `powersave`. PowerDevil sigue seleccionando
el perfil PPD según AC/batería. GameMode puede priorizar rendimiento mientras
juegas incluso con batería; al terminar se recupera el governor predeterminado.
Esta configuración no fija PL1/PL2 ni demuestra que la dGPU entre en RTD3:
eso depende del firmware, el driver y de medir el equipo.

Después de activar la generación y entrar en Plasma, comprobar:

```bash
powerprofilesctl list
powerprofilesctl get
grep -n -A1 -F -e '[AC][Performance]' -e '[Battery][Performance]' \
  -e '[LowBattery][Performance]' "$HOME/.config/powerdevilrc"
```

El archivo de configuración de PowerDevil es `~/.config/powerdevilrc`.
Con el cargador conectado, `powerprofilesctl get` debería reflejar
`performance`; al desconectarlo, `power-saver`. Repetir la prueba al conectar
y desconectar AC con el equipo despierto y después de reanudar de suspensión.
Hay reportes de versiones de Plasma que no actualizan el perfil si el cambio
de AC ocurre durante el sueño: comprobarlo antes de dar el comportamiento por
validado en el portátil.

No se fija brillo, refresco, acción de tapa, temporizadores de suspensión ni
umbral de carga: son preferencias y capacidades dependientes del hardware.
PowerDevil permite configurarlas por estado cuando el dispositivo las soporta.

Referencias: [PowerDevil: configuración por estados AC/batería](https://docs.kde.org/stable_kf6/en/powerdevil/kcontrol/powerdevil/),
[KConfig de los perfiles PowerDevil](https://github.com/KDE/powerdevil/blob/master/PowerDevilProfileSettings.kcfg),
[opción `qt.kde.settings` del Home Manager fijado](https://github.com/nix-community/home-manager/blob/82ce401aa350502897c3f2e85f384d61cd3b0b6d/modules/misc/qt/kconfig.nix).

## Comprobaciones necesarias en Elytra antes de diseñar perfiles AC/batería

Ejecutar y guardar la salida con cargador conectado y desconectado:

```bash
for p in /sys/class/power_supply/*; do
  printf '\n[%s] ' "$p"
  cat "$p/type" 2>/dev/null || true
  for f in online status capacity power_now energy_now; do
    [ ! -r "$p/$f" ] || { printf '%s=' "$f"; cat "$p/$f"; }
  done
done
sudo udevadm monitor --kernel --property --subsystem-match=power_supply
upower -e
powerprofilesctl list
systemctl status power-profiles-daemon thermald --no-pager

grep -H . /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null | head
grep -H . /sys/devices/system/cpu/intel_pstate/{status,no_turbo,max_perf_pct,min_perf_pct} 2>/dev/null
cpupower frequency-info

nvidia-smi -q -d POWER
nvidia-smi --query-gpu=name,pstate,power.draw,utilization.gpu --format=csv
lspci -nnk | grep -A4 -E 'VGA|3D|Display'
for d in /sys/bus/pci/devices/*; do
  [ -r "$d/power/runtime_status" ] || continue
  printf '%s ' "$d"; cat "$d/power/runtime_status"
done

nmcli -f DEVICE,TYPE,STATE,CONNECTION device
iw dev
modinfo rtw89_pci | grep -E 'disable_aspm|parm'
modinfo rtw89_core | grep -E 'disable_ps_mode|parm'
grep -H . /sys/module/rtw89_{pci,core}/parameters/* 2>/dev/null
find /sys/class/power_supply /sys/devices/platform -type f \
  \( -iname '*charge*' -o -iname '*threshold*' \) -print 2>/dev/null
lsmod | grep -E 'ideapad|thinkpad|lenovo|wmi'
```

Medir autonomía y estabilidad con el mismo brillo, refresco, carga y ubicación:
registrar descarga en W, desconexiones Wi-Fi, latencia/pérdida y eventos del
kernel durante un periodo comparable. No habilitar ahorro de Wi-Fi ni ASPM
hasta que la prueba confirme que no reaparecen fallos. Para Dynamic Boost,
comparar una carga CPU+GPU repetible en AC; no se deduce su eficacia de la
lectura en reposo.

## Comprobaciones de red antes de cerrar puertos

En Elytra y Titan:

```bash
sudo ss -lntup
sudo nft list ruleset
nmcli -f NAME,TYPE,DEVICE connection show
nmcli -f GENERAL.DEVICE,GENERAL.STATE,GENERAL.CONNECTION device show
ip -br address
ip rule
ip route show table all
ip -6 route show table all
resolvectl status
netbird status -d
warp-cli status
```

Comprobar desde otro dispositivo de la LAN doméstica que siguen accesibles
Moonlight/Sunshine, Syncthing, KDE Connect, Chromecast/Stremio y los servicios
que realmente se utilicen. Repetir desde un punto de acceso externo para
confirmar que no se exponen servicios innecesarios. No usar solo `nmap
localhost`: no representa el firewall de entrada visto desde otra máquina.

Después de desplegar en Pico, verificar el contenedor y la cadena de Technitium:

```bash
sudo ss -lntup | grep -E '(:53|:22)\b' || true
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
sudo docker network ls
sudo iptables -vnL DOCKER-USER
sudo iptables -vnL PICO-TECHNITIUM-PRIVATE
sudo ip6tables -vnL PICO-TECHNITIUM-PRIVATE
```

## Comprobaciones de servidores

Atlas:

```bash
systemctl status earlyoom docker nixos-upgrade.service --no-pager
journalctl -u earlyoom -b --no-pager
docker stats --no-stream
docker info --format 'log-driver={{.LoggingDriver}}'
sudo iptables -vnL DOCKER-USER
sudo ip6tables -vnL DOCKER-USER
systemctl list-timers --all | grep -E 'nixos-upgrade|fstrim'
git -C /home/juan/nixos status --short --branch
git -C /home/juan/nixos rev-parse HEAD
```

Pico:

```bash
df -h /
sudo du -xhd1 /nix /var/lib/docker 2>/dev/null | sort -h
docker info --format 'log-driver={{.LoggingDriver}}'
docker inspect arcane-agent --format '{{json .Mounts}}'
nix show-config | grep -E 'trusted-users|allowed-users'
sudo ss -lntup
```

El socket Docker del Arcane Edge Agent es una capacidad administrativa de alto
impacto; no montar el socket con `:ro` como sustituto de un proxy. Un proxy
solo debe desplegarse cuando su allowlist incluya y se pruebe cada API necesaria
para operaciones del agente (descubrimiento, gestión de contenedores, imágenes,
volúmenes, redes, logs y eventos, según la versión instalada).

## CI y mantenimiento de Actions

El workflow fija `actions/checkout` v6 y `cachix/install-nix-action` v31.11.3
por SHA completo. Checkout v6 usa Node 24; `persist-credentials = false` evita
dejar el token de checkout disponible después de la descarga. El runner tiene
que ser compatible con v6 (v2.329.0 o posterior). Dependabot revisa semanalmente
las Actions y propone PRs con nuevos SHAs, en vez de depender de etiquetas de
versión mutables.

## Build, cache y despliegue

La CI evalúa los cinco toplevels y construye las clausuras completas de Atlas y
Pico, además de construir Nori cuando cambian sus recetas. No construye las
clausuras completas de escritorio en cada PR: los escritorios tienen grandes clausuras
(Android Studio, IDEs, multimedia y gaming) y un build simultáneo puede superar
tiempo o memoria del runner. Para una prueba completa, construir el host que se
va a desplegar en un runner/estación con recursos suficientes:

```bash
nix flake check --no-build --show-trace
nix build --no-link --show-trace .#nixosConfigurations.elytra.config.system.build.toplevel
# Repetir cambiando el host por titan, atlas o pico.
```

Nix usa `https://cache.nixos.org` como caché binaria predeterminada. No se añade
un substituter privado ni un token Cachix a este repositorio; solo tiene sentido
cuando exista una caché propia que publique cierres de paquetes locales (por
ejemplo Nori) o builds de sistema de manera deliberada.

El timer `system.autoUpgrade` de Atlas/Pico no hace sincronización Git. Antes de
esperar que prepare una generación nueva, actualizar/revisar el checkout local,
comprobar el hash de Git y después revisar `journalctl -u nixos-upgrade.service`.
Los helpers Fish `nix-up-atlas` y `nix-up-pico` primero ejecutan
`nixos-rebuild build --flake .#host` localmente; si el build falla, abortan y no
ejecutan el `switch --target-host`. El cambio remoto solo comienza después de
un build satisfactorio del toplevel correspondiente.

## Fuera de alcance

No se modifica ninguna configuración ni archivo que pertenezca solo a Palco.
Los elementos de Palco enumerados en la solicitud permanecen como candidatos
para una posible limpieza separada. Tampoco se elimina RustDesk Privacy ni se
borra ningún dato persistente de Dockge/Arcane.
 \
  ~/.config/powerdevilrc
```

El fichero que escribe KDE es `~/.config/powerdevilrc`. Para comprobar el
perfil realmente seleccionado tras enchufar/desenchufar, ejecutar
`powerprofilesctl get` en ambos estados y revisar el log de
`plasma-powerdevil.service` si no cambia. Probar también después de reanudar
de suspensión; existen versiones de Plasma con incidencias al procesar un cambio
de AC ocurrido mientras el equipo duerme.

No se fija brillo, refresco, acción de tapa, temporizadores de suspensión ni
umbral de carga: son preferencias/hardware dependientes. PowerDevil ya permite
configurarlas por estado cuando el dispositivo las soporta.

Referencias: [PowerDevil: configuración por estados AC/batería](https://docs.kde.org/stable_kf6/en/powerdevil/kcontrol/powerdevil/),
[KConfig de los perfiles PowerDevil](https://github.com/KDE/powerdevil/blob/master/PowerDevilProfileSettings.kcfg),
[opción qt.kde.settings del Home Manager fijado](https://github.com/nix-community/home-manager/blob/82ce401aa350502897c3f2e85f384d61cd3b0b6d/modules/misc/qt/kconfig.nix).

## Comprobaciones necesarias en Elytra antes de diseñar perfiles AC/batería

Ejecutar y guardar la salida con cargador conectado y desconectado:

```bash
for p in /sys/class/power_supply/*; do
  printf '\n[%s] ' "$p"
  cat "$p/type" 2>/dev/null || true
  for f in online status capacity power_now energy_now; do
    [ ! -r "$p/$f" ] || { printf '%s=' "$f"; cat "$p/$f"; }
  done
done
sudo udevadm monitor --kernel --property --subsystem-match=power_supply
upower -e
powerprofilesctl list
systemctl status power-profiles-daemon thermald --no-pager

grep -H . /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null | head
grep -H . /sys/devices/system/cpu/intel_pstate/{status,no_turbo,max_perf_pct,min_perf_pct} 2>/dev/null
cpupower frequency-info

nvidia-smi -q -d POWER
nvidia-smi --query-gpu=name,pstate,power.draw,utilization.gpu --format=csv
lspci -nnk | grep -A4 -E 'VGA|3D|Display'
for d in /sys/bus/pci/devices/*; do
  [ -r "$d/power/runtime_status" ] || continue
  printf '%s ' "$d"; cat "$d/power/runtime_status"
done

nmcli -f DEVICE,TYPE,STATE,CONNECTION device
iw dev
modinfo rtw89_pci | grep -E 'disable_aspm|parm'
modinfo rtw89_core | grep -E 'disable_ps_mode|parm'
grep -H . /sys/module/rtw89_{pci,core}/parameters/* 2>/dev/null
find /sys/class/power_supply /sys/devices/platform -type f \
  \( -iname '*charge*' -o -iname '*threshold*' \) -print 2>/dev/null
lsmod | grep -E 'ideapad|thinkpad|lenovo|wmi'
```

Medir autonomía y estabilidad con el mismo brillo, refresco, carga y ubicación:
registrar descarga en W, desconexiones Wi-Fi, latencia/pérdida y eventos del
kernel durante un periodo comparable. No habilitar ahorro de Wi-Fi ni ASPM
hasta que la prueba confirme que no reaparecen fallos. Para Dynamic Boost,
comparar una carga CPU+GPU repetible en AC; no se deduce su eficacia de la
lectura en reposo.

## Comprobaciones de red antes de cerrar puertos

En Elytra y Titan:

```bash
sudo ss -lntup
sudo nft list ruleset
nmcli -f NAME,TYPE,DEVICE connection show
nmcli -f GENERAL.DEVICE,GENERAL.STATE,GENERAL.CONNECTION device show
ip -br address
ip rule
ip route show table all
ip -6 route show table all
resolvectl status
netbird status -d
warp-cli status
```

Comprobar desde otro dispositivo de la LAN doméstica que siguen accesibles
Moonlight/Sunshine, Syncthing, KDE Connect, Chromecast/Stremio y los servicios
que realmente se utilicen. Repetir desde un punto de acceso externo para
confirmar que no se exponen servicios innecesarios. No usar solo `nmap
localhost`: no representa el firewall de entrada visto desde otra máquina.

Después de desplegar en Pico, verificar el contenedor y la cadena de Technitium:

```bash
sudo ss -lntup | grep -E '(:53|:22)\b' || true
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
sudo docker network ls
sudo iptables -vnL DOCKER-USER
sudo iptables -vnL PICO-TECHNITIUM-PRIVATE
sudo ip6tables -vnL PICO-TECHNITIUM-PRIVATE
```

## Comprobaciones de servidores

Atlas:

```bash
systemctl status earlyoom docker nixos-upgrade.service --no-pager
journalctl -u earlyoom -b --no-pager
docker stats --no-stream
docker info --format 'log-driver={{.LoggingDriver}}'
sudo iptables -vnL DOCKER-USER
sudo ip6tables -vnL DOCKER-USER
systemctl list-timers --all | grep -E 'nixos-upgrade|fstrim'
git -C /home/juan/nixos status --short --branch
git -C /home/juan/nixos rev-parse HEAD
```

Pico:

```bash
df -h /
sudo du -xhd1 /nix /var/lib/docker 2>/dev/null | sort -h
docker info --format 'log-driver={{.LoggingDriver}}'
docker inspect arcane-agent --format '{{json .Mounts}}'
nix show-config | grep -E 'trusted-users|allowed-users'
sudo ss -lntup
```

El socket Docker del Arcane Edge Agent es una capacidad administrativa de alto
impacto; no montar el socket con `:ro` como sustituto de un proxy. Un proxy
solo debe desplegarse cuando su allowlist incluya y se pruebe cada API necesaria
para operaciones del agente (descubrimiento, gestión de contenedores, imágenes,
volúmenes, redes, logs y eventos, según la versión instalada).

## CI y mantenimiento de Actions

El workflow fija `actions/checkout` v6 y `cachix/install-nix-action` v31.11.3
por SHA completo. Checkout v6 usa Node 24; `persist-credentials = false` evita
dejar el token de checkout disponible después de la descarga. El runner tiene
que ser compatible con v6 (v2.329.0 o posterior). Dependabot revisa semanalmente
las Actions y propone PRs con nuevos SHAs, en vez de depender de etiquetas de
versión mutables.

## Build, cache y despliegue

La CI evalúa los cinco toplevels y construye las clausuras completas de Atlas y
Pico, además de construir Nori cuando cambian sus recetas. No construye las
clausuras completas de escritorio en cada PR: los escritorios tienen grandes clausuras
(Android Studio, IDEs, multimedia y gaming) y un build simultáneo puede superar
tiempo o memoria del runner. Para una prueba completa, construir el host que se
va a desplegar en un runner/estación con recursos suficientes:

```bash
nix flake check --no-build --show-trace
nix build --no-link --show-trace .#nixosConfigurations.elytra.config.system.build.toplevel
# Repetir cambiando el host por titan, atlas o pico.
```

Nix usa `https://cache.nixos.org` como caché binaria predeterminada. No se añade
un substituter privado ni un token Cachix a este repositorio; solo tiene sentido
cuando exista una caché propia que publique cierres de paquetes locales (por
ejemplo Nori) o builds de sistema de manera deliberada.

El timer `system.autoUpgrade` de Atlas/Pico no hace sincronización Git. Antes de
esperar que prepare una generación nueva, actualizar/revisar el checkout local,
comprobar el hash de Git y después revisar `journalctl -u nixos-upgrade.service`.
Los helpers Fish `nix-up-atlas` y `nix-up-pico` primero ejecutan
`nixos-rebuild build --flake .#host` localmente; si el build falla, abortan y no
ejecutan el `switch --target-host`. El cambio remoto solo comienza después de
un build satisfactorio del toplevel correspondiente.

## Fuera de alcance

No se modifica ninguna configuración ni archivo que pertenezca solo a Palco.
Los elementos de Palco enumerados en la solicitud permanecen como candidatos
para una posible limpieza separada. Tampoco se elimina RustDesk Privacy ni se
borra ningún dato persistente de Dockge/Arcane.
