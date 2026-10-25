#!/usr/bin/env bash
# Reporte HTML de visitas con GoAccess a partir de los registros de Nginx (se publica con usuario y clave en /reportes/).
set -euo pipefail
FORMATO='%h - [%d:%t %^] "%v" "%r" %s %b %T "%u"'
zcat -f /var/log/nginx/nazareno.access.log* 2>/dev/null | goaccess - --log-format="$FORMATO" --date-format='%d/%b/%Y' --time-format='%T' \
  --html-report-title='Sitio · Cooperativa Jesus Nazareno' --no-global-config -o /srv/nazareno/reportes/index.html 2>/dev/null
chmod 644 /srv/nazareno/reportes/index.html
echo "Reporte: https://www.nazareno.internal/reportes/ ($(du -h /srv/nazareno/reportes/index.html | cut -f1))"
