#!/usr/bin/env python3
"""
ARREIO — a MÃO da Linguagem-Bolha (spike 1)

Fluxo:
1. ATO FUNDADOR: cria as três bolhas-licença (uso-restrito, uso-livre, uso-privado)
   — bolhas-primeiras, escritas à mão, sem depender de outra licença.
2. IMPORTAR: recebe uma anotação (texto), calcula o hash, guarda os bytes no
   depósito e gera o manifesto referenciando conteúdo e licença por hash.

Conteúdo (imutável)  -> deposito/objetos/<hash>
Manifesto (evolutivo) -> bolhas/*.bolha  (versionado com git; jj vem depois)

Sintaxe do manifesto: provisória (enxuta). A definitiva nasce com o juiz (Lean).
"""

import hashlib
import os

RAIZ = os.path.dirname(os.path.abspath(__file__))
DEPOSITO = os.path.join(RAIZ, "deposito", "objetos")
BOLHAS = os.path.join(RAIZ, "bolhas")


def hash_bytes(dados: bytes) -> str:
    return hashlib.sha256(dados).hexdigest()


def gravar_objeto(dados: bytes) -> str:
    """Grava bytes no depósito por conteúdo e devolve o hash."""
    h = hash_bytes(dados)
    caminho = os.path.join(DEPOSITO, h)
    if not os.path.exists(caminho):
        with open(caminho, "wb") as f:
            f.write(dados)
    return h


def gravar_manifesto(nome: str, texto: str) -> str:
    """Grava o manifesto (texto) em bolhas/ e devolve o hash da bolha."""
    with open(os.path.join(BOLHAS, nome + ".bolha"), "w", encoding="utf-8") as f:
        f.write(texto)
    return hash_bytes(texto.encode("utf-8"))


def criar_licencas():
    """Ato fundador: as três bolhas-licença."""
    licencas = {
        "uso-restrito": "tipo: licenca\nnome: uso-restrito\nteto: hash\nescopo: restrito\n",
        "uso-livre":   "tipo: licenca\nnome: uso-livre\nteto: hash,ref\nescopo: livre\n",
        "uso-privado": "tipo: licenca\nnome: uso-privado\nteto: hash,ref\nescopo: privado\n",
    }
    hashes = {}
    for nome, manifesto in licencas.items():
        hashes[nome] = gravar_manifesto(nome, manifesto)
    return hashes


def importar_anotacao(texto: str, licenca_hash: str):
    """Importa uma anotação: conteúdo por hash + manifesto."""
    h_texto = gravar_objeto(texto.encode("utf-8"))
    manifesto = f"tipo: anotacao\nconteudo: {h_texto}\nlicenca: {licenca_hash}\n"
    h_bolha = gravar_manifesto("anotacao-" + h_texto[:12], manifesto)
    return h_texto, h_bolha, manifesto


def main():
    os.makedirs(DEPOSITO, exist_ok=True)
    os.makedirs(BOLHAS, exist_ok=True)

    print("=== ATO FUNDADOR (as três bolhas-licença) ===")
    lic = criar_licencas()
    for nome, h in lic.items():
        print(f"  {nome:14s} bolha: {h}")

    print("\n=== IMPORTAR ANOTAÇÃO ===")
    texto = ("Primeira anotação da Linguagem-Bolha — importada pela mão, "
             "marcada como uso-privado.")
    h_texto, h_bolha, manifesto = importar_anotacao(texto, lic["uso-privado"])
    print(f"  conteúdo (hash): {h_texto}")
    print(f"  bolha    (hash): {h_bolha}")
    print("  manifesto:")
    for linha in manifesto.rstrip().split("\n"):
        print(f"    {linha}")

    print("\n=== ESTRUTURA GERADA ===")
    for raiz, dirs, arquivos in os.walk(RAIZ):
        rel = os.path.relpath(raiz, RAIZ)
        if rel == ".":
            continue
        if ".git" in rel:
            continue
        print(f"  {rel}/")
        for a in sorted(arquivos):
            print(f"    {a}")


if __name__ == "__main__":
    main()
