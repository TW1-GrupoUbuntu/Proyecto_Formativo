#!/usr/bin/env bash
# Respaldo cifrado y deduplicado con restic de lo que NO se reinstala con apt (configuracion, sitio, certificados, claves de ns1).
set -euo pipefail
export RESTIC_REPOSITORY=/var/backups/nazareno-restic     # en produccion: disco externo, otro servidor o la nube
export RESTIC_PASSWORD_FILE=/root/.config/nazareno/restic.clave
if [[ ! -s $RESTIC_PASSWORD_FILE ]]; then
  install -d -m 700 "$(dirname "$RESTIC_PASSWORD_FILE")"; openssl rand -base64 32 > "$RESTIC_PASSWORD_FILE"; chmod 600 "$RESTIC_PASSWORD_FILE"
fi
restic cat config >/dev/null 2>&1 || restic init >/dev/null
RUTAS=()
for r in /etc/nginx /etc/ssh/sshd_config.d /etc/fail2ban/jail.d /srv/nazareno /etc/ssl/nazareno /home /etc/bind /var/lib/bind /etc/unbound /etc/postfix /etc/dovecot; do [[ -e $r ]] && RUTAS+=("$r"); done
restic backup --tag diario --exclude-caches "${RUTAS[@]}" | tail -n 3
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune | tail -n 1
restic check | tail -n 1
