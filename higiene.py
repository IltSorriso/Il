#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Higiene da prosa — o juiz da FORMA dos documentos.

O juiz em Lean prova a forma das BOLHAS. Este prova a forma dos DOCUMENTOS.
Ele nao julga o conteudo — isso e conversa humana, e nao se prova.
Julga o que da para decidir:

  1. todo documento .md declara o seu TIPO e a sua AUTORIDADE num cabecalho;
  2. documento que AFIRMA O PRESENTE (capa, apontador, contrato) nao usa TERMO
     MORTO. O diario (conversa) pode narrar o que morreu, porque e datado;
  3. todo caminho apontado entre crases EXISTE de fato — renomear um arquivo
     sem atualizar a prosa deixa de ser silencio e vira build vermelho;
  4. SO a capa pode morar na raiz. O resto vive em pasta propria;
  5. o mapa de onde a verdade mora e GERADO a cada execucao, nunca escrito a
     mao e nunca versionado — artefato gerado que se versiona e sombra de
     fabrica (e entra em conflito entre os dois repositorios).

Uso:
    python3 higiene.py           # verifica; sai != 0 se algo falhar
    python3 higiene.py --mapa    # imprime o mapa gerado, depois verifica
"""

import io
import os
import re
import sys

RAIZ = os.path.dirname(os.path.abspath(__file__))
PULAR = {".git", "node_modules", "deposito", "bolhas"}

# tipo -> (autoridade exigida, afirma o presente?, pode morar na raiz?)
NATUREZAS = {
    "capa":      ("pitch",         True,  True),
    "apontador": ("gerado",        True,  False),
    "contrato":  ("retrospectiva", True,  False),
    "conversa":  ("historico",     False, False),
}

# Termos que o CODIGO nao usa mais. Lista curta e datada de proposito: ela so
# cresce, e cada linha aqui e uma mentira que a prosa nao pode mais contar.
# (lista a mao, sim — mas conferida. Prosa sem conferencia e o que apodreceu.)
TERMOS_MORTOS = [
    ("uso-restrito", "2026-09-11", "virou `reservado` ou hash de bolha-licenca"),
    ("uso-livre",    "2026-09-11", "idem"),
    ("uso-privado",  "2026-09-11", "idem"),
    ("sem-registro", "2026-09-11", "idem"),
    ("LICENCAS.md",  "2026-09-11", "documento-sombra, removido"),
]

CABECALHO = re.compile(r"<!--\s*doc:\s*([^>]*?)-->")
CAMPO = re.compile(r"(\w+)\s*=\s*(\S+)")
CRASE = re.compile(r"`([^`\n]+)`")
EXTENSOES = (".lean", ".py", ".md", ".yml", ".yaml", ".bolha", ".txt", ".json")


def documentos():
    """Todo .md sob a raiz, menos o que precisa ser pulado."""
    achados = []
    for base, dirs, arquivos in os.walk(RAIZ):
        dirs[:] = [d for d in dirs if d not in PULAR and not d.startswith(".")]
        for a in sorted(arquivos):
            if a.endswith(".md"):
                achados.append(os.path.relpath(os.path.join(base, a), RAIZ))
    return sorted(achados)


def ler_cabecalho(caminho):
    """Le o cabecalho nas primeiras linhas. Devolve dict ou None."""
    try:
        with io.open(caminho, encoding="utf-8") as f:
            for _ in range(10):
                linha = f.readline()
                if not linha:
                    break
                m = CABECALHO.search(linha)
                if m:
                    return dict(CAMPO.findall(m.group(1)))
    except OSError:
        return None
    return None


def caminhos_citados(caminho):
    """Caminhos entre crases com separador de pasta e extensao conhecida."""
    try:
        texto = io.open(caminho, encoding="utf-8").read()
    except OSError:
        return []
    achados = []
    for c in CRASE.findall(texto):
        c = c.strip()
        if "/" not in c or "<" in c or "*" in c:
            continue
        if not c.endswith(EXTENSOES):
            continue
        achados.append(c)
    return sorted(set(achados))


def verificar(mostrar_mapa):
    falhas = []
    docs = documentos()
    linhas_mapa = []

    for rel in docs:
        cab = ler_cabecalho(os.path.join(RAIZ, rel))

        if not cab:
            falhas.append(f"{rel}: sem cabecalho `<!-- doc: tipo=... autoridade=... -->`")
            continue

        tipo = cab.get("tipo")
        autoridade = cab.get("autoridade")

        if tipo not in NATUREZAS:
            falhas.append(f"{rel}: tipo desconhecido {tipo!r} (validos: {', '.join(NATUREZAS)})")
            continue

        esperada, afirma_presente, na_raiz = NATUREZAS[tipo]
        if autoridade != esperada:
            falhas.append(f"{rel}: tipo={tipo} exige autoridade={esperada}, veio {autoridade!r}")

        if "/" not in rel and not na_raiz:
            falhas.append(f"{rel}: tipo={tipo} nao mora na raiz — a raiz e o produto (so a capa fica nela)")

        if afirma_presente:
            texto = io.open(os.path.join(RAIZ, rel), encoding="utf-8").read()
            for termo, quando, o_que in TERMOS_MORTOS:
                if termo in texto:
                    falhas.append(
                        f"{rel}: usa termo morto {termo!r} (morreu em {quando}: {o_que})"
                    )

        for citado in caminhos_citados(os.path.join(RAIZ, rel)):
            if not os.path.exists(os.path.join(RAIZ, citado)):
                falhas.append(f"{rel}: aponta para `{citado}` — nao existe")

        linhas_mapa.append((rel, tipo, autoridade))

    if mostrar_mapa:
        print("--- MAPA: onde a verdade mora (GERADO, nunca versionado) ---")
        print()
        print("| documento | tipo | autoridade |")
        print("|---|---|---|")
        for rel, tipo, autoridade in linhas_mapa:
            print(f"| `{rel}` | {tipo} | {autoridade} |")
        print()
        print(f"{len(linhas_mapa)} documento(s) declarado(s).")
        print("--- fim do mapa ---")
        print()

    print(f"higiene da prosa: {len(docs)} documento(s) varrido(s), {len(falhas)} falha(s)")
    for f in falhas:
        print(f"  FALHA  {f}")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(verificar("--mapa" in sys.argv))
