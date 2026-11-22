# Auditoría de rendimiento y estabilidad por host

**Revisión:** 29 de octubre de 2026  
**Alcance:** revisión estática del flake y de sus cinco hosts. No se ha accedido a las máquinas en ejecución ni se han medido FPS, latencias, consumo, temperaturas, transcodificación o cortes de audio. Por eso este documento separa los ajustes respaldados por documentación de los que necesitan una prueba física.

## Cambios aplicados en esta revisión

### Política común de memoria con zram

Los cinco hosts activan zram. La configuración común usa ahora `vm.swappiness = 100` y `vm.page-cluster = 0`, en lugar de combinar un valor 10 en el módulo común con 180 en escritorio y 100 en servidores.

- El kernel documenta que 100 trata el coste relativo de swap y de recuperar páginas de archivos como equivalente.
- Para zram pueden ser razonables valores por encima de 100, pero el propio kernel señala que el valor óptimo depende de la carga. No hay base para afirmar que 180 sea mejor para todos los equipos.
- `page-cluster = 0` evita la lectura anticipada de páginas de swap; zram es memoria comprimida, no una unidad de disco secuencial.

Fuentes: [documentación del kernel: VM sysctl](https://docs.kernel.org/admin-guide/sysctl/vm.html).

### Mitigaciones de CPU en los equipos gaming

Se ha eliminado `mitigations=off` de `elytra` y `titan`. El comentario que sugería una ganancia fija del 5–15 % no era una promesa que pudiera sostenerse para todas las cargas. Desactivar mitigaciones puede afectar al rendimiento en ciertos escenarios, pero también reduce protecciones frente a determinadas vulnerabilidades. La configuración base deja las mitigaciones que proporciona el kernel activadas.

Si en algún juego concreto se quiere valorar el compromiso, hay que comparar con el mismo juego, escena, resolución y perfil energético, y aceptar conscientemente el coste de seguridad; no debe presentarse como una optimización universal.

### Actualizaciones Flatpak en escritorio

`nix-flatpak` separa `update.onActivation` de las actualizaciones periódicas. Ahora los cambios de NixOS no intentan descargar actualizaciones Flatpak cada vez que se ejecuta `nixos-rebuild switch`; las aplicaciones se actualizan con un temporizador semanal.

Esto hace las activaciones más previsibles y menos dependientes de que haya conexión en ese instante. Las aplicaciones Flatpak viven fuera del almacén generacional de Nix, de modo que revertir una generación de NixOS no revierte automáticamente una actualización de Flatpak.

Fuente: [documentación oficial de nix-flatpak](https://github.com/gmodena/nix-flatpak#updates).

### ZimaBlade / Intel Apollo Lake

`pico` utiliza un Celeron N3450 con gráfica Intel Gen9 (Apollo Lake). Se cambia `intel-compute-runtime` por `intel-compute-runtime-legacy1` en la configuración de OpenCL. La documentación actual de NixOS/Nixpkgs y la de Intel especifican que Gen8, Gen9 y Gen11 necesitan la variante `legacy1`; el runtime normal se limita a Gen12 y posteriores.

Esto corrige la elección del runtime de cómputo. No demuestra por sí solo que toda ruta VA-API funcione en el host: verificarla con `vainfo` y la aplicación que consuma vídeo sigue siendo necesario. Si ningún servicio necesita OpenCL, se puede retirar el runtime en una revisión posterior.

Fuentes: [notas de lanzamiento de NixOS](https://nixos.org/manual/nixos/unstable/release-notes), [Intel Compute Runtime: plataformas legacy](https://github.com/intel/compute-runtime#legacy-platforms).

### Diagnóstico gráfico en servidores ligeros

En `atlas` y `pico`, los paquetes de GPU extra se centran en los runtimes de vídeo/cómputo necesarios. Se quitan de `hardware.graphics.extraPackages` paquetes genéricos o de diagnóstico que no son controladores extra (Mesa base, firmware, Vulkan loader/tools), y se añade `libva-utils` a las herramientas de sistema para que `vainfo` esté disponible en ambos hosts. Esto reduce la mezcla entre bibliotecas de ejecución y herramientas CLI sin cambiar el perfil de transcodificación.

La presencia de `vainfo` no garantiza que el contenedor tenga acceso a `/dev/dri`: hay que ejecutar la prueba en el host y dentro del contenedor que hace la transcodificación cuando corresponda.

### Límites de recursos y estabilidad compartida

- **Compilaciones Nix:** presupuesto específico: `elytra` 2 trabajos × 2 cores solicitados y `titan` 6 × 2; ambos ejecutan el daemon con política `SCHED_IDLE` para ceder CPU a las tareas interactivas. `atlas` usa 3 × 2, `pico` 1 × 1 y `palco` 1 × 1. La política puede alargar las compilaciones si hay carga interactiva continua. `cores` es una sugerencia (`NIX_BUILD_CORES`), no una cuota CPU rígida.
- **SSH:** `MaxAuthTries = 3` y `LoginGraceTime = 30s`. La contraseña y la prohibición de acceso SSH directo como root se mantienen para no perder la administración remota antes de desplegar y comprobar claves en todos los hosts.
- **Escritorios:** Fail2ban para el servicio SSH y registros persistentes limitados a 512 MiB/2 semanas.
- **RustDesk en los escritorios:** se instala el cliente estándar `rustdesk-flutter` de Nixpkgs en Elytra y Titan. No se añade un servicio de sistema para acceso previo al login ni se activa la variante unattended/DRM. El relay autoalojado `hbbs`/`hbbr` de Atlas permanece independiente.
- **Atlas:** registros limitados a 1 GiB/2 semanas (Docker usa journald como backend).
- **Pico:** registros limitados a 256 MiB/1 semana y TRIM periódico para dispositivos que lo soporten.
- **Palco:** se mantienen el quantum de PipeWire, los perfiles Bluetooth y el DSP. Se han corregido los comentarios: la cadena configurada es compresor → limitador; el comentario anterior afirmaba que había un HPF de 45 Hz que no estaba presente. También se ajusta la descripción del nivel del jack para reflejar el 100 % que ya configuraba el servicio.
- **Escritorio:** se han eliminado declaraciones repetidas de paquetes del perfil global sin quitar aplicaciones distintas.

### Red: parámetros conservadores y rutas VPN

El módulo común deja de imponer `cake`, `bbr`, buffers TCP de 16 MiB, `tcp_fastopen` y colas de conexiones elevadas. No se había medido que esos valores beneficiaran a estos equipos. Los valores por defecto del kernel son una base más predecible entre un portátil con VPN, una torre gaming, dos servidores y una Pi de audio.

La ruta inversa se configura por host y no globalmente:
- `elytra` y `titan` usan `checkReversePath = "loose"` por NetBird/WARP y posibles rutas asimétricas.
- `atlas` y `pico` ya usan modo loose para NetBird.
- `palco`, sin VPN overlay, conserva la política por defecto de NixOS.

El modo loose valida que la dirección origen sea alcanzable por alguna interfaz, pero no exige que la ruta inversa coincida con la interfaz de entrada. Es apropiado para redes con rutas asimétricas, aunque menos estricto que el filtro de ruta inversa estricto. Fuentes: [documentación del kernel](https://docs.kernel.org/networking/ip-sysctl.html) y [opción de firewall de NixOS](https://nixos.org/manual/nixos/unstable/options.html#opt-networking.firewall.checkReversePath).

## Decisiones por host

### `elytra` — portátil, Intel + RTX 5050 Laptop

**Se mantiene:** PRIME offload, módulo de kernel NVIDIA abierto, gestión energética de NVIDIA, aceleración Intel, kernel `linuxPackages_latest`, GameMode y `scx_cosmos`.

- La documentación de NixOS indica que las GPU Blackwell deben usar los módulos abiertos de NVIDIA; por eso no se cambia `hardware.nvidia.open = true`.
- El selector `hardware.nvidia.branch = "latest"` no significa exclusivamente «rama production»: en nixpkgs elige la más nueva entre las ramas production y new-feature. Se ha corregido el comentario para que no induzca a error.
- Se conserva el kernel más reciente como decisión orientada a hardware gaming reciente, no porque se haya demostrado que dé más FPS. El kernel LTS predeterminado de NixOS es una alternativa razonable si aparecen regresiones; no se cambia sin una prueba con el controlador NVIDIA instalado.
- Los parámetros específicos de Wi-Fi `rtw89` se conservan porque son ajustes de estabilidad ya presentes en la configuración. No se han medido su impacto en batería.
- GameMode y `scx_cosmos` quedan habilitados. `scx_cosmos` se describe upstream como scheduler generalista y listo para producción, pero eso no prueba que supere al scheduler del kernel en cada juego.


Fuentes: [NixOS NVIDIA](https://wiki.nixos.org/wiki/NVIDIA), [NixOS kernel](https://wiki.nixos.org/wiki/Linux_kernel), [scx_cosmos](https://sched-ext.com/docs/scheds/rust/scx_cosmos), [sched_ext en el kernel](https://docs.kernel.org/scheduler/sched-ext.html).

### `titan` — torre Ryzen + RX 6700 XT

**Se mantiene:** `amd_pstate=active`, AMDGPU, OpenCL, LACT/overdrive y `HSA_OVERRIDE_GFX_VERSION=10.3.0`.

- El kernel documenta que `amd_pstate=active` utiliza el driver amd-pstate EPP para enviar al firmware una preferencia de rendimiento/eficiencia cuando la plataforma soporta CPPC. Se conserva; la evaluación del flake no verifica que el firmware esté usando ese modo en tiempo de ejecución.
- `HSA_OVERRIDE_GFX_VERSION` es una anulación de compatibilidad para el runtime HSA/ROCm, no una optimización genérica de FPS. Se conserva porque puede estar relacionada con cargas locales de cómputo. Si una aplicación ROCm detecta la GPU mal, conviene limitar el ajuste a esa aplicación en vez de exportarlo globalmente; primero hay que verificar qué aplicaciones lo usan.
- LACT y overdrive permanecen porque el host los configura explícitamente. No se proponen overclock ni voltajes automáticos sin pruebas de estabilidad y temperatura.

Fuentes: [AMD P-State, documentación del kernel](https://www.kernel.org/doc/html/latest/admin-guide/pm/amd-pstate.html), [guía AMD GPU de NixOS](https://wiki.nixos.org/wiki/AMD_GPU).

### `atlas` — servidor principal, Intel de 12.ª generación y Docker

**Se mantiene:** canal NixOS estable, kernel estable predeterminado, Intel Media Driver, VPL/QSV, monitorización y ZRAM LZ4.

- La combinación `intel-media-driver` + `vpl-gpu-rt` corresponde a la ruta de VA-API/Quick Sync de Intel moderna. Debe comprobarse con `vainfo`, `intel_gpu_top` y una transcodificación real; tener los paquetes instalados no demuestra que Jellyfin o cualquier otro contenedor los esté usando.
- La dependencia de Docker con `/mnt/datos` protege los bind mounts de datos cuando el disco no está montado.
- El límite lógico de ZRAM configurado para este servidor no reserva toda esa RAM de forma inmediata. Aun así, hay que mirar `zramctl`, `free -h` y la carga de contenedores antes de aumentarlo o reducirlo.
- Las actualizaciones preparan una generación usando la configuración y el `flake.lock` presentes en el checkout local. No descargan por sí mismas una nueva revisión del lockfile: para recibir actualizaciones de paquetes, hay que actualizar/revisar el lockfile y sincronizar el repositorio local del servidor.
- El único montaje de datos persistentes declarado para Atlas es `/mnt/datos`. No hay otro punto de montaje de datos pendiente de configurar; no se deben añadir entradas de almacenamiento que no correspondan a un dispositivo real.

Fuentes: [Intel Graphics en NixOS](https://wiki.nixos.org/wiki/Intel_Graphics), [actualizaciones automáticas de NixOS](https://wiki.nixos.org/wiki/Automatic_system_upgrades), [restricciones de recursos de Docker](https://docs.docker.com/engine/containers/resource_constraints).

### `pico` — ZimaBlade, Apollo Lake

**Se mantiene:** kernel estable, ZRAM LZ4 y configuración ligera de servidor.

- El runtime OpenCL se ha corregido a la variante `legacy1` apropiada para Gen9.
- `intel-media-driver` se mantiene, pero el uso real de VA-API depende del motor de vídeo y de los perfiles/codecs que soporte esta GPU. Verificarlo en el host vale más que añadir parámetros a ciegas.
- No se activa SMART automáticamente sin confirmar que el almacenamiento instalado expone datos SMART utilizables; la configuración actual mantiene esa función deshabilitada.
- Las imágenes Docker que siguen usando `latest` deberían fijarse a una versión cuando se busque reproducibilidad estricta, pero hacerlo requiere revisar el flujo de actualizaciones de cada stack.

Fuentes: [Intel Compute Runtime](https://github.com/intel/compute-runtime#legacy-platforms), [restricciones de recursos de Docker](https://docs.docker.com/engine/containers/resource_constraints).

### `palco` — Raspberry Pi 4 como receptor Bluetooth/A2DP

**Se mantiene:** sistema headless, PipeWire/WirePlumber, zram, `socketActivation = false`, `linger = true`, 48 kHz y cuantum conservador con margen hasta 2048.

- NixOS documenta el inicio temprano de PipeWire y WirePlumber, junto con lingering, como solución para dispositivos de audio headless que deben reproducir desde el arranque.
- El cuantum actual prioriza estabilidad sobre una latencia mínima. Reducir el búfer a 32/64 muestras puede aumentar cortes en una Pi que hace DSP; no se propone sin mediciones de underruns.
- El Bluetooth permanece siempre visible/emparejable porque ese es el flujo de uso para los bolos. Eso facilita el uso, pero también permite intentos de conexión cercanos: es una decisión consciente del appliance.
- SSH por contraseña se mantiene. La imagen nueva requiere establecer una contraseña propia en consola; no se vuelve a almacenar una contraseña conocida en el repositorio público.

Fuentes: [PipeWire en NixOS, operación headless y latencia](https://wiki.nixos.org/wiki/PipeWire), [NixOS Raspberry Pi 4](https://wiki.nixos.org/wiki/NixOS_on_ARM/Raspberry_Pi_4).

## Parámetros que no se cambian sin medir

### Red: CAKE, BBR y buffers TCP

Se han retirado los ajustes globales de rendimiento de red no medidos (`cake`, `bbr`, buffers TCP elevados, `tcp_fastopen` y colas de conexiones). No se afirma que CAKE o BBR sean malos: su efecto depende del router, la ruta y la carga. Para mejorar bufferbloat, la disciplina y la tasa de shaping deben elegirse donde está el cuello de botella (habitualmente el router) y validarse con latencia bajo carga.

No es correcto afirmar que BBR, CAKE o buffers de 16 MiB mejoren por sí solos el ping de juegos y streaming en todas las redes.

Fuente: [documentación de sysctl de red del kernel](https://docs.kernel.org/networking/ip-sysctl.html).

### Kernel y scheduler en gaming

`linuxPackages_latest` y `scx_cosmos` quedan por ahora. Para decidir si conviene el kernel LTS o el último mainline, o si un scheduler alternativo rinde mejor, compara el mismo benchmark varias veces, en la misma versión del juego, resolución, escena, perfil energético y temperatura. Registra FPS medio, 1 % lows, clocks y temperaturas. No hay datos de este hardware dentro del CI.

## Lista de verificación en los equipos

- **elytra/titan:** repetir una escena en MangoHud; comparar FPS medio y 1 % lows, temperaturas y consumo en corriente. Confirmar GameMode con `gamemoded -s`; comprobar estado sched-ext con `cat /sys/kernel/sched_ext/state`.
- **atlas:** `systemctl status docker`, `findmnt /mnt/datos`, `zramctl`, `vainfo` y `intel_gpu_top` durante una transcodificación.
- **pico:** `vainfo`; `clinfo` solo si se necesita OpenCL; revisar registros de Docker y espacio libre.
- **palco:** reproducir varias pistas durante un periodo largo; comprobar `wpctl status`, registros de PipeWire/WirePlumber y errores de Bluetooth. No bajar quantum hasta confirmar que hay margen.
- **todos:** el workflow de GitHub Actions evalúa los cinco sistemas y ejecuta `nix flake check --no-build`, pero no construye toda la imagen ni sustituye las pruebas en cada máquina.

La prioridad es mantener cambios medibles, reversibles y específicos de cada uso, no acumular parámetros que parecen rápidos pero carecen de evidencia sobre este hardware.

## Resultados de diagnóstico en Atlas y Pico (29 de octubre de 2026)

Los informes iniciales de ambos hosts no incluían pruebas de carga. Posteriormente se añadieron las pruebas dedicadas de tres minutos documentadas en la sección «Resultados de las pruebas stress-ng».

### Atlas

- El sistema reporta 31 GiB de RAM y unos 21–23 GiB disponibles, ZRAM prácticamente sin uso, cero unidades de systemd fallidas y estado SMART `PASSED` en el NVMe y el SSD SATA detectados.
- `vainfo` inicializa el controlador Intel `iHD` y enumera perfiles de vídeo. Esto confirma la ruta VA-API en el host, pero no una transcodificación real: el diagnóstico no encontró ningún contenedor cuyo nombre contuviera `jellyfin`.
- El único montaje de datos de Atlas es `/mnt/datos`, correspondiente al SSD SATA detectado. El informe también registró el segundo enlace SATA sin conexión; por sí solo, eso no indica un fallo ni exige configurar otro montaje.
- El contenedor `kigo-grafana` estaba usando aproximadamente 244 MiB de un límite de 256 MiB (95 %). Revisar su compose/stack por separado y considerar aumentar el límite si el uso se mantiene alto; esta definición no está en la configuración del host inspeccionada.
- El contenedor `stepdaddylivehd` registró un rechazo de redirección a una IP interna por la protección SSRF de `curl_cffi`. No se recomienda desactivar la protección; hay que revisar la URL/redirección que recibe la aplicación.
- CrowdSec informó que no encontraba algunos patrones de registros de adquisición, entre ellos el patrón configurado para Zoraxy. Comprobar rutas y montajes de logs en el stack antes de cambiar CrowdSec.
- Se añade `lm_sensors` a los paquetes del sistema para que el siguiente informe pueda recoger temperaturas con `sensors`.

### Pico

- El host mostró 14 GiB de memoria disponibles, sin uso de swap/ZRAM, seis contenedores en ejecución, cero unidades de systemd fallidas y sin errores de E/S ni de EXT4 coincidentes con los filtros del diagnóstico.
- La raíz eMMC tiene aproximadamente 8,3 GiB libres (69 % usado). Mantener la poda semanal de Docker y la recolección Nix semanal; revisar espacio si se acerca al 80 %, en vez de borrar datos automáticamente sin inspección.
- La temperatura de CPU leída en el momento del informe rondaba 52–53 °C. Es una única lectura cercana al arranque, no una prueba térmica bajo carga.
- `lscpu` reporta `Reg file data sampling: Vulnerable: No microcode` para el Celeron N3450 incluso con `hardware.cpu.intel.updateMicrocode = true` y la revisión `0x48` cargada. La opción de NixOS sí carga el microcódigo disponible en el initrd, pero no puede añadir por sí misma una corrección que no esté en ese firmware. La revisión `0x48` de Apollo Lake se publicó en 2022, antes de la divulgación de RFDS en marzo de 2024. En febrero de 2026 se retiró una propuesta del kernel para forzar la mitigación de Goldmont, porque no se pudo confirmar que esa revisión realmente limpiara los registros afectados por RFDS. Por tanto, el estado actual debe considerarse real y no se debe forzar un parámetro ni parchear la detección para mostrar `Mitigation: Clear Register File` sin validación de Intel. Fuentes: [Intel RFDS advisory](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/advisory-guidance/register-file-data-sampling.html), [microcode 0x46 → 0x48 para Apollo Lake](https://newreleases.io/project/github/intel/Intel-Linux-Processor-Microcode-Data-Files/release/microcode-20220510), [explicación y retirada de la propuesta del kernel](https://lists.openwall.net/linux-kernel/2026/02/02/809).
- Los avisos `ee1004` y `EDAC pnd2` aparecen en el arranque, pero el informe no muestra evidencia suficiente para atribuirles un fallo funcional. Se conservan sin añadir parámetros de kernel especulativos.

### Próximas validaciones pendientes

1. Las pruebas de CPU y RAM con `stress-ng` ya están documentadas más abajo; no hace falta repetirlas por ahora.
2. En Atlas, revisar temperaturas con `sensors` y confirmar que `/mnt/datos` está montado correctamente.
3. En Atlas, verificar en el stack correcto qué contenedor realiza la transcodificación y observar actividad de Intel GPU durante una transcodificación real.
4. RFDS de Pico ya se ha comprobado tras actualizar: el microcódigo está cargado (`0x48`), pero no se reconoce una mitigación específica para RFDS. No queda una corrección confirmada pendiente de aplicar desde NixOS; revisar futuras actualizaciones oficiales de Intel/kernel, sin falsear el estado de seguridad.

## Resultados de las pruebas stress-ng (29 de octubre de 2026)

Pruebas de tres minutos en cada host, CPU y memoria por separado. Son verificaciones iniciales de estabilidad, no comparativas de rendimiento entre configuraciones.

### Atlas

- CPU: `stress-ng --cpu 4 --timeout 180s --metrics-brief`; 4 trabajadores, 1.214.422 operaciones reportadas, 6.746,76 ops/s en tiempo real, 0 fallos y métricas consideradas fiables por stress-ng. Pico observado de `x86_pkg_temp`: 79 °C durante la prueba.
- Memoria: `stress-ng --vm 1 --vm-bytes 25% --timeout 180s --metrics-brief`; aproximadamente 3,62 GiB de memoria de prueba, 21.165.957 operaciones, 117.365,41 ops/s, 0 fallos y métricas fiables. Pico observado en el registro de temperatura: 90 °C; al terminar la prueba el sensor marcaba 66 °C.
- Después de ambas pruebas había aproximadamente 22 GiB de RAM disponibles, zram prácticamente sin uso y los contenedores seguían en ejecución. Grafana continuaba alrededor del 95,5 % de su límite de 256 MiB.
- Intel publica para el i5-1250P un Tjunction de 100 °C. El pico de 90 °C no equivale por sí solo a una avería ni demuestra throttling; sí deja menos margen térmico de lo deseable para asumir que toda carga sostenida será igual. Por ahora no se cambia gobernador, ventilación ni límites de potencia. Si este host trabaja de forma habitual bajo carga alta, repetir una sesión más larga mientras se registra frecuencia, temperatura y cualquier indicador de throttling.
- Referencia de temperatura: [especificaciones oficiales Intel Core i5-1250P](https://www.intel.com/content/www/us/en/products/sku/226256/intel-core-i51250p-processor-12m-cache-up-to-4-40-ghz/specifications.html) y [explicación de Intel sobre Tjunction](https://www.intel.com/content/www/us/en/support/articles/000005597/processors.html).

### Pico

- CPU: `stress-ng --cpu 2 --timeout 180s --metrics-brief`; 2 trabajadores, 245.749 operaciones, 1.365,27 ops/s en tiempo real, 0 fallos y métricas fiables. Temperatura máxima observada aproximada: 57 °C.
- Memoria: `stress-ng --vm 1 --vm-bytes 15% --timeout 180s --metrics-brief`; aproximadamente 2 GiB de memoria de prueba, 8.225.288 operaciones, 44.596,24 ops/s, 0 fallos y métricas fiables. Temperatura máxima observada aproximada: 57 °C.
- Al finalizar seguían disponibles unos 14 GiB de RAM, sin uso apreciable de zram, y los seis contenedores del host seguían activos. No hay motivo basado en estas pruebas para aumentar la presión de carga en este Celeron.
- El sistema mantiene `Reg file data sampling: Vulnerable: No microcode` aun después de actualizar y con microcódigo `0x48` cargado. La opción de NixOS funciona para cargar la revisión disponible, pero esa revisión es anterior a la divulgación de RFDS y no se ha confirmado que incluya la corrección necesaria.

### Conclusión y próximos pasos

Las cuatro pruebas de CPU/RAM terminaron con código 0 y sin fallos reportados. Esto respalda la estabilidad básica bajo una carga limitada, pero no mide temperaturas de larga duración, rendimiento de servicios ni la presencia/ausencia de throttling de hardware. Se mantienen los parámetros de CPU, zram y scheduler sin cambios. Para Atlas, las siguientes tareas útiles son evaluar el límite de memoria de Grafana y validar una transcodificación Intel real; para Pico, mantener la carga del microcódigo activada y volver a revisar RFDS si Intel publica una revisión aplicable o el kernel ofrece una mitigación validada.



## Ajustes seguros adicionales en Atlas (22 de noviembre de 2026)

### Cambio declarativo

- Se fija `vm.overcommit_memory = 1` únicamente en Atlas. Redis recomienda este modo para evitar fallos de `fork()` al realizar tareas de persistencia RDB/AOF. El ajuste permite sobreasignación de memoria virtual; no reserva RAM física ni cambia los límites de memoria de Docker. Debe seguir monitorizándose el uso real de RAM y la presión de memoria.
- Se añaden `sysstat` (incluye `iostat`, `mpstat` y `pidstat`) y `bpftrace` a las herramientas administrativas de Atlas. Son herramientas bajo demanda; no se habilita ningún servicio de recopilación periódica ni agente residente.

Fuente para overcommit: [documentación oficial de Redis](https://redis.io/docs/latest/operate/oss_and_stack/management/admin/). Para `sysstat`: [proyecto sysstat](https://github.com/sysstat/sysstat).

### Diagnóstico runtime compartido por el propietario

- Memoria: 31 GiB totales, 18 GiB disponibles; zram de 23,3 GiB con solo 4 KiB usados. No hay evidencia para aumentar zram ni cambiar swappiness.
- Transparent Huge Pages: modo actual `madvise`. Se conserva: desactivarlo globalmente podría cambiar el comportamiento de cargas distintas de Redis (por ejemplo, ML), y primero conviene comprobar si Redis/Valkey siguen mostrando avisos o problemas de latencia.
- Cgroups: versión 2 con driver `systemd`; controladores `cpuset`, `cpu`, `io`, `memory`, `hugetlb`, `pids`, `rdma`, `misc` y `dmem` disponibles. PSI está expuesto en CPU, memoria y E/S, sin presión media reciente en la captura. No se imponen `MemoryHigh`, `MemoryMax`, `CPUWeight` ni `IOWeight` a los contenedores.
- Watchdog: aparece `intel_oc_wdt` con timeout de 60 segundos, junto a más de un dispositivo watchdog. No se activa `RuntimeWatchdogSec` hasta identificar `/dev/watchdog`, inspeccionar el segundo dispositivo y verificar capacidades/estado del controlador; un watchdog mal seleccionado podría provocar reinicios inesperados.
- Almacenamiento: NVMe con planificador `none` y SSD SATA con `mq-deadline`. Se mantienen; no hay mediciones de latencia que justifiquen cambiarlos. La utilidad `iostat` no estaba instalada en el host y queda disponible mediante `sysstat` tras activar la generación.
- GPU: están presentes `/dev/dri/card0` y `/dev/dri/renderD128`, Intel Alder Lake-P. Esto confirma el dispositivo en el host, no que cada contenedor lo tenga montado. No se modifican los Compose ni los permisos de dispositivos sin inspeccionar sus configuraciones reales.
- Docker: cgroups v2 con driver `systemd`, seguridad `seccomp` integrada y namespaces de cgroups. No se cambia el runtime, el snapshotter ni los perfiles de seguridad de los contenedores.
- Red: BBR está disponible, CUBIC es el algoritmo actual y la interfaz física `enp2s0` usa FQ-CoDel. Las colas observadas no tenían paquetes descartados ni backlog. Se pospone el cambio a BBR/FQ hasta comparar latencia y rendimiento bajo carga; no se altera el tráfico de los contenedores.

### Cambios deliberadamente no aplicados

No se desactiva globalmente Transparent Huge Pages, no se cambian algoritmos TCP/colas, no se modifican los límites ni prioridades de recursos Docker, no se activa el watchdog, no se cambia el planificador de discos y no se modifican los mapeos de GPU. Estas decisiones quedan pendientes de pruebas específicas para evitar efectos secundarios en multimedia, IA, bases de datos y DNS.

La instalación de herramientas y el sysctl no modifica ni recrea contenedores. La corrección declarativa de Arcane sí recreará únicamente el Manager al activar la generación; conserva los volúmenes existentes y no cambia PostgreSQL, sus credenciales ni la red privada. La validación final debe realizarse en Atlas después de activar la generación.

### Arcane Manager: diagnóstico del healthcheck y corrección declarativa

La inspección de `arcane` el 22 de noviembre de 2026 mostró la imagen `v3.1.1` con digest `sha256:f12cfe86238b892956d945681613e9056676ca0cda0d980abacad033ebb72bee`. El contenedor estaba `running` pero `unhealthy`, con 3324 fallos consecutivos. Los últimos resultados no indicaban un fallo de la aplicación: Docker intentaba ejecutar `/bin/sh`, que no existe en la imagen mínima del Manager.

La causa era `--health-cmd=./arcane health --timeout 2s` en `extraOptions` de NixOS. El Docker CLI transforma siempre `--health-cmd` en `CMD-SHELL`; no existe un modo de indicar `CMD` exec-form mediante esa opción. La prueba manual `docker exec arcane ./arcane health --timeout 2s` terminó con código 0, confirmando que el binario de salud funciona directamente.

La configuración elimina el healthcheck de Docker mediante `--no-healthcheck` y añade una unidad `systemd` oneshot ejecutada por `arcane-healthcheck.timer` cada minuto. Esta invoca `docker exec` directamente, sin shell dentro del contenedor. Un fallo real queda registrado como fallo de la unidad `arcane-healthcheck.service` y puede consultarse con `journalctl -u arcane-healthcheck.service`; Docker ya no mostrará un estado `healthy/unhealthy` para este contenedor, de forma intencionada.

La declaración de Atlas se alinea con la versión y digest ya observados en runtime (`v3.1.1`); no es una actualización de versión nueva en el servidor, sino evitar que una reconstrucción futura lo haga retroceder a `v3.0.1`. No se actualiza el Agent de Pico en esta revisión porque todavía falta su auditoría runtime.

Fuentes: [Docker CLI: `--health-cmd` se serializa como `CMD-SHELL`](https://github.com/docker/cli/blob/master/cli/command/container/opts.go), [Docker Engine API: diferencia entre `CMD` y `CMD-SHELL`](https://docs.docker.com/reference/api/engine/version/v1.57/schemas/HealthConfig/).

### Firewall Docker: punto pendiente, sin cambio automático

La política `ATLAS-DOCKER-PRIVATE` usa una lista explícita de puertos privados/control y termina con `RETURN`. Por tanto, esta cadena no bloquea por sí sola los puertos publicados que no estén en esas listas; su ausencia no demuestra que sean accesibles desde Internet, porque también intervienen el resto de reglas y el router. No se añade un bloqueo general en esta revisión para no interrumpir los servicios públicos de Zoraxy ni las aplicaciones que requieren acceso externo. Antes de endurecerla más, hay que comparar la salida completa de `docker ps --format 'table {{.Names}}\t{{.Ports}}'` con `PRIVATE_PORTS`, `CONTROL_PORTS` y las reglas efectivas de IPv4/IPv6.