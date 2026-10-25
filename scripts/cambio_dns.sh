#!/usr/bin/env bash
# Procedimiento de cambios de DNS (zona publica como codigo). Desde el anfitrion, en la carpeta del repositorio:
#   1) editar dnscontrol/dnsconfig.js en una rama de Git y revisar el cambio (git diff / solicitud de cambios)
#   2) bash scripts/cambio_dns.sh [--ttl N]     -> check, preview (diff), push, instala la zona, sube el serial y verifica
#   3) git commit/merge una vez verificado; si algo falla: git checkout -- dnscontrol/dnsconfig.js y repetir el paso 2 (reversa)
cd "$(dirname "$0")/.."
TTL=""; [ "$1" = "--ttl" ] && { TTL="--ttl $2"; shift 2; }
echo "== 1/6 Revision en Git (cambios pendientes en dnscontrol/)"; git diff --stat -- dnscontrol/ 2>/dev/null || echo "(sin git)"
cp dnscontrol/dnsconfig.js compartido/dnsconfig.js
S0=$(docker exec pf-externo dig +short @172.31.0.2 nazareno.example SOA | awk '{print $3}')
echo "== 2/6 dnscontrol check + preview"; docker exec -w /lab pf-ns1 bash scripts/dns_publicar.sh $TTL --solo-preview || { rm -f compartido/dnsconfig.js; echo "BLOQUEADO: no se publica nada"; exit 1; }
echo "== 3/6 push y recarga"; docker exec -w /lab pf-ns1 bash scripts/dns_publicar.sh $TTL || { rm -f compartido/dnsconfig.js; echo "ERROR en el push"; exit 2; }
echo "== 4/6 verificacion: serial y firmas"; sleep 3
S1=$(docker exec pf-externo dig +short @172.31.0.2 nazareno.example SOA | awk '{print $3}')
echo "serial publico: $S0 -> $S1"; [ "$S1" != "$S0" ] && echo "✅ el serial subio" || echo "⚠️  el serial no cambio (¿cambio sin diferencias?)"
echo "== 5/6 delv desde internet"; docker exec pf-externo delv @172.31.0.2 -a /compartido/ancla-nazareno.conf +root=nazareno.example www.nazareno.example 2>&1 | grep -E 'fully validated|; resolution failed' | head -n 1
echo "== 6/6 TTL vigente en la zona"; docker exec pf-externo dig +noall +answer @172.31.0.2 www.nazareno.example A
rm -f compartido/dnsconfig.js
echo "Siguiente paso: git commit -am 'DNS: <descripcion>' (tras la revision) y subir el serial interno si cambio algo en la vista interna."
