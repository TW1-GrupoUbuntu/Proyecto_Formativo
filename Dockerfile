# Ubuntu 24.04 con systemd y TODO el software del proyecto (DNS, resolutor, web, SSH, correo y operación).
# Los nueve nodos usan esta imagen; cada uno instala solo su rol con los scripts de scripts/instalar_*.sh.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=America/La_Paz
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d \
 && echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections \
 && apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus tzdata ca-certificates iproute2 iputils-ping curl nano less procps rsyslog openssl sudo python3 \
      bind9 bind9-utils bind9-dnsutils knot-dnsutils unbound unbound-anchor dns-root-data tcpdump netcat-openbsd nmap \
      nginx openssh-server openssh-client fail2ban nftables iptables ufw unattended-upgrades restic goaccess \
      postfix postfix-policyd-spf-python opendkim opendkim-tools opendmarc \
      dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sieve \
      swaks bsd-mailx libnet-ssleay-perl libio-socket-ssl-perl libauthen-sasl-perl libnet-dns-perl \
 && arch="$(dpkg --print-architecture)" && curl -fSL --retry 3 --connect-timeout 15 \
      "https://github.com/DNSControl/dnscontrol/releases/download/v5.2.0/dnscontrol-5.2.0.${arch}.deb" -o /tmp/dc.deb \
 && dpkg -i /tmp/dc.deb && rm /tmp/dc.deb \
 && rm -f /usr/sbin/policy-rc.d \
 && find /etc/systemd/system /lib/systemd/system -path '*.wants/*' \
      \( -name '*getty*' -o -name 'systemd-logind*' -o -name 'systemd-resolved*' \) -delete || true \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
# Ningun servicio arranca solo: cada rol activa los suyos (si no, named y unbound se pelean por el puerto 53)
RUN systemctl disable named bind9 unbound nginx ssh ssh.socket fail2ban postfix dovecot opendkim opendmarc >/dev/null 2>&1 || true
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
