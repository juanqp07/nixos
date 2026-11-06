# Modo privacidad de RustDesk en Elytra

El módulo modules/rustdesk-privacy.nix se carga solo en elytra. Añade un comando para apagar la retroiluminación del panel y aislar los dispositivos físicos de entrada mientras se sigue controlando el escritorio mediante RustDesk.

## Uso

~~~bash
rustdesk-privacy on
rustdesk-privacy off
rustdesk-privacy toggle
rustdesk-privacy status
~~~

El atajo global previsto es **Ctrl + Alt + P**. La configuración se escribe en kglobalshortcutsrc, pero Plasma 6 Wayland puede necesitar cerrar e iniciar sesión una vez después del primer despliegue para registrar un atajo nuevo. También se puede ejecutar el comando desde una terminal remota o buscar **Privacidad de RustDesk** en el menú de aplicaciones.

El modo no se activa automáticamente al conectarse ni se desactiva al desconectarse: se controla manualmente desde el equipo remoto.

## Qué hace

1. El servicio rustdesk-privacy-grabber.service comprueba que puede identificar y aislar al menos un teclado y un dispositivo apuntador físicos.
2. Abre los nodos físicos /dev/input/event* y aplica EVIOCGRAB. El kernel deja de entregar esos eventos a la sesión local mientras el proceso mantenga abiertos los descriptores.
3. Excluye los dispositivos cuyo sysfs esté bajo /devices/virtual/input/. RustDesk utiliza dispositivos virtuales uinput para inyectar la entrada remota en Linux; estos no se capturan.
4. Guarda el nivel de brillo original y pone a cero la retroiluminación del panel con brightnessctl. No apaga el monitor mediante DPMS, para no interrumpir deliberadamente la captura de pantalla.
5. Vigila los dispositivos cada segundo para aislar también los periféricos físicos que se conecten mientras el modo está activo.

Si falta un teclado, un dispositivo apuntador o una retroiluminación compatible, el inicio falla y el proceso libera los dispositivos ya capturados. El servicio no se reinicia automáticamente tras un fallo para evitar reactivar la privacidad sin intervención.

## Recuperación y seguridad

- rustdesk-privacy off detiene el servicio. Al cerrarse los descriptores, Linux libera los dispositivos físicos; ExecStopPost vuelve a intentar restaurar el brillo.
- Hay un límite de ejecución de **12 horas**. Al alcanzarlo, systemd detiene el servicio y ejecuta la restauración.
- El servicio es root porque necesita abrir y capturar nodos de entrada. Polkit autoriza a juan a iniciar y detener únicamente rustdesk-privacy-grabber.service; no concede permisos generales de administración de systemd.
- El estado de brillo original se guarda temporalmente en /run/rustdesk-privacy-backlight.json, con permisos solo para root.
- En caso de emergencia, desde una terminal remota: sudo systemctl stop rustdesk-privacy-grabber.service.
- Para diagnosticar un fallo: sudo journalctl -u rustdesk-privacy-grabber.service -b.

Si rustdesk-privacy status informa de una restauración de brillo pendiente, consulta el registro antes de borrar el archivo de estado. No elimines ese archivo sin restaurar primero el valor guardado.

## Límites que deben probarse en el equipo real

La captura de eventos es selectiva y depende de las propiedades que udev publique para cada dispositivo físico. Los dispositivos virtuales se dejan activos intencionadamente para conservar el control remoto. El brillo a cero depende de que el controlador exponga una retroiluminación de tipo backlight.

La evaluación y compilación de NixOS no pueden demostrar que la captura remota siga funcionando con la combinación concreta de RustDesk, KWin, PipeWire y el controlador gráfico de Elytra. Después de desplegar, comprueba primero status, después activa el modo y verifica que puedes seguir moviendo el ratón y escribiendo desde el cliente RustDesk; termina con rustdesk-privacy off.
