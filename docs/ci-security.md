# CI y protección del repositorio

## Comprobaciones automáticas

Las pull requests que modifican configuración, scripts, tests o workflows ejecutan un único workflow por fases:

1. **Static analysis and security** se ejecuta primero: aplica nixfmt, statix, deadnix, bash -n, shfmt, ShellCheck, Ruff y Actionlint sobre los archivos modificados; además ejecuta los tests unitarios del actualizador de Nori y Gitleaks.
2. **NixOS configuration evaluation** solo empieza si la fase anterior termina correctamente. Evalúa los cinco hosts en paralelo, con un máximo de tres runners simultáneos, y mantiene las compilaciones selectivas de servidores y Nori.

Las herramientas de análisis se obtienen de la revisión de nixpkgs fijada en flake.lock. Así se evita que un cambio de versión de los linters altere los resultados sin que cambie el lockfile. Gitleaks examina los commits del rango y redacta los secretos que pudiera mostrar en sus diagnósticos.

Los linters no reescriben archivos: una PR con formato incorrecto falla y debe corregirse en la rama de trabajo. Los checks de Nix se limitan a los archivos Nix modificados para no bloquear cambios nuevos por deuda de formato anterior en ficheros no relacionados.

## Actualizador automático de Nori

El workflow necesita únicamente los permisos contents: write y pull-requests: write. El checkout no persiste credenciales y los pushes de la rama de automatización usan --force-with-lease, que rechaza sobrescribir un cambio remoto inesperado.

El workflow también recupera una ejecución interrumpida después de subir la rama: si ya existe una diferencia de paquetes respecto a main, vuelve a construir ambos paquetes y reintenta crear o actualizar la PR aunque el script de versiones no encuentre una versión nueva.

Para permitir que GitHub Actions cree la PR, activa una vez en el repositorio:

1. **Settings → Actions → General**.
2. En **Workflow permissions**, activa **Allow GitHub Actions to create and approve pull requests**.
3. Guarda los cambios.

Esta opción es independiente de los permisos declarados en YAML y está desactivada por defecto en repositorios personales nuevos. No es necesario dar permisos de escritura al workflow de evaluación ni al de calidad.

## Protección recomendada para main

Configura un ruleset para la rama por defecto (main) desde **Settings → Rules → Rulesets** o desde **Settings → Branches**:

- Exigir que los cambios entren mediante pull request.
- Exigir que pasen los cinco checks matriciales de evaluación (Evaluate elytra, Evaluate titan, Evaluate atlas, Evaluate pico y Evaluate palco) y Static analysis and security. La matriz solo se inicia tras superar calidad y seguridad.
- Bloquear force pushes y el borrado de main.
- No exigir una segunda aprobación si mantienes el repositorio como proyecto personal de un solo mantenedor.

La configuración de protección de ramas se administra en los ajustes de GitHub; no se puede activar mediante los archivos de este repositorio. Comprueba los nombres exactos de los checks que muestra GitHub al crear el ruleset.
