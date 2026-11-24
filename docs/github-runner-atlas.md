# GitHub Actions runner de Atlas (FCTV)

## Qué instala

El módulo `modules/atlas-github-runner.nix` registra un runner **a nivel del repositorio privado** `juanqp07/fctv`.

- Nombre en GitHub: `atlas-fctv`.
- Etiquetas adicionales: `atlas`, `nixos`, `fctv`.
- Ejecución efímera: cada instancia atiende un solo trabajo y vuelve a registrarse.
- Usuario dinámico administrado por systemd; no se concede acceso al grupo `docker` ni al socket del Docker de producción.
- Límites del servicio: 4 CPU equivalentes y 8 GiB de memoria máxima; prioridad reducida frente a los servicios del servidor.

El servicio queda condicionado a la existencia del token. Un rebuild de NixOS sin el secreto no provoca intentos de registro fallidos.

## 1. Crear un token de GitHub

En GitHub, abre **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**.

Configura:

1. Resource owner: `juanqp07`.
2. Repository access: **Only select repositories** → `fctv`.
3. Repository permissions: **Administration: Read and write**.
4. Usa una expiración razonable y guarda el token generado, que empieza por `github_pat_`.

GitHub exige permiso de escritura de Administration para el endpoint de creación del token de registro de runners a nivel de repositorio. No concedas acceso a otros repositorios.

## 2. Instalar el secreto en Atlas

El archivo debe contener el PAT en una sola línea, sin salto de línea. No lo añadas al repositorio, a `flake.nix`, a `configuration.nix` ni a ningún archivo gestionado por Nix.

En Atlas:

```bash
sudo install -d -m 0700 -o root -g root /var/lib/secrets/github-runner

read -rsp "GitHub fine-grained PAT: " TOKEN
printf '\\n'
printf '%s' "$TOKEN" | sudo tee /var/lib/secrets/github-runner/fctv.token >/dev/null
unset TOKEN

sudo chown root:root /var/lib/secrets/github-runner/fctv.token
sudo chmod 0600 /var/lib/secrets/github-runner/fctv.token
```

## 3. Aplicar NixOS y arrancar

Desde el checkout local actualizado del repositorio NixOS:

```bash
sudo nixos-rebuild switch --flake .#atlas
sudo systemctl start github-runner-fctv.service
```

Comprueba el estado y el registro:

```bash
systemctl status github-runner-fctv.service
journalctl -u github-runner-fctv.service -f
```

En GitHub, abre **FCTV → Settings → Actions → Runners**. Debe aparecer `atlas-fctv` como `Idle` cuando esté conectado.

## 4. Usarlo desde un workflow

Una vez que GitHub muestre el runner como disponible, los trabajos compatibles pueden seleccionar sus etiquetas:

```yaml
runs-on: [self-hosted, linux, x64, atlas, fctv]
```

Empieza por trabajos que no necesiten Docker ni servicios de contenedor (por ejemplo, validación web o contratos). Los trabajos que usan `services: postgres`, `docker build` o Android SDK **no se deben mover todavía**: este runner no recibe acceso al daemon Docker de producción ni instala un Android SDK.

## Seguridad

Los runners propios ejecutan código del repositorio en Atlas. Úsalos únicamente con workflows y cambios de confianza; no ejecutes en ellos código de forks o contribuciones externas sin revisión. La modalidad efímera limpia el estado entre trabajos, pero no convierte el host en una VM desechable ni elimina el riesgo de que código no confiable intente acceder a la red del homelab.
