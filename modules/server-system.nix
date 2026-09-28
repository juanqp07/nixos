{ ... }:

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

    # Reiniciar si una tarea permanece bloqueada.
    "kernel.hung_task_panic" = 1;
    "kernel.hung_task_timeout_secs" = 300;

    # Tiempo antes de reiniciar después de kernel panic.
    "kernel.panic" = 10;

    # SysRq disponible para recuperación manual.
    "kernel.sysrq" = 1;
  };
}