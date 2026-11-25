# GitHub Actions runners de Atlas

## Diseño

Atlas aloja tres registros independientes de GitHub Actions para los repositorios privados:

| Runner | Repositorio | Etiqueta adicional |
|---|---|---|
| `atlas-fctv` | `juanqp07/fctv` | `fctv` |
| `atlas-fctv-2` | `juanqp07/fctv` | `fctv` |
| `atlas-kigo` | `juanqp07/kigo` | `kigo` |

Los tres registros son **persistentes**: un listener permanece conectado y procesa trabajos sucesivos. FCTV dispone de dos workers para ejecutar hasta dos jobs en paralelo; Kigo tiene uno. Cada servicio tiene su propio nombre, estado, workspace y usuario dinámico de systemd. Los tres comparten una slice limitada conjuntamente a 3 CPU equivalentes y 10 GiB de RAM (8 GiB como umbral alto), con prioridad reducida frente a los servicios normales de Atlas.

Los runners no pertenecen al grupo `docker` y no reciben acceso a `/var/run/docker.sock`. Solo pueden acceder al socket Unix de un BuildKit rootless dedicado.

## Herramientas disponibles

Todos los runners reciben herramientas comunes desde `extraPackages`:

- `curl`, `jq`, `python3`, `gawk` (comando `awk`) y `unzip`.
- Herramientas base del módulo de GitHub Runner: Bash, coreutils, Git, tar, gzip y el binario `nix`.

El runner de FCTV recibe además, de forma exclusiva:

| Paquete Nix | Uso |
|---|---|
| `nodejs_22` | Checks web y validación de contratos |
| `postgresql_17` | PostgreSQL temporal para tests de integración |
| `gcc` | CGO y detector de carreras de Go |
| `jdk17` | Gradle y SDK Android |
| `gitleaks` | Escaneo de secretos por rangos de commits |
| `gh` | GitHub CLI (`gh`) para consultar y gestionar recursos de GitHub desde los jobs |

El runner de Kigo recibe además, de forma exclusiva:

| Paquete Nix | Uso |
|---|---|
| `gcc` | CGO y detector de carreras de Go |
| `postgresql_17` | Dos instancias PostgreSQL temporales para tests de integración |
| `redis` | Redis temporal para pruebas Anti-Raid |

La revisión fijada de `nixpkgs-stable` proporciona Redis **8.8.4**. El CI de Kigo lo usa para integración; el Compose de producción continúa en Redis 7, por lo que la versión de CI debe revisarse al actualizar el lockfile.

Go 1.27.4 se instala mediante `actions/setup-go@v6`: el pin estable usado por Atlas no incluye `go_1_27`. No se ejecuta código Go ni se descargan toolchains con el daemon Nix.

**Los workflows no deben ejecutar `nix shell`, `nix build`, `nix develop` ni otros comandos que necesiten contactar con `nix-daemon`.** Los runners usan usuarios dinámicos y el daemon está restringido a `@wheel`. Dar acceso a esos usuarios o añadirlos a `wheel` ampliaría innecesariamente sus privilegios. Las herramientas de CI deben declararse en `extraPackages` y estar en el `PATH` del servicio.

Se conserva `NIX_LD` y `NIX_LD_LIBRARY_PATH` explícitamente en los servicios para binarios glibc externos, como algunas herramientas descargadas por Android SDK. Esto no concede acceso al daemon Nix.

## Ciclo de vida y recuperación de los runners

Los runners usan `ephemeral = false` porque Atlas es un host fijo, no un pool efímero autoscalado. La sesión y el registro de GitHub se mantienen entre trabajos; el listener no se desregistra ni se vuelve a registrar después de cada job. Así se evita la carrera que se producía al registrar repetidamente el mismo nombre con `--replace` mientras GitHub todavía estaba cerrando la sesión anterior.

El estado de autenticación permanece en `/var/lib/github-runner/<servicio>`; cada workspace está en el `RuntimeDirectory` de systemd bajo `/run/github-runner/<servicio>`. Los directorios de trabajo se limpian al iniciar el servicio, mientras que las credenciales locales necesarias para conservar el registro se mantienen.

