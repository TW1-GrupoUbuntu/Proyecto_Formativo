#!/usr/bin/env bash
# Se ejecuta DENTRO de ns2: BIND9 secundario; las zonas internas llegan de ns1 por transferencia autenticada con TSIG.
set -e
cat /compartido/claves/transferencia.key > /etc/bind/claves.conf; chown root:bind /etc/bind/claves.conf; chmod 640 /etc/bind/claves.conf
cp /lab/dns/named.conf.ns2 /etc/bind/named.conf
named-checkconf
systemctl enable named >/dev/null 2>&1; systemctl restart named
for i in $(seq 1 30); do dig +short +norec @127.0.0.1 nazareno.internal SOA | grep -q ns1 && break; sleep 1; done
echo "ns2: serial de nazareno.internal = $(dig +short +norec @127.0.0.1 nazareno.internal SOA | awk '{print $3}')"
