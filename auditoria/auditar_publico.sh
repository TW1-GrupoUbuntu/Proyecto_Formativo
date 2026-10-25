#!/usr/bin/env bash
# auditar_publico.sh — Lo que ve INTERNET del dominio público de la organización (vista externa, DNSSEC).
# Uso (desde el nodo EXTERNO):  bash auditar_publico.sh <dominio_publico> <ip_ns_publico> <ancla.conf> [nombre_interno]
#   ej.: bash auditar_publico.sh ue-horizonte.example 172.30.0.2 /lab/lab09/compartido/ancla-ue-horizonte.conf www.horizonte.internal
set -uo pipefail
DOM="${1:?Uso: bash auditar_publico.sh <dominio> <ip_ns> <ancla.conf> [nombre_interno]}"; NS="${2:?}"; ANCLA="${3:?}"
INTERNO="${4:-}"
bien=0; total=0
prueba() { local d="$1"; shift; total=$((total + 1)); if "$@" &>/dev/null; then echo "✅ $d"; bien=$((bien + 1)); else echo "❌ $d"; fi; }

prueba "El dominio público resuelve (www.$DOM)"            bash -c "[[ -n \$(dig +short @$NS www.$DOM A) ]]"
prueba "Respuestas firmadas (RRSIG)"                        bash -c "dig +dnssec +norec @$NS www.$DOM A | grep -q RRSIG"
prueba "delv: fully validated"                              bash -c "delv @$NS -a $ANCLA +root=$DOM www.$DOM 2>&1 | grep -q 'fully validated'"
prueba "delv: la inexistencia también se valida (NSEC3)"    bash -c "delv @$NS -a $ANCLA +root=$DOM no-existe-$RANDOM.$DOM 2>&1 | grep -q 'negative response, fully validated'"
prueba "SPF, DMARC y CAA en la zona pública"               bash -c "dig +short @$NS $DOM TXT | grep -q spf1 && dig +short @$NS _dmarc.$DOM TXT | grep -q DMARC1 && [[ -n \$(dig +short @$NS $DOM CAA) ]]"
prueba "Sin transferencia de zona para internet"            bash -c "dig @$NS $DOM AXFR | grep -q 'Transfer failed'"
[[ -n $INTERNO ]] && prueba "Los nombres internos no se revelan ($INTERNO)" bash -c "dig @$NS $INTERNO A | grep -qE 'status: (REFUSED|NXDOMAIN)'"
echo "Resultado: $bien de $total comprobaciones (vista externa)"
[[ $bien -eq $total ]]
