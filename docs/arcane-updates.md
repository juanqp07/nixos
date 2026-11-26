# Actualizaciones de Arcane en Atlas y Pico

Arcane se declara en el flake como imágenes OCI fijadas por versión y digest:
el Manager en `modules/atlas/arcane.nix` y el Agent en
`hosts/zimablade/configuration.nix`. NixOS controla el ciclo de vida de ambos
contenedores; no los actualices por separado desde Docker ni habilites el
actualizador interno de Arcane.

## Estado declarado en el repositorio

La configuración de `main` fija actualmente:

- **Atlas:** Arcane Manager `v3.1.1`, con el digest ya observado en runtime.
- **Pico:** Arcane Agent `v3.0.1`; sigue en la misma rama mayor y no se actualiza
  en este cambio, a la espera de revisar su estado runtime.
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
   `modules/atlas/arcane.nix`.

### Pico: Arcane Agent

Al ejecutar `nix-maintain` o `nix-maintain -y` en Pico:

1. Lee la URL del Manager desde `ARCANE_MANAGER_API_URL` en
   `hosts/zimablade/configuration.nix`.
2. Consulta en tiempo real `/api/app/version` de Atlas y usa
   `currentVersion` como versión de referencia. No depende de que el checkout
   de Pico tenga sincronizado `modules/atlas/arcane.nix` ni de publicar cambios
   locales de los servidores en GitHub.
La versión consultada es la que está ejecutándose en Atlas, no una generación
que solo esté preparada para el siguiente arranque. Por tanto, actualiza Pico
después de que Atlas haya arrancado con la nueva versión del Manager.
3. No hace downgrade si el Agent es más nuevo y no aplica automáticamente
   migraciones entre versiones principales distintas.
4. Antes de cambiar la imagen, ejecuta
   `sudo bash scripts/backup-arcane-agent.sh`.
5. Actualiza únicamente la referencia de imagen del Agent en
   `hosts/zimablade/configuration.nix`.

Con `-y` se aceptan automáticamente solo actualizaciones de la misma versión
principal. Si Manager y Agent ya coinciden, no se modifica nada. Si sus versiones
principales difieren, el mantenedor se detiene y remite a la guía de migración.
Si Atlas no responde o su endpoint de versión devuelve datos inválidos, Pico
omite la actualización sin recurrir a una versión antigua del checkout.

Los cambios quedan en el checkout local. El script no ejecuta `git add`,
`git commit`, `git stash` ni despliega remotamente. Revisa el diff, evalúa
las configuraciones y prepara/despliega las generaciones de Atlas y Pico de
forma explícita. Pico obtiene la versión de referencia directamente del
Manager que está ejecutándose en Atlas; no es necesario subir los cambios
locales de Atlas a GitHub ni sincronizar manualmente ese archivo en Pico.

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
- La declaración `modules/atlas/arcane.nix` utilizada.

El script detiene `docker-arcane.service` mientras copia los datos y lo vuelve
a iniciar mediante systemd al terminar. Esto es importante porque
`oci-containers` elimina el contenedor al detenerlo (`--rm`); systemd lo crea
de nuevo a partir de la declaración NixOS. No se debe intentar recuperarlo con
`docker start`. Los backups contienen secretos y datos privados: conserva
permisos restringidos y no los subas al repositorio.

### Agent en Pico

Antes de actualizar la imagen, el mantenedor ejecuta:

```bash
sudo bash scripts/backup-arcane-agent.sh
```

La copia se guarda en
`/var/lib/arcane-agent/backups/<fecha-UTC>.<sufijo>/` e incluye el volumen
Docker `arcane-agent-data`, el archivo privado `agent.env`, la declaración Nix
del Agent y la referencia de imagen del contenedor. El script detiene
`docker-arcane-agent.service` durante el archivo del volumen y lo vuelve a
iniciar mediante systemd. Como `oci-containers` elimina el contenedor al
detenerlo (`--rm`), systemd lo crea de nuevo a partir de la declaración NixOS;
no se debe usar `docker start` para recuperarlo.
El archivo `agent.env` contiene el token de inscripción: trata el backup como
un secreto y mantenlo fuera de Git.

## Migración de Arcane 2 a Arcane 3: ya aplicada

La configuración versionada refleja Arcane 3 en ambos hosts. En esta rama,
Atlas declara Manager v3.1.1 y Pico mantiene Agent v3.0.1 hasta completar su
revisión. Los documentos `docs/arcane-v3-atlas.md` y
`docs/arcane-v3-pico.md` conservan el procedimiento y las comprobaciones de
la migración, como referencia histórica y para recuperación.

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
