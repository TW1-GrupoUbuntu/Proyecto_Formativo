#!/usr/bin/env bash
# Se ejecuta en cliente: crea la CA interna de la cooperativa y un certificado por servicio (las claves no se suben al repositorio).
set -e
C=/compartido/ca; mkdir -p $C /compartido/certs; cd $C
[ -f ca.key ] || openssl req -x509 -newkey rsa:3072 -nodes -keyout ca.key -out ca.crt -days 825 -subj "/C=BO/O=Cooperativa Jesus Nazareno/CN=pki.nazareno.internal" 2>/dev/null
emitir() { h=$1; shift; san=$(printf 'DNS:%s,' "$@"); san=${san%,}
  [ -f /compartido/certs/$h.crt ] && return
  openssl req -newkey rsa:2048 -nodes -keyout /compartido/certs/$h.key -out /tmp/$h.csr -subj "/C=BO/O=Cooperativa Jesus Nazareno/CN=$h" 2>/dev/null
  printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n' "$san" > /tmp/$h.ext
  openssl x509 -req -in /tmp/$h.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out /compartido/certs/$h.crt -days 397 -sha256 -extfile /tmp/$h.ext 2>/dev/null; }
emitir www.nazareno.internal www.nazareno.internal portal.nazareno.internal www.nazareno.example nazareno.example
emitir mail.nazareno.internal mail.nazareno.internal imap.nazareno.internal smtp.nazareno.internal
emitir mail.aliada.internal mail.aliada.internal
chmod 600 /compartido/certs/*.key ca.key
echo "CA y certificados: $(ls /compartido/certs | tr '\n' ' ')"
