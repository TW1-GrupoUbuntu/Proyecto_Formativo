#!/usr/bin/env bash
# Reconstruye UN nodo desde cero con los scripts del repositorio:  bash scripts/reconstruir_nodo.sh <web|resolutor|ns2|mail|mail2|ns1|cliente|externo>
cd "$(dirname "$0")/.."
N=${1:?nodo}
x() { docker exec -w /lab "pf-$N" bash "scripts/$1" "${@:2}"; }
echo "Reconstruyendo $N ..."
docker compose -p pf up -d --force-recreate --no-deps "$N" >/dev/null 2>&1; sleep 12
case $N in
  web)       x instalar_web.sh; x instalar_operacion.sh;;
  resolutor) x instalar_resolutor.sh;;
  ns2)       x instalar_ns2.sh;;
  ns1)       x instalar_ns1.sh; docker exec -w /lab pf-ns1 bash scripts/publicar_dkim.sh; x instalar_operacion.sh;;
  mail)      x instalar_correo.sh nazareno.internal "ana luis marta" no; docker exec -w /lab pf-ns1 bash scripts/publicar_dkim.sh;;
  mail2)     x instalar_correo.sh aliada.internal "rosa pedro" no; docker exec -w /lab pf-ns1 bash scripts/publicar_dkim.sh;;
  cliente|externo) x preparar_cliente.sh;;
  *) echo "nodo desconocido"; exit 1;;
esac
echo "Nodo $N reconstruido. Comprobacion: bash scripts/verificar.sh"
