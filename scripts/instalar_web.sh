#!/usr/bin/env bash
# Se ejecuta en web: Nginx con HTTPS (CA interna, HSTS, CSP), SSH endurecido, fail2ban y firewall ufw.
set -e
# 1. Certificado y sitio
install -d -m 755 /etc/ssl/nazareno /srv/nazareno/www /srv/nazareno/reportes
cp /compartido/certs/www.nazareno.internal.crt /etc/ssl/nazareno/cert.pem
cp /compartido/certs/www.nazareno.internal.key /etc/ssl/nazareno/key.pem; chmod 600 /etc/ssl/nazareno/key.pem
cp /compartido/ca/ca.crt /usr/local/share/ca-certificates/ca-nazareno.crt && update-ca-certificates >/dev/null 2>&1
cp /lab/web/sitio/* /srv/nazareno/www/
cp /lab/web/nginx-log.conf /etc/nginx/conf.d/nazareno-log.conf
cp /lab/web/nginx-sitio.conf /etc/nginx/sites-available/nazareno; ln -sf /etc/nginx/sites-available/nazareno /etc/nginx/sites-enabled/nazareno; rm -f /etc/nginx/sites-enabled/default
# usuario y clave de los reportes (la clave no se muestra ni se sube)
[ -f /compartido/clave_reportes ] || openssl rand -base64 12 | tr -d '/+=' > /compartido/clave_reportes
printf 'reportes:%s\n' "$(openssl passwd -apr1 "$(cat /compartido/clave_reportes)")" > /etc/nginx/reportes.htpasswd
nginx -t 2>&1 | tail -n 1
systemctl enable nginx >/dev/null 2>&1; systemctl restart nginx
# 2. SSH: solo claves, sin root, grupo sshadmins
getent group sshadmins >/dev/null || groupadd sshadmins
id jhonc >/dev/null 2>&1 || useradd -m -s /bin/bash -G sshadmins jhonc
install -d -m 700 -o jhonc -g jhonc /home/jhonc/.ssh
cp /compartido/ssh/jhonc.pub /home/jhonc/.ssh/authorized_keys; chown jhonc:jhonc /home/jhonc/.ssh/authorized_keys; chmod 600 /home/jhonc/.ssh/authorized_keys
cp /lab/ssh/10-nazareno.conf /etc/ssh/sshd_config.d/; cp /lab/ssh/issue.net /etc/issue.net
install -d /run/sshd; ssh-keygen -A >/dev/null 2>&1; sshd -t
systemctl disable --now ssh.socket >/dev/null 2>&1 || true
systemctl enable ssh >/dev/null 2>&1; systemctl restart ssh
# 3. fail2ban (ssh.service en Ubuntu 24.04) y 4. firewall
install -d /etc/fail2ban/jail.d; cp /lab/ssh/nazareno-ssh.local /etc/fail2ban/jail.d/
systemctl enable fail2ban >/dev/null 2>&1; systemctl restart fail2ban
bash /lab/operacion/aplicar_ufw.sh >/dev/null
echo "web lista: $(systemctl is-active nginx) nginx, $(systemctl is-active ssh) ssh, $(systemctl is-active fail2ban) fail2ban"
