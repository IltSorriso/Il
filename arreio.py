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
import re
import sys
import unicodedata

RAIZ = os.path.dirname(os.path.abspath(__file__))
DEPOSITO = os.path.join(RAIZ, "deposito", "objetos")
BOLHAS = os.path.join(RAIZ, "bolhas")

RESERVADO = "reservado"

# O VOCABULÁRIO de cada espécie — os campos, NA ORDEM canônica.
# Espelho do `camposDe` do spec (juiz/Bolha.lean). A concordância das duas
# implementações é conferida pelos ENDEREÇOS: se o texto divergir, o hash muda.
CAMPOS = {
    "licenca":  ["tipo", "catalogo", "nome"],
    "anotacao": ["tipo", "conteudo", "licenca"],
    # A CANÇÃO. `letra` é o endereço do texto inteiro: o RENDER da reunião das
    # `partes`, na ordem. `partes` é uma lista de endereços separada por vírgula.
    "musica":   ["tipo", "titulo", "interprete", "letra", "partes", "licenca"],
    # A PARTE numerada: intro, verso, refrão, ponte, outro. Cada parte é uma
    # bolha — logo cada parte tem ENDEREÇO próprio, e trocar uma palavra de uma
    # parte muda o endereço dela, e só dela.
    "parte":    ["tipo", "numero", "papel", "letra", "licenca"],
}

# O CAMPO DE CONTEÚDO de cada espécie julgável — espelho do `registroConteudo`
# do spec (juiz/Bolha.lean). A bolha de licença não está aqui: ela aponta para
# um catálogo REAL, não carrega texto, e o juiz não a julga como manifesto.
CONTEUDO = {
    "anotacao": "conteudo",
    "musica":   "letra",
    "parte":    "letra",
}


def serializar(campos: dict) -> str:
    """A FORMA CANÔNICA: só os campos da espécie, na ordem canônica, `\n` final."""
    tipo = campos.get("tipo")
    if tipo not in CAMPOS:
        raise ValueError(f"espécie desconhecida: {tipo!r}")
    ordem = CAMPOS[tipo]
    faltando = [k for k in ordem if k not in campos]
    if faltando:
        raise ValueError(f"espécie {tipo!r} sem campo obrigatório: {faltando}")
    return "".join(f"{k}: {campos[k]}\n" for k in ordem)


def canonicidade_ok(texto: str) -> bool:
    """O texto já está na forma canônica? (mesma régua do `canonicidadeOk` do spec)"""
    campos = {}
    for linha in texto.split("\n"):
        if not linha.strip():
            continue
        partes = linha.split(":")
        if len(partes) != 2:
            return False
        campos[partes[0].strip()] = partes[1].strip()
    try:
        return serializar(campos) == texto
    except ValueError:
        return False


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
    manifesto = serializar({"tipo": "licenca", "catalogo": catalogo, "nome": nome})
    return gravar_manifesto(f"licenca-{catalogo}-{nome}", manifesto)


def importar_anotacao(texto: str, licenca: str = RESERVADO):
    """Importa uma anotação: conteúdo por hash + manifesto (também por hash)."""
    h_texto = gravar_objeto(texto.encode("utf-8"))
    manifesto = serializar({"tipo": "anotacao", "conteudo": h_texto, "licenca": licenca})
    h_bolha = gravar_manifesto("anotacao-" + h_texto[:12], manifesto)
    return h_texto, h_bolha, manifesto


# ── O FLUXO DA MÚSICA ────────────────────────────────────────────────────────
# A letra entra pela MÃO: um arquivo texto com as partes marcadas. A mão escreve
# o texto de cada parte, a bolha da parte (numerada), a letra inteira (a reunião
# das partes, na ordem) e a bolha da música. A mão NÃO julga: quem julga é o
# juiz (juiz/Conformidade.lean), sobre os artefatos que a mão deixou.

PAPEIS = {
    "intro": "intro", "introducao": "intro",
    "verso": "verso", "refrao": "refrao", "pre-refrao": "pre-refrao",
    "ponte": "ponte", "outro": "outro", "coro": "refrao", "corpo": "corpo",
}


def sem_acento(texto: str) -> str:
    """O texto sem acentos — o PAPEL da parte é metadado ASCII."""
    return "".join(c for c in unicodedata.normalize("NFD", texto)
                   if unicodedata.category(c) != "Mn")


def nfc(texto: str) -> str:
    """A forma NORMAL (NFC) do texto.

    Acentuação composta e decomposta são a MESMA palavra em duas grafias — e
    grafias diferentes dão ENDEREÇOS diferentes. A mão normaliza; o juiz nem
    fica sabendo que isso existiu. É a porta de uma mão do texto canônico
    (conversa/PLANO.md, seção 4) decidida aqui, no ponto em que o texto entra.

    """
    return unicodedata.normalize("NFC", texto)


