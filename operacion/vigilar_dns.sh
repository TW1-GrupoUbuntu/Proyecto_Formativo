#!/usr/bin/env bash
# vigilar_dns.sh — Monitoreo del DNS de la cooperativa (para ejecutar a mano o cada hora con un timer de systemd).
# Ejecutar EN ns1:  bash /lab/operacion/vigilar_dns.sh
# Revisa: seriales iguales, firmas DNSSEC que no estén por vencer, tiempos de respuesta y consultas por vista.
ALERTA_DIAS=${ALERTA_DIAS:-3}
estado=0
ok()    { echo "✅ $*"; }
aviso() { echo "⚠️  $*"; estado=1; }

echo "Monitoreo DNS — $(date '+%Y-%m-%d %H:%M')"

# 1. Seriales de la zona interna en ns1 y ns2
s1=$(dig +short +norec @10.20.0.2 nazareno.internal SOA | awk '{print $3}')
s2=$(dig +short +norec @10.20.0.3 nazareno.internal SOA | awk '{print $3}')
if [[ -n $s1 && $s1 == "$s2" ]]; then ok "nazareno.internal: serial $s1 en ns1 y ns2"
else aviso "nazareno.internal: ns1=$s1 ns2=${s2:-sin respuesta} (¿secundario desactualizado?)"; fi

# 2. Vencimiento de las firmas DNSSEC de la zona pública (vista externa)
vence=$(dig +dnssec +norec @172.31.0.2 nazareno.example SOA | awk '$4=="RRSIG" && $5=="SOA"{print $9}' | head -1)
if [[ -z $vence ]]; then
  aviso "nazareno.example: sin firma RRSIG (¿DNSSEC apagado?)"
else
  # $vence = AAAAMMDDhhmmss (UTC) -> segundos desde 1970 -> días que faltan
  venc_seg=$(date -u -d "${vence:0:8} ${vence:8:2}:${vence:10:2}:${vence:12:2}" +%s)
  dias=$(( (venc_seg - $(date -u +%s)) / 86400 ))
  if (( dias >= ALERTA_DIAS )); then ok "nazareno.example: firmas válidas por $dias días más"
  else aviso "nazareno.example: ¡las firmas vencen en $dias días! (¿BIND dejó de refirmar?)"; fi
fi

# 3. Tiempo de respuesta de cada servidor
for srv in 10.20.0.2 10.20.0.3 172.31.0.2; do
  t=$(dig +norec @$srv nazareno.example SOA 2>/dev/null | awk '/Query time/{print $4}')
  if [[ -n $t && $t -lt 100 ]]; then ok "$srv responde en ${t} ms"; else aviso "$srv lento o sin respuesta (${t:-—} ms)"; fi
done

# 4. Consultas por vista (del registro de consultas)
if [[ -r /var/log/named/consultas.log ]]; then
  echo "Consultas registradas por vista:"
  grep -o 'view [a-z]*' /var/log/named/consultas.log | sort | uniq -c | sed 's/^/   /'
fi

# 5. Estado del DS en el padre (hasta que el registrador lo publique, DNSSEC no protege a los visitantes)
ds=$(rndc dnssec -status nazareno.example in externa 2>/dev/null | awk '/- ds:/{print $3}')
[[ $ds == omnipresent ]] && ok "DS publicado en el padre" || echo "ℹ️  DS en el padre: ${ds:-desconocido} (entregar compartido/DS-nazareno.example.txt al registrador)"

exit $estado
