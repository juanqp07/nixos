# Actualizaciones de Arcane en Atlas

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
Agent que Pico ejecuta desde `hosts/zimablade/configuration.nix` conserva su
versión fijada: este paso no lo actualiza ni lo despliega. Revisa las notas de
la release antes de decidir si también corresponde actualizarlo; para una
migración mayor sí debe coordinarse con el Manager.

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

## Copia de seguridad

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

El dump de PostgreSQL se genera con `pg_dumpall` mientras el servidor sigue
activo. El volumen de aplicación y los proyectos se archivan sin detener Arcane;
por tanto, el dump SQL es la copia consistente de la base de datos y el archivo
del volumen es una captura de sus archivos en ese momento. Las copias contienen secretos y datos privados: el directorio queda con
permisos `0700` y sus archivos con permisos privados. No se borran copias
antiguas automáticamente; revisa el espacio ocupado antes de limpiarlas.

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
