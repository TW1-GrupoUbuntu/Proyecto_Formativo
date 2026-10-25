#!/usr/bin/env bash
# Verificador del Proyecto Formativo. Se ejecuta en el anfitrion (WSL), en la carpeta del repositorio:  bash scripts/verificar.sh
# Corre dentro de los nodos: las dos auditorias del curso y las pruebas de DNS, servicios por nombre y operacion.
cd "$(dirname "$0")/.."
bien=0; total=0
c()  { docker exec -w /lab pf-cliente bash -c "$1"; }      # desde el PC de la cooperativa
e()  { docker exec -w /lab pf-externo bash -c "$1"; }      # desde "internet"
n()  { docker exec -w /lab "pf-$1" bash -c "$2"; }         # en un nodo cualquiera
prueba() { total=$((total + 1)); if "${@:2}" >/dev/null 2>&1; then echo "✅ $1"; bien=$((bien + 1)); else echo "❌ $1"; fi; }
seccion() { echo; echo "── $1"; }
KT=/compartido/claves/transferencia.key; KD=/compartido/claves/dinamico.key

seccion "Auditorias del curso"
AI=$(c "RES=10.20.0.4 INFORME=/tmp/INFORME_AUDITORIA.md bash /lab/auditoria/auditar_infraestructura.sh nazareno.internal mail" 2>&1 | tee /tmp/pf_ai.txt | grep '^Resultado' )
echo "$AI"
BI=$(echo "$AI" | grep -oE '[0-9]+ de [0-9]+' | head -n 1); b1=${BI%% de *}; t1=${BI##* de }
prueba "Auditoria interna >= 90 % ($BI)" test $(( b1 * 100 / t1 )) -ge 90
AP=$(e "bash /lab/auditoria/auditar_publico.sh nazareno.example 172.31.0.2 /compartido/ancla-nazareno.conf www.nazareno.internal" 2>&1 | tee /tmp/pf_ap.txt | grep '^Resultado'); echo "$AP"
BP=$(echo "$AP" | grep -oE '[0-9]+ de [0-9]+' | head -n 1)
prueba "Auditoria publica al 100 % ($BP)" test "${BP%% de *}" = "${BP##* de }"

docker exec pf-cliente cat /tmp/INFORME_AUDITORIA.md > docs/INFORME_AUDITORIA.md 2>/dev/null   # /tmp es tmpfs: docker cp no puede leerlo
seccion "DNS: vistas, secundario, TSIG y DNSSEC"
prueba "Vista interna: www.nazareno.example = 10.20.0.20" c "[ \"\$(dig +short @10.20.0.2 www.nazareno.example)\" = 10.20.0.20 ]"
prueba "Vista externa: www.nazareno.example = 203.0.113.20" e "[ \"\$(dig +short @172.31.0.2 www.nazareno.example)\" = 203.0.113.20 ]"
prueba "Secundario ns2 con el mismo serial que ns1" c "[ -n \"\$(dig +short @10.20.0.2 nazareno.internal SOA | awk '{print \$3}')\" ] && [ \"\$(dig +short @10.20.0.2 nazareno.internal SOA | awk '{print \$3}')\" = \"\$(dig +short @10.20.0.3 nazareno.internal SOA | awk '{print \$3}')\" ]"
prueba "ns2 responde nombres de la zona interna" c "dig +short @10.20.0.3 www.nazareno.internal | grep -q 10.20.0.20"
prueba "Transferencia (AXFR) con la clave TSIG: permitida" c "dig @10.20.0.2 nazareno.internal AXFR -k $KT | grep -q 'XFR size'"
prueba "Transferencia (AXFR) sin clave: rechazada" c "dig @10.20.0.2 nazareno.internal AXFR | grep -q 'Transfer failed'"
prueba "Zona publica firmada: RRSIG y DNSKEY desde internet" e "dig +dnssec +norec @172.31.0.2 www.nazareno.example A | grep -q RRSIG && dig +norec @172.31.0.2 nazareno.example DNSKEY | grep -q DNSKEY"
prueba "delv: positivo y NXDOMAIN completamente validados" e "delv @172.31.0.2 -a /compartido/ancla-nazareno.conf +root=nazareno.example www.nazareno.example 2>&1 | grep -q 'fully validated' && delv @172.31.0.2 -a /compartido/ancla-nazareno.conf +root=nazareno.example no-existe.nazareno.example 2>&1 | grep -q 'negative response, fully validated'"
prueba "Ancla falsa: delv no valida (broken trust chain)" e "sed 's/\"\(.\)/\"A/' /compartido/ancla-nazareno.conf > /tmp/falsa.conf; delv @172.31.0.2 -a /tmp/falsa.conf +root=nazareno.example www.nazareno.example 2>&1 | grep -qE 'broken trust chain|resolution failed'"
prueba "DS generado para el registrador" n ns1 "test -s /compartido/DS-nazareno.example.txt"

seccion "Resolutor: DoT, RPZ y DNS dinamico"
prueba "El resolutor resuelve la zona interna" c "dig +short @10.20.0.4 www.nazareno.internal | grep -q 10.20.0.20"
prueba "DNS sobre TLS: consultas salen por el 853 y ninguna por el 53 hacia internet" bash -c "docker exec pf-resolutor bash -c 'timeout 15 tcpdump -i any -nn -l -c 1 \"port 853\" > /tmp/dot.txt 2>/dev/null & timeout 15 tcpdump -i any -nn -l -c 1 \"port 53 and (dst host 1.1.1.1 or dst host 9.9.9.9)\" > /tmp/p53.txt 2>/dev/null & sleep 2; dig @127.0.0.1 x\$RANDOM.cloudflare.com A >/dev/null; sleep 4; pkill tcpdump; grep -q 853 /tmp/dot.txt && ! grep -q . /tmp/p53.txt'"
prueba "RPZ: dominio de prestamos bloqueado (NXDOMAIN)" c "dig @10.20.0.4 prestamos-rapidos-ejemplo.com | grep -q NXDOMAIN"
prueba "RPZ: phishing redirigido a la pagina de aviso" c "[ \"\$(dig +short @10.20.0.4 www.nazareno-ahorros-login.com)\" = 10.20.0.20 ]"
prueba "RPZ: rastreador sin datos (NODATA)" c "dig @10.20.0.4 rastreo.publicidad-ejemplo.net | grep -q 'ANSWER: 0'"
prueba "nsupdate: el equipo se registra en la zona dinamica (con TSIG)" c "printf 'server 10.20.0.2\nzone dinamica.nazareno.internal\nupdate delete cliente.dinamica.nazareno.internal A\nupdate add cliente.dinamica.nazareno.internal 300 A 10.20.0.50\nsend\n' | nsupdate -k $KD && sleep 2 && dig +short @10.20.0.4 cliente.dinamica.nazareno.internal | grep -q 10.20.0.50"
prueba "nsupdate: la actualizacion llega al secundario" c "dig +short @10.20.0.3 cliente.dinamica.nazareno.internal | grep -q 10.20.0.50"
prueba "nsupdate: sin clave se rechaza" c "printf 'server 10.20.0.2\nzone dinamica.nazareno.internal\nupdate add intruso.dinamica.nazareno.internal 300 A 6.6.6.6\nsend\n' | nsupdate 2>&1 | grep -qiE 'refused|notauth|failed'"
prueba "nsupdate: la clave no sirve fuera de su zona" c "printf 'server 10.20.0.2\nzone nazareno.internal\nupdate add intruso.nazareno.internal 300 A 6.6.6.6\nsend\n' | nsupdate -k $KD 2>&1 | grep -qiE 'refused|notauth|failed'"

seccion "Servicios por nombre: web, SSH y correo"
prueba "HTTPS por nombre con certificado de la CA interna" c "curl -s -o /dev/null -w '%{http_code}' https://www.nazareno.internal/ | grep -q 200"
prueba "Reportes de GoAccess: 401 sin clave y 200 con clave" c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' https://www.nazareno.internal/reportes/)\" = 401 ] && [ \"\$(curl -s -o /dev/null -w '%{http_code}' -u reportes:\$(cat /compartido/clave_reportes) https://www.nazareno.internal/reportes/)\" = 200 ]"
prueba "SSH por nombre con clave (jhonc)" c "ssh -o StrictHostKeyChecking=no -o BatchMode=yes jhonc@www.nazareno.internal 'echo ok' | grep -q ok"
prueba "SSH: root no puede entrar" c "! ssh -o StrictHostKeyChecking=no -o BatchMode=yes root@www.nazareno.internal true"
prueba "Correo: relé cerrado (554 a un dominio ajeno)" c "swaks --server mail.nazareno.internal --from falso@nazareno.internal --to victima@otro.example --quit-after RCPT 2>&1 | grep -q '554 5.7.1'"
ASU="Prueba-$(date +%s)"
prueba "Correo: ana -> rosa (587 con TLS y AUTH)" c "swaks --server mail.nazareno.internal --port 587 --tls --auth PLAIN --auth-user ana --auth-password \"\$(cat /compartido/clave_buzones)\" --from ana@nazareno.internal --to rosa@aliada.internal --header 'Subject: $ASU' --body 'Prueba del proyecto' 2>&1 | grep -qE '^<[-~]\\*? +250 2.0.0 Ok'"
sleep 4
prueba "Correo: rosa lo recibe por IMAPS con dkim=pass y spf=pass" c "python3 /lab/scripts/analizar_cabeceras.py mail.aliada.internal rosa '$ASU' | grep -E 'Authentication-Results' | grep -q 'dkim=pass' && python3 /lab/scripts/analizar_cabeceras.py mail.aliada.internal rosa '$ASU' | grep -q 'Received-SPF: Pass'"

seccion "Seguridad y operacion"
prueba "ufw activo en el servidor web" n web "ufw status | grep -q 'Status: active'"
prueba "fail2ban con la jaula sshd activa" n web "fail2ban-client status sshd | grep -q 'Currently banned'"
prueba "fail2ban bloquea a un atacante (mail2 prueba 6 claves falsas) y luego se desbloquea" bash -c "for i in 1 2 3 4 5 6; do docker exec pf-mail2 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=4 intruso\$i@www.nazareno.internal true >/dev/null 2>&1; done; sleep 3; docker exec pf-web fail2ban-client status sshd | grep -q 10.20.0.26 && docker exec pf-web fail2ban-client set sshd unbanip 10.20.0.26 | grep -q 1"
prueba "Actualizaciones automaticas configuradas" n web "grep -q 'Unattended-Upgrade \"1\"' /etc/apt/apt.conf.d/20auto-upgrades"
prueba "Respaldo con restic y restauracion identica (SHA-256)" n web "bash /lab/operacion/probar_restauracion.sh | grep -q 'Restaurado identico'"
prueba "Temporizadores de vigilancia activos (web y DNS)" bash -c "docker exec pf-web systemctl is-active nazareno-vigilancia.timer nazareno-respaldo.timer nazareno-reporte.timer | grep -vc '^active' | grep -q '^0$' && docker exec pf-ns1 systemctl is-active nazareno-vigilar-dns.timer | grep -q '^active'"
prueba "Vigilancia del servidor web sin alertas" n web "bash /lab/operacion/vigilar_servidor.sh"
prueba "Vigilancia del DNS sin alertas" n ns1 "bash /lab/operacion/vigilar_dns.sh"

echo; echo "Resultado: $bien de $total comprobaciones correctas"
echo "Proyecto Formativo - Cooperativa Jesus Nazareno"
[ "$bien" -eq "$total" ]
