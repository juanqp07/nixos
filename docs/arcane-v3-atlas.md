# Arcane 3 en Atlas: migración del Manager

Esta nota documenta la migración de **Arcane Manager en Atlas** a v3.0.1.
La configuración actual de `main` ya fija el Manager en esa versión y también
fija Arcane Agent v3.0.1 en Pico; la migración del Agent se documenta por separado
en [arcane-v3-pico.md](arcane-v3-pico.md). Los pasos siguientes describen el
procedimiento histórico, no una actualización pendiente.

## Cambios incluidos

- Fija `ghcr.io/getarcaneapp/manager` en v3.0.1 con el digest multi-arquitectura verificado.
- Renombra en Nix las variables propias de Arcane: `APP_URL`, `LOG_LEVEL`, `LOG_JSON`, `OIDC_ENABLED` y `PROJECTS_DIRECTORY` reciben el prefijo `ARCANE_`.
- Mantiene `PUID`, `PGID` y `DOCKER_HOST` sin cambios.
- No modifica PostgreSQL, sus credenciales ni el socket proxy.

El archivo `/mnt/datos/AppData/arcane/arcane.env` no está versionado y su
contenido real no puede comprobarse desde este repositorio. Durante la migración,
las claves de Arcane debían quedar como `ARCANE_ENCRYPTION_KEY` y
`ARCANE_DATABASE_URL`; confirma esos nombres directamente en Atlas sin mostrar
ni compartir sus valores.

## Lista histórica de la migración

1. En el estado previo a la migración, comprueba que Atlas y Pico están en
   Arcane 2.17.3 y que no hay trabajos de Arcane en estado `Needs attention`.
2. Ejecuta la copia de seguridad del Manager:
   `sudo bash scripts/backup-arcane.sh`.
3. Haz una copia del archivo de entorno y renombra sus dos claves:
   ```bash
   sudo cp -a /mnt/datos/AppData/arcane/arcane.env \
     "/mnt/datos/AppData/arcane/arcane.env.bak.$(date -u +%Y%m%dT%H%M%SZ)"
   sudo sed -i -E \
     's/^([[:space:]]*(export[[:space:]]+)?)(ENCRYPTION_KEY|DATABASE_URL)=/\1ARCANE_\3/' \
     /mnt/datos/AppData/arcane/arcane.env
   ```
   Esto conserva los valores existentes. El nombre nuevo es
   `ARCANE_ENCRYPTION_KEY` y `ARCANE_DATABASE_URL`; no copies ni publiques
   sus valores.
4. Revisa el diff Nix y prepara la nueva generación. No borres volúmenes ni
   cambies el valor de `DATABASE_URL`: únicamente cambia el nombre de la variable.
5. Tras actualizar Atlas, valida el healthcheck, logs, acceso al panel y acceso
   a los proyectos. En la secuencia original, Pico se reinscribía después con
   los pasos de [arcane-v3-pico.md](arcane-v3-pico.md).

## Comprobaciones posteriores

```bash
docker inspect --format '{{.State.Status}} / {{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' arcane
docker logs --since 10m arcane
```

Arcane v3 hace una migración de base de datos. Para volver a 2.x no basta con
cambiar la etiqueta de imagen: hay que restaurar la copia previa completa
(base de datos, volumen, proyectos y archivos de entorno).

Guía oficial: https://getarcane.app/docs/get-started/migrate-v3
