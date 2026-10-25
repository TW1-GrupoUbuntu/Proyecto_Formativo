#!/usr/bin/env bash
# Simulacro de restauracion (en web): guarda la huella del sitio, respalda, borra el archivo, restaura y compara.
set -euo pipefail
export RESTIC_REPOSITORY=/var/backups/nazareno-restic RESTIC_PASSWORD_FILE=/root/.config/nazareno/restic.clave
F=/srv/nazareno/www/index.html
H1=$(sha256sum $F | cut -d' ' -f1); echo "huella original:  $H1"
bash /lab/operacion/respaldar.sh >/dev/null
rm -f $F; echo "archivo borrado: $([[ -e $F ]] && echo NO || echo si)"
restic restore latest --target / --include $F | tail -n 1
H2=$(sha256sum $F | cut -d' ' -f1); echo "huella restaurada: $H2"
[[ $H1 == "$H2" ]] && echo "Restaurado identico" || { echo "FALLO: las huellas difieren"; exit 1; }
