# Despliegue remoto con deploy-rs

## Alcance

El Flake declara despliegues remotos para **Atlas** y **Pico**. Elytra y Titan
siguen aplicándose localmente con nixos-rebuild, y Palco conserva su flujo de
construcción y grabación de imagen para Raspberry Pi.

Se usa deploy-rs **v1.0.0**, fijado en flake.lock. La herramienta se ejecuta
desde Elytra o Titan con el paquete del propio Flake, para que el CLI y los
scripts de activación transferidos a los servidores procedan de la misma
revisión.

## Modelo de acceso

- La compilación se realiza en el equipo desde el que se lanza el despliegue
  (remoteBuild = false). Atlas y Pico no consumen CPU compilando su propio
  sistema.
- SSH conecta como juan. Por defecto se utilizan las direcciones LAN que
  ya empleaban los comandos remotos existentes: Atlas 192.168.1.143 y Pico
  192.168.1.147.
- La activación NixOS se ejecuta como root mediante sudo interactivo. No se
  habilita SSH de root ni se almacenan contraseñas en el repositorio.
- Los comandos Fish incluyen --interactive: deploy-rs muestra los perfiles
  y pide confirmación antes de activarlos.

## Comprobaciones previas

Antes de ejecutar deploy-rs, los alias:

- Comprueban que ~/nixos es un repositorio Git.
- Rechazan cambios staged, unstaged y archivos sin seguimiento. Confirma o
  guarda los cambios antes de desplegar.
- Muestran la rama, el SHA corto de 12 caracteres y el asunto del commit que
  se va a construir.

No ejecutan git fetch, pull, checkout ni commit. La limpieza del árbol no
garantiza que la rama esté al día con GitHub: revisa que estés en la rama y
commit que quieres desplegar antes de ejecutar el alias.

## Transporte LAN y NetBird

El transporte predeterminado sigue siendo LAN:

```fish
nix-deploy-atlas
nix-deploy-pico
```

Para desplegar un único servidor a través de NetBird, añade --netbird:

```fish
nix-deploy-atlas --netbird
nix-deploy-pico --netbird
```

En ese modo el alias consulta el CLI local de NetBird con el filtro del
hostname esperado (atlas o pico), lee el JSON de status y exige encontrar
exactamente una IP de un peer conectado. Después pasa esa dirección a
deploy-rs mediante su opción --hostname. La dirección LAN declarada en
flake.nix no se modifica: el override solo se aplica a esa ejecución.

El modo NetBird requiere los comandos netbird y jq en el equipo de control,
que el peer aparezca conectado y que la política de acceso permita SSH
entrante al servidor. Si la resolución falla o devuelve cero o varias IP,
el despliegue se cancela; nunca cambia silenciosamente a LAN.

nix-deploy-servers continúa usando las direcciones LAN. Para utilizar
NetBird, despliega Atlas y Pico por separado con sus respectivos alias
individuales; así cada uno obtiene su propia dirección de peer.

## Por qué los rollbacks automáticos están desactivados

En esta integración se dejan explícitamente autoRollback = false y
magicRollback = false.

deploy-rs 1.0.0 reactiva la generación anterior ejecutando
/nix/var/nix/profiles/system/deploy-rs-activate. Las generaciones creadas por
nixos-rebuild o por el system.autoUpgrade actual no incluyen ese helper.
Por tanto, activar Magic Rollback no garantiza recuperar la generación previa:
el paso de reactivación puede fallar. Este caso sigue documentado en
serokell/deploy-rs#86, y el código de la versión fijada sigue dependiendo
de ese ejecutable.

Como Atlas y Pico preparan generaciones mediante system.autoUpgrade, no sería
responsable presentar Magic Rollback como una protección funcional. No se
deshabilita ni modifica system.autoUpgrade para poder activar esta herramienta.
Revisa la compatibilidad de rollback de deploy-rs antes de cambiar esta política.

## Comandos disponibles

Desde una sesión Fish en Elytra o Titan. Tras fusionar esta PR y actualizar el
checkout local, aplica primero el cambio de Home Manager en el escritorio que
vayas a usar, por ejemplo:

```bash
sudo nixos-rebuild switch --flake .#elytra
```

Cambia el host por titan si prefieres usar la torre.

| Comando | Acción |
| --- | --- |
| nix-deploy-atlas | Despliega Atlas por LAN |
| nix-deploy-atlas --netbird | Despliega Atlas por NetBird |
| nix-deploy-pico | Despliega Pico por LAN |
| nix-deploy-pico --netbird | Despliega Pico por NetBird |
| nix-deploy-servers | Despliega Atlas y Pico por LAN |
| nix-up-atlas | Alternativa existente con nixos-rebuild --target-host |
| nix-up-pico | Alternativa existente con nixos-rebuild --target-host |

También se puede invocar directamente:

```bash
nix run .#deploy-rs -- --interactive .#atlas
nix run .#deploy-rs -- --interactive .#pico
```

Para revisar qué se activaría sin aplicar los cambios:

```bash
nix run .#deploy-rs -- --dry-activate .#atlas
```

El comando conjunto nix-deploy-servers procesa todos los nodos definidos.
No es una transacción: al estar desactivado autoRollback, si Atlas se despliega
correctamente y Pico falla después (o al contrario), el primero no se revierte
automáticamente. Se recomienda desplegar y verificar cada servidor por separado.

## Validación

nix flake check --no-build --show-trace evalúa los outputs. El workflow de CI
construye además:

- checks.x86_64-linux.deploy-schema: valida la estructura de los nodos y
  perfiles mediante el esquema de deploy-rs.
- checks.x86_64-linux.deploy-activate: comprueba que cada perfil genera los
  ejecutables de activación necesarios.

Estas comprobaciones no conectan con los servidores ni realizan despliegues.
