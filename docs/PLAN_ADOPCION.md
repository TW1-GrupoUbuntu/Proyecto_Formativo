# Plan de adopción — Cooperativa Jesús Nazareno

Documento para la cooperativa: qué se propone, cuánto cuesta, qué riesgos hay y cómo se migra sin interrumpir el servicio. **Las cifras son estimaciones de orden de magnitud con supuestos explícitos (tipo de cambio oficial 6,96 Bs por USD); deben validarse con cotizaciones antes de decidir.** Origen del diagnóstico: consultas DNS públicas del dominio real (radiografía de 6 de 12); no se tocó ningún sistema de la cooperativa.

## 1. Situación actual (de datos públicos y del brief)

El sitio y el correo están en un proveedor externo que también administra el DNS; el dominio no publica DMARC, CAA ni DNSSEC, el SPF termina en `~all` y la delegación declara servidores distintos en el padre y en la zona. La cooperativa no tiene visibilidad ni copia propia de su configuración DNS, y los correos a socios terminan a menudo en spam.

## 2. Alternativas

| Opción | Qué es | Ventajas | Desventajas |
|---|---|---|---|
| A. Seguir como está | Todo con el proveedor actual | Costo cero adicional | Sin control, sin DMARC/DNSSEC, dependencia de un solo proveedor |
| **B. Híbrida (recomendada)** | Zona pública como código en Git, publicada en un DNS gestionado y en servidores propios; zona interna y resolutor propios | Control y reversa; DNS público muy disponible; la zona interna nunca sale | Requiere una persona que opere Git y DNSControl |
| C. Todo propio | Servidores DNS, web y correo propios en la cooperativa | Máximo control | Más costo operativo, enlace y energía propios, más riesgo |

## 3. Costos estimados (por año, opción B)

| Concepto | Supuesto | USD | Bs |
|---|---|---|---|
| Servidor secundario (VPS pequeño, otra red) | 1 equipo de ~12 USD/mes | 144 | 1.002 |
| DNS gestionado | Plan gratuito de un proveedor (cuota suficiente para una zona) | 0 | 0 |
| Dominio | Renovación anual (sin cambio) | ~15 | ~104 |
| Respaldo externo | ~100 GB de almacenamiento, ~5 USD/mes | 60 | 418 |
| Certificados | Autoridad pública gratuita (ACME) | 0 | 0 |
| Implementación inicial (única vez) | ~60 h de un técnico a ~10 USD/h | 600 | 4.176 |
| Capacitación (única vez) | 2 talleres de 3 h, 4 personas | 150 | 1.044 |
| Operación mensual | ~4 h/mes de un técnico propio o contratado | 480 | 3.341 |
| **Total primer año** | | **~1.449** | **~10.085** |
| **Total años siguientes** | sin los costos únicos | **~699** | **~4.865** |

Comparación: la opción C sumaría un servidor, enlace redundante y energía propios (orden de 2 a 3 veces el costo de B); la opción A no tiene costo adicional pero mantiene el riesgo de un correo que sigue llegando a spam y de una caída sin plan de recuperación.

## 4. Riesgos y mitigación

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Cortar el correo al cambiar el MX o los NS | Media | Alto | Bajar el TTL 24 h antes, ventana de baja actividad, reversa con el MX anterior y respaldo previo 30 días |
| DMARC `reject` demasiado pronto bloquea correo legítimo | Media | Alto | Empezar en `p=none`, leer informes 4 semanas, subir a `quarantine` y luego `reject` |
| DNSSEC mal publicado (DS incorrecto) deja el dominio sin resolver | Baja | Muy alto | Publicar el DS solo tras validar con `delv`; plan de retirada del DS |
| Pérdida de claves (DNSSEC, DKIM, restic) | Baja | Alto | Respaldo cifrado y copia de las contraseñas fuera del servidor; simulacro mensual de restauración |
| Dependencia de una persona | Media | Medio | Manual de operación, scripts idempotentes y capacitación de dos personas |
| Costos mayores a los estimados | Media | Bajo | Validar cotizaciones; empezar por la fase 1–3 (sin costo recurrente) |

## 5. Plan de migración por fases

| Fase | Semana | Actividades | Criterio de salida |
|---|---|---|---|
| 1. Diagnóstico | 1 | Inventario de registros, quién administra el registrador, copia de la zona actual | Lista firmada |
| 2. Zona como código | 2 | Importar la zona a `dnsconfig.js`, `check` y `preview`; corregir NS, SPF `-all`, CAA | `preview` sin diferencias inesperadas |
| 3. Correo | 3 | Publicar DKIM y DMARC `p=none`; verificar `dkim=pass` en un buzón de prueba | Mensajes de prueba autenticados |
| 4. Híbrido | 4 | Publicar la zona en el DNS gestionado, agregar el secundario propio, cambiar NS con TTL bajo | Respuestas iguales en todos los NS |
| 5. DNSSEC | 5 | Firmar, validar con `delv` y publicar el DS en el registrador | Cadena validada desde internet |
| 6. Endurecer | 6–12 | DMARC a `quarantine` y luego `reject`; cerrar cuentas y puertos innecesarios | Menos de 1 % de fallos legítimos |
| 7. Operar | continuo | Timers de vigilancia, respaldos y simulacro mensual | Reportes sin alertas |

## 6. Indicadores de éxito

- Radiografía DNS del dominio de 6 a por lo menos 11 de 12.
- Correos de la cooperativa con `dkim=pass`, `spf=pass` y `dmarc=pass` en el destino y menos quejas de spam.
- Tiempo de recuperación de un nodo menor a 15 minutos con `reconstruir_nodo.sh`; restauración de respaldo probada cada mes.

## 7. Adopción y responsables

Responsable de Sistemas (opera), auxiliar de soporte (suplente) y Gerencia (aprueba el cambio). Capacitación en `dig`, DNSControl, lectura de informes DMARC y restauración. Revisión del plan a los 3 y 12 meses.
