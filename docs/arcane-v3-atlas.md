# Arcane 3 en Atlas: migración del Manager

Este cambio prepara **Arcane Manager en Atlas** para v3.0.1. No actualiza Pico:
el antiguo Direct Agent se migra en un PR separado y deberá reinscribirse después
de que el Manager esté funcionando en v3.

## Cambios incluidos

- Fija `ghcr.io/getarcaneapp/manager` en v3.0.1 con el digest multi-arquitectura verificado.
- Renombra en Nix las variables propias de Arcane: `APP_URL`, `LOG_LEVEL`, `LOG_JSON`, `OIDC_ENABLED` y `PROJECTS_DIRECTORY` reciben el prefijo `ARCANE_`.
- Mantiene `PUID`, `PGID` y `DOCKER_HOST` sin cambios.
- No modifica PostgreSQL, sus credenciales ni el socket proxy.

El archivo `/mnt/datos/AppData/arcane/arcane.env` no está versionado. En el
estado actual contiene las claves `ENCRYPTION_KEY` y `DATABASE_URL`; ambas
deben renombrarse también.

## Antes de desplegar

1. Comprueba que Atlas y Pico siguen en Arcane 2.17.3 y que no hay trabajos de
   Arcane en estado `Needs attention`.
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
   a los proyectos. El agente de Pico puede quedar desconectado hasta completar
   la segunda parte y la reinscripción del agente v3.

## Comprobaciones posteriores

```bash
docker inspect --format '{{.State.Status}} / {{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' arcane
docker logs --since 10m arcane
```

Arcane v3 hace una migración de base de datos. Para volver a 2.x no basta con
cambiar la etiqueta de imagen: hay que restaurar la copia previa completa
(base de datos, volumen, proyectos y archivos de entorno).

Guía oficial: https://getarcane.app/docs/get-started/migrate-v3