La recuperación no depende de borrar los registros a mano:

1. Un guard de systemd se ejecuta con el usuario dinámico del runner y antes de los hooks de configuración del módulo NixOS.
2. Si el marcador de configuración existe pero GitHub Runner ha eliminado `.runner` o `.credentials`, el guard invalida los marcadores locales.
3. El hook estándar de NixOS detecta el estado incompleto, limpia el estado anterior y vuelve a registrar el runner usando el PAT protegido.
4. `replace = true` solo actúa durante esa nueva configuración; no sustituye un registro sano en cada trabajo o reinicio normal.

Los servicios usan `Restart = always` y un intervalo de 30 segundos. Un límite de cinco arranques en quince minutos evita ciclos de reinicio ilimitados si la API de GitHub, el token o el registro vuelven a fallar. Los errores transitorios de conexión los gestiona primero el propio listener.

## Seguridad y aislamiento

El repositorio `juanqp07/nixos` es público. Sus workflows de PR y push deben seguir usando runners alojados por GitHub, nunca Atlas. GitHub recomienda evitar runners propios en repositorios públicos porque cualquier persona puede abrir una PR e intentar ejecutar código no confiable en el servidor. Referencias: [seguridad de self-hosted runners](https://docs.github.com/en/actions/reference/security/secure-use) y [facturación de Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Los runners de Atlas solo deben ejecutar workflows de los repositorios privados de confianza. En particular, no se deben retirar las condiciones que evitan ejecutar código procedente de forks no confiables. Un workflow puede ejecutar código arbitrario con los permisos del runner.

No se añade ninguno de los runners al grupo `docker`, no se monta el socket Docker de producción y no se desactiva el aislamiento systemd.

## 1. Crear dos Fine-grained PATs

Crea **un token diferente para cada repositorio** desde GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens.

Para cada token:

1. Resource owner: `juanqp07`.
2. Repository access: **Only select repositories** y selecciona únicamente `fctv` o `kigo`.
3. Repository permissions: **Administration: Read and write**.
4. Configura una expiración razonable y guarda el token (prefijo `github_pat_`).

El endpoint que crea el token de registro de un runner de repositorio exige permiso de escritura `Administration`. Consulta [la documentación de GitHub](https://docs.github.com/en/rest/actions/self-hosted-runners#create-a-registration-token-for-a-repository).

No reutilices un PAT entre repositorios ni concedas acceso a otros repositorios.

## 2. Instalar los tokens en Atlas

En Atlas, guarda cada PAT en su archivo correspondiente. El contenido debe ser una sola línea, sin salto de línea. El PAT de FCTV se reutiliza únicamente para registrar los dos runners del mismo repositorio; el PAT de Kigo sigue siendo independiente. No añadas estos archivos a Git, Nix Store, `flake.nix` ni a `configuration.nix`.

```bash
sudo install -d -m 0700 -o root -g root /var/lib/secrets/github-runner

for repo in fctv kigo; do
  read -rsp "Fine-grained PAT for $repo: " TOKEN
  printf '\n'
  printf '%s' "$TOKEN" | sudo tee "/var/lib/secrets/github-runner/$repo.token" >/dev/null
  unset TOKEN
  sudo chown root:root "/var/lib/secrets/github-runner/$repo.token"
  sudo chmod 0600 "/var/lib/secrets/github-runner/$repo.token"
done
```

Puedes provisionar los tokens por separado. El servicio correspondiente no arranca hasta que exista su archivo.

## 3. Aplicar NixOS y comprobar los servicios

Programa la migración cuando no haya jobs en ejecución. Primero construye la nueva generación y después detén los listeners antiguos para que no quede ninguna sesión anterior durante el cambio de modelo:

```bash
sudo nixos-rebuild build --flake .#atlas

sudo systemctl stop \
  github-runner-fctv.service \
  github-runner-fctv2.service \
  github-runner-kigo.service \
  github-buildkit.service

sudo nixos-rebuild switch --flake .#atlas
sudo systemctl reset-failed \
  github-runner-fctv.service \
  github-runner-fctv2.service \
  github-runner-kigo.service \
  github-buildkit.service

sudo systemctl start \
  github-buildkit.service \
  github-runner-fctv.service \
  github-runner-fctv2.service \
  github-runner-kigo.service
```

Comprueba los cuatro servicios:

```bash
systemctl status \
  github-runner-fctv \
  github-runner-fctv2 \
  github-runner-kigo \
  github-buildkit --no-pager
```

El estado esperado es `active (running)`. Los runners deben aparecer como `Idle` en GitHub cuando no tienen jobs asignados. Para seguir su actividad:

```bash
journalctl -u github-runner-fctv -u github-runner-fctv2 -u github-runner-kigo -f
```

```bash
journalctl -u github-buildkit -f
```

No borres `/var/lib/github-buildkit` durante la recuperación: contiene la caché persistente de compilación. Tampoco elimines manualmente los directorios `/var/lib/github-runner/*`; el guard y el módulo NixOS gestionan el registro.

## 4. Seleccionar un runner desde cada workflow

FCTV:

```yaml
runs-on: [self-hosted, linux, x64, atlas, fctv]
```

Kigo:

```yaml
runs-on: [self-hosted, linux, x64, atlas, kigo]
```

FCTV puede utilizar los paquetes Nix expuestos en el `PATH` de su runner. Para PostgreSQL, cada job debe crear una instancia temporal bajo `$RUNNER_TEMP`, escuchando solo en localhost, y limpiarla al salir.

## 5. Construcción de imágenes con BuildKit rootless

Los runners disponen de Docker CLI y Buildx, pero **no** del socket `/var/run/docker.sock` del host. Las compilaciones se envían a un daemon BuildKit rootless dedicado:

- Servicio systemd: `github-buildkit.service`.
- Usuario sin privilegios: `github-buildkit`, con rangos subordinados propios en `/etc/subuid` y `/etc/subgid`.
- Socket Unix: `/run/github-buildkit/buildkitd.sock`.
- Estado y caché persistentes: `/var/lib/github-buildkit`.
- RootlessKit proporciona el espacio de nombres de usuario y la red aislada mediante `slirp4netns`.
- Worker OCI explícito: `runc` con snapshotter `fuse-overlayfs`.
- Worker containerd deshabilitado: BuildKit no intenta acceder a `/run/containerd/containerd.sock`.
- Los runners reciben únicamente acceso al grupo `github-buildkit`.
- BuildKit comparte `github-runners.slice` y sus límites de 3 CPU / 10 GiB con los trabajos de CI.

El worker OCI usa `runc`, requerido por BuildKit para crear contenedores de compilación. El snapshotter `fuse-overlayfs` permite almacenamiento copy-on-write en modo rootless. No se habilita `--oci-worker-no-process-sandbox`: no es necesario para este servicio y reduciría el aislamiento de procesos. El daemon rootless no administra contenedores, redes, volúmenes ni imágenes del Docker de producción.

En cada job que construya una imagen, crea un builder remoto de Buildx:

```yaml
- name: Configure isolated BuildKit
  run: |
    docker buildx create \
      --name atlas-buildkit \
      --driver remote \
      unix:///run/github-buildkit/buildkitd.sock \
      --use
    docker buildx inspect --bootstrap

- name: Build image
  run: |
    docker buildx build \
      --tag ghcr.io/${{ github.repository }}:${{ github.sha }} \
      --load .
```

Para publicar en GHCR, autentica el CLI con el token efímero del workflow y usa `--push` en lugar de `--load`:

```yaml
permissions:
  contents: read
  packages: write

steps:
  - name: Login to GHCR
    run: |
      echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io \
        --username "${{ github.actor }}" --password-stdin

  - name: Build and push
    run: |
      docker buildx build \
        --tag ghcr.io/${{ github.repository }}:${{ github.sha }} \
        --push .
```

El builder remoto es compartido por los runners: no almacenes secretos dentro de capas, argumentos o contexto de build. Usa BuildKit secrets cuando una compilación necesite credenciales. Los runners deben seguir limitados a repositorios privados de confianza; un workflow puede ejecutar código arbitrario con los permisos del runner.
