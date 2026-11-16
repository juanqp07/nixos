# Actualizaciones de Arcane en Atlas y Pico

Arcane se declara en `modules/atlas-docker.nix` como una imagen OCI fijada por
versión y digest. El contenedor no debe actualizarse por separado desde Docker
o desde el actualizador interno de Arcane: NixOS es quien controla su ciclo de
vida y debe seguir siendo la fuente de verdad.

## Actualizaciones normales con nix-maintain

Al ejecutar `nix-maintain` o `nix-maintain -y` en **Atlas**:

1. Se consultan las releases estables publicadas en GitHub. No se consideran
   borradores ni versiones preliminares.
2. Se compara SemVer con la versión fijada y se selecciona la release más nueva
   que mantenga la misma versión principal.
3. Si existe una versión más nueva compatible, se obtiene el digest de su
   manifiesto en GHCR. Las versiones principales posteriores se notifican, pero
   no impiden recibir correcciones de la rama mayor instalada.
4. Antes de tocar el módulo se crea una copia de seguridad local.
5. Se actualiza únicamente la referencia de imagen de Arcane Manager. Después,
   el mantenimiento continúa con `nix flake update`, la evaluación, la
   construcción y la preparación de la generación NixOS.

En modo interactivo se pide confirmación para la actualización de Arcane. Con
`-y` se aceptan automáticamente solo actualizaciones de la misma versión
principal. El script no instala pre-releases, no cambia a otra versión mayor y
no actualiza contenedores cuando el mantenimiento se ejecuta en otro host.

El cambio queda en `modules/atlas-docker.nix` como modificación local. El Direct
Agent de Pico se mantiene como una actualización separada, ejecutada desde el
propio host Pico. Así cada máquina respalda y modifica únicamente el servicio
que administra.

El script no ejecuta `git add`, `git commit`, `git stash` ni descarta cambios.
Revisa y confirma el diff cuando te convenga.

Atlas utiliza `system.autoUpgrade.operation = "boot"`. Por eso, `nix-maintain`
prepara la generación; la imagen nueva se aplicará al arrancar con esa
generación, no durante la comprobación. Tras el siguiente reinicio verifica:

```bash
docker inspect --format '{{.State.Status}} / {{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' arcane
docker logs --since 10m arcane
```

Comprueba además el acceso al panel y que las notificaciones siguen llegando.

## Actualización del Direct Agent en Pico

Al ejecutar `nix-maintain` o `nix-maintain -y` en **Pico**, se comprueba la
versión fijada del Manager en `modules/atlas-docker.nix` y se compara con la
imagen de `ghcr.io/getarcaneapp/agent` declarada en
`hosts/zimablade/configuration.nix`.

- Si el agente está en una versión anterior de la misma rama mayor, se propone
  actualizarlo exactamente a la versión del Manager y se fija su digest GHCR.
- Si las versiones ya coinciden, no se modifica nada.
- Si el agente es más nuevo que el Manager, no se hace un downgrade.
- Si Manager y agente pertenecen a versiones mayores distintas, se omite la
  actualización automática y se requiere la migración manual.

La versión del Manager es la fuente de verdad: el agente no busca una release
independiente ni se adelanta a Atlas. Antes de cambiar la declaración Nix, Pico
crea una copia local de seguridad con:

```bash
sudo bash scripts/backup-arcane-agent.sh
```

La copia se guarda en
`/var/lib/arcane-agent/backups/<fecha-UTC>.<sufijo>/` e incluye el volumen
Docker `arcane-agent-data`, `agent.env` (token de inscripción), la declaración
Nix y la referencia de imagen que utilizaba el contenedor. El agente se detiene
de forma ordenada durante el archivo del volumen y se reinicia al terminar,
incluso si el backup falla. El panel de Atlas puede mostrar Pico como desconectado
durante ese breve intervalo.

La actualización queda como un cambio local en
`hosts/zimablade/configuration.nix`; no se hace `git add`, commit ni despliegue
remoto. Revisa y confirma el cambio antes de desplegar. El mantenimiento de Pico
prepara la nueva generación para el siguiente arranque, de acuerdo con
`system.autoUpgrade.operation = "boot"`.

