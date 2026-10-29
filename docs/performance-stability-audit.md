# Auditoría de rendimiento y estabilidad por host

**Revisión:** 28 de octubre de 2026  
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

El módulo común conserva los ajustes de red ya existentes en esta revisión, no porque se haya demostrado que sean óptimos, sino porque su efecto depende de la ruta, el router y la carga. CAKE sin límite de ancho de banda configurado no hace shaping al ritmo real del cuello de botella de la conexión. Para mejorar bufferbloat de forma efectiva, la disciplina y la tasa de shaping deben elegirse en el dispositivo que forma el cuello de botella (habitualmente el router) o validarse con pruebas de latencia bajo carga.

No es correcto afirmar que BBR, CAKE, buffers de 16 MiB o una cola concreta mejoren por sí solos el ping de los juegos y el streaming en todas las redes.

Fuente: [documentación de sysctl de red del kernel](https://docs.kernel.org/admin-guide/sysctl/net.html).

### Kernel y scheduler en gaming

`linuxPackages_latest` y `scx_cosmos` quedan por ahora. Para decidir si conviene el kernel LTS o el último mainline, o si un scheduler alternativo rinde mejor, compara el mismo benchmark varias veces, en la misma versión del juego, resolución, escena, perfil energético y temperatura. Registra FPS medio, 1 % lows, clocks y temperaturas. No hay datos de este hardware dentro del CI.

## Lista de verificación en los equipos

- **elytra/titan:** repetir una escena en MangoHud; comparar FPS medio y 1 % lows, temperaturas y consumo en corriente. Confirmar GameMode con `gamemoded -s`; comprobar estado sched-ext con `cat /sys/kernel/sched_ext/state`.
- **atlas:** `systemctl status docker`, `findmnt /mnt/datos`, `zramctl`, `vainfo` y `intel_gpu_top` durante una transcodificación.
- **pico:** `vainfo`; `clinfo` solo si se necesita OpenCL; revisar registros de Docker y espacio libre.
- **palco:** reproducir varias pistas durante un periodo largo; comprobar `wpctl status`, registros de PipeWire/WirePlumber y errores de Bluetooth. No bajar quantum hasta confirmar que hay margen.
- **todos:** el workflow de GitHub Actions evalúa los cinco sistemas, pero no construye toda la imagen ni sustituye las pruebas en cada máquina.

La prioridad es mantener cambios medibles, reversibles y específicos de cada uso, no acumular parámetros que parecen rápidos pero carecen de evidencia sobre este hardware.
