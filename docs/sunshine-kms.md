# Sunshine KMS: acceso remoto antes del login

## Alcance

Este módulo es un despliegue piloto para **Titan**. Su objetivo es poder entrar con Moonlight después de reiniciar, ver el greeter de SDDM y escribir la contraseña sin activar el inicio automático de sesión.

Elytra no activa este módulo todavía. Su configuración de RustDesk y SDDM queda intacta hasta que Titan supere las pruebas físicas.

## Diseño

- Sunshine se instala desde Nixpkgs mediante `services.sunshine`.
- La captura se fija explícitamente a `kms`; no se depende de la selección automática ni del portal de escritorio.
- Se reutiliza el servicio de usuario generado por el módulo NixOS. Su `WantedBy` pasa de `graphical-session.target` a `default.target`, y se eliminan sus dependencias de la sesión gráfica.
- `users.users.juan.linger = true` hace que el gestor systemd de Juan arranque con el sistema y permanezca activo cuando no hay una sesión gráfica.
- El servicio sigue ejecutándose como Juan. `services.sunshine.capSysAdmin` hace que NixOS cree el wrapper con `CAP_SYS_ADMIN`; el wrapper pertenece al grupo dedicado `sunshine-kms`, al que se añade Juan. Sus permisos son `u+rx,g+x,o-rwx`, por lo que otros usuarios locales no pueden ejecutarlo. No se ejecuta Sunshine como root.
- Sunshine necesita acceso de escritura a `/dev/uinput`. La regla local asigna ese nodo al grupo `uinput`, al que Juan ya pertenece por el módulo de escritorio. No se añade Juan al grupo amplio `input`, que puede dar acceso de lectura a dispositivos físicos de teclado.
- No se usa `services.sunshine.openFirewall`. Los puertos TCP/UDP se permiten solamente en la interfaz NetBird `wt0`; UPnP queda desactivado.
- `origin_web_ui_allowed = "wan"` permite el acceso a la Web UI desde cualquier origen que consiga llegar al servicio; no es una restricción a la VPN. La barrera de red es el firewall por interfaz (`wt0`). Mantén las ACL de NetBird y una contraseña fuerte de Sunshine: los peers autorizados para llegar a esos puertos pueden alcanzar la Web UI.

No se crea un segundo proceso Sunshine ni se inventa una unidad de sistema distinta. Se adapta la unidad de usuario que ya genera NixOS para que no dependa de una sesión Plasma activa.

## Riesgos y límites conocidos

- `CAP_SYS_ADMIN` es una capacidad muy amplia, cercana a privilegios de root. Aunque el proceso se ejecuta como Juan y la capacidad se concede mediante el wrapper de NixOS, debe tratarse como una superficie de seguridad sensible.
- KMS permite capturar el framebuffer DRM, pero upstream no garantiza expresamente que todas las combinaciones de SDDM Wayland, KWin/Weston, controladores y GPU funcionen como greeter remoto.
- La enumeración de conectores y framebuffers ocurre al inicializar la captura. El servicio puede arrancar antes de SDDM; la prueba real debe iniciar la transmisión cuando el greeter ya esté dibujado.
- En equipos NVIDIA, upstream documenta posibles pantallas negras si DRM modesetting no está habilitado. Titan usa AMD; la validación de Elytra requerirá una revisión separada de Intel/NVIDIA.
- Sunshine documenta posibles problemas de ventanas que parpadean o desaparecen con KMS y KDE Plasma 6.5 o posterior. No se fuerza ningún ajuste global de KWin: primero hay que reproducir el problema y medir el impacto.
- KMS es una vía de bajo nivel que upstream contempla sustituir progresivamente por captura mediante XDG Portal. Se usa aquí porque el objetivo es capturar la pantalla anterior al login; la captura portal normal requiere autorización de una sesión de escritorio.

## Validación en Titan

La evaluación de Nix y GitHub Actions no pueden demostrar que se vea el greeter ni que el teclado virtual sea aceptado por SDDM. Después de desplegar en Titan, comprobar en este orden:

1. Confirmar que Juan tiene lingering habilitado:
   `loginctl show-user juan -p Linger`.
2. Confirmar que Sunshine está habilitado en el gestor de usuario:
   `systemctl --user is-enabled sunshine` y `systemctl --user status sunshine`.
3. Revisar el log:
   `journalctl --user -u sunshine -b`.
4. Reiniciar Titan y no iniciar sesión localmente.
5. Desde un cliente Moonlight conectado por NetBird, conectar a Titan, comprobar que aparece SDDM y probar teclado, ratón y contraseña.
6. Iniciar Plasma y confirmar que la misma conexión continúa mostrando y controlando el escritorio.
7. Repetir después de otro reinicio para descartar una conexión que dependiera de estado previo.

No se debe declarar cumplido el objetivo hasta superar las pruebas 4–7 físicamente.

## Recuperación

SSH por NetBird permanece disponible como vía de recuperación. Si Sunshine KMS no funciona:

1. Entrar por SSH y ejecutar una generación anterior de NixOS o desactivar `services.sunshine-kms.enable`.
2. Para volver al servicio Sunshine convencional, restaurar la configuración normal de `services.sunshine`, quitar la captura KMS explícita y dejar que el módulo vuelva a vincular el servicio a `graphical-session.target`.
3. Comprobar que SDDM vuelve a su configuración anterior.

El cambio no elimina el cliente RustDesk ni altera el servicio RustDesk de Elytra.
