# Gestión general de recursos de Elytra

Auditoría y ajustes específicos de **Elytra** (Lenovo LOQ Essential, Intel Core i5-13450HX, RTX 5050 Laptop, 16 GiB RAM, NixOS 26.11). No se modifican Titan ni el módulo compartido que utiliza.

La finalidad es que el equipo se comporte de forma equilibrada con cualquier carga: escritorio KDE, navegador, desarrollo, compilaciones, juegos, contenedores y máquinas virtuales. Ningún ajuste está asociado a una aplicación concreta.

## Cambios propuestos en esta rama

### 1. earlyoom: recuperar margen antes de una situación crítica

`modules/common-system.nix` configura earlyoom al 5 % de memoria disponible y al 5 % de swap libre. Ese valor se conserva para los demás hosts. Elytra lo sobrescribe localmente con:

```nix
services.earlyoom = {
  freeMemThreshold = lib.mkForce 10;
  freeSwapThreshold = lib.mkForce 10;
};
```

earlyoom empieza enviando SIGTERM cuando **ambas** condiciones (memoria disponible y swap libre) caen por debajo de sus umbrales. Si no se recupera margen y ambas cruzan los umbrales de terminación, envía SIGKILL. Como no se fijan explícitamente los umbrales SIGKILL, quedan en la mitad de los valores SIGTERM:

| Ajuste | SIGTERM | SIGKILL implícito |
|---|---:|---:|
| Antes | 5 % memoria + 5 % swap | 2,5 % + 2,5 % |
| Elytra | 10 % memoria + 10 % swap | 5 % + 5 % |

Esto adelanta la primera señal y da más oportunidad de cerrar procesos de forma ordenada. No limita la RAM de ninguna aplicación. earlyoom sigue necesitando que memoria y swap estén simultáneamente por debajo de sus umbrales.

La configuración se aplica solo a Elytra. La opción `lib.mkForce` es necesaria porque los valores 5 % están declarados en el módulo común con prioridad normal.

Referencia: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/system/earlyoom.nix

### 2. scx_cosmos: usar los valores generales del scheduler

`modules/desktop-gaming.nix` aplica `-s 700` al scheduler de los dos equipos de escritorio. La documentación del ecosistema sched-ext clasifica esa opción dentro del perfil Gaming de scx_cosmos; el perfil Auto no añade argumentos. El scheduler describe su objetivo principal como propósito general para cargas de escritorio y servidor.

Elytra sobrescribe únicamente sus argumentos:

```nix
services.scx.extraArgs = lib.mkForce [ ];
```

Así se conservan `scx_cosmos` y sched-ext, pero se evita imponer de forma permanente el quantum del perfil gaming a todas las cargas. No se modifica `desktop-gaming.nix`, por lo que Titan conserva su configuración.

Esto es una elección de equilibrio, no una afirmación de que el perfil automático vaya a dar más FPS en todos los juegos. Se deberá comparar con la configuración anterior en las mismas escenas y medir FPS medios, 1 % lows y consistencia de frametimes antes de considerar otro ajuste.

Referencias:
- https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_cosmos/README.md
- https://github.com/sched-ext/scx-loader/blob/main/crates/scx_loader/configuration.md

### 3. NVIDIA Dynamic Boost

Se habilita `hardware.nvidia.dynamicBoost.enable` solo en Elytra. El diagnóstico aportado para la RTX 5050 indicaba que el firmware/controlador anunciaba soporte. NixOS activa con esta opción el servicio `nvidia-powerd`, que redistribuye dinámicamente presupuesto de potencia entre CPU y GPU en portátiles compatibles.

Es una función para repartir potencia bajo carga, no un ajuste de consumo en reposo. No se fuerzan RTD3 ni S0ix porque el controlador informó de que la plataforma no los soporta. Tampoco se presupone que Dynamic Boost aumente siempre la potencia: depende del firmware, la temperatura, el cargador y la carga de trabajo.

Referencia: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/hardware/video/nvidia.nix

## Ajustes existentes que se conservan

