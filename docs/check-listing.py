#!/usr/bin/env python3
"""Comprueba que los textos de la ficha caben en los límites de Apple.

Se pasan de largo con facilidad —sobre todo el subtítulo, que son 30
caracteres— y App Store Connect los rechaza al pegar, no al guardar.
"""
import re, sys, pathlib

LIMITES = {"Nombre": 30, "Subtítulo": 30, "Texto promocional": 170,
           "Descripción": 4000, "Palabras clave": 100}

texto = pathlib.Path(__file__).with_name("app-store-listing.md").read_text(encoding="utf-8")
fallos = 0
for m in re.finditer(r"^## (\w+)", texto, re.M):
    app = m.group(1)
    trozo = texto[m.end():]
    siguiente = re.search(r"^## ", trozo, re.M)
    if siguiente:
        trozo = trozo[:siguiente.start()]
    encontrados = []
    for campo, tope in LIMITES.items():
        # texto en línea:  **Campo** (30): `valor`
        inline = re.search(rf"\*\*{campo}\*\*[^:]*:\s*`([^`]+)`", trozo)
        # o en bloque de código bajo  **Campo** (n):
        bloque = re.search(rf"\*\*{campo}\*\*[^:]*:\s*\n```\n(.*?)```", trozo, re.S)
        valor = (inline.group(1) if inline else bloque.group(1).strip() if bloque else None)
        if valor is None:
            continue
        n = len(valor)
        ok = n <= tope
        fallos += 0 if ok else 1
        encontrados.append(f"  {'✓' if ok else '✗'} {campo:<20} {n:>5} / {tope}")

    # las secciones que no son una app —como la de instrucciones— no traen
    # ningún campo: no tiene sentido listarlas
    if encontrados:
        print(f"\n{app}")
        print("\n".join(encontrados))

sys.exit(1 if fallos else 0)
