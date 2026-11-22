# Arcane 3 en Pico: migración del agente

Esta nota documenta la migración del antiguo Direct Agent al agente remoto de
Arcane 3. El Manager de Atlas se declara ahora en v3.1.1, mientras que el Agent
de Pico permanece en v3.0.1; esta PR no modifica Pico porque su auditoría runtime
está pendiente. Los pasos siguientes registran el procedimiento de migración y
sirven para reinscribir Pico durante una recuperación; no indican que la
migración de v2 a v3 esté pendiente. La declaración del repositorio no permite verificar el estado
runtime del contenedor ni la validez del token guardado en Pico.

## Cambios incluidos

- Actualiza la imagen oficial del agente a v3.0.1 y fija el digest multi-arquitectura de GHCR.
- Cambia la configuración a `ARCANE_AGENT`, `ARCANE_MANAGER_API_URL` y `ARCANE_AGENT_TOKEN`.
- Elimina el modo Direct, el transporte Edge antiguo y la publicación de TCP/3553.
- Elimina del firewall de Pico las reglas de entrada de 3553; conserva las reglas DNS de Technitium.
- Conserva el volumen `arcane-agent-data:/app/data` y los stacks de Dockge.
- Actualiza el mantenedor para sincronizar el agente con el Manager desde GHCR.

## Reinscripción durante la migración

En v3 los Direct Agents antiguos pasan a estado Pending. No se debe reutilizar
el valor antiguo de `AGENT_TOKEN` como si fuera el nuevo token de inscripción.
Con el Manager de Atlas ya actualizado:

1. Abre **Agents** en Arcane.
2. Selecciona Pico y entra en **Connection & Agent**.
3. Pulsa **Generate Enrollment Token** y copia el comando/token nuevo.
4. En Pico sustituye el contenido del archivo de entorno por el nuevo token:

   ```bash
   sudo cp -a /var/lib/arcane-agent/agent.env \
     "/var/lib/arcane-agent/agent.env.bak.$(date -u +%Y%m%dT%H%M%SZ)"
   sudoedit /var/lib/arcane-agent/agent.env
   sudo chmod 600 /var/lib/arcane-agent/agent.env
   ```

   La línea debe ser `ARCANE_AGENT_TOKEN=arc_etkn_...` con el token recién
   generado. No lo pegues en Git ni lo compartas por chat. El agente guarda
   la API key resultante cifrada en el volumen persistente `/app/data`.

5. Revisa la generación Nix y despliega la nueva configuración en Pico.
6. Comprueba que Pico aparece Online y revisa Git Sync, webhooks, jobs y stacks.

## Red en la configuración actual

El agente v3 inicia la conexión hacia Atlas. No escucha en TCP/3553 ni necesita
un puerto publicado. Por eso se eliminan `ports = [ "3553:3553" ]` y las reglas
de entrada correspondientes. No se deben borrar las reglas de TCP/UDP 53 ni
las reglas de las consolas de Technitium.

El volumen `arcane-agent-data` debe mantenerse: contiene el estado y la clave
del agente tras completar la inscripción. No lo borres durante la migración.

## Validación

```bash
docker ps --filter name=arcane-agent
docker logs --since 10m arcane-agent
docker inspect --format '{{json .Mounts}}' arcane-agent
```

Guías oficiales:
- https://getarcane.app/docs/get-started/migrate-v3
- https://getarcane.app/docs/remote/agents
