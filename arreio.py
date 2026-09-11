#!/usr/bin/env python3
"""
ARREIO — a MÃO da Linguagem-Bolha.

Modelo simplificado + depósito unificado (2026-09-11):
- UM depósito por conteúdo (hash sha256 → texto do objeto) guarda TUDO:
  os objetos de conteúdo E os manifestos (uma bolha também é conteúdo endereçado).
  Por isso não há "coleção" à parte — achar uma bolha é achar o objeto por hash.
- Licença: `reservado` (ausência deliberada de direito) OU o hash de uma
  bolha-licença que aponta para um catálogo REAL (CC / SPDX).
- Endereçamento SEMPRE por hash.

Conteúdo (imutável)  -> deposito/objetos/<hash>
Manifestos (revisáveis) -> bolhas/*.bolha  (VISÃO humana; o endereço é o depósito)
"""

import hashlib
import os

RAIZ = os.path.dirname(os.path.abspath(__file__))
DEPOSITO = os.path.join(RAIZ, "deposito", "objetos")
BOLHAS = os.path.join(RAIZ, "bolhas")

RESERVADO = "reservado"


def hash_bytes(dados: bytes) -> str:
    return hashlib.sha256(dados).hexdigest()


def gravar_objeto(dados: bytes) -> str:
    """Grava bytes no depósito por conteúdo e devolve o hash (o endereço)."""
    h = hash_bytes(dados)
    caminho = os.path.join(DEPOSITO, h)
    if not os.path.exists(caminho):
        with open(caminho, "wb") as f:
            f.write(dados)
    return h


def gravar_manifesto(nome: str, texto: str) -> str:
    """Grava o manifesto na VISÃO humana (bolhas/) e no depósito (endereçado).

    O manifesto é, ele próprio, conteúdo endereçado — logo vai para o depósito
    sob o seu hash. O arquivo em bolhas/ é só uma janela com nome legível.
    """
    with open(os.path.join(BOLHAS, nome + ".bolha"), "w", encoding="utf-8") as f:
        f.write(texto)
    return gravar_objeto(texto.encode("utf-8"))


def criar_bolha_licenca(catalogo: str, nome: str) -> str:
    """Bolha-licença: aponta para um catálogo REAL. Devolve o hash (endereço)."""
    manifesto = f"tipo: licenca\ncatalogo: {catalogo}\nnome: {nome}\n"
    return gravar_manifesto(f"licenca-{catalogo}-{nome}", manifesto)


def importar_anotacao(texto: str, licenca: str = RESERVADO):
    """Importa uma anotação: conteúdo por hash + manifesto (também por hash)."""
    h_texto = gravar_objeto(texto.encode("utf-8"))
    manifesto = f"tipo: anotacao\nconteudo: {h_texto}\nlicenca: {licenca}\n"
    h_bolha = gravar_manifesto("anotacao-" + h_texto[:12], manifesto)
    return h_texto, h_bolha, manifesto


def main():
    os.makedirs(DEPOSITO, exist_ok=True)
    os.makedirs(BOLHAS, exist_ok=True)

    print("=== BOLHA-LICENÇA (catálogo real) ===")
    h_cc0 = criar_bolha_licenca("CC", "CC0-1.0")
    print(f"  licenca CC0-1.0        endereço: {h_cc0}")

    print("\n=== IMPORTAR ANOTAÇÃO (padrão: reservado) ===")
    texto = ("Primeira anotação da Linguagem-Bolha — importada pela mão, "
             "marcada como reservado.")
    h_texto, h_bolha, manifesto = importar_anotacao(texto, RESERVADO)
    print(f"  conteúdo               endereço: {h_texto}")
    print(f"  manifesto da anotação  endereço: {h_bolha}")
    print("  manifesto:")
    for linha in manifesto.rstrip().split("\n"):
        print(f"    {linha}")

    print("\n=== DEPÓSITO (tudo endereçado por hash) ===")
    for raiz, dirs, arquivos in os.walk(RAIZ):
        rel = os.path.relpath(raiz, RAIZ)
        if rel == "." or ".git" in rel:
            continue
        print(f"  {rel}/")
        for a in sorted(arquivos):
            print(f"    {a}")


if __name__ == "__main__":
    main()
