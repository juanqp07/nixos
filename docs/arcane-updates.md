# Actualizaciones de Arcane en Atlas y Pico

Arcane se declara en el flake como imágenes OCI fijadas por versión y digest:
el Manager en `modules/atlas-docker.nix` y el Agent en
`hosts/zimablade/configuration.nix`. NixOS controla el ciclo de vida de ambos
contenedores; no los actualices por separado desde Docker ni habilites el
actualizador interno de Arcane.

## Estado declarado en el repositorio

La configuración de `main` fija actualmente:

- **Atlas:** Arcane Manager `v3.0.1`.
- **Pico:** Arcane Agent `v3.0.1`, alineado con la versión del Manager.
- **Conexión:** el Agent inicia la conexión hacia
  `http://192.168.1.143:3552` (Manager en Atlas).
- **Puerto 3553:** el Agent v3 no escucha ni publica TCP/3553. No se debe
  abrir ese puerto en INPUT ni crear una regla DOCKER-USER para él.

Esto describe la configuración versionada; no demuestra por sí solo que los
contenedores estén desplegados, que Pico aparezca Online o que el token de
inscripción del host sea válido.

## Actualizaciones normales con nix-maintain

El mantenimiento separa las tareas según el servidor en el que se ejecuta:

### Atlas: Arcane Manager

Al ejecutar `nix-maintain` o `nix-maintain -y` en Atlas:

1. Consulta las releases estables de Arcane Manager y selecciona una versión
   compatible dentro de la misma rama principal.
2. Obtiene el digest del manifiesto en GHCR.
3. Ejecuta `sudo bash scripts/backup-arcane.sh` antes de modificar la imagen.
4. Actualiza únicamente la referencia del Manager en
   `modules/atlas-docker.nix`.

### Pico: Arcane Agent

Al ejecutar `nix-maintain` o `nix-maintain -y` en Pico:

1. Lee la versión fijada del Manager en `modules/atlas-docker.nix` y la imagen
   del Agent en `hosts/zimablade/configuration.nix`.
2. Usa el Manager como fuente de verdad y propone alinear el Agent con esa
   versión si ambos pertenecen a la misma rama principal.
3. No hace downgrade si el Agent es más nuevo y no aplica automáticamente
   migraciones entre versiones principales distintas.
4. Antes de cambiar la imagen, ejecuta
   `sudo bash scripts/backup-arcane-agent.sh`.
5. Actualiza únicamente la referencia de imagen del Agent en
   `hosts/zimablade/configuration.nix`.

Con `-y` se aceptan automáticamente solo actualizaciones de la misma versión
principal. Si Manager y Agent ya coinciden, no se modifica nada. Si sus versiones
principales difieren, el mantenedor se detiene y remite a la guía de migración.

Los cambios quedan en el checkout local. El script no ejecuta `git add`,
`git commit`, `git stash` ni despliega remotamente. Revisa el diff, evalúa
las configuraciones y prepara/despliega las generaciones de Atlas y Pico de
forma explícita. En Pico, el checkout debe contener la misma versión fijada del
Manager que se haya decidido desplegar en Atlas.

Ambos servidores usan `system.autoUpgrade.operation = "boot"`: la generación
preparada se activa en el siguiente arranque, no durante la comprobación.

## Copias de seguridad

### Manager en Atlas

Antes de actualizar la imagen, el mantenedor ejecuta:

```bash
sudo bash scripts/backup-arcane.sh
```

La copia se guarda en
`/mnt/datos/AppData/arcane/backups/<fecha-UTC>.<sufijo>/` e incluye:

- Dump lógico de PostgreSQL (`arcane-postgres`).
- Volumen Docker `arcane-data`.
- Directorio de proyectos `/mnt/datos/arcane/projects`.
- `arcane.env` y `postgres.env`.
- La declaración `modules/atlas-docker.nix` utilizada.

El script detiene Arcane mientras copia los datos y lo vuelve a iniciar al
terminar. Los backups contienen secretos y datos privados: conserva permisos
restringidos y no los subas al repositorio.

### Agent en Pico

Antes de actualizar la imagen, el mantenedor ejecuta:

```bash
sudo bash scripts/backup-arcane-agent.sh
```

La copia se guarda en
`/var/lib/arcane-agent/backups/<fecha-UTC>.<sufijo>/` e incluye el volumen
Docker `arcane-agent-data`, el archivo privado `agent.env`, la declaración Nix
del Agent y la referencia de imagen del contenedor. El agente se detiene de
forma ordenada durante el archivo del volumen y se reinicia al terminar.
El archivo `agent.env` contiene el token de inscripción: trata el backup como
un secreto y mantenlo fuera de Git.

## Migración de Arcane 2 a Arcane 3: ya aplicada

La configuración versionada ya refleja Arcane 3.0.1 en Atlas y Pico. Los
documentos `docs/arcane-v3-atlas.md` y `docs/arcane-v3-pico.md` conservan el
procedimiento y las comprobaciones de la migración, como referencia histórica
y para recuperación.

Puntos importantes de la migración:

1. Se respalda el Manager completo antes de actualizar la base de datos y los
   volúmenes.
2. Las variables de Arcane del Manager usan el prefijo `ARCANE_`; entre ellas,
   `ARCANE_ENCRYPTION_KEY` y `ARCANE_DATABASE_URL`. Las variables estándar o
   de terceros como `PUID`, `PGID` y `DOCKER_HOST` no reciben ese prefijo.
3. Los agentes Direct antiguos pueden quedar en estado Pending y deben
   reinscribirse con un token nuevo de Arcane 3. En Pico el archivo privado
   `/var/lib/arcane-agent/agent.env` debe contener
   `ARCANE_AGENT_TOKEN=...`; no reutilices el antiguo `AGENT_TOKEN`.
4. Se conserva el volumen `arcane-agent-data`, que almacena el estado y la
   clave persistente del agente.
5. El Agent v3 inicia la conexión hacia Atlas por TCP/3552. No hay un puerto
   entrante 3553 que publicar o permitir en Pico. La cadena
   `PICO-TECHNITIUM-PRIVATE` sigue protegiendo únicamente los puertos de
   Technitium.

La migración de la base de datos de Arcane 3 es incompatible hacia atrás. Para
volver a 2.x no basta con cambiar el tag: restaura la copia completa previa de
base de datos, volúmenes, proyectos y archivos de entorno.

Para futuras migraciones mayores, sigue la documentación oficial y no las
apliques mediante el flujo automático de mantenimiento:

- [Arcane: migrar a 3.0](https://getarcane.app/docs/get-started/migrate-v3)
- [Arcane: agentes remotos](https://getarcane.app/docs/remote/agents)
- [Arcane: notas de versión](https://getarcane.app/changelog)
