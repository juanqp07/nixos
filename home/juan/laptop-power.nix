{ ... }:

{
  # PowerDevil detecta AC, batería y nivel bajo. Cambia el perfil PPD
  # automáticamente sin TLP ni servicios de cambio de perfil adicionales.
  qt.kde.settings.powerdevilrc = {
    AC.Performance.PowerProfile = "performance";
    Battery.Performance.PowerProfile = "power-saver";
    LowBattery.Performance.PowerProfile = "power-saver";
  };
}
