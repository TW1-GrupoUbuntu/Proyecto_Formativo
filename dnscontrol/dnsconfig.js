// dnsconfig.js — La zona PÚBLICA de la cooperativa escrita como código (DNSControl).
// Flujo profesional: editar → dnscontrol check → dnscontrol preview (ver el diff) → dnscontrol push (aplicar).
// Aquí el proveedor es BIND (genera zonas/nazareno.example.zone). Cambiando creds.json a Cloudflare, el MISMO
// archivo publicaría la zona real en internet. ".example" está reservado para documentación (RFC 2606).

var REG_NINGUNO = NewRegistrar("none");
var DNS_BIND    = NewDnsProvider("bind");

var IP_WEB  = "203.0.113.20";   // 203.0.113.0/24: rango reservado para documentación (RFC 5737)
var IP_MAIL = "203.0.113.25";
var TTL     = 3600;          // el procedimiento de cambios baja este valor antes de mover un servicio (ver el manual)

D("nazareno.example", REG_NINGUNO, DnsProvider(DNS_BIND),
    DefaultTTL(TTL),
    // SOA: primario, correo del responsable (¡con punto final!), refresh, retry, expire, TTL negativo
    SOA("@", "ns1.nazareno.example.", "ti.nazareno.example.", 3600, 600, 1209600, 300),
    NAMESERVER("ns1.nazareno.example."),
    NAMESERVER("ns2.nazareno.example."),
    A("ns1", "203.0.113.2"),
    A("ns2", "198.51.100.3"),                 // el secundario en OTRA red (redundancia real)

    A("@",   IP_WEB),
    A("www", IP_WEB),
    CNAME("portal", "www"),

    MX("@", 10, "mail"),
    A("mail", IP_MAIL),
    SPF_BUILDER({ label: "@", parts: ["v=spf1", "mx", "-all"] }),
    DMARC_BUILDER({ policy: "quarantine", rua: ["mailto:dmarc@nazareno.example"] }),

    CAA_BUILDER({ label: "@", iodef: "mailto:ti@nazareno.example", issue: ["letsencrypt.org"], issuewild: ["none"] }),
    TXT("@", "v=nazareno-verificacion-ejemplo")
);
