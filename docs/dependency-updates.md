# Actualización de Flakes e imágenes OCI

## Qué automatiza

El workflow `.github/workflows/update-dependencies.yml` se ejecuta cada miércoles
a las 08:17 UTC y también admite ejecución manual desde GitHub Actions.

Realiza dos operaciones:

1. Ejecuta `nix flake update` y actualiza el `flake.lock` completo. Esto
   incluye nixpkgs unstable, nixpkgs-stable, Home Manager, nix-flatpak y
   nixos-hardware. No cambia los canales declarados en `flake.nix`.
2. Consulta el registro OCI de cada imagen declarada con `image = "..."; `
   en los módulos de Atlas y Pico. Obtiene el digest SHA-256 del manifiesto
   multi-plataforma y deja referencias con tag y digest, por ejemplo
   `imagen:version@sha256:...`.

En la primera ejecución se fijarán también las imágenes que hoy solo tengan
tag. Actualmente el alcance NixOS incluye el socket proxy, Arcane Manager,
PostgreSQL y Arcane Edge Agent. Los Compose que se mantienen fuera del
repositorio no se modifican.

## Qué ocurre cuando encuentra cambios

- Crea o actualiza la rama `automation/flake-and-image-updates`.
- Abre o actualiza una PR de dependencias.
- Lanza explícitamente `nixos-check.yml` contra la rama de actualización.
- Espera a que la PR supere sus comprobaciones; no instala ni despliega nada
  en los equipos.
- Si no hay cambios en el lockfile ni en los digests, no abre una PR vacía.

Se conserva el tag legible junto con el digest inmutable. El tag ayuda a
identificar la versión prevista; el digest evita que ese tag cambie el
contenido descargado sin que el diff de Git lo muestre.

## Primera puesta en marcha y permisos

En GitHub, abre **Settings → Actions → General → Workflow permissions** y
activa **Allow GitHub Actions to create and approve pull requests**. El
workflow ya declara permisos mínimos de escritura en contenidos, PRs y
ejecuciones de Actions; esta opción de repositorio también debe permitir la
creación automática de PR.

Tras fusionar esta configuración, puedes iniciarla manualmente desde
**Actions → Update Flake inputs and container digests → Run workflow**.
La ejecución programada posterior es semanal.

## Revisión de las PR

No habilites auto-merge para esta automatización. Revisa:

- El diff de `flake.lock`: qué inputs cambiaron y si pertenecen a los
  canales previstos.
- Los cambios de `image =`: conserva el tag esperado y comprueba que el
  digest corresponde al manifiesto publicado por el registro.
- Los seis checks: calidad/seguridad y evaluación de `elytra`, `titan`,
  `atlas`, `pico` y `palco`.
- Cualquier nota de migración o cambio incompatible del upstream antes de
  fusionar.

El CI evalúa las configuraciones y construye las clausuras de Atlas y Pico,
pero no despliega ni sustituye pruebas reales de servicios, GPU, Bluetooth,
red o contenedores.

## Actualizar el alcance de imágenes

El script `scripts/update-docker-digests.py` reconoce asignaciones Nix
literales `image = "registry/repository:tag";` en:

- `hosts/servidor/configuration.nix`
- `hosts/zimablade/configuration.nix`

Por ahora soporta Docker Hub y GHCR públicos. Si se añade otro registro,
primero hay que implementar y probar su autenticación anónima o la gestión
segura de credenciales; no se deben guardar tokens en el repositorio.

Las pruebas offline están en
`tests/test_update_docker_digests.py`. Se ejecutan junto con el resto de
tests unitarios del job de calidad.
