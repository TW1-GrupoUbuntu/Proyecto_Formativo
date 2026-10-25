# Manual de operación — Cooperativa Jesús Nazareno

Comandos probados en el laboratorio (anfitrión WSL, carpeta del repositorio). En producción cambian las direcciones, no el procedimiento.

## 1. Mapa rápido

| Nodo | IP | Servicio | Configuración principal |
|---|---|---|---|
| ns1 | 10.20.0.2 (+ 172.31.0.2 pública) | BIND9 primario: vistas, TSIG, DNSSEC, DNSControl | `/etc/bind/`, `/var/lib/bind/{interna,externa,dinamica,claves}` |
| ns2 | 10.20.0.3 | BIND9 secundario (TSIG) | `/etc/bind/named.conf`, zonas en `/var/cache/bind` |
| resolutor | 10.20.0.4 | Unbound: caché, DNSSEC, DoT, RPZ | `/etc/unbound/unbound.conf.d/nazareno-resolutor.conf`, `/etc/unbound/rpz.nazareno.internal` |
| web | 10.20.0.20 | Nginx HTTPS, sshd, fail2ban, ufw, restic, GoAccess | `/etc/nginx`, `/etc/ssh/sshd_config.d`, `/etc/fail2ban/jail.d` |
| mail / mail2 | 10.20.0.25 / .26 | Postfix, Dovecot, OpenDKIM, OpenDMARC | `/etc/postfix`, `/etc/dovecot`, `/etc/opendkim` |
| cliente / externo | 10.20.0.50 / 172.31.0.100 | PC de la cooperativa / “internet” (auditorías) | — |

## 2. Tareas frecuentes

- **Agregar un nombre interno** (ej. `impresora2`): editar `dns/zonas/db.nazareno.internal`, copiarlo a ns1 (`bash scripts/instalar_ns1.sh` o editar en `/var/lib/bind/interna/`), subir el serial con `bash scripts/subir_serial.sh nazareno.internal` y comprobar que ns2 lo tiene (`dig +short @10.20.0.3 impresora2.nazareno.internal`). Si el serial no sube, ns2 no copia nada.
- **Cambiar un registro público** (zona `nazareno.example`): seguir el procedimiento de la sección 7 (`scripts/cambio_dns.sh`); nunca editar el archivo de la zona pública a mano.
- **Registrar un equipo con IP cambiante** (DNS dinámico): `nsupdate -k /compartido/claves/dinamico.key` con `zone dinamica.nazareno.internal`; la clave solo permite registros A y TXT en esa zona.
- **Agregar o quitar un dominio de la lista de bloqueo (RPZ)**: editar `resolutor/rpz.nazareno.internal`, copiarlo al resolutor y `unbound-control reload`; probar con `dig @10.20.0.4 <dominio>` (NXDOMAIN).
- **Crear una cuenta de correo**: `useradd -m -s /usr/sbin/nologin <usuario>` en `mail`, asignar contraseña (`chpasswd`), agregar alias en `/etc/aliases` y `newaliases`; probar el envío por el 587 con `swaks`.
- **Dar acceso SSH a un técnico**: crearlo en el grupo `sshadmins`, instalar su clave pública en `~/.ssh/authorized_keys` (permisos 700/600) y comprobar que entra sin contraseña; las contraseñas están deshabilitadas.

## 3. Tareas periódicas

| Cuándo | Qué | Cómo |
|---|---|---|
| Cada hora (timer) | Monitoreo del DNS: seriales iguales, firmas DNSSEC con más de 3 días, tiempos de respuesta | `bash operacion/vigilar_dns.sh` en ns1 (`journalctl -t …`, `systemctl status nazareno-vigilar-dns.timer`) |
| Cada 5 min (timer) | Vigilancia del servidor web: servicios, HTTPS, certificado, disco, memoria, respaldo reciente | `bash operacion/vigilar_servidor.sh`; alertas con `journalctl -t nazareno-vigilancia` |
| Diario 02:00 (timer) | Respaldo cifrado con restic y retención 7/4/6 | `bash operacion/respaldar.sh` |
| Diario 03:00 (timer) | Reporte de visitas de GoAccess | `https://www.nazareno.internal/reportes/` (usuario `reportes`, clave en `compartido/clave_reportes`) |
| Semanal | Revisar fail2ban y actualizaciones | `fail2ban-client status sshd`; las actualizaciones de seguridad son automáticas (`unattended-upgrades`) |
| Mensual | Simulacro de restauración | `bash operacion/probar_restauracion.sh` en web (debe terminar con «Restaurado idéntico») |
| Antes de 14 días del vencimiento | Renovar el certificado de la CA interna del servicio | `bash scripts/crear_ca.sh` con certificados nuevos y `bash scripts/instalar_web.sh` |
| Anual | Rotar la clave DKIM con un selector nuevo y revisar el `dnssec-policy` | Ver sección 5 |

## 4. Ante un problema

