# Gestión de recursos de Elytra

Este documento recoge los cambios aplicados tras los diagnósticos de memoria, cgroups y NVIDIA del 2 de noviembre de 2026. Se limita a **Elytra**; Titan queda fuera porque actualmente ejecuta Windows.

## Estado observado

- Elytra usa cgroups v2 y systemd 262.
- La sesión tiene 16 GiB de RAM. En la medición inicial había aproximadamente 8,1 GiB disponibles y PSI de memoria/E/S en 0 %: no había presión global de memoria en ese momento.
- `earlyoom` está activo con `-m5 -r3600 -s5`. Se conserva sin cambios.
- `systemd-oomd` está activo. Su configuración global no define límites propios, por lo que se aplican los valores predeterminados de systemd: 60 % de presión de memoria durante 30 segundos.
- Las unidades transitorias de Konsole aparecen con `ManagedOOMMemoryPressure=kill`. En la terminal que ejecutaba Kilo, el cgroup de la pestaña consumía aproximadamente 3,1 GiB. Los contadores `memory.events` mostraban `oom 0` y `oom_kill 0`; el journal consultado no registraba eliminaciones de systemd-oomd.
- Los procesos de Kilo y sus auxiliares (Node, Playwright y gopls) estaban dentro del scope de la pestaña de Konsole. Por tanto, podían quedar entre los cgroups descendientes elegibles si systemd-oomd tuviera que actuar sobre ese scope.

La propiedad `ManagedOOMMemoryPressure=kill` no significa que el proceso vaya a morir inmediatamente: habilita la supervisión del cgroup y la actuación depende de que se supere el umbral de presión durante el periodo configurado. systemd-oomd selecciona cgroups descendientes elegibles, no mata automáticamente el scope que define la política.

## Cambios aplicados

### Kilo en un cgroup independiente

Se declara el slice de usuario `app-kilo.slice` con:

| Propiedad | Valor | Efecto |
|---|---:|---|
| `CPUWeight` | 80 | Prioridad relativa algo menor que el peso predeterminado 100 cuando hay contención de CPU |
| `IOWeight` | 80 | Prioridad relativa algo menor cuando hay contención de E/S |
| `MemoryHigh` | 8 GiB | Umbral de presión/reclaim, no un límite duro de memoria |

No se configura `MemoryMax`: no queremos imponer un techo rígido que pueda matar Kilo, sus compilaciones o sus procesos auxiliares. Los pesos son relativos y no reservan CPU ni ancho de banda cuando el equipo está ocioso.

Se añade el alias `kilo-isolated`. Al ejecutar ese comando, systemd crea un scope dentro de `app-kilo.slice`, fuera del scope de Konsole. Kilo y los procesos que lance heredan ese cgroup. El comando habitual `kilo` no se modifica.

Ejemplo:

```sh
kilo-isolated
```

Comprobación del slice:

```sh
systemctl --user show app-kilo.slice \
  -p ControlGroup -p CPUWeight -p IOWeight -p MemoryHigh -p MemoryMax
```

Durante una sesión de Kilo:

```sh
systemd-cgls --user-unit app-kilo.slice
```

El valor esperado de `MemoryMax` es `infinity`; `MemoryHigh` debe mostrar el umbral de 8 GiB.

### NVIDIA Dynamic Boost

El diagnóstico de la RTX 5050 indicaba que el firmware anuncia soporte de Notebook Dynamic Boost. Se habilita `hardware.nvidia.dynamicBoost.enable`, que activa `nvidia-powerd` para redistribuir dinámicamente el presupuesto de potencia entre CPU y GPU en portátiles compatibles.

Esto está orientado al rendimiento bajo carga y **no soluciona el consumo en reposo**. La lectura de aproximadamente 6,9–7 W, con VRAM activa y Runtime D3/S0ix no soportados por la plataforma, no justifica forzar parámetros ACPI o modos de energía no anunciados por el controlador.

Comprobaciones tras desplegar:

```sh
systemctl status nvidia-powerd
journalctl -b -u nvidia-powerd --no-pager
cat /proc/driver/nvidia/gpus/0000:01:00.0/power
nvidia-smi -q -d POWER
```

Comparar potencia y límite de GPU durante una carga de juego, conectado al cargador y con un perfil energético equivalente. Dynamic Boost puede no elevar el límite en todas las condiciones: el firmware decide cuándo permite la redistribución.

## Decisiones deliberadas

- No se cambia el umbral global de systemd-oomd ni se desactiva el servicio: los datos no demuestran que haya eliminado procesos.
- No se cambia la política de earlyoom.
- No se aplica `MemoryMax` a Kilo ni se limita artificialmente su RAM.
- No se añade un límite global a KDE, KWin o PipeWire. Los pesos más bajos de Kilo permiten que las cargas interactivas con prioridad predeterminada tengan ventaja relativa cuando compiten por CPU/E/S.
- No se añade un parámetro de kernel para forzar Runtime D3 o S0ix: el controlador reporta que no están soportados.
- No se cambia el kernel, `scx_cosmos`, zram ni los parámetros de mitigación de CPU en esta intervención.
- Titan no se modifica.

## Validación pendiente en Elytra

Después de aplicar la generación:

1. Comprobar que `app-kilo.slice` muestra los pesos y `MemoryHigh=8G`, y que `MemoryMax=infinity`.
2. Ejecutar Kilo con `kilo-isolated` y verificar que sus procesos aparecen bajo `app-kilo.slice`, no dentro de `app-org.kde.konsole-*.scope`.
3. Repetir el uso habitual de Kilo con Playwright/gopls y observar `memory.current`, `memory.events`, `/proc/pressure/memory` y la respuesta de KDE.
4. Confirmar que `nvidia-powerd` arranca correctamente y comparar la potencia bajo carga. No evaluar Dynamic Boost solo con la lectura en reposo.
5. Ejecutar `nix flake check --no-build` y construir `.#elytra` desde el checkout local antes de activar.

La configuración no se considera validada en hardware hasta completar estas comprobaciones.