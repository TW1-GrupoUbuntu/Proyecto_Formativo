#!/usr/bin/env bash
# Levanta TODO el proyecto desde cero (desde WSL, en la carpeta del repositorio):  bash scripts/levantar.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p compartido
[ -f compartido/clave_buzones ] || { openssl rand -base64 18 | tr -d '/+=' | cut -c1-20 > compartido/clave_buzones; chmod 600 compartido/clave_buzones; }
docker compose -p pf up -d --build
echo "esperando a systemd..."; sleep 15
x() { echo "── $1: $2"; docker exec -w /lab "pf-$1" bash "scripts/$2" "${@:3}"; }
x cliente crear_ca.sh
x cliente preparar_cliente.sh
x externo preparar_cliente.sh
x resolutor instalar_resolutor.sh
x ns1 instalar_ns1.sh
x ns2 instalar_ns2.sh
x web instalar_web.sh
x mail2 instalar_correo.sh aliada.internal "rosa pedro" no
x mail instalar_correo.sh nazareno.internal "ana luis marta" no
x ns1 publicar_dkim.sh
x web instalar_operacion.sh
x ns1 instalar_operacion.sh
echo "Entorno listo. Verificacion:  docker exec -w /lab pf-cliente bash scripts/verificar.sh"
