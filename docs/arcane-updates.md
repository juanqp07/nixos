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

## Migración a Arcane 3.x

Una migración de versión principal **no se ejecuta con nix-maintain -y**. El
actualizador normal debe seguir deteniéndose en 2.17.3 hasta que se complete
este procedimiento. No cambies el tag por tu cuenta ni despliegues la
configuración v3 antes de adaptar los archivos de entorno.

La migración debe hacerse en dos fases: primero el Manager de Atlas y, cuando
esté disponible Arcane 3, volver a inscribir Pico como Agent normal. Durante
ese intervalo Pico puede aparecer desconectado en el panel.

### 1. Preparación y copias de seguridad

Comprueba que Atlas y Pico siguen usando Arcane 2.17.3. En ambos equipos,
guarda una copia antes de cambiar nada:

En Atlas:

~~~bash
sudo bash scripts/backup-arcane.sh
~~~

En Pico:

~~~bash
sudo bash scripts/backup-arcane-agent.sh
~~~

Las copias incluyen los volúmenes persistentes y los archivos de entorno. No
borres el volumen arcane-agent-data de Pico: debe conservarse para que el
Agent tenga almacenamiento persistente en v3.

Antes de arrancar v3, resuelve también los trabajos de Arcane que aparezcan
como **Needs attention**.

### 2. Adaptar el entorno del Manager en Atlas

En el archivo real
/mnt/datos/AppData/arcane/arcane.env se han detectado estas claves:

| Actual | Arcane 3 |
|---|---|
| ENCRYPTION_KEY | ARCANE_ENCRYPTION_KEY |
| DATABASE_URL | ARCANE_DATABASE_URL |

Renombra solo las claves; conserva exactamente sus valores. No compartas el
contenido del archivo, porque contiene secretos. La copia de seguridad anterior
conserva el archivo original.

Además, en modules/atlas-docker.nix, los nombres de las variables Arcane
declaradas dentro de environment deben quedar así:

| Actual | Arcane 3 |
|---|---|
| APP_URL | ARCANE_APP_URL |
| LOG_LEVEL | ARCANE_LOG_LEVEL |
| LOG_JSON | ARCANE_LOG_JSON |
| OIDC_ENABLED | ARCANE_OIDC_ENABLED |
| PROJECTS_DIRECTORY | ARCANE_PROJECTS_DIRECTORY |

Mantén PUID, PGID y DOCKER_HOST sin cambios: no son variables
específicas de Arcane. El montaje
/mnt/datos/arcane/projects:/app/data/projects también se conserva. Mantén
ARCANE_PROJECTS_DIRECTORY con el mismo valor de la variable anterior: Arcane 3
sigue soportando esa ruta.

El archivo postgres.env pertenece al contenedor PostgreSQL y no debe
renombrarse como si fuese un archivo de variables Arcane.

### 3. Resolver los digests de v3

La versión estable usada para esta migración es v3.0.1. No reutilices los
digests de v2 ni copies un digest por arquitectura. Obtén el digest del
manifiesto de cada imagen desde GHCR con el resolutor del repositorio:

~~~bash
python3 - <<'PY'
import importlib.util
from pathlib import Path

path = Path("scripts/update-docker-digests.py")
spec = importlib.util.spec_from_file_location("update_docker_digests", path)
if spec is None or spec.loader is None:
    raise SystemExit("No se pudo cargar el resolutor de digests")

module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

for repository in (
    "ghcr.io/getarcaneapp/manager",
    "ghcr.io/getarcaneapp/agent",
):
    print(f"{repository}:v3.0.1@{module.fetch_digest(repository, 'v3.0.1')}")
PY
~~~

En los módulos Nix se fijan las imágenes con el formato
ghcr.io/getarcaneapp/manager:v3.0.1@sha256:... y
ghcr.io/getarcaneapp/agent:v3.0.1@sha256:.... El digest debe salir del
comando anterior; no se debe inventar ni dejar sin fijar.

### 4. Actualizar primero el Manager de Atlas

