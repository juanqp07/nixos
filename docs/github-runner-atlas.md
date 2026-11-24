# GitHub Actions runners de Atlas

## Diseño

Atlas aloja dos registros independientes de GitHub Actions para los repositorios privados:

| Runner | Repositorio | Etiqueta adicional |
|---|---|---|
| `atlas-fctv` | `juanqp07/fctv` | `fctv` |
| `atlas-kigo` | `juanqp07/kigo` | `kigo` |

Cada runner tiene su propia credencial, estado, workspace y servicio efímero. Comparten el host Atlas y una slice de systemd limitada conjuntamente a 3 CPU equivalentes y 10 GiB de RAM (8 GiB como umbral alto). Cada servicio tiene prioridad reducida frente a los servicios normales del servidor.

Los servicios usan usuarios dinámicos gestionados por systemd. No se añaden al grupo `docker` ni reciben acceso al socket Docker de producción.

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

Go 1.27.4 se instala mediante `actions/setup-go@v6`: el pin estable 26.05 usado por Atlas no incluye `go_1_27`. No se ejecuta código Go ni se descargan toolchains con el daemon Nix.

**Los workflows no deben ejecutar `nix shell`, `nix build`, `nix develop` ni otros comandos que necesiten contactar con `nix-daemon`.** Los runners usan usuarios dinámicos y el daemon está restringido a `@wheel`. Dar acceso a esos usuarios efímeros o añadirlos a `wheel` ampliaría innecesariamente sus privilegios. Las herramientas de CI deben declararse en `extraPackages` y estar en el `PATH` del servicio.

Se conserva `NIX_LD` y `NIX_LD_LIBRARY_PATH` explícitamente en ambos servicios para binarios glibc externos, como algunas herramientas descargadas por Android SDK. Esto no concede acceso al daemon Nix.

## Recuperación de registros existentes

Ambos runners usan `ephemeral = true`: GitHub los desregistra después de procesar un trabajo y systemd vuelve a iniciar el servicio para registrar una nueva instancia. Sin embargo, si Atlas se detiene o reinicia mientras un runner está inactivo, el registro remoto anterior puede seguir apareciendo en GitHub aunque el estado local se haya limpiado.

Por eso el constructor común configura también `replace = true`. Al arrancar, NixOS pide a GitHub que sustituya cualquier registro existente con el mismo nombre (`atlas-fctv` o `atlas-kigo`) en el repositorio correspondiente, en lugar de fallar con el error `A runner exists with the same name`. Cada servicio conserva su propio PAT y la sustitución se limita al nombre de ese runner.

## Seguridad y aislamiento

El repositorio `juanqp07/nixos` es público. Los workflows de PR y push de este repositorio deben seguir usando runners alojados por GitHub, nunca Atlas. GitHub recomienda evitar runners propios en repositorios públicos porque cualquier persona puede abrir una PR e intentar ejecutar código no confiable en el servidor. Referencias: [seguridad de self-hosted runners](https://docs.github.com/en/actions/reference/security/secure-use) y [facturación de Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

No se añade ninguno de los runners al grupo `docker`, no se monta `/var/run/docker.sock` y no se desactiva el aislamiento systemd.

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

En Atlas, guarda cada PAT en su archivo correspondiente. El contenido debe ser una sola línea, sin salto de línea. No añadas estos archivos a Git, Nix Store, `flake.nix` ni a `configuration.nix`.

```bash
sudo install -d -m 0700 -o root -g root /var/lib/secrets/github-runner

for repo in fctv kigo; do
  read -rsp "Fine-grained PAT for $repo: " TOKEN
  printf '\\n'
  printf '%s' "$TOKEN" | sudo tee "/var/lib/secrets/github-runner/$repo.token" >/dev/null
  unset TOKEN
  sudo chown root:root "/var/lib/secrets/github-runner/$repo.token"
  sudo chmod 0600 "/var/lib/secrets/github-runner/$repo.token"
done
```

Puedes provisionar los tokens por separado. El servicio correspondiente no arranca hasta que exista su archivo.

## 3. Aplicar NixOS y comprobar los servicios

Desde el checkout local actualizado del repositorio NixOS:

```bash
sudo nixos-rebuild switch --flake .#atlas

sudo systemctl restart github-runner-fctv.service
sudo systemctl restart github-runner-kigo.service
```

Consulta el estado:

```bash
systemctl status github-runner-fctv
systemctl status github-runner-kigo
```

Para ver registros:

```bash
journalctl -u github-runner-fctv -u github-runner-kigo -f
```

En cada repositorio, abre **Settings → Actions → Runners**. El runner correspondiente debe aparecer como `Idle` cuando esté conectado.

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

## 5. Límites actuales

El runner no recibe acceso al Docker del host. Los jobs que necesiten `docker build` o Docker Compose deben permanecer en un runner/VM aislado con etiqueta específica. No se concede acceso al socket Docker de Atlas: ese acceso equivale prácticamente a root sobre el host.

El SDK Android se descarga dentro del job, en `$RUNNER_TEMP`; solo se proporciona JDK 17 y las herramientas auxiliares mediante Nix. Debe limitarse el paralelismo de Gradle y comprobarse el consumo de disco y memoria.

La modalidad efímera limpia el estado del runner después de un trabajo, pero no convierte el host en una máquina virtual desechable. Ejecuta en Atlas únicamente workflows y cambios de confianza.
