# Runners de GitHub Actions en Atlas

## Diseño

Atlas aloja tres registros independientes de GitHub Actions, uno por repositorio:

| Runner | Repositorio | Visibilidad | Etiqueta adicional |
|---|---|---|---|
| `atlas-fctv` | `juanqp07/fctv` | Privado | `fctv` |
| `atlas-kigo` | `juanqp07/kigo` | Privado | `kigo` |
| `atlas-nixos` | `juanqp07/nixos` | Público | `nixos-config` |

Son tres servicios efímeros independientes en el mismo host. Cada uno tiene su propia credencial, identidad de runner y estado; no se comparte un registro ni un token entre repositorios.

Los tres servicios utilizan el módulo oficial `services.github-runners` de la revisión estable fijada en `flake.lock`. Systemd los coloca en `github-runners.slice`, que limita el conjunto a un máximo de 3 CPU equivalentes y 12 GiB de RAM (10 GiB como umbral alto). Cada servicio tiene prioridad reducida frente a los servicios normales de Atlas.

Los runners usan usuarios dinámicos gestionados por systemd. No se añaden al grupo `docker` ni reciben acceso al socket Docker de producción.

## 1. Crear tres Fine-grained PATs

Crea **un token diferente para cada repositorio** desde GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens.

En cada token configura:

1. Resource owner: `juanqp07`.
2. Repository access: **Only select repositories** y selecciona únicamente el repositorio correspondiente (`fctv`, `kigo` o `nixos`).
3. Repository permissions: **Administration: Read and write**.
4. Establece una expiración razonable y guarda el token generado (prefijo `github_pat_`).

El endpoint de GitHub para crear el token de registro del runner de un repositorio exige permiso de escritura `Administration`. Consulta [la documentación de GitHub](https://docs.github.com/en/rest/actions/self-hosted-runners#create-a-registration-token-for-a-repository).

No reutilices un PAT entre repositorios ni concedas acceso a repositorios adicionales.

## 2. Instalar los tokens en Atlas

En Atlas, guarda cada PAT en su archivo correspondiente. El contenido debe ser una sola línea, sin salto de línea. No añadas estos archivos a Git, Nix Store, `flake.nix` ni a `configuration.nix`.

```bash
sudo install -d -m 0700 -o root -g root /var/lib/secrets/github-runner

for repo in fctv kigo nixos; do
  read -rsp "Fine-grained PAT for $repo: " TOKEN
  printf '\n'
  printf '%s' "$TOKEN" | sudo tee "/var/lib/secrets/github-runner/$repo.token" >/dev/null
  unset TOKEN
  sudo chown root:root "/var/lib/secrets/github-runner/$repo.token"
  sudo chmod 0600 "/var/lib/secrets/github-runner/$repo.token"
done
```

Puedes provisionar los tokens en momentos distintos. El servicio correspondiente no arranca hasta que exista su archivo.

## 3. Aplicar NixOS y comprobar los servicios

Desde el checkout local actualizado del repositorio NixOS:

```bash
sudo nixos-rebuild switch --flake .#atlas

sudo systemctl start github-runner-fctv.service
sudo systemctl start github-runner-kigo.service
sudo systemctl start github-runner-nixos.service
```

Consulta cada servicio:

```bash
systemctl status github-runner-fctv
systemctl status github-runner-kigo
systemctl status github-runner-nixos
```

Para ver registros:

```bash
journalctl -u github-runner-fctv -u github-runner-kigo -u github-runner-nixos -f
```

En cada repositorio, abre **Settings → Actions → Runners**. El registro correspondiente debe aparecer como `Idle` cuando esté conectado.

## 4. Seleccionar un runner desde cada workflow

Los runners conservan las etiquetas predeterminadas `self-hosted`, `linux` y `x64`, además de las etiquetas comunes y específicas:

FCTV:

```yaml
runs-on: [self-hosted, linux, x64, atlas, fctv]
```

Kigo:

```yaml
runs-on: [self-hosted, linux, x64, atlas, kigo]
```

NixOS:

```yaml
runs-on: [self-hosted, linux, x64, atlas, nixos-config]
```

Esta PR instala los runners, pero **no modifica los workflows de los proyectos**. Conviene migrar los trabajos gradualmente después de comprobar los tres registros.

## 5. Precaución especial con NixOS

El repositorio `juanqp07/nixos` es público. No ejecutes código de pull requests no confiables en el runner de Atlas: un workflow modificado por una contribución podría intentar acceder a la red privada del homelab.

Mantén las validaciones de `pull_request` en runners alojados por GitHub. Reserva `atlas-nixos` para workflows disparados por `push` a `main` después de revisión, o por `workflow_dispatch` iniciado por un mantenedor de confianza. No uses el runner de Atlas para `pull_request` ni `pull_request_target` con código de contribuciones.

## 6. Límites actuales

El runner no tiene acceso al Docker del host. Por tanto, los jobs que requieran `services: postgres`, `docker build` o Docker Compose deben permanecer en runners alojados por GitHub hasta diseñar un entorno de contenedores aislado.

Tampoco se instala Android SDK. Los trabajos Android permanecen en runners alojados por GitHub hasta preparar un SDK reproducible y validar el consumo de RAM.

La modalidad efímera limpia el estado del runner después de un trabajo, pero no convierte el host en una máquina virtual desechable ni elimina el riesgo de ejecutar código no confiable.
