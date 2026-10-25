#!/usr/bin/env bash
# Se ejecuta DENTRO de un nodo de correo. Instala y configura Postfix, Dovecot, OpenDKIM, OpenDMARC y (opcional) Rspamd + ClamAV.
# Uso:  bash instalar_correo.sh <dominio> "<usuarios>" <si|no antispam>
#       bash /lab/scripts/instalar_correo.sh horizonte.internal "ana luis marta" si
set -e
DOM=${1:?dominio}; USUARIOS=${2:?usuarios}; ANTI=${3:-no}
HOSTN=mail.$DOM
LAB=/lab/correo
CLAVE_FILE=/compartido/clave_buzones
[ -f "$CLAVE_FILE" ] || { echo "falta $CLAVE_FILE (lo crea levantar.sh)"; exit 1; }

# 1. Certificado y CA
install -d -m 755 /etc/ssl/correo
cp /compartido/certs/$HOSTN.crt /etc/ssl/correo/cert.pem
cp /compartido/certs/$HOSTN.key /etc/ssl/correo/key.pem
cp /compartido/ca/ca.crt /etc/ssl/correo/ca.crt
cp /compartido/ca/ca.crt /usr/local/share/ca-certificates/ca-nazareno.crt && update-ca-certificates >/dev/null 2>&1
chmod 640 /etc/ssl/correo/key.pem; chgrp ssl-cert /etc/ssl/correo/key.pem 2>/dev/null || true

# 2. Buzones del personal (usuarios del sistema; la contraseña no se muestra)
for u in $USUARIOS; do
  id "$u" >/dev/null 2>&1 || useradd -m -s /usr/sbin/nologin "$u"
  echo "$u:$(cat $CLAVE_FILE)" | chpasswd
done
PRIMERO=${USUARIOS%% *}
cat > /etc/aliases <<A
postmaster: root
root: $PRIMERO
dmarc: $PRIMERO
abuse: $PRIMERO
A

# 3. Postfix
MILTERS="inet:127.0.0.1:8891, inet:127.0.0.1:8893"
[ "$ANTI" = si ] && MILTERS="$MILTERS, inet:127.0.0.1:11332"
sed "s/__DOM__/$DOM/g; s#__MILTERS__#$MILTERS#; s/__ANTISPAM__/antispam: $ANTI/" $LAB/postfix/main.cf.in > /etc/postfix/main.cf
[ -f /etc/postfix/master.cf ] || cp /usr/share/postfix/master.cf.dist /etc/postfix/master.cf
grep -q 'Actividad 4' /etc/postfix/master.cf || cat $LAB/postfix/master.cf.add >> /etc/postfix/master.cf
printf '/^([^@]+)@%s$/ ${1}\n' "$(echo $DOM | sed 's/\./\\./g')" > /etc/postfix/login_maps
# SPF: solo se anota el resultado en la cabecera Received-SPF (la decisión la toma DMARC / Rspamd)
sed -i 's/^HELO_reject.*/HELO_reject = False/; s/^Mail_From_reject.*/Mail_From_reject = False/' /etc/postfix-policyd-spf-python/policyd-spf.conf
echo "$HOSTN" > /etc/mailname
newaliases

# 4. Dovecot (IMAP sobre TLS, LMTP, Sieve)
sed "s/__DOM__/$DOM/g" $LAB/dovecot/99-nazareno.conf > /etc/dovecot/conf.d/99-nazareno.conf
install -d /etc/dovecot/sieve; cp $LAB/dovecot/antispam.sieve /etc/dovecot/sieve/; sievec /etc/dovecot/sieve/antispam.sieve

# 5. OpenDKIM (clave 2048 bits, selector "mail") y OpenDMARC
install -d -o opendkim -g opendkim -m 750 /etc/opendkim/keys/$DOM
[ -f /etc/opendkim/keys/$DOM/mail.private ] || opendkim-genkey -b 2048 -d $DOM -s mail -D /etc/opendkim/keys/$DOM
chown opendkim:opendkim /etc/opendkim/keys/$DOM/*; chmod 600 /etc/opendkim/keys/$DOM/mail.private
echo "mail._domainkey.$DOM $DOM:mail:/etc/opendkim/keys/$DOM/mail.private" > /etc/opendkim/KeyTable
echo "*@$DOM mail._domainkey.$DOM" > /etc/opendkim/SigningTable
sed "s/__DOM__/$DOM/g" $LAB/opendkim/opendkim.conf.in > /etc/opendkim.conf
sed "s/__DOM__/$DOM/g" $LAB/opendkim/opendmarc.conf.in > /etc/opendmarc.conf
sed -i '/^SOCKET=/d' /etc/default/opendkim 2>/dev/null || true
install -d -o opendkim -g opendkim /run/opendkim; install -d -o opendmarc -g opendmarc /run/opendmarc
# la clave PUBLICA (registro DNS) va a /compartido para que ns1 la publique
install -d /compartido/dkim; cp /etc/opendkim/keys/$DOM/mail.txt /compartido/dkim/$DOM.txt

# 6. Antispam y antivirus (Rspamd + ClamAV)
if [ "$ANTI" = si ]; then
  for f in worker-proxy.inc options.inc; do cp $LAB/rspamd/$f /etc/rspamd/local.d/; done
  for f in milter_headers actions antivirus greylist rbl; do cp $LAB/rspamd/$f.conf /etc/rspamd/local.d/; done
  grep -q '^TCPSocket' /etc/clamav/clamd.conf || printf 'TCPSocket 3310\nTCPAddr 127.0.0.1\n' >> /etc/clamav/clamd.conf
  systemctl stop clamav-freshclam >/dev/null 2>&1 || true
  [ -f /var/lib/clamav/main.cvd ] || [ -f /var/lib/clamav/main.cld ] || freshclam --quiet || freshclam
  systemctl enable clamav-freshclam clamav-daemon rspamd >/dev/null 2>&1
  systemctl restart clamav-freshclam clamav-daemon
  systemctl restart rspamd
fi

# 7. Arranque
systemctl enable postfix dovecot opendkim opendmarc >/dev/null 2>&1
systemctl restart opendkim opendmarc dovecot postfix
sleep 3
for s in postfix dovecot opendkim opendmarc; do printf '%s: %s\n' $s "$(systemctl is-active $s)"; done
[ "$ANTI" = si ] && for s in rspamd clamav-daemon; do printf '%s: %s\n' $s "$(systemctl is-active $s)"; done
echo "instalacion de $DOM terminada"
