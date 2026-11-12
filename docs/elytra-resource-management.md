# Gestión de recursos de Elytra

Auditoría específica de **Elytra** (Lenovo LOQ Essential 15IRX11, Intel Core i5-13450HX, RTX 5050 Laptop, 16 GiB RAM, NixOS 26.11). Los cambios de este documento se limitan al portátil; Titan y los servidores conservan su configuración.

La prioridad es mantener el escritorio KDE/Wayland fluido mientras se usan navegador, herramientas de desarrollo, compilaciones y juegos. Los registros del 12 de noviembre de 2026 sirven como línea base, no como prueba de que una única pieza sea la causa de todos los bloqueos.

## Cambios de esta revisión

### 1. Nix: ejecutar compilaciones como carga de fondo

En `hosts/portatil/configuration.nix`:

```nix
nix.settings = {
  max-jobs = 2;
  cores = 2;
};

nix.daemonCPUSchedPolicy = "idle";
```

Antes Elytra permitía 4 derivaciones simultáneas y solicitaba 2 cores por derivación: hasta 8 cores de build para los builders que respetasen `NIX_BUILD_CORES`. Ahora se limita a 2 derivaciones y 2 cores por derivación: 4 cores solicitados como máximo.

Además, `nix.daemonCPUSchedPolicy = "idle"` hace que el daemon y sus procesos de compilación hereden la política de CPU `SCHED_IDLE`. El módulo de NixOS documenta expresamente este modo para equipos de escritorio y portátiles con periodos puntuales de compilación: los builds ceden CPU a las tareas interactivas. La contrapartida es que pueden tardar más si el equipo mantiene una carga interactiva continua.

No es una cuota rígida: `cores` se traduce en `NIX_BUILD_CORES`, y cada builder debe respetar esa sugerencia. `max-jobs` sí limita cuántas derivaciones se ejecutan en paralelo.

Referencias:
- https://nix.dev/manual/nix/2.34/advanced-topics/cores-vs-jobs.html
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/system/nix-daemon.nix

### 2. sched-ext / scx_cosmos: conservar el scheduler, con vigilancia

El módulo compartido activa `services.scx-loader` y selecciona `scx_cosmos`; Elytra utiliza el modo `Auto` desde `hosts/portatil/configuration.nix`. No se desactiva en esta revisión.

