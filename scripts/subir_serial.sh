#!/usr/bin/env bash
# Se ejecuta en ns1. Uso: bash subir_serial.sh <zona>   (nazareno.internal | aliada.internal | 0.20.10.in-addr.arpa | nazareno.example)
# Sube en 1 el serial de la zona interna y recarga: sin esto el secundario no copia los cambios.
Z=${1:?zona}; B=/var/lib/bind/interna
case $Z in 0.20.10.in-addr.arpa) F=$B/db.0.20.10;; *) F=$B/db.$Z;; esac
S=$(grep -oE '\( *[0-9]{10}' "$F" | grep -oE '[0-9]{10}')
sed -i "s/$S/$((S + 1))/" "$F"
rndc reload "$Z" in interna >/dev/null && echo "$Z serial $S -> $((S + 1))"
