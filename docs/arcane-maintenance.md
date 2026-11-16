# Mantenimiento de Arcane en Atlas

## Política de versiones

`nix-maintain maintain` y `nix-maintain update` comprueban Arcane cuando se ejecutan en Atlas. El actualizador consulta las releases estables oficiales de `getarcaneapp/arcane`, excluye borradores y prereleases y resuelve el digest publicado en GHCR.

- Solo actualiza dentro de la misma versión mayor que ya está fijada en `modules/atlas-docker.nix`.
- Actualiza conjuntamente la etiqueta y su digest SHA256; nunca usa `latest`.
- No modifica `modules/atlas-docker.nix` si el archivo ya tiene cambios locales.
- Si GitHub o GHCR no responden, conserva la versión actual y permite que continúe el mantenimiento NixOS.
- Si existe una versión mayor nueva, la muestra como disponible pero no la instala.

El actualizador cambia el archivo local `modules/atlas-docker.nix`. No crea commits, no hace push y no descarta cambios. Revisa el resultado con:

```bash
git diff -- modules/atlas-docker.nix
```

Conserva el cambio en Git después de revisarlo. Si cancelas la activación, la versión queda preparada en el checkout; `nix-maintain apply` detectará que difiere del contenedor activo y hará la copia de seguridad antes de aplicarla.

## Copia de seguridad previa

Antes de aplicar una imagen diferente en Atlas, el mantenimiento compara la imagen declarada con `arcane` en Docker. Si cambia, exige que la copia previa termine correctamente; ante un error, no ejecuta `nixos-rebuild switch` ni `nixos-rebuild boot`.

La copia se almacena en:

```text
/mnt/datos/AppData/arcane/backups/nix-maintain/<UTC timestamp>/
```

Incluye:

- Volcado lógico de todas las bases de datos y roles PostgreSQL (`pg_dumpall`).
- Volumen de datos de Arcane (`/app/data`).
- Directorio externo de proyectos.
- `arcane.env` y `postgres.env`, necesarios para recrear el servicio.
- Manifiesto con la imagen anterior, la nueva y la fecha de la copia.

Los archivos contienen datos y credenciales. El directorio se crea con permisos `0700` y los archivos con `0600`. Las copias no se eliminan automáticamente: revisa el espacio disponible y gestiona su retención manualmente.

La copia lógica de PostgreSQL se toma mientras el servidor está activo. El archivo `/app/data` y el directorio de proyectos se archivan antes de recrear el contenedor. No se para PostgreSQL ni se alteran los volúmenes en el proceso de copia.

## Verificación después de actualizar

Cuando `system.autoUpgrade.operation = "switch"`, el mantenimiento espera a que:

- El contenedor `arcane` ejecute exactamente la imagen declarada.
- El healthcheck de Arcane llegue a `healthy`.
- PostgreSQL esté ejecutándose y responda a `pg_isready`.

Si se preparó una generación con operación `boot`, la copia se hace antes de preparar el siguiente arranque. Después de reiniciar Atlas, ejecuta:

```bash
nix-arcane-check
```

El comando también está disponible para comprobar el estado manualmente cuando sea necesario. Si falla, conserva la copia, revisa los logs con `docker logs arcane` y `docker logs arcane-postgres` y no elimines la copia previa.

## Actualización mayor: Arcane 3.x

La migración de Arcane 2.x a 3.x no se incluye en esta automatización. El actualizador no cambiará de 2.x a 3.x aunque detecte una release estable.

Arcane 3.0 requiere una migración explícita: renombrar variables de entorno con el prefijo `ARCANE_`, revisar variables eliminadas o invertidas, cambiar los nombres de las imágenes GHCR donde corresponda, actualizar agentes/CLI y revisar notificaciones y permisos. La documentación oficial exige llegar a 2.17.3 antes de migrar, hacer una copia de base de datos, `/app/data`, proyectos y ficheros de entorno, y actualizar Manager y agentes siguiendo el orden indicado.

Documentación oficial: <https://getarcane.app/docs/get-started/migrate-v3>.

El actualizador mantiene la instalación en la rama 2.x hasta que se apruebe y prepare esa migración por separado.
