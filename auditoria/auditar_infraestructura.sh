#!/usr/bin/env bash
# auditar_infraestructura.sh — Auditoría de la infraestructura del Proyecto Socioformativo (Tecnología Web I).
# Revisa DNS, web, SSH, correo y firewall de una organización y escribe el informe de pruebas en Markdown.
#
# Uso (desde el nodo CLIENTE de la red interna de la organización):
#   bash auditar_infraestructura.sh <dominio_interno> [selector_dkim]
#   ej.: bash auditar_infraestructura.sh horizonte.internal mail
# Variables opcionales: WEB (por defecto www.<dominio>), RES (resolutor; por defecto el del sistema),
#                       INFORME (archivo de salida; por defecto INFORME_AUDITORIA.md)
set -uo pipefail
DOM="${1:?Uso: bash auditar_infraestructura.sh <dominio_interno> [selector_dkim]}"
SEL="${2:-mail}"
WEB="${WEB:-www.$DOM}"
INFORME="${INFORME:-INFORME_AUDITORIA.md}"
RES_OPC=""; [[ -n ${RES:-} ]] && RES_OPC="@$RES"
for h in dig curl openssl nmap ssh swaks; do command -v $h >/dev/null || { echo "Falta $h (apt install dnsutils curl openssl nmap openssh-client swaks)"; exit 1; }; done

bien=0; total=0; LINEAS=()
seccion() { LINEAS+=("" "## $1" ""); echo; echo "── $1"; }
anotar()  { local e="$1"; shift; total=$((total + 1)); [[ $e == "✅" ]] && bien=$((bien + 1)); LINEAS+=("- $e $*"); echo "$e $*"; }
prueba()  { local d="$1"; shift; if "$@" &>/dev/null; then anotar ✅ "$d"; else anotar ❌ "$d"; fi; }
q()       { dig +short $RES_OPC "$@"; }

# ─────────────────────────────── DNS ───────────────────────────────
seccion "DNS"
NS=$(q "$DOM" NS | sort)
prueba "Al menos 2 servidores de nombres ($(echo $NS | wc -w))" test "$(echo $NS | wc -w)" -ge 2
SERIALES=""; COJOS=""
for ns in $NS; do
  r=$(dig +norec +time=3 +tries=1 @"$ns" "$DOM" SOA 2>/dev/null)
  if grep -q 'flags:.* aa' <<<"$r"; then SERIALES+="$(awk '$4=="SOA"{print $7}' <<<"$r") "; else COJOS+="$ns "; fi
done
prueba "Todos los NS responden con autoridad ${COJOS:+(fallan: $COJOS)}" test -z "$COJOS"
prueba "Mismo serial en todos los NS ($(echo $SERIALES | tr ' ' '\n' | sort -u | tr '\n' ' '))" \
       bash -c "[[ -n '${SERIALES// /}' && \$(echo $SERIALES | tr ' ' '\n' | sort -u | wc -l) -eq 1 ]]"
NS1=$(echo $NS | awk '{print $1}')
prueba "Transferencia de zona sin clave rechazada en $NS1" bash -c "dig @$NS1 $DOM AXFR | grep -q 'Transfer failed'"
prueba "Los autoritativos no hacen recursión" bash -c "dig @$NS1 cloudflare.com A | grep -q 'status: REFUSED'"
prueba "Versión de BIND oculta" bash -c "! dig +short @$NS1 CH TXT version.bind | grep -qi '[0-9]\.[0-9]'"
prueba "Zona inversa del servidor web (PTR)" bash -c "ip=\$(dig +short $RES_OPC $WEB A | tail -1); [[ -n \$ip ]] && dig +short $RES_OPC -x \$ip | grep -q ."
prueba "El resolutor valida DNSSEC (flag ad en cloudflare.com)" bash -c "dig +dnssec $RES_OPC cloudflare.com SOA | grep -q 'flags:.* ad'"
prueba "El resolutor rechaza firmas falsas (dnssec-failed.org → SERVFAIL)" bash -c "dig $RES_OPC dnssec-failed.org A | grep -q SERVFAIL"
prueba "CAA publicado" bash -c "[[ -n \$(dig +short $RES_OPC $DOM CAA) ]]"