Actualiza en modules/atlas-docker.nix la imagen del Manager a
ghcr.io/getarcaneapp/manager:v3.0.1 con el digest obtenido y aplica los
nombres de variables de la sección 2. No cambies PostgreSQL ni el proxy Docker.

Revisa el diff y evalúa la configuración antes de desplegar Atlas. Después del
despliegue, comprueba el estado y los logs:

~~~bash
docker inspect --format '{{.State.Status}} / {{if .State.Health}}{{.State.Health.Status}}{{else}}sin healthcheck{{end}}' arcane
docker logs --since 10m arcane
~~~

Inicia sesión en el panel y confirma que los proyectos existentes, usuarios y
configuración se han conservado. No continúes con Pico si el Manager no inicia
correctamente.

### 5. Volver a inscribir Pico como Agent

El contenedor actual de Pico es un **Direct Agent** de Arcane 2.x. En Arcane 3,
los Direct Agents pasan a estado **Pending** y deben inscribirse de nuevo:

1. Abre **Agents** en el Manager de Atlas y selecciona la entrada de Pico.
2. En **Connection & Agent**, genera un nuevo **Enrollment Token** y copia el
   comando de instalación.
3. No reutilices el valor antiguo de AGENT_TOKEN. Es el token de la
   instalación Direct Agent anterior.
4. Guarda el token nuevo, que empieza por arc_etkn_, en
   /var/lib/arcane-agent/agent.env con el nombre
   ARCANE_AGENT_TOKEN. No lo introduzcas en Git, en la configuración Nix ni
   en el historial de la shell. El archivo debe seguir siendo privado.

La configuración Nix del Agent debe usar la imagen
ghcr.io/getarcaneapp/agent:v3.0.1 con su digest y estas variables:

~~~nix
environment = {
  ARCANE_AGENT = "true";
  ARCANE_MANAGER_API_URL = "http://192.168.1.143:3552";
};
~~~

El token se carga desde /var/lib/arcane-agent/agent.env mediante
environmentFiles. Conserva el volumen arcane-agent-data:/app/data y el
montaje de /var/lib/dockge/stacks.

En v3 el Agent inicia una conexión saliente con el Manager. Por tanto, elimina
AGENT_MODE, EDGE_TRANSPORT y MANAGER_API_URL, quita la publicación
3553:3553 y elimina únicamente las reglas IPv4/IPv6 del firewall que
permitían el acceso entrante al puerto 3553. No elimines las reglas de
Technitium DNS (53, 8665 y 53443). Tampoco añadas un healthcheck TCP para 3553:
el nuevo Agent no escucha en ese puerto.

Despliega Pico después de haber generado y guardado el nuevo token. Comprueba
en el panel que Pico aparece conectado y que conserva sus proyectos, Git Sync,
webhooks y trabajos.

### 6. Comprobaciones posteriores y vuelta atrás

Comprueba lo siguiente antes de dar la migración por terminada:

- Manager y Agent muestran la misma versión 3.x.
- Pico aparece conectado y puede gestionar contenedores y proyectos.
- Los proyectos existentes y los stacks de Dockge siguen disponibles.
- Los roles personalizados y las claves API tienen los permisos esperados.
- Los proveedores de notificaciones se configuran de nuevo en
  **System → Notifications**, porque ahora son globales al Manager.
- Si usas arcane-cli o scripts que llamen a la API, actualízalos a v3 y
  revisa los cambios de comandos y rutas descritos en la guía oficial.

Para volver a 2.x, restaura la copia completa tomada antes de la migración:
base de datos, volumen del Manager, proyectos y archivos de entorno. En Pico,
restaura también el volumen arcane-agent-data, su archivo de entorno y la
configuración Nix anterior. **No basta con volver a etiquetar la imagen como
v2** después de que Arcane haya migrado la base de datos.

Documentación oficial:

- [Arcane: migrar a 3.0](https://getarcane.app/docs/get-started/migrate-v3)
- [Arcane: variables de entorno](https://getarcane.app/docs/reference/environment-variables)
- [Arcane: agentes remotos](https://getarcane.app/docs/remote/agents)
- [Arcane: volver de 3.0 a 2.x](https://getarcane.app/docs/get-started/downgrading)
