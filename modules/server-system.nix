{ lib, ... }:

{
  # ============================================================
  # BOOT / RESILIENCIA DEL SERVIDOR
  # ============================================================

  # Reiniciar automáticamente después de un kernel panic.
  boot.kernelParams = [
    "panic=10"
    "boot.panic_on_fail"
    "nmi_watchdog=1"
  ];

  boot.kernel.sysctl = {
    # --- Auto-reinicio ante fallos críticos ---

    # Reiniciar si el kernel entra en OOM.
    "vm.panic_on_oom" = 1;

    # Reiniciar ante kernel oops.
    "kernel.panic_on_oops" = 1;

    # Reiniciar ante soft lockup de CPU.
    "kernel.softlockup_panic" = 1;

    # hung_task_panic eliminado: un bloqueo temporal de disco o Docker no debe
    # reiniciar el servidor entero (el kernel sigue avisando en el log).

    # Tiempo antes de reiniciar después de kernel panic.
    "kernel.panic" = 10;

    # Con zram el swap es memoria comprimida (barato): swappiness 100 y sin readahead de swap.
    # mkForce porque common-system.nix lo deja en 10.
    "vm.swappiness" = lib.mkForce 100;
    "vm.page-cluster" = 0;

    # SysRq disponible para recuperación manual.
    "kernel.sysrq" = 1;
  };
}