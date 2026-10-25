#!/usr/bin/env bash
# Se ejecuta DENTRO de ns1: BIND9 primario con vistas interna/externa, TSIG, DNSSEC (dnssec-policy) y la zona publica de DNSControl.
set -e
B=/var/lib/bind
install -d -o bind -g bind $B/interna $B/externa $B/dinamica $B/claves /var/log/named
mkdir -p /compartido/claves; cd /compartido/claves
[ -f transferencia.key ] || tsig-keygen -a hmac-sha256 transferencia-nazareno > transferencia.key
[ -f dinamico.key ] || tsig-keygen -a hmac-sha256 dinamico-nazareno > dinamico.key
cat transferencia.key dinamico.key > /etc/bind/claves.conf; chown root:bind /etc/bind/claves.conf; chmod 640 /etc/bind/claves.conf
cp /lab/dns/named.conf /lab/dns/named.conf.options /lab/dns/named.conf.local /etc/bind/
Z=/lab/dns/zonas
cp $Z/db.nazareno.internal $Z/db.aliada.internal $Z/db.0.20.10 $B/interna/
cp $Z/db.nazareno.example.interna $B/interna/db.nazareno.example
cp --update=none $Z/db.dinamica.nazareno.internal $B/dinamica/
# serial creciente en cada instalacion (AAMMDDHHMM): el secundario nunca ve un serial menor que el que ya tiene
SER=$(date +%y%m%d%H%M); sed -i "s/2026102501/$SER/" $B/interna/db.nazareno.internal $B/interna/db.aliada.internal $B/interna/db.0.20.10 $B/interna/db.nazareno.example $B/dinamica/db.dinamica.nazareno.internal 2>/dev/null || true
for d in nazareno aliada; do [ -f $B/interna/dkim.$d.internal.inc ] || echo "; clave DKIM de $d.internal (la publica scripts/publicar_dkim.sh)" > $B/interna/dkim.$d.internal.inc; done
bash /lab/scripts/dns_publicar.sh | tail -n 3
chown -R bind:bind $B /var/log/named
named-checkconf
for z in nazareno.internal:db.nazareno.internal aliada.internal:db.aliada.internal 0.20.10.in-addr.arpa:db.0.20.10 nazareno.example:db.nazareno.example; do
  named-checkzone ${z%%:*} $B/interna/${z##*:} >/dev/null && echo "zona ${z%%:*} OK"
done
systemctl enable named >/dev/null 2>&1; systemctl restart named; sleep 4; systemctl is-active named
# Ancla de confianza (para delv desde el nodo externo) y registro DS (para el registrador)
for i in $(seq 1 20); do ls $B/claves/Knazareno.example.+013+*.key >/dev/null 2>&1 && break; sleep 1; done
K=$(ls $B/claves/Knazareno.example.+013+*.key | head -n 1)
KEY=$(awk '/DNSKEY/ && / 257 3 13 /{for (i = 1; i <= NF; i++) if ($i == "DNSKEY") {for (j = i + 4; j <= NF; j++) printf "%s", $j; print ""}}' $K)
printf 'trust-anchors { nazareno.example. static-key 257 3 13 "%s"; };\n' "$KEY" > /compartido/ancla-nazareno.conf
dnssec-dsfromkey -2 $K > /compartido/DS-nazareno.example.txt
echo "ancla y DS generados"
