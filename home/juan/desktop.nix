{ lib, ... }:

{
  # Atajo global de KWin para maximizar la ventana activa.
  # Meta representa la tecla Super. Se libera Meta+Alt+Up de la acción
  # "Switch Window Up" para evitar que ambas acciones compitan por el atajo.
  qt.kde.settings.kglobalshortcutsrc.kwin = {
    "Window Maximize" = "Meta+Alt+Up,Meta+Alt+Up,Maximize Window";
    "Switch Window Up" = "none,none,Switch to Window Above";
  };

  # Fastfetch local y funciones de despliegue remoto para los escritorios.
  # Las sesiones SSH no lanzan fastfetch automáticamente.
  programs.fish.interactiveShellInit = lib.mkAfter ''
    if not set -q SSH_CONNECTION; and not set -q SSH_TTY
      fastfetch
    end

  '';

}
