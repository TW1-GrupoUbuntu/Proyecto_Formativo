#!/usr/bin/env bash
# Se ejecuta en ns1: publica en cada zona de correo la clave publica DKIM que genero el servidor (/compartido/dkim/<dominio>.txt).
for d in nazareno aliada; do
  f=/compartido/dkim/$d.internal.txt
  [ -f "$f" ] || { echo "falta $f"; continue; }
  install -o bind -g bind -m 644 "$f" /var/lib/bind/interna/dkim.$d.internal.inc
  named-checkzone $d.internal /var/lib/bind/interna/db.$d.internal >/dev/null && bash /lab/scripts/subir_serial.sh $d.internal
done