def papel_de(marcador: str) -> str:
    """O papel de uma parte, a partir do marcador: `[Refrão]` → `refrao`."""
    chave = sem_acento(nfc(marcador)).strip().lower()
    chave = "".join(c for c in chave if not c.isdigit())
    chave = chave.strip(" -_").replace(" ", "-")
    return PAPEIS.get(chave, chave or "corpo")


def ler_partes(caminho: str):
    """Lê o arquivo da letra: [(papel, texto)], cada texto com um `\n` final.

    As partes são marcadas por linhas `[Nome]`. Recado antes do primeiro
    marcador (linha começando por `#`) não é letra.
    """
    with open(caminho, encoding="utf-8") as f:
        linhas = nfc(f.read()).split("\n")
    partes, papel, corpo = [], None, []
    for linha in linhas:
        m = re.match(r"^\s*\[(.+?)\]\s*$", linha)
        if m:
            if papel is not None:
                partes.append((papel, corpo))
            papel, corpo = papel_de(m.group(1)), []
        elif papel is not None:
            corpo.append(linha)
    if papel is not None:
        partes.append((papel, corpo))
    saida = []
    for papel, corpo in partes:
        while corpo and not corpo[-1].strip():
            corpo.pop()
        while corpo and not corpo[0].strip():
            corpo.pop(0)
        saida.append((papel, nfc("\n".join(corpo)) + "\n"))
    return saida


def importar_musica(caminho: str, titulo: str, interprete: str, licenca: str = RESERVADO):
    """O FLUXO: letra → partes numeradas → bolha da música.

    Devolve (endereço da música, manifesto, mapa das partes, endereço da letra
    inteira). A licença padrão é `reservado`: canção de outra pessoa não é nossa
    para licenciar — publicar é operação de licença, e é ato de quem tem o
    direito.
    """
    partes = ler_partes(caminho)
    if not partes:
        raise ValueError(f"nenhuma parte em {caminho}: marque cada parte com [Nome]")
    titulo, interprete = nfc(titulo), nfc(interprete)
    enderecos, mapa = [], []
    for numero, (papel, texto) in enumerate(partes, start=1):
        h_texto = gravar_objeto(texto.encode("utf-8"))
        h_parte = gravar_manifesto(f"parte-{numero:02d}-{h_texto[:12]}", serializar({
            "tipo": "parte", "numero": str(numero), "papel": papel,
            "letra": h_texto, "licenca": licenca,
        }))
        enderecos.append(h_parte)
        mapa.append((numero, papel, h_texto, h_parte))
    letra_inteira = "".join(texto for _, texto in partes)   # a reunião, na ordem
    h_letra = gravar_objeto(letra_inteira.encode("utf-8"))
    manifesto = serializar({
        "tipo": "musica", "titulo": titulo, "interprete": interprete,
        "letra": h_letra, "partes": ",".join(enderecos), "licenca": licenca,
    })
    slug = re.sub(r"[^a-z0-9]+", "-", sem_acento(titulo).lower()).strip("-") or "musica"
    h_musica = gravar_manifesto(f"musica-{slug}", manifesto)
    return h_musica, manifesto, mapa, h_letra


def imprimir_mapa(titulo: str, interprete: str, licenca: str, h_musica: str, h_letra: str, mapa):
    """O MAPA: a letra inteira organizada, com o endereço de cada parte."""
    print(f"\n=== MAPA DA MÚSICA — {titulo} ({interprete}) ===")
    print(f"  bolha da música   endereço: {h_musica}")
    print(f"  letra inteira     endereço: {h_letra}   (a reunião das partes, na ordem)")
    print(f"  licença: {licenca}")
    print("")
    print("  nº | papel        | texto da parte          | bolha da parte (endereço)")
    print("  ---+--------------+-------------------------+------------------------------------------")
    for numero, papel, h_texto, h_parte in mapa:
        print(f"  {numero:>2} | {papel:<12} | {h_texto} | {h_parte}")


