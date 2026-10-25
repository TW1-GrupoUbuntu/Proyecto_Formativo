#!/usr/bin/env bash
# firewall/aplicar_ufw.sh — Cortafuegos del servidor del colegio: todo cerrado salvo lo que se sirve.
# ⚠️  Permite SSH ANTES de activar ufw o te quedarás afuera.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root"; exit 1; }
ufw --force reset >/dev/null
ufw default deny incoming           # la política por defecto deniega todo lo que entra
ufw default allow outgoing          # el servidor puede salir (actualizaciones, DNS, correo)
ufw limit 22/tcp comment 'SSH con limite'   # limit: deniega a quien abre 6 o mas conexiones en 30 s
ufw allow 80/tcp  comment 'HTTP (solo redirige a HTTPS)'
ufw allow 443/tcp comment 'HTTPS'
ufw logging low
ufw --force enable
ufw status verbose