| Síntoma | Primer comando | Causa frecuente | Solución |
|---|---|---|---|
| «No abre el sitio» | `curl -I https://www.nazareno.internal` | Nginx caído, certificado vencido, ufw | `systemctl status nginx`, `nginx -t`, `ufw status` |
| «Un nombre no resuelve» | `dig @10.20.0.4 nombre` luego `@10.20.0.2` | Serial sin subir, RPZ, secundario desactualizado | Subir el serial; `rndc retransfer` en ns2; revisar la RPZ |
| `SERVFAIL` para la zona interna | `dig @10.20.0.4 www.nazareno.internal` | Falta `domain-insecure` en Unbound | Verificar el archivo del resolutor y `unbound-control reload` |
| `named` no arranca | `named-checkconf` y `journalctl -u named` | Error de sintaxis o permisos en `/var/lib/bind` | Corregir y `chown -R bind:bind /var/lib/bind` |
| «No llegan correos» | `postqueue -p`, `tail /var/log/mail.log` | Cola atascada, MX sin resolver, DKIM | `dig MX`; `opendkim-testkey -d nazareno.internal -s mail -vvv` |
| `dkim=fail key not found` | `opendkim-testkey …` | OpenDKIM no usa el resolutor correcto | `Nameservers 10.20.0.4` en `/etc/opendkim.conf` |
| fail2ban no bloquea | `fail2ban-client get sshd journalmatch` | En Ubuntu 24.04 la unidad es `ssh.service` | `journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd` |
| Firmas DNSSEC por vencer | `dig +dnssec SOA nazareno.example` | BIND dejó de refirmar | `rndc signing -list nazareno.example in externa` y reiniciar `named` |

## 5. Recuperación ante desastres

1. **Un nodo falla:** `bash scripts/reconstruir_nodo.sh <nodo>` lo recrea desde cero con los scripts (web, resolutor, ns2, mail y mail2 se reconstruyen sin pérdida de configuración; los buzones se restauran desde restic).
2. **Todo el entorno:** `bash scripts/levantar.sh` y `bash scripts/verificar.sh` (unos 10 minutos).
3. **Claves y secretos:** las claves DNSSEC (`/var/lib/bind/claves`), TSIG y DKIM, la CA y la contraseña de restic **no están en el repositorio**: se guardan en el respaldo cifrado (que incluye `/etc/bind` y `/var/lib/bind`) y la contraseña del repositorio, fuera del servidor (sobre cerrado o gestor de contraseñas de la cooperativa).
4. **Orden:** red y resolutor → ns1 y ns2 → web → mail y mail2 → publicar DKIM → operación → verificar.
5. **Rotación de DKIM:** generar la clave con otro selector, publicarla en `ns1` sin quitar la anterior, cambiar el selector de firma en `mail`, y retirar la vieja una semana después.
6. **DS de DNSSEC:** si se recrea ns1 se generan claves nuevas; hay que publicar el nuevo DS (`compartido/DS-nazareno.example.txt`) en el registrador antes de que se vuelva a validar desde internet.

## 6. Contactos y responsables

| Rol | Responsable |
|---|---|
| Responsable de Sistemas de la cooperativa | Cargo entrevistado (ver brief) |
| Auxiliar de soporte | Auxiliar de Sistemas |
| Registrador y hosting actual | Proveedor actual del dominio real |
| Autores del proyecto | Equipo Ubuntu, Tecnología Web I (UPDS) |

## 7. Procedimiento de cambios de DNS y plan de migración

**Cambios (zona pública como código).**
1. *Rama y revisión:* crear una rama, editar `dnscontrol/dnsconfig.js` y abrir la solicitud de cambios; otra persona revisa el `git diff`.
2. *TTL:* con 24 horas de antelación a mover un servicio, bajar el TTL (`var TTL = 300`; o `--ttl 300` en el script) para que el cambio se propague rápido, y volver a 3600 después.
3. *Aplicar:* `bash scripts/cambio_dns.sh [--ttl N]` ejecuta `dnscontrol check`, `preview` (muestra el diff y bloquea si hay errores), `push`, instala la zona, recarga con `rndc` y verifica que el **serial subió** y que `delv` sigue validando.
4. *Reversa:* `git checkout -- dnscontrol/dnsconfig.js` (o `git revert`) y repetir el paso 3.
5. *Interno:* los cambios en las zonas internas se hacen en `dns/zonas/` y se aplican con `subir_serial.sh`; ns2 los recibe por NOTIFY y transferencia con TSIG.

**Migración a DNS gestionado o híbrido.** `dnscontrol/dnsconfig_hibrido.js` publica la misma zona en dos proveedores (BIND propio y un DNS gestionado). Fases: (1) inventario y bajar TTL; (2) publicar la zona en el proveedor gestionado con `preview` y comparar respuestas con `dig @<ns del proveedor>`; (3) cambiar los NS en el registrador (modelo híbrido: ns propios + gestionados), (4) monitorear una semana y (5) decidir si los servidores propios quedan como respaldo o solo para la zona interna. La zona **interna** nunca se publica fuera. Detalle de costos y riesgos en `docs/PLAN_ADOPCION.md`.