def fluxo_musica(args):
    """A linha de comando do fluxo:

        python3 arreio.py musica <letra.txt> --titulo T --interprete I
                                  [--licenca reservado|HASH] [--mapa ARQUIVO]

    O mapa é GERADO, nunca escrito à mão: versionar mapa gerado é criar sombra.
    """
    if not args:
        print("uso: arreio.py musica <letra.txt> --titulo T --interprete I [--licenca L] [--mapa A]")
        return 1
    caminho, opcoes, i = args[0], {}, 1
    while i < len(args):
        if args[i].startswith("--") and i + 1 < len(args):
            opcoes[args[i][2:]] = args[i + 1]
            i += 2
        else:
            i += 1
    titulo, interprete = opcoes.get("titulo"), opcoes.get("interprete")
    if not titulo or not interprete:
        print("faltou --titulo e/ou --interprete: a bolha da canção carrega os dois.")
        return 1
    licenca = opcoes.get("licenca", RESERVADO)
    if licenca != RESERVADO and len(licenca) != 64:
        print(f"licença {licenca!r}: ou `reservado`, ou o hash (64) de uma bolha-licença.")
        return 1
    h_musica, manifesto, mapa, h_letra = importar_musica(caminho, titulo, interprete, licenca)
    imprimir_mapa(titulo, interprete, licenca, h_musica, h_letra, mapa)
    print("\n  bolha da música:")
    for linha in manifesto.rstrip().split("\n"):
        print(f"    {linha}")
    if opcoes.get("mapa"):
        with open(opcoes["mapa"], "w", encoding="utf-8") as f:
            f.write(f"# MAPA DA MÚSICA — {titulo} ({interprete}) — GERADO, nunca escrito à mão\n\n")
            f.write("| nº | papel | texto da parte | bolha da parte |\n|---|---|---|---|\n")
            for numero, papel, h_texto, h_parte in mapa:
                f.write(f"| {numero} | {papel} | `{h_texto}` | `{h_parte}` |\n")
            f.write(f"\nbolha da música: `{h_musica}`\nletra inteira: `{h_letra}`\nlicença: {licenca}\n")
        print(f"  mapa escrito em {opcoes['mapa']} (GERADO)")
    return 0



# --- A VISTA: bolhas/ e PROJECAO do deposito, nunca fonte -------------------
# O nome de cada janela e FUNCAO dos campos do proprio objeto. Foi medido: 18 de
# 18 janelas dos dois repositorios tem nome derivavel assim, e os seus bytes sao
# copia byte-a-byte de um objeto do deposito sob o proprio sha256. Por isso a
# janela pode morrer e voltar: e' projecao.
JANELA = {
    "parte":    lambda c: f"parte-{int(c['numero']):02d}-{c['letra'][:12]}",
    "anotacao": lambda c: f"anotacao-{c['conteudo'][:12]}",
    "musica":   lambda c: f"musica-{slug(c['titulo'])}",
    "licenca":  lambda c: f"licenca-{c['catalogo']}-{c['nome']}",
}


def slug(texto: str) -> str:
    """O rotulo legivel de uma janela: sem acento, minusculo, espaco vira hifen."""
    t = sem_acento(texto).lower()
    return "-".join("".join(ch if ch.isalnum() else " " for ch in t).split())


def campos_de(texto: str) -> dict:
    """Le os campos de um objeto. NAO valida: quem valida e' o juiz."""
    campos = {}
    for linha in texto.split("\n"):
        if not linha.strip() or ":" not in linha:
            continue
        k, _, v = linha.partition(":")
        campos[k.strip()] = v.strip()
    return campos


def nome_da_janela(texto: str):
    """O nome da janela, ou None se a especie nao tem convencao (conteudo nao tem)."""
    c = campos_de(texto)
    f = JANELA.get(c.get("tipo"))
    if not f:
        return None
    try:
        return f(c)
    except Exception:
        return None


def regenerar_janelas(argv):
    """Reconstroi bolhas/ a partir do deposito — a vista e' projecao, nunca fonte."""
    dep = DEPOSITO
    if len(argv) > 1 and argv[0] == "--de":
        dep = argv[1]
    if not os.path.isdir(dep):
        print(f"nao ha deposito em {dep}")
        return 1
    os.makedirs(BOLHAS, exist_ok=True)
    escritas = iguais = sem_nome = 0
    for h in sorted(os.listdir(dep)):
        p = os.path.join(dep, h)
        if not os.path.isfile(p):
            continue
        dados = open(p, "rb").read()
        try:
            texto = dados.decode("utf-8")
        except UnicodeDecodeError:
            sem_nome += 1
            continue
        nome = nome_da_janela(texto)
        if not nome:
            sem_nome += 1
            continue
        destino = os.path.join(BOLHAS, nome + ".bolha")
        if os.path.exists(destino) and open(destino, "rb").read() == dados:
            iguais += 1
            continue
        with open(destino, "w", encoding="utf-8") as f:
            f.write(texto)
        escritas += 1
        print(f"  {nome}.bolha  <-  {h[:12]}...")
    print(f"\njanelas: {escritas} escritas · {iguais} ja identicas · {sem_nome} sem janela")
    print("a vista e projecao do deposito — nunca fonte.")
    return 0


def main():
    os.makedirs(DEPOSITO, exist_ok=True)
    os.makedirs(BOLHAS, exist_ok=True)

    # O FLUXO DA MÚSICA, quando pedido: `arreio.py musica <letra.txt> ...`
    if len(sys.argv) > 1 and sys.argv[1] == "musica":
        return fluxo_musica(sys.argv[2:])

    # A VISTA, quando pedido: `arreio.py janelas [--de <deposito>]`
    if len(sys.argv) > 1 and sys.argv[1] == "janelas":
        return regenerar_janelas(sys.argv[2:])

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
    sys.exit(main() or 0)
