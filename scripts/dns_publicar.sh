#!/usr/bin/env bash
# Se ejecuta DENTRO de ns1. Publica la zona PUBLICA escrita como codigo (dnscontrol/dnsconfig.js): check -> preview -> push,
# instala el archivo generado en la vista externa y recarga BIND. Uso: bash dns_publicar.sh [--ttl N] [--solo-preview]
set -e
TTL=""; SOLO=0
while [ $# -gt 0 ]; do case $1 in --ttl) TTL=$2; shift 2;; --solo-preview) SOLO=1; shift;; *) shift;; esac; done
W=/root/dnscontrol; mkdir -p $W/zonas
cp /lab/dnscontrol/dnsconfig.js /lab/dnscontrol/creds.json $W/ 2>/dev/null || true
[ -f /compartido/dnsconfig.js ] && cp /compartido/dnsconfig.js $W/dnsconfig.js      # cambio en revision (ver cambio_dns.sh)
[ -n "$TTL" ] && sed -i "s/^var TTL *= *[0-9]*;/var TTL     = $TTL;/" $W/dnsconfig.js
cd $W
dnscontrol check
dnscontrol preview 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'MODIFY|CREATE|DELETE|Done|ERROR|No changes' || true
[ $SOLO -eq 1 ] && exit 0
dnscontrol push 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'SUCCESS|Done|ERROR' || true
install -d -o bind -g bind /var/lib/bind/externa
install -o bind -g bind -m 644 zonas/nazareno.example.zone /var/lib/bind/externa/db.nazareno.example
named-checkzone nazareno.example /var/lib/bind/externa/db.nazareno.example | tail -n 1
systemctl is-active -q named && rndc reload nazareno.example in externa >/dev/null && echo "zona publica recargada (serial $(awk '/SOA/{f=1} f&&/[0-9]{8}/{print $1; exit}' zonas/nazareno.example.zone))"
exit 0