Hay una incidencia upstream de `scx_cosmos` (#3247) que registró un `runnable task stall` y un hilo de KWin ejecutándose con clase real-time. El mantenedor explicó que el servidor de deadlines de sched_ext del kernel 7.0 mitigaba ese caso. En el `flake.lock` actual de este repositorio, `linuxPackages_latest` resuelve a Linux 7.3, por lo que esa incidencia concreta no justifica retirar ahora sched-ext. Esto no garantiza que cualquier versión o configuración de sched-ext esté libre de regresiones.

Si vuelve a haber una congelación, hay que conservar el journal de `scx_loader` y buscar mensajes `runnable task stall`, reinicios del scheduler o avisos del watchdog antes de atribuir el problema a ZRAM o a NVIDIA.

Referencias:
- https://github.com/sched-ext/scx/issues/3247
- https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_cosmos/README.md
- https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/linux-kernels.nix

### 3. ZRAM: conservarla hasta tener evidencia contraria

Elytra tiene `zramSwap.enable = true`, algoritmo `zstd`, una capacidad lógica máxima predeterminada del 50 % (8 GiB) y ningún dispositivo de swap en disco (`swapDevices = [ ]`). Ese 50 % es un límite lógico; no reserva 8 GiB de RAM física al arrancar.

En el informe aportado se observaron aproximadamente 3,3 GiB de datos almacenados en ZRAM y 935 MiB comprimidos. La presión de memoria PSI era 0 en la captura y quedaban unos 3,4 GiB disponibles. No estaba cerca de la capacidad máxima lógica y no hay evidencia de que ZRAM estuviera provocando presión sostenida en ese momento.

Desactivarla ahora dejaría a Elytra sin swap. Con 16 GiB y cargas de desarrollo, navegador y emuladores, eso podría adelantar situaciones de OOM en lugar de resolver los bloqueos. Se conserva `zstd`, el límite del 50 %, `vm.swappiness = 100` y `vm.page-cluster = 0`. No se cambia el algoritmo o la política de intercambio sin comparar presión de memoria, latencia y compresión durante una carga reproducible.

Referencia: https://docs.kernel.org/admin-guide/blockdev/zram.html

## Decisiones que se mantienen

| Área | Configuración | Motivo |
|---|---|---|
| earlyoom | Umbrales locales de 10 % para memoria y swap | Mantener margen para actuar antes de una situación crítica; no se observaron kills en el informe |
| systemd-oomd | Política existente | PSI de memoria a cero en la captura; no hay base para hacerla más agresiva |
| ZRAM | zstd, máximo lógico 50 % | Hay uso real de swap comprimido y no existe swap en disco |
| Swappiness / page-cluster | 100 / 0 | Ajustes coherentes con swap comprimido; no se han medido beneficios de alterarlos |
| Nix builds | 2 trabajos × 2 cores solicitados + `SCHED_IDLE` | Priorizar la respuesta del escritorio durante `nix-maintain` |
| Scheduler | `scx_cosmos`, modo `Auto` | El kernel fijado es 7.3; se conserva y se vigila el watchdog |
| Kernel | `linuxPackages_latest` | Mantener el soporte de hardware reciente; la revisión del lockfile resuelve a 7.3 |
| NVIDIA | PRIME offload y Dynamic Boost | No se ha demostrado un problema de potencia sostenida ni de temperatura |
| Térmicas | thermald + perfiles PowerDevil | CPU a unos 64 °C en la captura, sin evidencia de throttling |

### Por qué no se cambia systemd-oomd

El diagnóstico anterior mostró PSI de memoria a cero y no registró eventos OOM/OOM-kill. Las unidades de la sesión tenían vigilancia de presión de memoria, pero no se observó el umbral mantenido necesario para que systemd-oomd actuara. Se conserva la política actual en vez de terminar procesos de forma más agresiva.

## Hallazgos del diagnóstico del 12 de noviembre de 2026

- **Waterfox fue el proceso más llamativo.** Un proceso `WebExtensions` rondaba 4,2 GiB RSS y aproximadamente el 37 % de un core lógico; otros procesos de Waterfox también consumían CPU y memoria. El porcentaje de `ps` es por core, no porcentaje de toda la CPU del equipo. Esto merece revisión desde `about:processes` y `about:memory`; no se modifica la configuración del navegador a ciegas ni se atribuye el consumo a una extensión sin identificarla.
- **RAM/ZRAM:** había memoria disponible y PSI de memoria a cero. El uso de ZRAM no demuestra por sí mismo thrashing.
- **CPU:** la temperatura del paquete rondaba 64 °C, sin señal clara de throttling térmico en esa muestra.
- **NVIDIA:** la RTX 5050 estaba en P8 con unos 3,5 W en reposo; el límite actual reportado era 50 W (por defecto 35 W, máximo 65 W). No estaba demostrado que se quedase bloqueada en 35 W. Los avisos ACPI/SBIOS del arranque no bastan para justificar overrides de ACPI, cambios de límites de potencia o parámetros forzados.
- **Almacenamiento:** la raíz estaba al 83 % con unos 76 GB libres. Las muestras no mostraron espera de E/S sostenida que justifique cambiar ahora la optimización del almacén Nix.

Estos datos son una captura puntual. Para encontrar la causa de un bloqueo hay que repetir la recogida mientras ocurre y conservar los registros del kernel y del scheduler.

## Recogida de datos si vuelve a ocurrir

Ejecutar durante la carga problemática:

```sh
zramctl
swapon --show
free -h
vmstat 1
cat /proc/pressure/cpu
cat /proc/pressure/memory
cat /proc/pressure/io
cat /sys/kernel/sched_ext/state
systemctl show nix-daemon.service -p CPUSchedulingPolicy
systemctl status scx_loader.service earlyoom.service systemd-oomd.service
journalctl -b -k -g 'sched_ext|runnable task stall|NVRM|Xid|oom|Out of memory|i915' --no-pager
journalctl -b -u scx_loader.service -u nix-daemon.service --no-pager
```

En Waterfox, abrir `about:processes` y ordenar por CPU y memoria. Anotar la pestaña o extensión asociada al proceso que crece; no basta con mirar el consumo total del navegador.

Para comparar el cambio de Nix, repetir el mismo mantenimiento con las mismas entradas del flake. Registrar duración, respuesta del escritorio, CPU, memoria disponible y PSI. La configuración reduce la concurrencia y baja la prioridad de las compilaciones; no promete que una aplicación con un proceso descontrolado deje de consumir recursos.

## Pendiente de medir

- Identificar qué pestaña o extensión provoca el uso elevado de Waterfox.
- Comparar latencia y frametimes con el mismo juego y escena, sin cambiar simultáneamente scheduler, GameMode o perfil energético.
- Medir el uso de ZRAM y PSI durante una compilación que reproduzca el problema.
- Comprobar el límite de potencia de NVIDIA bajo una carga CPU+GPU sostenida, no solo en reposo.
- Medir consumo y autonomía del Wi-Fi antes de retirar las opciones de ahorro/ASPM de rtw89.

## Alcance

- Cambios de configuración limitados a Elytra.
- Titan conserva sus límites de build, su scheduler y su configuración de ZRAM.
- No se alteran los límites de potencia NVIDIA, ACPI, kernel parameters de memoria, extensiones de Waterfox ni los parámetros de OOM sin evidencia reproducible.
- No se ejecuta `nixos-rebuild switch` ni se despliega automáticamente.
