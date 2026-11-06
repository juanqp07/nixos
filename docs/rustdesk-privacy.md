# Modo privacidad de RustDesk en Elytra

El módulo modules/rustdesk-privacy.nix se carga solo en elytra. Permite apagar la retroiluminación del panel y aislar los dispositivos físicos de entrada mientras el escritorio sigue siendo controlable por RustDesk.

## Uso manual

~~~bash
rustdesk-privacy on
rustdesk-privacy off
rustdesk-privacy toggle
rustdesk-privacy status
~~~

- on activa el modo con propiedad **manual**. La desconexión de RustDesk no lo desactiva.
- off lo desactiva y restaura pantalla, teclado y ratón.
- toggle es un control manual: si está activo, lo apaga; si está apagado, lo activa en modo manual.
- status muestra si el modo está apagado, automático o manual.

Una activación manual permanece activa hasta ejecutar rustdesk-privacy off o volver a pulsar el atajo manual. No tiene límite de 12 horas.

El atajo global KDE previsto es **Ctrl + Alt + P**. También está disponible el lanzador **Privacidad de RustDesk** en el menú de aplicaciones.

## Activación automática por sesión

Un servicio de usuario de Home Manager escucha el D-Bus de XDG Desktop Portal durante la sesión gráfica de KDE. En RustDesk 1.5.0 para Linux/Wayland, la captura del escritorio utiliza PipeWire y XDG Desktop Portal.

El monitor no se activa por detectar un proceso, un socket TCP o una conexión pendiente. Espera la respuesta positiva del portal al paso ScreenCast Start (request handle token u4), que llega después de que se haya concedido la captura de pantalla. Solo acepta ese evento cuando el propietario de la petición es el proceso RustDesk de servidor entrante (rustdesk --server).

Cuando llega el evento:

1. El monitor registra el propietario de la sesión del portal en XDG_RUNTIME_DIR.
2. Ejecuta rustdesk-privacy auto-on.
3. Si no existe una activación manual ni una supresión manual vigente, inicia rustdesk-privacy-grabber.service y marca el modo como automático.

Cuando el portal emite Session.Closed, el monitor retira ese propietario. Tras un margen breve de 2,5 segundos, si no queda ninguna sesión de escritorio RustDesk, ejecuta auto-off. Esto evita restaurar el equipo si una reconexión inmediata ya abrió otra sesión.

El servicio manual tiene prioridad:
- Si el modo está en manual, auto-on y auto-off no pueden modificarlo.
- Si el modo está en automático, ejecutar manual on lo convierte en manual; seguirá activo al desconectarse RustDesk.
- Ejecutar manual off durante una sesión remota desactiva la privacidad y suprime una reactivación automática hasta que se cierre esa sesión del portal. Una conexión posterior podrá volver a activarla automáticamente.
- Si el modo se activa desde fuera del comando y no hay estado de propiedad, el monitor lo trata como manual y no lo apaga por su cuenta.

El monitor se inicia con graphical-session.target y se detiene al terminar la sesión gráfica. Si se detiene de forma ordenada, retira la activación automática; una activación manual se conserva.

## Qué hace el servicio privilegiado

1. Comprueba que puede aislar al menos un teclado físico y un dispositivo apuntador físico.
2. Abre los nodos físicos /dev/input/event* y aplica EVIOCGRAB.
3. Excluye los nodos bajo /devices/virtual/input/, incluidos los dispositivos uinput de RustDesk.
4. Guarda el brillo original y pone la retroiluminación del panel a cero con brightnessctl. No apaga la salida mediante DPMS.
5. Vigila los dispositivos físicos conectados en caliente mientras el modo está activo.

Si no se identifican las entradas físicas o no se encuentra una retroiluminación compatible, el inicio falla y libera los descriptores que ya hubiera capturado. Al detenerse, systemd ejecuta una segunda restauración del brillo mediante ExecStopPost.

## Seguridad y recuperación

- El servicio de captura de eventos se ejecuta como root porque EVIOCGRAB necesita acceso privilegiado a /dev/input.
- Polkit autoriza a juan únicamente a iniciar y detener rustdesk-privacy-grabber.service; no concede permisos generales para administrar unidades.
- El estado del brillo original se guarda en /run/rustdesk-privacy-backlight.json con permisos solo para root.
- El estado manual/automático y los propietarios de sesiones se guardan en el XDG_RUNTIME_DIR del usuario.
- Para recuperar la entrada física desde SSH: sudo systemctl stop rustdesk-privacy-grabber.service.
- Para diagnosticar el capturador: sudo journalctl -u rustdesk-privacy-grabber.service -b.
- Para diagnosticar el monitor: journalctl --user -u rustdesk-privacy-watcher -b.

## Límites de la validación

La evaluación NixOS comprueba la configuración y los servicios, pero no puede simular el portal KDE, el hardware de teclado/touchpad ni la sesión RustDesk real. La primera prueba debe hacerse con SSH disponible y comprobar, por este orden: conexión entrante autorizada, pantalla física apagada, control remoto todavía operativo, desconexión, restauración automática y persistencia del modo manual después de desconectar.