| Área | Estado actual | Decisión |
|---|---|---|
| RAM / zram | zstd, tamaño máximo lógico del 50 % de RAM | Mantener; no confundir capacidad de swap con RAM física ocupada |
| Swappiness | 100 | Mantener mientras zram sea el swap principal |
| page-cluster | 0 | Mantener para el swap comprimido |
| systemd-oomd | Umbral predeterminado 60 % PSI durante 30 s | No cambiar: las mediciones no registraron kills ni presión de memoria |
| Nix builds | 4 trabajos × 2 cores por trabajo | Mantener; es un máximo de concurrencia, no una reserva permanente de CPU |
| Scheduler | scx_cosmos | Mantener el scheduler; solo retirar el argumento gaming fijo en Elytra |
| GameMode | habilitado, renice y perfil de rendimiento | Mantener; actúa al solicitar modo de juego |
| Energía / térmicas | power-profiles-daemon + thermald | Mantener; no se han medido problemas que justifiquen sustituirlos |
| NVIDIA PRIME | offload + fine-grained habilitados | Mantener; no forzar modos de energía no soportados |
| Kernel / mitigaciones | linuxPackages_latest y mitigaciones activas | Mantener; no introducir riesgos de seguridad por supuestas ganancias de FPS |

### Por qué no se cambia systemd-oomd

El diagnóstico anterior mostró presión de memoria y E/S en 0 %, contadores `oom`/`oom_kill` a cero y ningún registro de eliminación en el journal consultado. Las unidades de la sesión tenían `ManagedOOMMemoryPressure=kill`, pero esa propiedad habilita vigilancia: systemd-oomd espera a que el PSI supere el umbral durante el periodo configurado y solo puede terminar cgroups descendientes elegibles.

No hay evidencia suficiente para bajar globalmente el umbral o cambiar qué cgroups pueden ser candidatos. Se conserva el comportamiento predeterminado de systemd (60 % durante 30 s) como margen de seguridad y se mejora únicamente el umbral de aviso temprano de earlyoom en Elytra.

Referencia: https://www.freedesktop.org/software/systemd/man/262/oomd.conf.d.html

### Memoria: por qué se conserva zram al 50 %

En NixOS, `zramSwap.memoryPercent` define la capacidad máxima del dispositivo zram como porcentaje de RAM; no reserva ese porcentaje de RAM física desde el arranque. El 50 % ya es el valor predeterminado del módulo de NixOS. Se mantiene zstd y `vm.swappiness=100`; cambiar compresión o capacidad sin observar `zramctl`, PSI y la carga real sería especulativo.

Referencia: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/zram.nix

## Medición y validación en el equipo

La evaluación de GitHub verifica la evaluación Nix de las configuraciones, pero no puede medir latencia, consumo o temperatura en el portátil. Antes de activar la generación:

1. Revisar el diff y confirmar que solo cambia `hosts/portatil/configuration.nix` y este documento.
2. Construir `.#elytra` localmente sin activar todavía.
3. Tras desplegar y reiniciar si procede, comprobar:
   ```sh
   systemctl status earlyoom systemd-oomd scx nvidia-powerd
   systemctl show scx -p Environment
   oomctl
   zramctl
   swapon --show
   cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io
   journalctl -b -u earlyoom -u systemd-oomd -u scx -u nvidia-powerd --no-pager
   ```
4. Probar el uso habitual de forma repetible: escritorio y navegador, desarrollo/compilación, juego, y una carga combinada. Registrar temperatura, frecuencias, potencia, RAM disponible, zram usada, PSI y frametimes.
5. Para valorar el cambio de scheduler, repetir la misma escena con el quantum anterior y con los valores generales, sin cambiar simultáneamente GameMode, perfil energético, resolución ni configuración gráfica. Comparar FPS medios, 1 % lows y variabilidad de frametimes.
6. Para Dynamic Boost, comparar una carga CPU+GPU con el cargador conectado y las mismas condiciones térmicas. Una lectura en reposo no valida esta función.

## Pendiente de investigar con mediciones

- El consumo en batería del Wi-Fi: Elytra desactiva el ahorro de energía de NetworkManager y el ahorro de energía de rtw89/ASPM mediante opciones del driver. No se han retirado porque podrían ser mitigaciones de estabilidad; medir primero desconexiones, latencia y autonomía.
- El consumo en reposo de la RTX 5050: el controlador reportó RTD3/S0ix no soportados y unos 7 W en la medición anterior. No forzar ACPI ni parámetros del módulo sin confirmar soporte del firmware.
- El paralelismo de Nix y las cargas de VM/contenedores: ajustar solo si se observa presión de CPU o memoria durante compilaciones reales.

## Alcance

- Solo se ajusta Elytra.
- Titan, Atlas, Pico y Palco no reciben cambios de configuración en esta propuesta.
- No se asignan límites de memoria ni prioridades especiales a Kilo, Konsole, KDE o aplicaciones concretas.
- No se ejecuta `nixos-rebuild switch` ni se despliega automáticamente.
