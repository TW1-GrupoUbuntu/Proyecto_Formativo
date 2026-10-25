#!/usr/bin/env python3
"""Analiza las cabeceras de un correo recibido (lee el mensaje de un buzon por IMAPS) y explica cada hallazgo.
Uso: python3 analizar_cabeceras.py <servidor> <usuario> <asunto>
Muestra: recorrido (Received, de abajo hacia arriba), TLS de cada salto, firma DKIM, SPF, DKIM, DMARC y el puntaje antispam."""
import email, imaplib, re, ssl, sys
from email import policy

servidor, usuario, asunto = sys.argv[1:4]
clave = open("/compartido/clave_buzones").read().strip()
m = imaplib.IMAP4_SSL(servidor, 993, ssl_context=ssl.create_default_context(cafile="/compartido/ca/ca.crt"))
m.login(usuario, clave)
m.select("INBOX", readonly=True)
_, ids = m.search(None, "ALL")
elegido = None
for i in ids[0].split():
    _, d = m.fetch(i, "(BODY.PEEK[])")
    msg = email.message_from_bytes(d[0][1], policy=policy.default)
    if asunto in str(msg["Subject"]):
        elegido = msg
if elegido is None:
    sys.exit("no se encontro el mensaje")
msg = elegido
plano = lambda v: " ".join(str(v).split())

print(f"Mensaje: {msg['Subject']}  |  De: {msg['From']}  |  Para: {msg['To']}  |  Fecha: {msg['Date']}")
print(f"Message-ID: {msg['Message-ID']}\n")

print("1) RECORRIDO (Received, del origen al destino)")
for n, r in enumerate(reversed(msg.get_all("Received", [])), 1):
    r = plano(r)
    de = re.search(r"from (\S+)(?: \(([^)]*)\))?", r)
    por = re.search(r"by (\S+)", r)
    tls = re.search(r"using (TLSv[\d.]+) with cipher (\S+)", r)
    prot = re.search(r"with (E?SMTPS?A?|LMTP)", r)
    print(f"  salto {n}: de {de.group(1) if de else '?'}{' ' + de.group(2).split(' ')[-1] if de and de.group(2) else ''} -> {por.group(1) if por else '?'}"
          f"  protocolo={prot.group(1) if prot else '?'}  cifrado={(tls.group(1) + ' ' + tls.group(2)) if tls else 'sin TLS (salto local)'}")

print("\n2) FIRMA DKIM")
sig = msg["DKIM-Signature"]
if sig:
    t = dict(p.strip().split("=", 1) for p in plano(sig).split(";") if "=" in p)
    print(f"  d={t.get('d')}  s={t.get('s')}  a={t.get('a')}  c={t.get('c')}  cabeceras firmadas h={t.get('h')}")
else:
    print("  el mensaje no trae firma DKIM")

print("\n3) RESULTADOS DE AUTENTICACION (los agrega el servidor que RECIBE)")
for ar in msg.get_all("Authentication-Results", []):
    print("  Authentication-Results:", plano(ar)[:230])
for sp in msg.get_all("Received-SPF", []):
    print("  Received-SPF:", plano(sp)[:230])

print("\n4) PUNTAJE ANTISPAM (Rspamd)")
hay = False
for k in ("X-Spamd-Result", "X-Spam-Status", "X-Spam-Flag", "X-Spam", "X-Spamd-Bar"):
    if msg[k]:
        hay = True
        print(f"  {k}: {plano(msg[k])[:230]}")
if not hay:
    print("  (este servidor no ejecuta Rspamd: el filtrado antispam esta en el servidor de horizonte.internal)")
m.logout()
