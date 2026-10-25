// dnsconfig_hibrido.js — Plan de migracion a DNS hibrido: la MISMA zona publica en dos proveedores (BIND propio + DNS gestionado).
// No se ejecuta contra internet en el laboratorio: "dnscontrol check --config dnsconfig_hibrido.js" valida la sintaxis y,
// con las credenciales reales del proveedor (variable de entorno, nunca en el repositorio), "preview" mostraria el diff.
var REG_NINGUNO = NewRegistrar("none");
var DNS_BIND    = NewDnsProvider("bind");
var DNS_GESTION = NewDnsProvider("gestionado");        // en creds_hibrido.json: TYPE CLOUDFLAREAPI con el token en $CF_API_TOKEN

var IP_WEB = "203.0.113.20"; var IP_MAIL = "203.0.113.25";
D("nazareno.example", REG_NINGUNO, DnsProvider(DNS_BIND), DnsProvider(DNS_GESTION),
    DefaultTTL(300),                                   // TTL bajo durante la migracion
    SOA("@", "ns1.nazareno.example.", "ti.nazareno.example.", 3600, 600, 1209600, 300),
    NAMESERVER("ns1.nazareno.example."), NAMESERVER("ns2.nazareno.example."),
    A("ns1", "203.0.113.2"), A("ns2", "198.51.100.3"),
    A("@", IP_WEB), A("www", IP_WEB), CNAME("portal", "www"),
    MX("@", 10, "mail"), A("mail", IP_MAIL),
    SPF_BUILDER({ label: "@", parts: ["v=spf1", "mx", "-all"] }),
    DMARC_BUILDER({ policy: "quarantine", rua: ["mailto:dmarc@nazareno.example"] }),
    CAA_BUILDER({ label: "@", iodef: "mailto:ti@nazareno.example", issue: ["letsencrypt.org"], issuewild: ["none"] })
);
