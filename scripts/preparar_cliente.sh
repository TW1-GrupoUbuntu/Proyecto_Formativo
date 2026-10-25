#!/usr/bin/env bash
# Se ejecuta en cliente y externo: confian en la CA de la cooperativa; el cliente genera la clave SSH del administrador.
cp /compartido/ca/ca.crt /usr/local/share/ca-certificates/ca-nazareno.crt && update-ca-certificates >/dev/null 2>&1 && echo "CA instalada en $(hostname)"
if [ "$(hostname)" = cliente ]; then
  [ -f /root/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519 -C jhonc@cliente
  mkdir -p /compartido/ssh && cp /root/.ssh/id_ed25519.pub /compartido/ssh/jhonc.pub
fi
