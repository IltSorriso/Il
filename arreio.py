#!/usr/bin/env python3
"""
ARREIO — a MÃO da Linguagem-Bolha (spike 1)

Modelo simplificado (2026-09-11):
- Sem "ato fundador" de licenças inventadas. Uma bolha-licença aponta para um
  CATÁLOGO REAL (Creative Commons para conteúdo, SPDX para programa) — o sistema
  não inventa termos jurídicos.
- O estado padrão de criação é `reservado`: a ausência deliberada de licença.
  Não é uma licença, é o ponto de partida. Liberar = trocar por um hash de licença.
- Endereçamento SEMPRE por hash (o eixo "teto" hash/ref morreu).

Fluxo:
  criar_bolha_licenca(catalogo, nome)  -> manifesto da licença (referência de catálogo)
  importar_anotacao(texto, licenca)    -> conteúdo por hash + manifesto da anotação

Conteúdo (imutável)  -> deposito/objetos/<hash>
Manifesto (evolutivo) -> bolhas/*.bolha  (versionado com git)

Sintaxe do manifesto: provisória (enxuta). A definitiva nasce com o juiz (Lean).
"""

import hashlib
import os

RAIZ = os.path.dirname(os.path.abspath(__file__))
DEPOSITO = os.path.join(RAIZ, "deposito", "objetos")
BOLHAS = os.path.join(RAIZ, "bolhas")

RESERVADO = "reservado"  # estado: nenhum direito concedido (padrão de criação)


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


def criar_bolha_licenca(catalogo: str, nome: str) -> str:
    """Bolha-licença: aponta para um catálogo REAL (CC / SPDX), não inventa termos.

    catalogo: "CC" (conteúdo) ou "SPDX" (programa)
    nome:     identificador no catálogo, ex.: "CC0-1.0", "AGPL-3.0"
    """
    manifesto = f"tipo: licenca\ncatalogo: {catalogo}\nnome: {nome}\n"
    return gravar_manifesto(f"licenca-{catalogo}-{nome}", manifesto)


def importar_anotacao(texto: str, licenca: str = RESERVADO):
    """Importa uma anotação: conteúdo por hash + manifesto.

    licenca: `reservado` (padrão) OU o hash de uma bolha-licença.
    """
    h_texto = gravar_objeto(texto.encode("utf-8"))
    manifesto = f"tipo: anotacao\nconteudo: {h_texto}\nlicenca: {licenca}\n"
    h_bolha = gravar_manifesto("anotacao-" + h_texto[:12], manifesto)
    return h_texto, h_bolha, manifesto


def main():
    os.makedirs(DEPOSITO, exist_ok=True)
    os.makedirs(BOLHAS, exist_ok=True)

    print("=== BOLHA-LICENÇA (catálogo real) ===")
    h_cc0 = criar_bolha_licenca("CC", "CC0-1.0")
    print(f"  licenca-CC-CC0-1.0   bolha: {h_cc0}")

    print("\n=== IMPORTAR ANOTAÇÃO (padrão: reservado) ===")
    texto = ("Primeira anotação da Linguagem-Bolha — importada pela mão, "
             "marcada como reservado.")
    h_texto, h_bolha, manifesto = importar_anotacao(texto, RESERVADO)
    print(f"  conteúdo (hash): {h_texto}")
    print(f"  bolha    (hash): {h_bolha}")
    print("  manifesto:")
    for linha in manifesto.rstrip().split("\n"):
        print(f"    {linha}")

    print("\n=== ESTRUTURA GERADA ===")
    for raiz, dirs, arquivos in os.walk(RAIZ):
        rel = os.path.relpath(raiz, RAIZ)
        if rel == "." or ".git" in rel:
            continue
        print(f"  {rel}/")
        for a in sorted(arquivos):
            print(f"    {a}")


if __name__ == "__main__":
    main()
