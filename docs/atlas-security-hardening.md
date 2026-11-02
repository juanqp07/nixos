# Endurecimiento de red y CrowdSec en Atlas

Este documento acompaña los cambios NixOS de la rama `security/atlas-docker-hardening`.
La configuración queda declarada, pero no se aplica al servidor hasta desplegar la generación nueva.

## Qué cambia en Atlas

- Arcane deja de montar `/var/run/docker.sock` directamente. Usa `wollomatic/socket-proxy` con el socket montado en solo lectura, sin capabilities y con allowlist de operaciones Docker.
- Se bloquea el acceso directo a los puertos publicados de aplicaciones y paneles desde Internet. Los paneles siguen accesibles desde la LAN `192.168.1.0/24` y NetBird (`wt0`); los bridges Docker conservan el acceso del proxy y de las comunicaciones internas.
- Las APIs administrativas de IPFS RPC (5553), CrowdSec LAPI (8019) y Gluetun Control (8001) quedan accesibles solo desde bridges Docker, no desde Internet, LAN ni NetBird.
- La restricción se instala en `DOCKER-USER`, ya que los puertos publicados por Docker pueden saltarse las reglas normales de INPUT de NixOS.
- No se filtran los puertos públicos de Zoraxy (80/443), SSH (22), RustDesk, Syncthing ni Minecraft (25565).

La lista protegida incluye DNS/AdGuard (53), IPFS RPC (5553), CrowdSec LAPI (8019), Gluetun API/proxies (8001, 1800, 8888), Zoraxy Admin (8000), Arcane (3552), paneles de administración y puertos HTTP directos de aplicaciones. Los paneles siguen accesibles desde la LAN/NetBird. Según indicas, no están publicados mediante redirecciones del router hacia Internet; el filtro DOCKER-USER queda como segunda barrera para los puertos directos. IPFS RPC, CrowdSec LAPI y Gluetun Control quedan únicamente en bridges Docker.

La regla IPv6 permite NetBird, bridges Docker y direcciones ULA (`fc00::/7`). Los clientes LAN que solo tengan IPv6 global deberán entrar por IPv4 o NetBird para acceder directamente a los paneles.

## CrowdSec + Zoraxy: corregir la adquisición

### 1. Diagnóstico confirmado

CrowdSec ya tiene registrado el bouncer `zoraxy-crowdsec-bouncer`. Los registros del 29/10/2026 muestran consultas `GET /v1/decisions/stream` con HTTP 200 cada 10 segundos. Por tanto, la comunicación bouncer → LAPI ya funciona.

El Compose que has compartido ya monta el directorio de logs de Zoraxy en CrowdSec en modo de solo lectura y en la misma ruta interna:

- Host: `/mnt/datos/AppData/zoraxy/log/`
- Contenedor CrowdSec: `/opt/zoraxy/log/`

Por tanto, no hay que añadir otro volumen ni sustituir la ruta por `/var/log/zoraxy`. La advertencia `No matching files for pattern /opt/zoraxy/log/zr_*.log` indica que, en el momento de iniciar la adquisición, el patrón no encontró ningún fichero. Hay que comprobar si el directorio del host está vacío, si Zoraxy está generando archivos con otro nombre o si CrowdSec inició antes del primer log.

### 2. Comprobaciones necesarias

En Atlas, comparar el contenido del directorio de logs del host con lo que ve CrowdSec dentro de su contenedor, y revisar el contenido de `/etc/crowdsec/acquis.d/zoraxy.yaml`. La adquisición correcta para el montaje actual es:

```yaml
filenames:
  - /opt/zoraxy/log/zr_*.log
labels:
  type: zoraxy
```

No crear una ruta alternativa ni duplicar el bind mount. Una vez que existan ficheros que coincidan con el patrón, comprobar `cscli metrics show acquisition` para verificar que aumentan las líneas leídas.

### 3. Colección y parser

Tu Compose ya declara `COLLECTIONS: "Raithmir/zoraxy"`, así que la colección se instala mediante la variable de entorno de CrowdSec. No hay que instalarla manualmente otra vez si ya figura en `cscli collections list`. Esta colección incorpora el parser de Zoraxy y escenarios HTTP genéricos. El parser requiere el formato de logs de Zoraxy 3.2.0 o posterior.

Si CrowdSec lee líneas pero no las parsea, el siguiente paso es revisar una línea real del log con `cscli explain` y confirmar que coincide con el formato esperado por el parser.