# ─────────────────────────────── WEB ───────────────────────────────
seccion "Sitio web ($WEB)"
prueba "Responde por HTTPS con certificado válido (200)" bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code}' https://$WEB/) == 200 ]]"
prueba "http:// redirige a https:// (301)" bash -c "curl -sI http://$WEB/ | tr -d '\r' | grep -qi '^location: https://'"
prueba "Negocia TLS 1.3" bash -c "echo | openssl s_client -connect $WEB:443 -servername $WEB 2>/dev/null | grep -q TLSv1.3"
CAB=$(curl -sI "https://$WEB/" | tr -d '\r' | tr 'A-Z' 'a-z')
prueba "HSTS" grep -q '^strict-transport-security:' <<<"$CAB"
prueba "Content-Security-Policy" grep -q '^content-security-policy:' <<<"$CAB"
prueba "X-Content-Type-Options: nosniff" grep -q '^x-content-type-options: nosniff' <<<"$CAB"
prueba "Servidor sin versión en la cabecera Server" bash -c "! grep -qE '^server: .*[0-9]\.[0-9]' <<<\"$CAB\""
DIAS=$(( ( $(date -d "$(echo | openssl s_client -connect $WEB:443 -servername $WEB 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)" +%s) - $(date +%s) ) / 86400 ))
prueba "Certificado vigente por más de 14 días ($DIAS días)" test "$DIAS" -gt 14

# ─────────────────────────────── SSH ───────────────────────────────
seccion "Acceso remoto (SSH en $WEB)"
SSHV=$(ssh -v -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 auditor@"$WEB" true 2>&1)
solo_claves() { local l; l=$(grep 'Authentications that can continue' <<<"$SSHV" | head -1 | tr -d '\r'); [[ -n $l && $l != *password* && $l != *keyboard-interactive* ]]; }
prueba "Solo acepta claves (sin contraseñas)" solo_claves
prueba "Intercambio de claves post-cuántico" bash -c "grep -qE 'kex: algorithm: (sntrup761x25519|mlkem768x25519)' <<<\"\$0\"" "$SSHV"
prueba "TELNET cerrado (puerto 23)" bash -c "! (echo > /dev/tcp/$WEB/23) 2>/dev/null"

# ────────────────────────────── CORREO ─────────────────────────────
seccion "Correo ($DOM)"
MX=$(q "$DOM" MX | sort -n | head -1 | awk '{print $2}'); MX=${MX%.}
prueba "MX publicado (${MX:-ninguno})" test -n "$MX"
if [[ -n $MX ]]; then
  prueba "SPF con -all" bash -c "dig +short $RES_OPC $DOM TXT | grep -q 'v=spf1.*-all'"
  prueba "Clave DKIM publicada ($SEL._domainkey)" bash -c "dig +short $RES_OPC $SEL._domainkey.$DOM TXT | grep -q 'v=DKIM1'"
  prueba "DMARC con política quarantine o reject" bash -c "dig +short $RES_OPC _dmarc.$DOM TXT | grep -qE 'p=(quarantine|reject)'"
  prueba "IMAPS (993) con certificado válido" bash -c "echo | openssl s_client -connect $MX:993 -servername $MX -verify_return_error 2>&1 | grep -q 'Verification: OK'"
  prueba "IMAP sin cifrar (143) cerrado" bash -c "! (echo > /dev/tcp/$MX/143) 2>/dev/null"
  prueba "Envío (587) sin TLS no ofrece autenticación" bash -c "swaks --server $MX --port 587 --quit-after EHLO 2>&1 | grep -v STARTTLS | grep -q '250' && ! swaks --server $MX --port 587 --quit-after EHLO 2>&1 | grep -q 'AUTH'"
fi

# ───────────────────────────── FIREWALL ────────────────────────────
seccion "Puertos expuestos ($WEB)"
ABIERTOS=$(nmap -Pn -p 21,22,23,25,80,110,143,443,3306,5432,8080,8081 "$WEB" 2>/dev/null | awk '/open/{print $1}' | cut -d/ -f1 | tr '\n' ' ')
prueba "Solo 22, 80 y 443 abiertos en el servidor web (abiertos: ${ABIERTOS:-ninguno})" test "$ABIERTOS" = "22 80 443 "

# ───────────────────────────── INFORME ─────────────────────────────
{
  echo "# Informe de auditoría — $DOM"
  echo
  echo "Fecha: $(date '+%Y-%m-%d %H:%M') · equipo auditor: $(hostname) · resolutor: ${RES:-el del sistema}"
  echo
  echo "**Resultado: $bien de $total comprobaciones ($(( bien * 100 / total )) %)**"
  printf '%s\n' "${LINEAS[@]}"
  echo
  echo "> Las comprobaciones de la vista externa (zona pública firmada, validación con delv) se ejecutan desde el nodo"
  echo "> externo con auditar_publico.sh."
} > "$INFORME"
echo; echo "Resultado: $bien de $total comprobaciones → $INFORME"
