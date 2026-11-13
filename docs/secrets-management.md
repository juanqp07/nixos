# Gestión de secretos con SOPS-nix y age

## Estado de esta integración

El módulo SOPS-nix está importado por los cinco hosts. Cada host usa su clave
privada Ed25519 de OpenSSH (/etc/ssh/ssh_host_ed25519_key) como identidad age
para descifrar secretos. La clave privada no se copia al repositorio ni al
almacén Nix.

La migración de credenciales de Arcane queda preparada, pero no se activa aún:
faltan los destinatarios age públicos reales y los archivos cifrados creados a
partir de los .env existentes en Atlas y Pico. No deben sustituirse por
valores inventados ni crear archivos vacíos, porque eso podría impedir que
Arcane y PostgreSQL arranquen.

## 1. Preparar la clave de administración

En el equipo desde el que se editarán los secretos:

    nix develop .#secrets
    mkdir -p ~/.config/sops/age
    age-keygen -o ~/.config/sops/age/keys.txt
    age-keygen -y ~/.config/sops/age/keys.txt

Guarda el archivo ~/.config/sops/age/keys.txt en un lugar seguro y con copia
de recuperación. **Nunca lo añadas a Git, no lo compartas y no lo guardes en el
mismo servidor que contiene los únicos secretos.** Solo publica el valor
age1... que imprime age-keygen -y; es una clave pública.

Si ya tienes una clave age de administración respaldada, puedes reutilizarla
en lugar de generar otra.

## 2. Obtener los destinatarios públicos de los cinco hosts

Tras integrar esta PR y desplegar la generación en cada máquina, ejecuta en
cada host:

    sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key | ssh-to-age

El resultado age1... es público y puede incorporarse a .sops.yaml.
Repite la operación para elytra, titan, atlas, pico y palco.
No copies ni compartas el archivo privado /etc/ssh/ssh_host_ed25519_key.

Si una máquina no tiene ese archivo, detente y comprueba que OpenSSH haya
generado su clave de host; no generes ni sustituyas claves SSH existentes sin
revisar las consecuencias de confianza de los clientes.

## 3. Crear la política .sops.yaml

Cuando tengas los seis destinatarios públicos (clave de administración y cinco
hosts), crea .sops.yaml en la raíz. La estructura recomendada es:

    keys:
      - &admin age1REEMPLAZAR_CLAVE_PUBLICA_ADMIN
      - &elytra age1REEMPLAZAR_DESTINATARIO_ELYTRA
      - &titan age1REEMPLAZAR_DESTINATARIO_TITAN
      - &atlas age1REEMPLAZAR_DESTINATARIO_ATLAS
      - &pico age1REEMPLAZAR_DESTINATARIO_PICO
      - &palco age1REEMPLAZAR_DESTINATARIO_PALCO

    creation_rules:
      - path_regex: ^secrets/atlas/.*
        key_groups:
          - age:
              - *admin
              - *atlas
      - path_regex: ^secrets/pico/.*
        key_groups:
          - age:
              - *admin
              - *pico
      - path_regex: ^secrets/elytra/.*
        key_groups:
          - age:
              - *admin
              - *elytra
      - path_regex: ^secrets/titan/.*
        key_groups:
          - age:
              - *admin
              - *titan
      - path_regex: ^secrets/palco/.*
        key_groups:
          - age:
              - *admin
              - *palco

Sustituye todos los marcadores. Los archivos de cada host se cifran para que
puedan descifrarlos la clave de administración y ese host, no los otros
equipos. Comprueba la sintaxis de la configuración con sops -e en un
archivo de prueba antes de migrar secretos reales.

## 4. Migrar los archivos de entorno de Atlas y Pico

Los archivos actuales están fuera del repositorio:

- Atlas: /mnt/datos/AppData/arcane/arcane.env
- Atlas: /mnt/datos/AppData/arcane/postgres.env
- Pico: /var/lib/arcane-agent/agent.env

Desde el directorio del repositorio, con los permisos adecuados para leer los
archivos actuales, crea los destinos cifrados sin imprimir su contenido:

    mkdir -p secrets/atlas secrets/pico
    sops --encrypt --input-type dotenv --output-type dotenv \
      /mnt/datos/AppData/arcane/arcane.env > secrets/atlas/arcane.env
    sops --encrypt --input-type dotenv --output-type dotenv \
      /mnt/datos/AppData/arcane/postgres.env > secrets/atlas/postgres.env
    sops --encrypt --input-type dotenv --output-type dotenv \
      /var/lib/arcane-agent/agent.env > secrets/pico/agent.env

Comprueba que cada archivo contiene bloques ENC[AES256_GCM,...] y
metadatos SOPS, nunca valores en claro. No uses cat, set -x ni pegues
valores secretos en una terminal compartida o en un issue.

Antes de activar la migración, verifica que los tres archivos se descifran
correctamente con sops -d y que los destinatarios de destino pueden abrirlos.
Mantén los archivos externos originales hasta confirmar que los servicios
arrancan con los secretos nuevos y que tienes una restauración probada.

## 5. Conectar los secretos a los servicios

Una vez existan los archivos cifrados, declara los secretos en la configuración
de cada host. Ejemplo para Atlas:

    sops.secrets.arcane-env = {
      sopsFile = ../../secrets/atlas/arcane.env;
      format = "dotenv";
    };

    sops.secrets.postgres-env = {
      sopsFile = ../../secrets/atlas/postgres.env;
      format = "dotenv";
    };

Y sustituye los environmentFiles actuales del contenedor Arcane y de
PostgreSQL por config.sops.secrets.arcane-env.path y
config.sops.secrets.postgres-env.path, respectivamente.

En Pico, declara agent-env con sopsFile = ../../secrets/pico/agent.env y
format = "dotenv", y cambia el environmentFiles del agente para que apunte a
config.sops.secrets.agent-env.path.

Los secretos de sistema se materializan en /run/secrets durante la fase de
arranque de SOPS-nix; los servicios normales de systemd empiezan después de
sysinit.target. Si se cambia su orden de inicio, conserva una dependencia
explícita respecto a sops-install-secrets.service. Los archivos se crean
como root y con permisos restrictivos por defecto; no amplíes sus permisos sin
una necesidad concreta.

## 6. Rotación y recuperación

- Para añadir o retirar destinatarios de un secreto ya cifrado, usa
  sops updatekeys secrets/... y revisa el diff cifrado.
- Si se pierde una clave privada de host, ese host no podrá descifrar los
  secretos destinados a él hasta que se añada un nuevo destinatario y se
  vuelva a cifrar/actualizar el archivo.
- Si se pierde la clave de administración, usa la copia segura de recuperación.
  Sin ningún destinatario privado válido no se pueden recuperar los valores.
- No guardes las claves privadas en el repositorio, GitHub Actions, el almacén
  Nix ni en un volumen compartido que dependa del mismo host.

## Herramientas

nix develop .#secrets proporciona sops, age y ssh-to-age solo durante la sesión
de desarrollo. No instala estas utilidades en los cinco sistemas.