Importante: la copia local del repositorio en Pico debe contener la versión de
Manager que se haya decidido desplegar en Atlas. Sincroniza el commit de esa
declaración antes de ejecutar el mantenimiento de Pico. No se modifica ni se
despliega Pico desde el proceso que se ejecuta en Atlas.

## Copia de seguridad del Manager en Atlas

Antes de cambiar la referencia de imagen, el actualizador ejecuta:

```bash
sudo bash scripts/backup-arcane.sh
```

La copia se guarda en `/mnt/datos/AppData/arcane/backups/<fecha-UTC>.<sufijo>/` e
incluye:

- Dump lógico de PostgreSQL (`arcane-postgres`).
- Volumen Docker `arcane-data`.
- Directorio de proyectos `/mnt/datos/arcane/projects`.
- `arcane.env` y `postgres.env`.
- La declaración `modules/atlas-docker.nix` usada en ese momento.

Antes de respaldar los datos, el script detiene Arcane de forma ordenada
(`docker stop --time 30 arcane`) para evitar escrituras mientras copia el
volumen y los proyectos. PostgreSQL permanece activo para generar el volcado
lógico con `pg_dumpall`. Un trap vuelve a iniciar Arcane incluso si falla alguna
parte de la copia; si no consigue iniciarlo, el script termina con error para
que no se pase por alto la incidencia.

La interrupción del panel y de las notificaciones de Arcane dura únicamente lo
que tarda la copia. Los archivos contienen secretos y datos privados: el
directorio queda con permisos `0700` y sus archivos con permisos privados. No
se borran copias antiguas automáticamente; revisa el espacio ocupado antes de
limpiarlas.

## Actualizaciones mayores

Una actualización de versión principal **se detecta, pero nunca se aplica
automáticamente**, tampoco con `-y`. Debe revisarse su guía de migración y
adaptarse la configuración antes de cambiar el tag.

Arcane 3.0 es un cambio incompatible desde 2.x. La guía oficial exige partir de
2.17.3, respaldar los datos, renombrar las variables de Arcane al prefijo
`ARCANE_`, actualizar Manager y todos los agentes a la misma versión y revisar
roles y notificaciones. No basta con cambiar `v2.x` por `v3.x`.

Antes de migrar a 3.x:

1. Comprueba que el Manager y los agentes que tengas conectados están en
   versiones compatibles y resuelve los trabajos que requieran atención.
2. Ejecuta `sudo bash scripts/backup-arcane.sh` y conserva la copia.
3. Revisa `modules/atlas-docker.nix`, `arcane.env` y el archivo
   `/var/lib/arcane-agent/agent.env` de Pico. Por ejemplo, la declaración Nix
   `APP_URL` pasa a `ARCANE_APP_URL`. Actualiza las demás variables de Arcane
   según la tabla de la guía oficial. No antepongas `ARCANE_` a variables estándar o de terceros como `PUID`,
   `PGID`, `DOCKER_HOST`, `DOCKER_CONFIG`, `TZ` o `OTEL_*`.
4. Retira variables eliminadas y aplica las conversiones indicadas por la guía.
   En particular, no conserves nombres antiguos como `JWT_SECRET`,
   `EDGE_MUX_DISABLED` o `EDGE_TRANSPORT=poll`.
5. Actualiza Manager y cada agente a la misma versión mayor,
   incluido el Direct Agent declarado en
   `hosts/zimablade/configuration.nix`. Despliega después la configuración de
   Pico con `nix-deploy-pico`. El contenedor `arcane-docker-proxy` de Atlas
   es un proxy de la API Docker, no un agente Arcane.
6. Revisa los roles, las claves API y configura de nuevo los proveedores de
   notificaciones en System → Notifications.
7. Solo entonces cambia la imagen a 3.x, fija su digest y aplica la nueva
   generación. Valida logs, estado saludable, proyectos y notificaciones.

La guía oficial contiene los pasos completos y las tablas de variables y
cambios incompatibles:

- [Arcane: migrar a 3.0](https://getarcane.app/docs/get-started/migrate-v3)
- [Arcane: notas de versión](https://getarcane.app/changelog)

Para volver a 2.x, restaura la copia de seguridad completa de base de datos,
volumen, proyectos y archivos de entorno. No basta con regresar el tag de la
imagen después de que una migración de base de datos haya comenzado.
