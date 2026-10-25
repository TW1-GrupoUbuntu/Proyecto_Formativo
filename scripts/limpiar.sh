#!/usr/bin/env bash
# Elimina contenedores, redes y volumenes del proyecto (no toca nada mas).
cd "$(dirname "$0")/.." && docker compose -p pf down -v --remove-orphans
