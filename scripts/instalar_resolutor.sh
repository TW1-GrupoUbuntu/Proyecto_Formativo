#!/usr/bin/env bash
# Se ejecuta en resolutor: Unbound con cache, DNSSEC, DNS sobre TLS hacia internet, RPZ y zonas propias por stub-zone.
set -e
cp /lab/resolutor/nazareno-resolutor.conf /etc/unbound/unbound.conf.d/
cp /lab/resolutor/rpz.nazareno.internal /etc/unbound/
unbound-anchor -a /var/lib/unbound/root.key >/dev/null 2>&1 || true
chown -R unbound:unbound /var/lib/unbound 2>/dev/null || true
unbound-checkconf >/dev/null && echo "unbound.conf OK"
systemctl enable unbound >/dev/null 2>&1; systemctl restart unbound; sleep 2; systemctl is-active unbound
