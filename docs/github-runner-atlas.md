# GitHub Actions runners de Atlas

## Diseño

Atlas aloja dos registros independientes de GitHub Actions para los repositorios privados:

| Runner | Repositorio | Visibilidad | Etiqueta adicional |
|---|---|---|---|
| `atlas-fctv` | `juanqp07/fctv` | Privado | `fctv` |
| `atlas-kigo` | `juanqp07/kigo` | Privado | `kigo` |

Cada runner tiene su propia credencial, estado, workspace y servicio efímero. Comparten el host Atlas y una slice de systemd limitada conjuntamente a 3 CPU equivalentes y 10 GiB de RAM (8 GiB como umbral alto). Cada servicio tiene prioridad reducida frente a los servicios normales del servidor.

Los servicios usan usuarios dinámicos gestionados por systemd. No se añaden al grupo `docker` ni reciben acceso al socket Docker de producción.

### ¿Por qué NixOS no usa Atlas?

El repositorio `juanqp07/nixos` es público. GitHub recomienda evitar runners propios en repositorios públicos: cualquier persona puede abrir una PR y tratar de ejecutar código malicioso en el servidor. Además, los runners estándar alojados por GitHub son gratuitos e ilimitados para repositorios públicos.

Por tanto, NixOS debe mantener `ubuntu-latest` en sus workflows de PR y de push. No necesita consumir recursos de Atlas ni la cuota privada de Actions. Referencias: [seguridad de self-hosted runners](https://docs.github.com/en/actions/reference/security/secure-use) y [facturación de Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

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
  printf '\n'
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

sudo systemctl start github-runner-fctv.service
sudo systemctl start github-runner-kigo.service
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

Esta PR instala los runners, pero **no modifica todavía los workflows**. Migra los trabajos después de comprobar que ambos registros están conectados.

## 5. Límites actuales

El runner no recibe acceso al Docker del host. Los jobs que necesiten `services: postgres`, `docker build` o Docker Compose deben permanecer en GitHub-hosted hasta preparar un entorno de contenedores aislado.

Tampoco se instala Android SDK. Los trabajos Android permanecen en GitHub-hosted hasta preparar un SDK reproducible y validar el consumo de RAM.

La modalidad efímera limpia el estado del runner después de un trabajo, pero no convierte el host en una máquina virtual desechable. Ejecuta en Atlas únicamente workflows y cambios de confianza.
