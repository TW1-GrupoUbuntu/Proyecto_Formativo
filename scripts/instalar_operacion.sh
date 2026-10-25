#!/usr/bin/env bash
# Instala la operacion como servicios y temporizadores de systemd.
#   web: respaldo diario (restic), reporte de GoAccess y vigilancia cada 5 min; ns1: monitoreo del DNS cada hora; actualizaciones automaticas.
set -e
unidad() { # unidad <nombre> <descripcion> <orden> <calendario>
  printf '[Unit]\nDescription=%s\n[Service]\nType=oneshot\nExecStart=%s\n' "$2" "$3" > /etc/systemd/system/$1.service
  printf '[Unit]\nDescription=Temporizador: %s\n[Timer]\nOnCalendar=%s\nPersistent=true\n[Install]\nWantedBy=timers.target\n' "$2" "$4" > /etc/systemd/system/$1.timer; }
# actualizaciones de seguridad automaticas
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
case $(hostname) in
  web)
    unidad nazareno-respaldo "Respaldo cifrado con restic" "/bin/bash /lab/operacion/respaldar.sh" "*-*-* 02:00:00"
    unidad nazareno-reporte  "Reporte de visitas con GoAccess" "/bin/bash /lab/operacion/generar_reporte.sh" "*-*-* 03:00:00"
    unidad nazareno-vigilancia "Vigilancia del servidor web" "/bin/bash /lab/operacion/vigilar_servidor.sh" "*:0/5"
    T="nazareno-respaldo nazareno-reporte nazareno-vigilancia";;
  ns1)
    unidad nazareno-vigilar-dns "Monitoreo del DNS (seriales, firmas DNSSEC, tiempos)" "/bin/bash /lab/operacion/vigilar_dns.sh" "hourly"
    unidad nazareno-respaldo "Respaldo cifrado de la configuracion de DNS" "/bin/bash /lab/operacion/respaldar.sh" "*-*-* 02:30:00"
    T="nazareno-vigilar-dns nazareno-respaldo";;
esac
systemctl daemon-reload
for t in $T; do systemctl enable --now $t.timer >/dev/null 2>&1; done
systemctl list-timers --no-pager | grep -E 'nazareno' | awk '{print $NF, $(NF-1)}' | head -n 4
bash /lab/operacion/respaldar.sh >/dev/null && echo "primer respaldo hecho"
[ "$(hostname)" = web ] && bash /lab/operacion/generar_reporte.sh
exit 0
