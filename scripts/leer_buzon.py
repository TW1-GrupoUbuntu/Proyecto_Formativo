#!/usr/bin/env python3
"""Cliente IMAP sobre TLS (993) para las pruebas: valida el certificado con la CA del laboratorio.
Uso: python3 leer_buzon.py <servidor> <usuario> [carpeta] [listar|cabeceras|completo] [asunto-a-buscar]
La contrasena se lee de /compartido/clave_buzones (no se imprime)."""
import imaplib, ssl, sys, email
from email import policy

servidor, usuario = sys.argv[1], sys.argv[2]
carpeta = sys.argv[3] if len(sys.argv) > 3 else "INBOX"
modo = sys.argv[4] if len(sys.argv) > 4 else "listar"
buscar = sys.argv[5] if len(sys.argv) > 5 else None
clave = open("/compartido/clave_buzones").read().strip()
ctx = ssl.create_default_context(cafile="/compartido/ca/ca.crt")
m = imaplib.IMAP4_SSL(servidor, 993, ssl_context=ctx)
print(f"# Conexion IMAPS con {servidor}:993 - {m.sock.version()} - {m.sock.cipher()[0]} - certificado valido: {m.sock.getpeercert()['subject'][-1][0][1]}")
m.login(usuario, clave)
tipo, datos = m.select(carpeta, readonly=True)
print(f"# Carpeta {carpeta}: {datos[0].decode()} mensajes")
tipo, ids = m.search(None, "ALL")
ids = ids[0].split()
sel = []
for i in ids:
    _, d = m.fetch(i, "(BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])")
    h = email.message_from_bytes(d[0][1], policy=policy.default)
    if buscar is None or buscar in str(h["Subject"]):
        sel.append(i)
        if modo == "listar":
            print(f"{i.decode():>3} | {str(h['From'])[:34]:<34} | {str(h['Subject'])[:60]}")
if modo in ("cabeceras", "completo") and sel:
    _, d = m.fetch(sel[-1], "(BODY.PEEK[])")
    msg = email.message_from_bytes(d[0][1], policy=policy.default)
    if modo == "completo":
        print(msg.as_string())
    else:
        for k, v in msg.items():
            print(f"{k}: {' '.join(str(v).split())}")
m.logout()
