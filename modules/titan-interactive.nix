_:

{
  # Las compilaciones Nix son carga de fondo y ceden CPU a juegos y tareas interactivas.
  # Pueden tardar más mientras el equipo mantiene una carga interactiva continua.
  nix.daemonCPUSchedPolicy = "idle";
}
