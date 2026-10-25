#!/usr/bin/env bash
# Chequeo de salud del servidor web: servicios, HTTPS, certificado, disco, memoria y respaldo. Escribe en el journal (nazareno-vigilancia).
R="--resolve www.nazareno.internal:443:127.0.0.1"
problemas=0
ok()     { echo "✅ $*"; }
alerta() { echo "❌ $*"; echo "ALERTA: $*" | systemd-cat -t nazareno-vigilancia -p warning; problemas=$((problemas + 1)); }
for s in nginx ssh fail2ban; do systemctl is-active -q "$s" && ok "servicio $s activo" || alerta "servicio $s DETENIDO"; done
c=$(curl -s -o /dev/null -w '%{http_code}' -m 5 $R https://www.nazareno.internal/); [[ $c == 200 ]] && ok "https://www.nazareno.internal/ → 200" || alerta "https → $c"
openssl x509 -checkend $((14 * 86400)) -noout -in /etc/ssl/nazareno/cert.pem >/dev/null && ok "certificado vigente por mas de 14 dias" || alerta "el certificado vence en menos de 14 dias"
uso=$(df --output=pcent / | tail -1 | tr -dc 0-9); (( uso < 85 )) && ok "disco al ${uso}%" || alerta "disco al ${uso}%"
libre=$(awk '/MemAvailable/{a=$2}/MemTotal/{t=$2}END{printf "%d", a*100/t}' /proc/meminfo); (( libre > 10 )) && ok "memoria disponible ${libre}%" || alerta "memoria disponible ${libre}%"
export RESTIC_REPOSITORY=/var/backups/nazareno-restic RESTIC_PASSWORD_FILE=/root/.config/nazareno/restic.clave
ult=$(restic snapshots --latest 1 --json 2>/dev/null | grep -o '"time":"[^"]*' | head -1 | cut -d'"' -f4)
if [[ -n $ult ]] && (( $(date +%s) - $(date -d "$ult" +%s) < 26*3600 )); then ok "ultimo respaldo: ${ult:0:16}"; else alerta "no hay respaldo de las ultimas 26 horas"; fi
echo "ℹ️  IP bloqueadas por fail2ban: $(fail2ban-client status sshd 2>/dev/null | awk '/Currently banned/{print $NF}')"
(( problemas == 0 )) && echo "OK: servidor sano" | systemd-cat -t nazareno-vigilancia -p info
exit $(( problemas > 0 ))
