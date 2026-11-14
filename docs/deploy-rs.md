# Despliegue remoto con deploy-rs

## Alcance

El Flake declara despliegues remotos para **Atlas** y **Pico**. Elytra y Titan
siguen aplicándose localmente con `nixos-rebuild`, y Palco conserva su flujo de
construcción y grabación de imagen para Raspberry Pi.

Se usa deploy-rs **v1.0.0**, fijado en `flake.lock`. La herramienta se ejecuta
desde Elytra o Titan con el paquete del propio Flake, para que el CLI y los
scripts de activación transferidos a los servidores procedan de la misma
revisión.

## Modelo de acceso

- La compilación se realiza en el equipo desde el que se lanza el despliegue
  (`remoteBuild = false`). Atlas y Pico no consumen CPU compilando su propio
  sistema.
- SSH conecta como `juan`, usando las direcciones LAN que ya empleaban los
  comandos remotos existentes: Atlas `192.168.1.143` y Pico `192.168.1.147`.
- La activación NixOS se ejecuta como `root` mediante sudo interactivo. No se
  habilita SSH de root ni se almacenan contraseñas en el repositorio.
- Los comandos Fish incluyen `--interactive`: deploy-rs muestra los perfiles
  y pide confirmación antes de activarlos.

## Por qué los rollbacks automáticos están desactivados

En esta integración se dejan explícitamente `autoRollback = false` y
`magicRollback = false`.

deploy-rs 1.0.0 reactiva la generación anterior ejecutando
`/nix/var/nix/profiles/system/deploy-rs-activate`. Las generaciones creadas por
`nixos-rebuild` o por el `system.autoUpgrade` actual no incluyen ese helper.
Por tanto, activar Magic Rollback no garantiza recuperar la generación previa:
el paso de reactivación puede fallar. Este caso sigue documentado en
[serokell/deploy-rs#86](https://github.com/serokell/deploy-rs/issues/86), y el
código de la versión fijada sigue dependiendo de ese ejecutable.

Como Atlas y Pico preparan generaciones mediante `system.autoUpgrade`, no sería
responsable presentar Magic Rollback como una protección funcional. No se
deshabilita ni modifica `system.autoUpgrade` para poder activar esta herramienta.
Revisa la compatibilidad de rollback de deploy-rs antes de cambiar esta política.

## Comandos disponibles

Desde una sesión Fish en Elytra o Titan:

| Comando | Acción |
| --- | --- |
| `nix-deploy-atlas` | Despliega solo Atlas |
| `nix-deploy-pico` | Despliega solo Pico |
| `nix-deploy-servers` | Despliega todos los nodos declarados (Atlas y Pico) |
| `nix-up-atlas` | Alternativa existente con `nixos-rebuild --target-host` |
| `nix-up-pico` | Alternativa existente con `nixos-rebuild --target-host` |

También se puede invocar directamente:

```bash
nix run .#deploy-rs -- --interactive .#atlas
nix run .#deploy-rs -- --interactive .#pico
```

Para revisar qué se activaría sin aplicar los cambios:

```bash
nix run .#deploy-rs -- --dry-activate .#atlas
```

El comando conjunto `nix-deploy-servers` procesa todos los nodos definidos.
Se recomienda probar primero cada servidor por separado y usar el despliegue
conjunto solo cuando ambos estén accesibles y se haya revisado el cambio.

## Validación

`nix flake check --no-build --show-trace` evalúa los outputs. El workflow de CI
construye además:

- `checks.x86_64-linux.deploy-schema`: valida la estructura de los nodos y
  perfiles mediante el esquema de deploy-rs.
- `checks.x86_64-linux.deploy-activate`: comprueba que cada perfil genera los
  ejecutables de activación necesarios.

Estas comprobaciones no conectan con los servidores ni realizan despliegues.