### 4. Mantener la API LAPI solo en la red Docker

El bouncer y CrowdSec deben compartir una red Docker definida por el usuario. La dirección del API dentro de esa red es:

```text
http://crowdsec:8080
```

En el proyecto CrowdSec, eliminar el puerto publicado del host:

```yaml
# Quitar:
ports:
  - "8019:8080"
```

El puerto 8080 debe quedar accesible solo entre contenedores de la red. El plugin de Zoraxy no necesita el puerto host 8019.

En los proyectos Compose gestionados por Arcane, eliminar también estos mapeos del host (no basta con ocultarlos en el router):

```yaml
# IPFS/Kubo: quitar
ports:
  - "5553:5001"

# CrowdSec: quitar
ports:
  - "8019:8080"

# Gluetun: quitar
ports:
  - "8001:8000"
```

Mantener los puertos internos de los contenedores y las redes Docker necesarias. Los servicios que deban consultar estas API deben hacerlo por nombre de contenedor dentro de la red correspondiente. En particular, el plugin debe usar `http://crowdsec:8080`, no el puerto host 8019.

### 5. Configuración del plugin instalado en Zoraxy

Conservar la clave de bouncer ya registrada si sigue siendo válida. No ponerla en Git, documentación, capturas o mensajes. El `config.yaml` del plugin debe tener esta estructura (usar la clave real ya existente, no el texto de ejemplo):

```yaml
api_key: "<CLAVE_BOUNCER_EXISTENTE>"
agent_url: "http://crowdsec:8080"
stream_update_frequency: 10s
log_level: warning
is_proxied_behind_cloudflare: false
```

`is_proxied_behind_cloudflare` debe permanecer en `false` mientras el DNS de Cloudflare esté en modo DNS-only (sin proxy naranja). Cambiarlo solo si el tráfico pasa realmente por el proxy de Cloudflare.

Reiniciar el plugin desde Zoraxy después de editar el archivo. El log del bouncer debería seguir mostrando consultas correctas a `/v1/decisions/stream`.

### 6. Activar la protección por etiquetas en Zoraxy

El bouncer es un *Dynamic Capture Plugin*: que aparezca como activo no significa que proteja automáticamente todos los hosts.

En el panel de Zoraxy:

1. Abrir la gestión de Plugins y crear/seleccionar una etiqueta, por ejemplo `protected`.
2. Asignar el plugin CrowdSec a esa etiqueta/grupo.
3. Asignar esa misma etiqueta a cada proxy host que se quiera proteger.
4. Guardar y comprobar las estadísticas del plugin: debe aumentar el contador de peticiones procesadas para esos hosts.

El plugin actual aplica decisiones de ban. No proporciona CAPTCHA. Al ser un plugin de captura dinámica, no puede interceptar rutas que otro plugin estático ya haya capturado y no debe considerarse un reemplazo de la autenticación de los paneles.

## Verificación después de aplicar

En Atlas:

```bash
docker exec crowdsec cscli metrics show acquisition
docker exec crowdsec cscli bouncers list
docker exec crowdsec cscli decisions list
```

La fuente de Zoraxy debe mostrar líneas leídas/procesadas y no debe aparecer el aviso `No matching files for pattern`. En la lista de bouncers debe figurar el bouncer de Zoraxy con conexión reciente. Después, generar tráfico contra un host etiquetado y comprobar el contador del plugin.

Para verificar los filtros Docker:

```bash
sudo iptables -vnL DOCKER-USER
sudo ip6tables -vnL DOCKER-USER
```

No publicar la API de CrowdSec ni la API RPC de IPFS en Internet. El puerto 5553 es la API administrativa de Kubo; mantenerla en la red interna salvo que exista una necesidad explícita y una capa de autenticación/protección adicional.

## Referencias

- [CrowdSec Docker datasource](https://docs.crowdsec.net/docs/data_sources/docker/)
- [CrowdSec acquisition sources](https://docs.crowdsec.net/docs/log_processor/data_sources/intro/)
- [Zoraxy + CrowdSec: guía de adquisición y parser](https://github.com/tobychui/zoraxy/discussions/338)
- [Zoraxy CrowdSec Bouncer: instalación, etiquetas y configuración](https://github.com/AnthonyMichaelTDM/zoraxy_crowdsec_bouncer)
- [Arcane: Docker socket proxy](https://getarcane.app/docs/security/socket-proxy)
