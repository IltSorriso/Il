#!/usr/bin/env python3
"""servidor — a mesma fonte para todas as telas.

POR QUE EXISTE. A janela de agente da interface diz: o CLI ja' e' a API; se a
tela tiver de refazer a conta, o CLI devolveu pouco. Este servidor NAO refaz
conta nenhuma: ele le' o deposito e DEVOLVE DADO. Toda a regra continua no juiz
e nos objetos — aqui nao ha' lei, ha' leitura.

ELE NAO TEM VOCABULARIO PROPRIO. As especies, os campos, as relacoes e os
sigilos saem do proprio depósito (bolhas de tipo `especie`, `campo` e
`caminho`). Se o dado mudar, o servidor muda — nao ha' tabela a sincronizar.

O QUE ELE ENTREGA, e por que cada um:
  /<ambito>/estado          o retrato do acervo, com procedencia
  /<ambito>/retrato         o retrato largo: prazos, caminhos, licencas
  /<ambito>/objeto/<e>      o texto de um objeto
  /<ambito>/bytes/<e>       OS BYTES CRUS de um objeto — sem isto a midia morre
  /<ambito>/formulario      a FORMA de cada especie, lida do dado
  /<ambito>/grafo           nos e arestas, com grau, morada e procedencia
  /<ambito>/compor          compoe a partir da especie e devolve o ENDERECO
  /<ambito>/recorte/<agente> a meta-janela-modular, montada e dita

OS BYTES CRUS EXISTEM PORQUE A LEITURA DE TEXTO DESTROI MIDIA. Medido em
22/09/2026 sobre um arquivo de audio de 16044 bytes: a leitura de texto devolve
15444 caracteres, com 6963 caracteres de substituicao. Um objeto de midia lido
como texto nao e' o mesmo objeto. Por isso `/bytes/` entrega o arquivo como
ele e', e o `/estado` reporta o tamanho REAL, nao o do texto decodificado.

AMBITO E' PARAMETRO, NAO SUPOSICAO. Nenhum caminho de repositorio esta' escrito
no codigo: eles vem do ambiente. O mesmo servidor serve o Il e o IltS — e o
cabecalho de cada resposta DIZ qual ambito mediu.
"""
import hashlib, json, os, re, subprocess, sys, time, unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote
# `paineis` mora ao lado deste arquivo. O caminho e' posto a mao para o
# servidor funcionar tambem quando chamado de outro diretorio.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paineis  # noqa: E402

HEX = re.compile(r"^[0-9a-f]{64}$")
RE_HEX = re.compile(r"\b[0-9a-f]{64}\b")
LINHA = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):[ ]?(.*)$")
AQUI = os.path.dirname(os.path.abspath(__file__))

# O nome da pasta decide o que o objeto E'. Nao e' suposicao: e' o caminho.
PROCEDENCIAS = (("exemplos/deposito/objetos", "canone"),
                ("exemplos/quebrados/objetos", "quebrado"),
                ("deposito/objetos", "acervo"))


def ambitos():
    """nome=caminho, separados por virgula. Sem padrao embutido.

    Aceita tambem a grafia antiga (BOLHA_RAIZ) para nao quebrar chamador velho.
    """
    mapa = {}
    for par in os.environ.get("IL_AMBITOS", "").split(","):
        if "=" in par:
            n, c = par.split("=", 1)
            mapa[n.strip()] = c.strip()
    if not mapa and os.environ.get("BOLHA_RAIZ"):
        mapa["il"] = os.path.abspath(os.environ["BOLHA_RAIZ"])
    return mapa


def bolhasDeAmbito(raiz):
    """Le' o deposito UMA vez e devolve o que a bolha DECLARA.

    Duas naturezas, e a distincao e' o ponto:
      - o AMBITO e' de QUEM   — nome, dono, e os caminhos que ele usa;
      - o CAMINHO e' ONDE     — com o proprio sigilo ("o RECIPIENTE DECIDE").
    O servidor passa a LE' a bolha em vez de confiar so' na variavel de
    ambiente. A variavel diz ONDE esta' nesta maquina; a bolha diz QUEM
    responde e QUAIS lugares o ambito usa. Quando as duas discordam, o errado
    e' o ambiente — entao o servidor DIZ, e nao corrige em silencio.
    """
    amb, cam = {}, {}
    for o in objetos(raiz):
        c = o["campos"]
        if o.get("tipo") == "caminho":
            cam[o["endereco"]] = {"nome": c.get("nome"), "padrao": c.get("padrao"),
                                  "sigilo": c.get("sigilo")}
        elif o.get("tipo") == "ambito":
            amb[c.get("nome")] = {
                "endereco": o["endereco"], "dono": c.get("dono"),
                "licenca": c.get("licenca"), "procedencia": o["procedencia"],
                "enderecos": [x for x in (c.get("caminhos") or "").split(",")
                              if len(x) == 64]}
    return amb, cam


def declaracaoDoAmbito(raiz, nome):
    """O ambito DECLARADO em bolha — ou None. None NAO e' erro: e' a resposta
    honesta para um ambito que so' existe no ambiente e em bolha nenhuma."""
    if not nome:
        return None
    amb, cam = bolhasDeAmbito(raiz)
    a = amb.get(nome)
    if not a:
        return None
    a = dict(a)
    a["nome"] = nome
    a["caminhos"] = [cam[x] for x in a.pop("enderecos") if x in cam]
    return a


def nomeDoAmbito(raiz):
    """O nome pelo qual ESTA raiz e' servida — a volta da tabela do ambiente."""
    for n, c in ambitos().items():
        if os.path.abspath(c) == os.path.abspath(raiz):
            return n
    return None


def ler_texto(p):
    """A VISTA de texto. Objeto que nao e' texto nao e' bolha — bolha se le'.

    Os caracteres de substituicao que aparecem aqui NAO significam que o
    arquivo esta' corrompido: significam que ele nao e' texto. Quem precisa
    dos bytes de verdade usa `ler_bytes`.
    """
    try:
        with open(p, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return None


def ler_bytes(p):
    try:
        with open(p, "rb") as f:
            return f.read()
    except OSError:
        return None


def campos(txt):
    """campo: valor, na ordem. Valor nao contem ':' seguido de espaco."""
    d, ordem = {}, []
    for linha in txt.split("\n"):
        m = LINHA.match(linha)
        if m and m.group(1) not in d:
            d[m.group(1)] = m.group(2)
            ordem.append(m.group(1))
    return d, ordem


def objetos(raiz):
    """Todo objeto, com a procedencia. O caminho decide o que ele E'.

    `bytes` e' o tamanho REAL do arquivo, e `texto` diz se ele decodifica
    como UTF-8. Sem essa distincao o servidor mentiria sobre midia.
    """
    fora = []
    for rel, procedencia in PROCEDENCIAS:
        d = os.path.join(raiz, rel)
        if not os.path.isdir(d):
            continue
        for n in sorted(os.listdir(d)):
            if len(n) != 64:
                continue
            p = os.path.join(d, n)
            b = ler_bytes(p)
            if b is None:
                continue
            try:
                t = b.decode("utf-8")
                eh_texto = True
            except UnicodeDecodeError:
                t, eh_texto = b.decode("utf-8", "replace"), False
            c = campos(t)[0] if eh_texto else {}
            ordem = campos(t)[1] if eh_texto else []
            fora.append({"endereco": n, "procedencia": procedencia,
                         "caminho_rel": rel, "tipo": c.get("tipo"),
                         "nome": (c.get("nome") or c.get("titulo")
                                  or c.get("ramo") or c.get("numero")),
                         "licenca": c.get("licenca"), "campos": c, "ordem": ordem,
                         "texto": t, "bytes": len(b), "eh_texto": eh_texto})
    return fora


def por_endereco(objs):
    return {o["endereco"]: o for o in objs}


def liga(objs, e, prefixo=6):
    """Acha por PREFIXO, como o CLI faz. Devolve None se nao houver UM so'."""
    if len(e) == 64:
        m = [o for o in objs if o["endereco"] == e]
        return m[0] if m else None
    m = [o for o in objs if o["endereco"].startswith(e)]
    return m[0] if len(m) == 1 else None


def especies(objs):
    """A FORMA de cada especie, lida DO DADO — nunca de tabela deste programa."""
    idx = por_endereco(objs)
    saida = {}
    for o in objs:
        if o["tipo"] != "especie":
            continue
        nomes = []
        for h in o["campos"].get("campos", "").split(","):
            h = h.strip()
            if not h:
                continue
            alvo = idx.get(h)
            nomes.append(alvo["campos"].get("nome", h[:12]) if alvo else h[:12])
        saida[o["campos"].get("nome", o["endereco"][:12])] = {
            "objeto": o["endereco"], "campos": nomes,
            "conteudo": o["campos"].get("conteudo", ""),
            "licenca_exigida": o["campos"].get("licenca_exigida", ""),
            "licenca": o["campos"].get("licenca", ""),
        }
    return saida


def relacoes(objs):
    """O que cada campo CARREGA: `nenhuma` = valor; outra = endereco de objeto."""
    r = {}
    for o in objs:
        if o["tipo"] == "campo":
            r[o["campos"].get("nome", "?")] = o["campos"].get("relacao", "nenhuma")
    return r


def formulario(objs):
    """A tela se auto-monta daqui.

    A MARCA `*` diz exatamente onde a interface poe SELETOR DE OBJETO em vez
    de campo de texto: e' o campo cujo `relacao` nao e' `nenhuma`.
    """
    esp, rel = especies(objs), relacoes(objs)
    for nome, e in esp.items():
        e["campos_detalhe"] = [
            {"nome": c, "relacao": rel.get(c, "nenhuma"),
             "aponta": rel.get(c, "nenhuma") != "nenhuma",
             "carrega_conteudo": (c == e["conteudo"])}
            for c in e["campos"]]
    return esp


def sigilo_dos_caminhos(objs):
    """O RECIPIENTE DECIDE: o sigilo vem da bolha `caminho`, nunca do codigo."""
    d = {}
    for o in objs:
        if o["tipo"] == "caminho":
            c = o["campos"]
            d[c.get("padrao", "?")] = {"sigilo": c.get("sigilo", "?"),
                                       "endereco": o["endereco"],
                                       "nome": c.get("nome", "?")}
    return d



def morada(raiz, padrao):
    """O sigilo do LUGAR, lido da bolha `caminho` — nunca repetido como literal.

    A bolha `deposito` diz `sigilo: privado`. Escrever "privado" aqui seria uma
    SEGUNDA FONTE: se alguem mudasse a bolha, o codigo continuaria afirmando o
    antigo. E' a mesma classe do `cli/il` que escrevia as quatro camadas, e do
    recorte que nao distinguia as duas anotacoes.
    """
    return sigilo_dos_caminhos(objetos(raiz)).get(padrao, {}).get("sigilo", "NAO DECLARADO")


def alcance(objs):
    """Quem aponta quem — e a PROCEDENCIA de quem aponta decide o que o
    apontado E': apontado pelo canone e' conteudo; so' por quebrado e' insumo
    de teste; por ninguem e' artefato."""
    ids = {o["endereco"] for o in objs}
    grau = {}
    for o in objs:
        if not o["eh_texto"]:
            continue
        for r in set(RE_HEX.findall(o["texto"])):
            if r in ids and r != o["endereco"]:
                g = grau.setdefault(r, {"total": 0, "por": set(), "de": set()})
                g["total"] += 1
                g["por"].add(o["procedencia"])
                g["de"].add(o["endereco"])
    return grau


def grafo(raiz):
    """Nos e arestas. Cada no carrega os eixos que o grafo de texto nao tem:
    morada (o sigilo do lugar), procedencia, licenca e grau de entrada."""
    objs = objetos(raiz)
    nos = por_endereco(objs)
    sig = sigilo_dos_caminhos(objs)
    grau = alcance(objs)
    arestas = []
    for o in objs:
        if not o["eh_texto"]:
            continue
        for r in set(RE_HEX.findall(o["texto"])):
            if r in nos and r != o["endereco"]:
                arestas.append({"de": o["endereco"], "para": r,
                                "campo": _campo_que_cita(o, r)})
    saida = []
    for o in objs:
        g = grau.get(o["endereco"], {"total": 0, "por": set(), "de": set()})
        saida.append({
            "endereco": o["endereco"], "tipo": o["tipo"] or "(conteudo)",
            "nome": o["nome"], "bytes": o["bytes"], "eh_texto": o["eh_texto"],
            "procedencia": o["procedencia"],
            "morada": sig.get(o["caminho_rel"], {}).get("sigilo", "NAO DECLARADO"),
            "licenca": o["licenca"] or "(sem campo licenca)",
            "grau_entrada": g["total"],
            "grau_saida": sum(1 for a in arestas if a["de"] == o["endereco"]),
        })
    return {"ambito": raiz, "nos": saida, "arestas": arestas,
            "contagem": {"nos": len(saida), "arestas": len(arestas)},
            "distribuicao": _distrib(grau, objs)}


def _campo_que_cita(o, endereco):
    for nome, valor in o.get("campos", {}).items():
        if valor == endereco:
            return nome
    return None


def _distrib(grau, objs):
    faixas = {"0": 0, "1": 0, "2-3": 0, "4+": 0}
    for o in objs:
        g = grau.get(o["endereco"], {"total": 0})["total"]
        faixas["0" if g == 0 else "1" if g == 1 else "2-3" if g <= 3 else "4+"] += 1
    return faixas


def estado(raiz):
    objs = objetos(raiz)
    grau = alcance(objs)
    por_tipo, por_proc, semtipo = {}, {}, []
    for o in objs:
        por_proc[o["procedencia"]] = por_proc.get(o["procedencia"], 0) + 1
        if o["tipo"]:
            por_tipo[o["tipo"]] = por_tipo.get(o["tipo"], 0) + 1
        else:
            semtipo.append(o)
    conteudo, insumo, orfaos = [], [], []
    for o in semtipo:
        g = grau.get(o["endereco"], {"total": 0, "por": set()})
        if g["total"] == 0:
            orfaos.append({"endereco": o["endereco"], "procedencia": o["procedencia"],
                           "bytes": o["bytes"]})
        elif g["por"] == {"quebrado"}:
            insumo.append({"endereco": o["endereco"], "procedencia": o["procedencia"],
                           "bytes": o["bytes"]})
        else:
            conteudo.append(o["endereco"])
    compart = sorted(((h, g["total"], sorted(g["por"])) for h, g in grau.items()
                      if g["total"] > 1), key=lambda x: -x[1])
    return {"ambito": raiz, "objetos": len(objs), "bytes": sum(o["bytes"] for o in objs),
            "por_procedencia": por_proc, "por_especie": por_tipo,
            "quantos_texto": sum(1 for o in objs if o["eh_texto"]),
            "quantos_midia": sum(1 for o in objs if not o["eh_texto"]),
            "conteudo": {"quantos": len(conteudo)}, "insumo_de_teste": insumo,
            "orfaos": orfaos,
            "conteudo_compartilhado": [{"endereco": h, "grau": g, "apontado_por": p}
                                       for h, g, p in compart],
            "caminhos": sigilo_dos_caminhos(objs),
            "ressalva": "medido da ARVORE DE TRABALHO, nao do historico do git"}


def retrato(raiz):
    """O retrato largo: prazos, caminhos, licencas. E' o que a pagina desenha."""
    objs = objetos(raiz)
    hoje = time.strftime("%Y-%m-%d")
    por_especie, por_deposito, licencas = {}, {}, {}
    declaracoes, caminhos = [], []
    for o in objs:
        e = o["tipo"] or "(conteudo)"
        c = o["campos"]
        por_especie[e] = por_especie.get(e, 0) + 1
        por_deposito[o["caminho_rel"]] = por_deposito.get(o["caminho_rel"], 0) + 1
        if c.get("licenca"):
            k = c["licenca"] if HEX.match(c["licenca"]) else "reservado"
            licencas[k] = licencas.get(k, 0) + 1
        if o["tipo"] == "declaracao":
            p, dias = c.get("prazo", ""), None
            try:
                dias = int(round((time.mktime(time.strptime(p, "%Y-%m-%d"))
                                  - time.mktime(time.strptime(hoje, "%Y-%m-%d"))) / 86400.0))
            except ValueError:
                pass
            declaracoes.append({"objeto": o["endereco"], "ramo": c.get("ramo", ""),
                                "prazo": p, "dias": dias, "texto": c.get("texto", ""),
                                "licenca": c.get("licenca", ""),
                                "deposito": o["caminho_rel"]})
        elif o["tipo"] == "caminho":
            caminhos.append({"objeto": o["endereco"], "nome": c.get("nome", ""),
                             "padrao": c.get("padrao", ""), "sigilo": c.get("sigilo"),
                             "licenca": c.get("licenca", "")})
    declaracoes.sort(key=lambda d: (d["prazo"] or "9999-99-99"))
    # QUEM, nao so' ONDE — e AQUI, porque a raiz do servidor (`/`) serve a
    # PAGINA, nao JSON: aquele ramo que lista as rotas so' responde a caminho
    # vazio, e portanto nunca executa. A declaracao mora onde a pagina a ve'.
    return {"ambito": raiz, "ambito_nome": nomeDoAmbito(raiz),
            "ambito_declarado": declaracaoDoAmbito(raiz, nomeDoAmbito(raiz)),
            "quando": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "assinatura": _assinatura(objs),
            "total": len(objs), "bytes": sum(o["bytes"] for o in objs),
            "por_especie": por_especie, "por_deposito": por_deposito,
            "licencas": licencas, "declaracoes": declaracoes, "caminhos": caminhos,
            "especies": {k: {"campos": v["campos"], "licenca_exigida": v["licenca_exigida"],
                             "conteudo": v["conteudo"]}
                         for k, v in especies(objs).items()}}


def _assinatura(objs):
    m = max([int(os.path.getmtime(os.path.join(
        o.get("_p", "")) )) if False else 0 for o in objs] or [0])
    s = "%d|%d" % (len(objs), sum(o["bytes"] for o in objs))
    return hashlib.sha256(s.encode()).hexdigest()[:16]


def mime_de(dados):
    """O TIPO, lido dos PROPRIOS BYTES — projecao, nao campo guardado.

    A bolha nao carrega tipo de midia, e nao deve: quem sabe o que um arquivo e'
    sao os seus primeiros bytes. Guardar o tipo num campo seria segunda fonte, e
    a segunda fonte diverge. Se um dia o tipo nao se adivinhar aqui, o certo e'
    melhorar ESTA leitura — nao inventar campo.
    """
    if dados[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if dados[:2] == b"\xff\xd8":
        return "image/jpeg"
    if dados[:4] == b"RIFF" and dados[8:12] == b"WAVE":
        return "audio/wav"
    if dados[:4] == b"OggS":
        return "audio/ogg"
    if dados[:4] == b"\x1a\x45\xdf\xa3":
        return "audio/webm"
    if dados[4:8] == b"ftyp":
        return "audio/mp4"
    if dados[:4] == b"fLaC":
        return "audio/flac"
    if dados[:3] == b"ID3":
        return "audio/mpeg"
    if dados[:4] == b"%PDF":
        return "application/pdf"
    if dados[:2] == b"PK":
        return "application/zip"
    return "application/octet-stream"


def gravar(raiz, dados):
    """RECEBE BYTES e os poe no acervo PRIVADO — nunca no canone.

    A interface pode gravar, mas so' para onde e' privado: `deposito/objetos` e'
    o unico caminho declarado com `sigilo: privado`. O que a tela recebe nasce
    privado; promover ao canone continua sendo ato separado e deliberado — assim
    um engano na tela nunca suja o repositorio publico.

    Devolve o endereco do CONTEUDO e o da ANOTACAO que aponta para ele. Nada e'
    sobrescrito: o endereco E' o sha256 dos bytes, entao gravar duas vezes o
    mesmo audio da' o mesmo nome, e o segundo ato nao faz nada.
    """
    if not dados:
        return {"erro": "corpo vazio — nada a gravar"}
    destino = os.path.join(raiz, "deposito/objetos")
    try:
        os.makedirs(destino, exist_ok=True)
    except OSError as erro:
        return {"erro": "nao consigo escrever no acervo privado: %s" % erro}
    h = hashlib.sha256(dados).hexdigest()
    novo = not os.path.exists(os.path.join(destino, h))
    if novo:
        with open(os.path.join(destino, h), "wb") as f:
            f.write(dados)
    texto = "tipo: anotacao\nconteudo: %s\nlicenca: reservado\n" % h
    b = texto.encode("utf-8")
    ha = hashlib.sha256(b).hexdigest()
    nova = not os.path.exists(os.path.join(destino, ha))
    if nova:
        with open(os.path.join(destino, ha), "wb") as f:
            f.write(b)
    return {"onde": "deposito/objetos", "sigilo": morada(raiz, "deposito/objetos"),
            "conteudo": h, "conteudo_novo": novo, "bytes": len(dados),
            "tipo_de_midia": mime_de(dados),
            "anotacao": ha, "anotacao_nova": nova, "texto": texto,
            "nota": "nasceu PRIVADO. O canone e' ato separado."}


def _por_no_privado(raiz, dados):
    """Escreve bytes no acervo PRIVADO. Devolve (endereco, e_novo)."""
    import hashlib as _h
    destino = os.path.join(raiz, "deposito/objetos")
    os.makedirs(destino, exist_ok=True)
    h = _h.sha256(dados).hexdigest()
    novo = not os.path.exists(os.path.join(destino, h))
    if novo:
        with open(os.path.join(destino, h), "wb") as f:
            f.write(dados)
    return h, novo


def apontar(raiz, alvo):
    """Uma ANOTACAO que aponta para um objeto que JA' existe.

    E' a forma que o acervo ja' tem — `tipo, conteudo, licenca`, e `conteudo` e'
    literalmente "onde vive o endereco do conteudo". NAO precisa de especie nova.
    Serve para marcar uma mensagem da conversa, ou apontar de volta para ela.
    """
    import re as _re
    if not _re.match(r"^[0-9a-f]{64}$", alvo or ""):
        return {"erro": "endereco invalido — sao 64 hex"}
    destino = os.path.join(raiz, "deposito/objetos")
    if not os.path.exists(os.path.join(destino, alvo)):
        return {"erro": "esse objeto nao esta' no acervo privado"}
    texto = "tipo: anotacao\nconteudo: %s\nlicenca: reservado\n" % alvo
    h, novo = _por_no_privado(raiz, texto.encode("utf-8"))
    return {"onde": "deposito/objetos", "sigilo": morada(raiz, "deposito/objetos"),
            "aponta_para": alvo, "anotacao": h, "anotacao_nova": novo,
            "nota": "anotacao apontando — nasceu PRIVADA"}


NOME_DA_GENERICA = "saida-generativa"


def licencasDeModelo(raiz):
    """TODAS as licencas-modelo do acervo, como (nome, endereco).

    O endereco NUNCA e' inventado: e' lido do deposito. Isto e' o que torna
    possivel haver mais de uma — uma por modelo — sem que o codigo saiba de
    antemao quais existem.
    """
    achadas = []
    for origem in ("exemplos/deposito/objetos", "deposito/objetos"):
        d = os.path.join(raiz, origem)
        if not os.path.isdir(d):
            continue
        for h in sorted(os.listdir(d)):
            try:
                with open(os.path.join(d, h), "rb") as f:
                    t = f.read().decode("utf-8", "replace")
            except OSError:
                continue
            if t.startswith("tipo: licenca") and "\ncatalogo: modelo\n" in t:
                nome = ""
                for linha in t.splitlines():
                    if linha.startswith("nome: "):
                        nome = linha[6:].strip()
                achadas.append((nome, h))
    return achadas


def licencaDoModelo(raiz, modelo=None):
    """O ENDERECO da licenca-selo. QUAL delas depende de sabermos QUEM respondeu.

    A ordem, e cada passo e' dito:
      1. a licenca cujo `nome` E' o modelo que respondeu — a ESPECIFICA
      2. a generica (`saida-generativa`)                 — quando nao se sabe quem
      3. nenhuma                                         — quem chama NAO grava selo

    O MODELO QUE VALE E' O QUE VOLTOU, nao o apelido que foi pedido. Medido em
    04/10/2026: pedindo `deepseek-chat`, quem respondeu foi `deepseek-flash`. Se o
    selo gravasse o pedido, diria um nome FALSO — e a politica de um modelo nao e'
    a do outro, entao um selo falso e' pior que selo nenhum.
    """
    achadas = licencasDeModelo(raiz)
    if modelo:
        for nome, h in achadas:
            if nome == modelo:
                return h
    for nome, h in achadas:
        if nome == NOME_DA_GENERICA:
            return h
    if len(achadas) == 1:
        return achadas[0][1]
    return None


def registrar(raiz, texto, papel="pergunta", licenca=None):
    """Grava UMA mensagem da conversa, de forma ESTRUTURADA.

    Tres objetos, todos de especies que JA' existem — nenhuma especie nova, e
    nenhuma linha mexida no juiz:
        conteudo  = o texto da mensagem
        anotacao  = aponta para o texto
        carimbo   = carimba o INSTANTE na anotacao

    A ORDEM vem do carimbo, e e' isso que faz disto uma CADEIA — cada mensagem
    e' alcancavel a partir do carimbo dela, e os carimbos se ordenam no tempo.
    """
    import re as _re, time as _t
    if not (texto or "").strip():
        return {"erro": "mensagem vazia"}
    if papel not in ("pergunta", "resposta", "nota", "marca"):
        return {"erro": "papel desconhecido: %s" % papel}
    h, novo = _por_no_privado(raiz, texto.encode("utf-8"))
    # O SELO: o que saiu de um modelo generativo nasce com a licenca-selo, em vez
    # de `reservado`. A licenca E' o selo — e viaja no dado, entao a conta do
    # acervo separa sozinha o que foi escrito por gente do que veio de modelo.
    lic = licenca if (licenca and len(licenca) == 64) else "reservado"
    ta = "tipo: anotacao\nconteudo: %s\nlicenca: %s\n" % (h, lic)
    ha, nova = _por_no_privado(raiz, ta.encode("utf-8"))
    # O CARIMBO e' o elo: ele aponta para a anotacao e diz QUANDO.
    # O tempo vai em SEGUNDOS DE EPOCA — o formato nao aceita ':' no valor, e a
    # epoca e' a mesma unidade que o git usa, entao os dois tempos sao comparaveis.
    tc = "tipo: carimbo\nobjeto: %s\ntempo: %d\nlicenca: reservado\n" % (ha, int(_t.time()))
    hc, novo_c = _por_no_privado(raiz, tc.encode("utf-8"))
    return {"onde": "deposito/objetos", "sigilo": morada(raiz, "deposito/objetos"), "papel": papel,
            "licenca": lic, "selo_de_modelo": lic != "reservado",
            "conteudo": h, "conteudo_novo": novo, "bytes": len(texto.encode("utf-8")),
            "anotacao": ha, "anotacao_nova": nova,
            "carimbo": hc, "carimbo_novo": novo_c,
            "nota": "tres objetos, tres especies que ja' existiam. nasceu PRIVADO."}


def sugerir(raiz, enderecos=None, parcial="", ambito=""):
    """NOMES SUGERIDOS PELO PROPRIO SISTEMA — sem rede, sem modelo.

    Tres origens, e CADA UMA DIZ DE ONDE VEIROU. Nao ha sugestao anonima: quem
    le' precisa poder separar o que o acervo AFIRMA do que um modelo opinou.

      acervo  — nomes que JA' existem no deposito e casam com o que voce digitou
      grafo   — objetos LIGADOS aos que voce escolheu (quem os aponta, o que apontam)
      forma   — as listas que ja' existem: repetir nome e' visivel, nao silencioso
    """
    enderecos = [e for e in (enderecos or []) if isinstance(e, str) and len(e) == 64]
    objs = objetos(raiz)
    dentro = _quem_aponta(objs)
    p = (parcial or "").strip().lower()

    # ---- acervo: os nomes que ja' existem ----
    existentes = []
    for o in objs:
        n = (o.get("nome") or o["campos"].get("titulo") or "").strip()
        if n:
            existentes.append({"nome": n, "especie": o.get("tipo") or "(conteudo)",
                               "endereco": o["endereco"]})
    vistos = {}
    for e in existentes:
        vistos.setdefault(e["nome"].lower(), []).append(e)
    repetidos = sorted(k for k, v in vistos.items() if len(v) > 1)

    acervo = [e for e in existentes if p and p in e["nome"].lower()][:12]
    if not p:
        acervo = sorted(existentes, key=lambda e: e["nome"].lower())[:12]

    # ---- grafo: o que esta' ligado ao que voce escolheu ----
    ligados, vistos_l = [], set()
    for e in enderecos:
        for quem in dentro.get(e, []):
            if quem not in vistos_l:
                vistos_l.add(quem)
                o = next((x for x in objs if x["endereco"] == quem), None)
                if o:
                    ligados.append({"endereco": quem, "especie": o.get("tipo") or "(conteudo)",
                                    "nome": (o.get("nome") or o["campos"].get("titulo") or "")
                                            or "(sem nome proprio)",
                                    "porque": "aponta para um dos escolhidos"})
        o = next((x for x in objs if x["endereco"] == e), None)
        if o:
            for alvo in _hexes(o):
                if alvo in vistos_l or alvo in enderecos:
                    continue
                vistos_l.add(alvo)
                t = next((x for x in objs if x["endereco"] == alvo), None)
                if t:
                    ligados.append({"endereco": alvo, "especie": t.get("tipo") or "(conteudo)",
                                    "nome": (t.get("nome") or t["campos"].get("titulo") or "")
                                            or "(sem nome proprio)",
                                    "porque": "e' apontado por um dos escolhidos"})

    return {"acervo": acervo, "grafo": ligados[:12],
            "repetidos": repetidos,
            "nota": ("tudo aqui veio do proprio acervo — nada saiu da maquina. "
                     "o modelo, quando usado, e' camada ADICIONAL e dira' que saiu."),
            "fonte": "proprio sistema"}


def criarLista(raiz, nome, enderecos):
    """A LISTA: nome (pode ser VAZIO) + os itens que voce juntou.

    Os itens vao no campo `partes`, cuja relacao e' `reuniao` — e o juiz JA'
    CONFERE reuniao, entao esta lista nasce verificada sem uma linha nova.
    Nasce PRIVADA, como tudo que a tela grava.
    """
    itens = [e for e in (enderecos or []) if isinstance(e, str) and len(e) == 64]
    destino = os.path.join(raiz, "deposito/objetos")
    for e in itens:
        if not os.path.exists(os.path.join(destino, e)):
            return {"erro": "nao achei o objeto %s no acervo privado" % e[:12]}
    nome = (nome or "").strip()
    texto = ("tipo: lista\nnome: %s\npartes: %s\nlicenca: reservado\n"
             % (nome, ",".join(itens)))
    h, novo = _por_no_privado(raiz, texto.encode("utf-8"))
    return {"onde": "deposito/objetos", "sigilo": morada(raiz, "deposito/objetos"), "lista": h,
            "lista_nova": novo, "nome": nome, "itens": len(itens),
            "vazia": nome == "",
            "nota": ("lista sem nome: e' a caixa para organizar depois."
                     if nome == "" else "lista nomeada.")}


def _hexes(o):
    """Todo valor de 64 hex que aparece em QUALQUER campo deste objeto."""
    import re as _re
    achados = []
    for _, v in o["campos"].items():
        for h in _re.findall(r"\b[0-9a-f]{64}\b", v):
            achados.append(h)
    return achados


def _quem_aponta(objs):
    """endereco -> [quem cita]. A inversa do grafo, montada uma vez so'."""
    dentro = {}
    for o in objs:
        if not o.get("tipo"):
            continue
        for h in _hexes(o):
            dentro.setdefault(h, []).append(o["endereco"])
    return dentro


def midias(raiz):
    """AS MIDIAS — o que nao e' texto, com quem aponta para cada uma.

    Nao ha campo de tipo de midia em bolha nenhuma, e nao deve haver: o tipo se
    le' dos BYTES. Aqui ele e' DITO, como projecao.
    """
    objs = objetos(raiz)
    dentro = _quem_aponta(objs)
    fora = []
    for o in objs:
        if o["eh_texto"]:
            continue
        b = ler_bytes(os.path.join(raiz, o["caminho_rel"], o["endereco"])) or b""
        fora.append({"endereco": o["endereco"], "bytes": o["bytes"],
                     "tipo_de_midia": mime_de(b),
                     "procedencia": o["procedencia"],
                     "apontado_por": sorted(set(dentro.get(o["endereco"], []))),
                     "rotas": {"bytes": "/bytes/" + o["endereco"]}})
    fora.sort(key=lambda x: -x["bytes"])
    return {"ambito": raiz, "quantas": len(fora),
            "bytes": sum(x["bytes"] for x in fora),
            "midias": fora,
            "nota": "o tipo vem dos PRIMEIROS BYTES, lido na hora — nao ha campo guardado"}


def _ramos(raiz):
    """Os ramos que AINDA existem — uma chamada so' de git."""
    import subprocess as _sp
    try:
        r = _sp.run(["git", "branch", "-a", "--format=%(refname:short)"],
                    cwd=raiz, capture_output=True, text=True, timeout=15)
    except (OSError, _sp.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    fora = set()
    for linha in (r.stdout or "").splitlines():
        n = linha.strip()
        if n.startswith("origin/"):
            n = n[len("origin/"):]
        if n and n != "HEAD":
            fora.add(n)
    return fora


def _dias_ate(prazo):
    """Dias entre hoje e AAAA-MM-DD. None se o prazo nao for data valida."""
    import datetime as _dt
    try:
        a, m, d = [int(x) for x in prazo.split("-")]
        return (_dt.date(a, m, d) - _dt.date.today()).days
    except (ValueError, AttributeError):
        return None


def _resposta_acervo(raiz, q):
    """A conversa DETERMINISTICA: le' o deposito e responde FATO.

    Regra: se nao souber, DIZ que nao sabe. Um chat que inventa para parecer
    util e' pior que um chat que cala — porque o inventado nao se distingue do
    medido na tela.
    """
    objs = objetos(raiz)
    e = estado(raiz)
    ql = q.lower().strip()
    linhas, fontes = [], []

    def comeca(*chaves):
        return any(c in ql for c in chaves)

    if not ql or comeca("ajuda", "socorro", "o que voce", "o que vc", "comandos", "?"):
        return ("sei responder, lendo o acervo e sem inventar:\n"
                "  quantos            — objetos por procedencia e por especie\n"
                "  prazos             — as declaracoes e quanto falta\n"
                "  especies           — as formas e quantos campos cada uma tem\n"
                "  caminhos           — onde o acervo mora, e o sigilo de cada lugar\n"
                "  midias             — o que nao e' texto (audio, imagem)\n"
                "  carimbos           — quando cada coisa existiu no mundo\n"
                "  orfaos             — o que ninguem alcanca\n"
                "  quem aponta <end>  — quem cita aquele endereco\n"
                "  buscar <termo>     — procura o termo nos textos\n"
                "\nnada disso sai da maquina, e nada disso e' probabilidade.")

    if comeca("quantos", "quantas", "quantidade", "total"):
        p = e["por_procedencia"]
        linhas.append("o acervo tem %d objetos, %s bytes." % (e["objetos"],
                      format(e["bytes"], ",d").replace(",", " ")))
        linhas.append("por origem: " + " · ".join("%s %d" % (k, v) for k, v in sorted(p.items())))
        esp = sorted(e["por_especie"].items(), key=lambda x: -x[1])
        linhas.append("por especie: " + " · ".join("%s %d" % (k, v) for k, v in esp if k != "SEM TIPO"))
        if e["por_especie"].get("SEM TIPO"):
            linhas.append("sem tipo (conteudo): %d" % e["por_especie"]["SEM TIPO"])
        return "\n".join(linhas)

    if comeca("prazo", "vence", "vencimento", "atrasad"):
        d = [o for o in objs if o.get("tipo") == "declaracao"]
        if not d:
            return "nao ha declaracao nenhuma neste ambito."
        vivos = _ramos(raiz)
        linhas.append("as declaracoes — sao elas que carregam prazo:")
        for o in sorted(d, key=lambda x: x["campos"].get("prazo") or "9999"):
            pz = o["campos"].get("prazo") or "?"
            dias = _dias_ate(pz)
            if dias is None:
                estado_txt = "MALFORMADO — nao e' data"
            elif dias < 0:
                estado_txt = "VENCEU ha %d dia(s)" % (-dias)
            elif dias <= 7:
                estado_txt = "vence em %d dia(s)" % dias
            else:
                estado_txt = "faltam %d dias" % dias
            ramo = o["campos"].get("ramo") or "?"
            # O prazo de um ramo que JA' NAO EXISTE nao corre: o trabalho ou foi
            # fundido ou foi abandonado, e dizer "venceu" seria mentira util.
            if vivos is not None and ramo not in vivos:
                if dias is None:
                    estado_txt += " · ramo nao existe mais"
                else:
                    estado_txt = "ramo nao existe mais (fundido ou abandonado)"
            linhas.append("  %s  %-34s %s" % (pz, ramo, estado_txt))
            fontes.append(o["endereco"])
        return "\n".join(linhas)

    if comeca("especie", "espécie", "formas", "formulario", "formulário"):
        esp = especies(objs)
        linhas.append("%d especies, e a forma de cada uma vem do proprio dado:" % len(esp))
        for n in sorted(esp):
            linhas.append("  %-14s %s" % (n, " + ".join(esp[n]["campos"])))
        linhas.append("\n(um campo terminando em * carrega um ENDERECO — e' ponteiro, nao texto)")
        return "\n".join(linhas)

    if comeca("caminho", "onde mora", "deposito", "depósito", "sigilo"):
        c = e["caminhos"]
        linhas.append("os lugares declarados, e o sigilo de cada um:")
        for k, v in sorted(c.items()):
            linhas.append("  %-32s %s" % (k, v))
        return "\n".join(linhas)

    if comeca("midia", "mídia", "audio", "áudio", "som", "gravac", "gravaç", "imagem", "video", "vídeo"):
        m = midias(raiz)
        if not m["quantas"]:
            return "nenhuma midia no acervo. (o que nao e' texto aparece aqui)"
        linhas.append("%d midias, %d bytes:" % (m["quantas"], m["bytes"]))
        for x in m["midias"]:
            quem = ", ".join(y[:12] for y in x["apontado_por"]) or "NINGUEM aponta"
            linhas.append("  %s…  %8d B  %-16s  %s  %s"
                          % (x["endereco"][:12], x["bytes"], x["tipo_de_midia"],
                             x["procedencia"], quem))
        linhas.append("\n(abra /bytes/<endereco> para ouvir ou ver)")
        return "\n".join(linhas)

    if comeca("carimbo", "quando"):
        d = [o for o in objs if o.get("tipo") == "carimbo"]
        if not d:
            return "nenhum carimbo: o tempo do mundo ainda nao foi registrado para nada."
        linhas.append("%d carimbos — o tempo do MUNDO, que o git nao sabe:" % len(d))
        for o in d:
            t = o["campos"].get("tempo") or "?"
            import time as _t
            try:
                legivel = _t.strftime("%Y-%m-%d %H:%M UTC", _t.gmtime(int(t)))
            except (ValueError, OverflowError, TypeError):
                legivel = "?"
            linhas.append("  %s  carimba %s" % (legivel, (o["campos"].get("objeto") or "?")[:12]))
        return "\n".join(linhas)

    if comeca("orf", "ninguem alcanca", "ninguém alcança", "artefat"):
        if not e["orfaos"]:
            return "nenhum orfao: todo objeto sem tipo tem quem o alcance."
        linhas.append("%d orfao(s) — sem tipo e sem alcance:" % len(e["orfaos"]))
        for o in e["orfaos"]:
            linhas.append("  %s  %s bytes  %s" % (o["endereco"][:12], o["bytes"], o["procedencia"]))
        return "\n".join(linhas)

    import re as _re
    m = _re.search(r"\b([0-9a-f]{6,64})\b", ql)
    if ("quem" in ql or "aponta" in ql or "cita" in ql or "referencia" in ql) and m:
        alvo = m.group(1)
        achou = [o for o in objs if o["endereco"].startswith(alvo)]
        if not achou:
            return "nenhum objeto comeca com %s neste ambito." % alvo
        dentro = _quem_aponta(objs)
        quem = dentro.get(achou[0]["endereco"], [])
        if not quem:
            return "%s — NINGUEM aponta para ele." % achou[0]["endereco"]
        return "%s e' apontado por:\n" % achou[0]["endereco"] + "\n".join(
            "  " + x for x in sorted(set(quem)))

    termo = ql
    for p0 in ("buscar", "busca", "procur", "procure", "onde esta", "onde est"):
        if termo.startswith(p0):
            termo = termo[len(p0):].strip()
    if len(termo) >= 3:
        achados = []
        for o in objs:
            alvo = (o["texto"] or "").lower()
            if termo in alvo or termo in (o.get("nome") or "").lower():
                achados.append(o)
        if achados:
            linhas.append('\"%s\" aparece em %d objeto(s):' % (termo, len(achados)))
            for o in achados[:12]:
                nome = o.get("nome") or o.get("tipo") or "conteudo"
                linhas.append("  %s…  %-16s %s" % (o["endereco"][:12], nome, o["procedencia"]))
            if len(achados) > 12:
                linhas.append("  ... e %d outros" % (len(achados) - 12))
            return "\n".join(linhas)
        return ("nao achei \"%s\" em nenhum objeto deste ambito.\n\n"
                "posso ter errado: tente uma palavra mais curta, ou \"ajuda\" para ver "
                "o que eu sei responder." % termo)

    return ("nao sei responder isso lendo o acervo — e nao vou inventar.\n\n"
            "escreva \"ajuda\" para ver o que eu sei. Se quiser perguntar a um MODELO, "
            "e' outro ato: ele manda a pergunta para fora da maquina.")


# ═══ CAMADA 2 — VERIFICAR ════════════════════════════════════════════════════
# A CAMADA QUE FALTAVA EM TODO LUGAR. O CLI so' IMPRIMIA a instrucao ("corrida
# inteira: lean --run cadeia/Cadeia.lean --etapa tudo") e a interface nao tinha
# nem isso — o portao de entrada nao existia como coisa que se USA.
#
# O caso de uso e' explicito: "para saber QUAL passo falhou, sem ler log
# inteiro". Por isso aqui NAO se devolve o log: devolve-se, por passo, SE RODOU,
# QUANDO, a MEDIDA (a linha de total) e — quando falhou — a CAUDA que diz o
# motivo. A extracao da medida e' a MESMA do `numero` do Cadeia.lean: a ultima
# linha que contem 'f' (conferencias/falhas, documento(s)/falha(s)).

ORDEM_DA_CADEIA = ["versao-do-lean", "hash-sha256", "spec-bolha", "ponte",
                   "arreio-olean", "mao-escreve-a-cancao", "conformidade",
                   "higiene-da-prosa"]


def _quando_do_arquivo(p):
    try:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(os.path.getmtime(p)))
    except Exception:
        return ""


def _cauda(p):
    """A CAUSA, nao o arquivo: a primeira linha que diz 'error' ou 'falha'."""
    try:
        with open(p, "r", errors="replace") as f:
            for l in f:
                t = l.strip()
                if t and ("error" in t or "Error" in t or "falha" in t):
                    return t[:220]
    except Exception:
        pass
    return ""


RE_TOTAL = re.compile(r"\d+\s+(confer|documento|falha)")


def _medida(txt):
    """A linha de total — e SO' quando ela E' um total.

    A primeira versao pegava "a ultima linha que contem f", que e' o que o
    `numero` do Cadeia.lean faz. Mas ele so' e' chamado sobre os arquivos que
    TEM contagem. Aplicado aos oito passos, devolvia bobagem: "instead of" para
    o arreio-olean, o cabecalho da versao do Lean para o versao-do-lean, e um
    hash solto para a mao. MEIA-VERDADE E' PIOR QUE SILENCIO: passo sem
    contagem fica sem medida, e a tela nao inventa uma.
    """
    for l in reversed(txt.split("\n")):
        if RE_TOTAL.search(l):
            return l.strip()[:200]
    return ""


def verificar(raiz):
    passos = []
    for r in ORDEM_DA_CADEIA:
        prova = os.path.join(raiz, "prova-" + r + ".txt")
        marco = os.path.join(raiz, ".falhou-" + r)
        existe = os.path.exists(prova)
        falhou = os.path.exists(marco)
        texto = ""
        if existe:
            try:
                with open(prova, "r", errors="replace") as f:
                    texto = f.read()
            except Exception:
                pass
        passos.append({"passo": r, "rodou": existe, "falhou": falhou,
                       "quando": _quando_do_arquivo(prova) if existe else "",
                       "medida": _medida(texto) if existe else "",
                       "erro": _cauda(prova) if falhou else ""})

    recibos = []
    for etapa in ("tudo", "juiz", "prosa"):
        p = os.path.join(raiz, "recibo-" + etapa + ".txt")
        if not os.path.exists(p):
            continue
        try:
            with open(p, "r", errors="replace") as f:
                corpo = f.read()
        except Exception:
            continue
        recibos.append({"etapa": etapa, "quando": _quando_do_arquivo(p),
                        "passou": "PASSOU" in corpo[:400], "corpo": corpo[:2000]})

    falhou = [p["passo"] for p in passos if p["falhou"]]
    nunca = [p["passo"] for p in passos if not p["rodou"]]
    return {
        "ambito": raiz, "camada": 2,
        "papel": "roda o juiz e a prosa — o portao de entrada",
        "casos_de_uso": ["antes de empurrar para a origem",
                         "depois de cada mudanca que troca o leitor",
                         "saber QUAL passo falhou, sem ler log inteiro"],
        "ordem": ORDEM_DA_CADEIA,
        "passos": passos,
        "recibos": recibos,
        "falhou": falhou,
        "nunca_rodou": nunca,
        "veredito": (("FALHOU em " + ", ".join(falhou)) if falhou else
                     ("nunca rodou: " + ", ".join(nunca)) if nunca else
                     "PASSOU — os 8 passos tem prova no disco"),
        "como_rodar": "POST neste mesmo caminho (lanca em segundo plano), ou: "
                      "LEAN_PATH=juiz:arreio lean --run cadeia/Cadeia.lean --etapa tudo",
    }


def lancarCadeia(raiz, etapa="tudo"):
    """Lanca a cadeia DESLIGADA da sessao e volta NA HORA.

    A corrida leva ~2-3 min (so' o passo `arreio-olean` compila 2.875 linhas,
    ~40 s) — muito mais que qualquer espera razoavel de HTTP. Entao ela sai por
    `setsid`, e a tela ACOMPANHA lendo o recibo e os marcos de falha. E' o mesmo
    arranjo do portao do pre-push, e o unico que sobrevive ao teto desta casa.
    """
    if etapa not in ("juiz", "prosa", "tudo"):
        return {"lancou": False, "erro": "etapa desconhecida: " + etapa,
                "etapas": ["juiz", "prosa", "tudo"]}
    env = dict(os.environ)
    elan = os.path.join(os.path.expanduser("~"), ".elan", "bin")
    env["PATH"] = elan + os.pathsep + env.get("PATH", "")
    env.setdefault("ELAN_TOOLCHAIN", "leanprover/lean4:v4.34.0")
    log = "/tmp/cadeia-" + etapa + ".log"
    cmd = ("cd " + raiz + " && LEAN_PATH=juiz:arreio " + env.get("IL_LEAN", "lean")
           + " --run cadeia/Cadeia.lean --etapa " + etapa)
    try:
        with open(log, "wb") as f:
            subprocess.Popen(["setsid", "sh", "-c", cmd], stdout=f, stderr=f,
                             stdin=subprocess.DEVNULL, env=env,
                             start_new_session=True)
    except Exception as ex:
        return {"lancou": False, "erro": str(ex)}
    return {"lancou": True, "etapa": etapa, "log": log,
            "aviso": "a corrida leva ~2-3 min. Acompanhe pelo recibo e pelos marcos "
                     "de falha — esta rota NAO espera por ela."}


def janelaDe(raiz, nome):
    """A META-JANELA escolhida, resolvida do acervo.

    HONESTIDADE: a especie `agente` carrega `nome`, `papel` e `texto` — e NAO
    carrega as FONTES do recorte. Entao trocar de meta-janela muda o contexto
    dado ao MODELO, mas NAO muda o que o acervo responde: o acervo responde o
    mesmo, porque le' o mesmo deposito. Isto e' um limite medido, nao um enfeite.
    """
    if not nome:
        return None
    for o in objetos(raiz):
        if o.get("tipo") != "agente":
            continue
        if (o.get("nome") or o["campos"].get("nome")) == nome:
            t = o["campos"].get("texto") or ""
            corpo = ""
            if len(t) == 64:
                caminho = os.path.join(raiz, "deposito/objetos", t)
                if not os.path.exists(caminho):
                    caminho = os.path.join(raiz, "exemplos/deposito/objetos", t)
                try:
                    with open(caminho, "rb") as f:
                        corpo = f.read().decode("utf-8", "replace")
                except OSError:
                    corpo = ""
            return {"nome": nome, "papel": o["campos"].get("papel") or "",
                    "texto": t, "convencao": corpo, "endereco": o["endereco"]}
    return None


def conversar(raiz, pergunta, modo="acervo", janela=None):
    """A conversa. Duas naturezas, e a resposta DIZ qual foi usada.

    `acervo` (padrao): le' o deposito, responde FATO, nada sai da maquina.
    `modelo`: manda a pergunta para FORA e devolve o que voltar. Nao e' o
      acervo falando — e' um modelo opinando, e a resposta nao finge o contrario.
    """
    j = janelaDe(raiz, janela) if janela else None
    if modo != "modelo":
        r = _resposta_acervo(raiz, pergunta)
        if j:
            r = ("[meta-janela: %s — %s]\n(ela NAO muda esta resposta: o acervo le' o "
                 "mesmo deposito. ela muda o contexto dado ao MODELO.)\n\n" % (j["nome"], j["papel"])) + r
        return {"modo": "acervo", "saiu_da_maquina": False, "janela": j, "resposta": r, "fontes": []}
    if not pergunta:
        return {"modo": "modelo", "saiu_da_maquina": False,
                "resposta": "pergunta vazia."}
    import subprocess as _sp
    script = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "cli", "modelo")
    if not os.path.exists(script):
        return {"modo": "modelo", "saiu_da_maquina": False,
                "resposta": "o modulo cli/modelo nao esta' aqui."}
    try:
        com = pergunta
        if j and j["convencao"]:
            com = ("Convencao desta meta-janela (%s):\n%s\n\nPergunta: %s"
                   % (j["nome"], j["convencao"], pergunta))
        r = _sp.run(["python3", script, "--json", com],
                     capture_output=True, text=True, timeout=90)
    except _sp.TimeoutExpired:
        return {"modo": "modelo", "saiu_da_maquina": True, "resposta": "o modelo nao respondeu em 90 s."}
    except OSError as erro:
        return {"modo": "modelo", "saiu_da_maquina": False, "resposta": "nao consegui chamar: %s" % erro}
    if r.returncode != 0:
        return {"modo": "modelo", "saiu_da_maquina": True,
                "resposta": "o modelo recusou (codigo %d):\n%s" % (r.returncode, (r.stderr or "")[:400])}
    # O MODELO QUE RESPONDEU, lido do JSON — e' ELE que vai no selo, nao o apelido
    # pedido. Medido em 04/10/2026: pedindo `deepseek-chat`, respondeu `deepseek-flash`.
    resposta, respondeu = "", ""
    try:
        dj = json.loads((r.stdout or "").strip() or "{}")
        resposta = (dj.get("saida") or "").strip()
        respondeu = (dj.get("modelo") or "").strip()
    except ValueError:
        resposta = (r.stdout or "").strip()
    return {"modo": "modelo", "saiu_da_maquina": True, "janela": j,
            "modelo": respondeu,
            "resposta": resposta,
            "aviso": "isto NAO e' o acervo: e' um modelo de fora. Nada aqui foi conferido pelo juiz."}


def compor(raiz, especie, valores):
    """COMPOE a partir da especie e devolve o ENDERECO — sem gravar nada.

    E' a peca que permite a interface PREENCHER. Ela faz tres coisas que a tela
    faria errado se tentasse sozinha:
      1. a ORDEM dos campos vem da especie, nao da ordem em que a tela os tem;
      2. `tipo` e `licenca` se preenchem sozinhos;
      3. o endereco e' calculado ANTES de gravar, e diz se o objeto JA EXISTE.
    A tela nao calcula nada disto — e se calculasse, divergiria.
    """
    objs = objetos(raiz)
    esp = especies(objs)
    if especie not in esp:
        return {"erro": "especie desconhecida: %s" % especie,
                "conhecidas": sorted(esp)}
    nomes, linhas, faltando = esp[especie]["campos"], [], []
    rel = relacoes(objs)
    for n in nomes:
        v = (valores.get(n) or "").strip()
        if not v:
            if n == "tipo":
                v = especie
            elif n == "licenca":
                # O PADRAO NAO CONCEDE DIREITO. `reservado` e' ausencia
                # deliberada de licenca: a interface nunca outorga por descuido.
                v = "reservado"
            else:
                faltando.append(n)
                continue
        linhas.append("%s: %s" % (n, unicodedata.normalize("NFC", v)))
    texto = "".join(l + "\n" for l in linhas)
    b = texto.encode("utf-8")
    end = hashlib.sha256(b).hexdigest()
    return {"especie": especie, "texto": texto, "endereco": end, "bytes": len(b),
            "faltando": faltando, "ordem": nomes, "ja_existe": end in por_endereco(objs),
            "licenca_exigida": esp[especie]["licenca_exigida"],
            "avisos": _avisos(esp[especie], valores, rel)}


def _avisos(e, valores, rel):
    """O que a interface precisa DIZER antes de gravar — nao esconder."""
    fora = []
    lic = (valores.get("licenca") or "").strip()
    ex = e["licenca_exigida"]
    if ex == "sem_licenca" and lic:
        fora.append("esta especie NAO carrega campo `licenca` — remova-o")
    if ex == "livre" and lic and lic != "reservado" and not HEX.match(lic):
        fora.append("`livre` exige o ENDERECO de uma licenca (64 hex), nao um rotulo")
    if ex == "livre_ou_reservado" and lic and not HEX.match(lic) and lic != "reservado":
        fora.append("aceita o endereco de uma licenca, ou o estado `reservado`")
    for n in e["campos"]:
        v = (valores.get(n) or "").strip()
        if v and rel.get(n, "nenhuma") != "nenhuma" and not HEX.match(v):
            fora.append("`%s` carrega um ENDERECO (64 hex) — recebeu %r" % (n, v[:24]))
    return fora


def recorte(raiz, nome):
    """A META-JANELA-MODULAR, montada e DITA. Nada e' enviado; nada e' gravado."""
    objs = objetos(raiz)
    por_id = por_endereco(objs)
    sig = sigilo_dos_caminhos(objs)
    alvo = [a for a in agentes(raiz) if a["nome"] == nome]
    if not alvo:
        return None
    a = alvo[0]
    pedacos = []

    def juntar(rotulo, end, origem):
        if not end:
            return
        o = por_id.get(end)
        if o is None:
            pedacos.append({"rotulo": rotulo, "endereco": end, "presente": False,
                            "aviso": "apontado e AUSENTE do ambito — texto pendurado"})
            return
        lic = o["campos"].get("licenca")
        if lic and len(lic) == 64 and lic in por_id:
            lic = "%s (sigilo: %s)" % (lic[:12], por_id[lic]["campos"].get("sigilo", "?"))
        pedacos.append({"rotulo": rotulo, "endereco": end, "presente": True,
                        "conteudo_declara": bool(o["campos"].get("conteudo")),
                        "licenca": lic or "(sem campo licenca)",
                        "bytes": o["bytes"], "origem": origem,
                        "procedencia": o["procedencia"],
                        "morada": sig.get(o["caminho_rel"], {}).get("sigilo", "NAO DECLARADO")})

    juntar("agente: papel", a["endereco"], "agente")
    if a.get("texto"):
        juntar("agente: convencao", a["texto"], "texto do agente")
    for o in objs:
        if o["tipo"] == "proposito":
            juntar("camada: %s" % o["nome"], o["campos"].get("texto", ""), "proposito")
    privados = [p for p in pedacos if p.get("morada") == "privado"]
    ausentes = [p for p in pedacos if not p.get("presente")]
    sem_sig = [p for p in pedacos if p.get("morada") == "NAO DECLARADO"]
    return {"ambito": raiz, "agente": a, "pedacos": pedacos,
            "contagem": {"pedacos": len(pedacos),
                         "bytes": sum(p.get("bytes", 0) for p in pedacos)},
            "LEI DO RECIPIENTE": {
                "destino_externo_declarado": False,
                "nota": ("NENHUMA bolha deste ambito declara destino externo. Se este recorte "
                         "for enviado a um recipiente de fora, sai sem lei que olhe para isso."),
                "de_morada_privada": [p["rotulo"] for p in privados],
                "de_morada_nao_declarada": [p["rotulo"] for p in sem_sig],
                "apontados_e_ausentes": [p["rotulo"] for p in ausentes]}}


def agentes(raiz):
    return [{"endereco": o["endereco"], "nome": o["campos"].get("nome"),
             "papel": o["campos"].get("papel"), "texto": o["campos"].get("texto")}
            for o in objetos(raiz) if o["tipo"] == "agente"]


class Mao(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    # --- respostas -------------------------------------------------------
    def bruto(self, codigo, tipo, corpo):
        if isinstance(corpo, str):
            corpo = corpo.encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(corpo)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(corpo)

    def responder(self, dado, codigo=200):
        self.bruto(codigo, "application/json; charset=utf-8",
                   json.dumps(dado, ensure_ascii=False, indent=2))

    def corpo(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(n).decode("utf-8")) if n else {}
        except Exception:
            return {}

    def corpo_bytes(self):
        """CORPO CRU, sem decodificar — e' por aqui que a midia entra."""
        try:
            n = int(self.headers.get("Content-Length") or 0)
            return self.rfile.read(n) if n else b""
        except Exception:
            return b""

    # --- leitura ---------------------------------------------------------
    def do_GET(self):
        p = urlparse(self.path).path
        A = ambitos()

        # A PAGINA. Servida na raiz, com o retrato ja' embutido no lugar do
        # marcador — assim ela abre mesmo sem servidor de dados.
        if p in ("/", "/index.html"):
            padrao = os.environ.get("IL_AMBITO_PADRAO") or (list(A)[0] if A else None)
            if padrao is None:
                return self.responder({"erro": "nenhum ambito; defina IL_AMBITOS"}, 400)
            try:
                with open(os.path.join(AQUI, "pagina.html"), encoding="utf-8") as fh:
                    html = fh.read()
            except OSError:
                return self.responder({"erro": "pagina.html nao encontrada"}, 404)
            html = html.replace("__SNAPSHOT__",
                                json.dumps(retrato(A[padrao]), ensure_ascii=False))
            return self.bruto(200, "text/html; charset=utf-8", html)

        if p == "/api/eventos":
            return self.sse(A)

        if p.startswith("/api/"):
            padrao = os.environ.get("IL_AMBITO_PADRAO") or (list(A)[0] if A else None)
            if padrao is None:
                return self.responder({"erro": "nenhum ambito"}, 400)
            return self.rota(A[padrao], p[len("/api/"):].split("/"))

        partes = [x for x in p.split("/") if x]
        if not partes:
            return self.responder({"servidor": "le' o deposito, nao refaz conta",
                                   "ambitos": A,
                                   "rotas": ["/<ambito>/estado", "/<ambito>/retrato",
                                             "/<ambito>/formulario", "/<ambito>/grafo",
                                             "/<ambito>/bytes/<e>", "/<ambito>/objeto/<e>",
                                             "/<ambito>/recorte/<agente>",
                                             "/<ambito>/compor (POST)"]})
        amb = partes[0]
        if amb not in A:
            return self.responder({"erro": "ambito desconhecido", "ambito": amb,
                                   "conhecidos": list(A)}, 404)
        return self.rota(A[amb], partes[1:])

    def rota(self, raiz, resto):
        if not resto:
            # QUEM, nao so' ONDE. O nome vem da volta da tabela do ambiente; a
            # declaracao vem da bolha. `declarado: False` e' achado, nao falha:
            # significa que este ambito existe so' no ambiente.
            _nome = nomeDoAmbito(raiz)
            _dec = declaracaoDoAmbito(raiz, _nome)
            return self.responder({"ambito": raiz, "ambito_nome": _nome,
                                   "declarado": _dec is not None,
                                   "declaracao": _dec,
                                   "rotas": ["estado", "diagnostico", "formulario", "grafo", "painel[/tempo|peso|forma|alcance|licencas]",
                                             "bytes/<e>", "objeto/<e>", "agentes",
                                             "recorte/<agente>", "verificar", "alertas",
                                             "compor (POST)"]})
        verbo, args = resto[0], resto[1:]
        try:
            if verbo == "alertas" and not args:
                # A QUINTA PRIMA. O alertas e' a REGUA do itinerario, e a conta
                # inteira ja' esta' feita no cli. Esta rota NAO refaz nada: roda
                # o MESMO programa e devolve o que ele mediu — fonte unica, e a
                # tela desenha em vez de recalcular. (O cli devolve 1 quando ha'
                # alerta ALTO, e isso e' resposta valida, nao erro.)
                import subprocess as _sp
                r = _sp.run([sys.executable, os.path.join(raiz, "cli", "alertas"), "--json"],
                            capture_output=True, text=True, timeout=90,
                            env=dict(os.environ, IL_RAIZ=raiz))
                if r.returncode not in (0, 1) or not r.stdout.strip():
                    return self.responder({"erro": "o cli/alertas nao devolveu dado",
                                           "codigo": r.returncode,
                                           "detalhe": (r.stderr or "")[-300:]}, 500)
                d = json.loads(r.stdout)
                d["ambito"] = raiz
                return self.responder(d)
            if verbo == "estado" and not args:
                # A MESMA FORMA QUE A TELA DESENHA. Antes devolvia `estado()`,
                # de forma diferente, e o render morria em `caminhos.forEach`.
                return self.responder(retrato(raiz))
            if verbo == "diagnostico" and not args:
                return self.responder(estado(raiz))
            if verbo == "retrato" and not args:
                return self.responder(retrato(raiz))
            if verbo == "agentes" and not args:
                return self.responder({"ambito": raiz, "agentes": agentes(raiz)})
            if verbo == "verificar" and not args:
                return self.responder(verificar(raiz))
            if verbo == "formulario":
                objs = objetos(raiz)
                f = formulario(objs)
                if not args:
                    return self.responder({"ambito": raiz, "especies": f,
                                           "como_ler": ("`aponta: true` marca o campo que "
                                                        "carrega o ENDERECO de outro objeto — "
                                                        "e' onde a tela poe seletor, nao texto.")})
                if args[0] not in f:
                    return self.responder({"erro": "especie desconhecida", "especie": args[0],
                                           "conhecidas": sorted(f)}, 404)
                return self.responder({"ambito": raiz, "especie": args[0], "forma": f[args[0]]})
            if verbo == "midias" and not args:
                return self.responder(midias(raiz))
            if verbo == "grafo" and not args:
                return self.responder(grafo(raiz))
            if verbo == "painel":
                objs = objetos(raiz)
                g = alcance(objs)
                if not args:
                    return self.responder(paineis.tudo(raiz, objs, g))
                if args[0] not in ("tempo", "peso", "forma", "alcance", "licencas"):
                    return self.responder({"erro": "painel desconhecido",
                                           "pedido": args[0],
                                           "conhecidos": ["tempo", "peso", "forma", "alcance", "licencas"]}, 404)
                f = {"tempo":    lambda: paineis.tempo(raiz, objs),
                     "peso":     lambda: paineis.peso(objs),
                     "forma":    lambda: paineis.forma(objs),
                     "alcance":  lambda: paineis.alcance(objs, g),
                     "licencas": lambda: paineis.licencas(raiz, objs)}[args[0]]
                return self.responder({"ambito": raiz, "painel": args[0], "dados": f()})
            if verbo == "objeto" and len(args) == 1:
                o = self._achar(raiz, args[0])
                if o is None:
                    return self.responder({"erro": "objeto nao esta' neste ambito",
                                           "pedido": args[0]}, 404)
                return self.responder({"ambito": raiz, "objeto": o})
            if verbo == "bytes" and len(args) == 1:
                # OS BYTES CRUS. Sem esta rota a midia morre na leitura.
                o = self._achar(raiz, args[0])
                if o is None:
                    return self.responder({"erro": "objeto nao esta' neste ambito",
                                           "pedido": args[0]}, 404)
                b = ler_bytes(os.path.join(raiz, o["caminho_rel"], o["endereco"]))
                if b is None:
                    return self.responder({"erro": "nao consegui ler os bytes"}, 500)
                return self.bruto(200, mime_de(b), b)
            if verbo == "recorte" and len(args) == 1:
                r = recorte(raiz, args[0])
                if r is None:
                    return self.responder({"erro": "agente nao esta' neste ambito",
                                           "disponiveis": [a["nome"] for a in agentes(raiz)]}, 404)
                return self.responder(r)
        except Exception as ex:
            return self.responder({"erro": "falha ao ler", "detalhe": str(ex)}, 500)
        return self.responder({"erro": "rota desconhecida", "pedido": self.path}, 404)

    def _achar(self, raiz, e):
        return liga(objetos(raiz), e.strip().lower())

    # --- escrita (compor NAO grava: devolve o endereco) -------------------
    def do_POST(self):
        p = urlparse(self.path).path
        A = ambitos()
        alvo = None
        if p.startswith("/api/"):
            padrao = os.environ.get("IL_AMBITO_PADRAO") or (list(A)[0] if A else None)
            alvo, resto = (A.get(padrao), p[len("/api/"):].split("/")) if padrao else (None, [])
        else:
            partes = [x for x in p.split("/") if x]
            alvo, resto = (A.get(partes[0]), partes[1:]) if partes else (None, [])
        if alvo is None:
            return self.responder({"erro": "ambito desconhecido"}, 404)
        if resto and resto[0] == "sugerir":
            b = self.corpo()
            return self.responder(sugerir(alvo, b.get("enderecos") or [],
                                          b.get("parcial") or ""))
        if resto and resto[0] == "listar":
            b = self.corpo()
            return self.responder(criarLista(alvo, b.get("nome") or "",
                                             b.get("enderecos") or []))
        if resto and resto[0] == "apontar":
            b = self.corpo()
            return self.responder(apontar(alvo, (b.get("objeto") or "").strip()))
        if resto and resto[0] == "registrar":
            b = self.corpo()
            lic = (b.get("licenca") or "").strip()
            if (b.get("selo_de_modelo") or "").strip():
                lic = licencaDoModelo(alvo, (b.get("modelo") or "").strip() or None) or ""
            return self.responder(registrar(alvo, b.get("texto") or "",
                                            (b.get("papel") or "pergunta").strip(), lic))
        if resto and resto[0] == "verificar":
            b = self.corpo()
            return self.responder(lancarCadeia(alvo, (b.get("etapa") or "tudo").strip()))
        if resto and resto[0] == "chat":
            b = self.corpo()
            return self.responder(conversar(alvo, (b.get("q") or "").strip(),
                                            b.get("modo") or "acervo",
                                            (b.get("janela") or "").strip() or None))
        if resto and resto[0] == "gravar":
            return self.responder(gravar(alvo, self.corpo_bytes()))
        b = self.corpo()
        if resto and resto[0] == "compor":
            return self.responder(compor(alvo, b.get("especie", ""), b.get("valores") or {}))
        return self.responder({"erro": "rota desconhecida", "pedido": self.path}, 404)

    def sse(self, A):
        """O fluxo que avisa quando o acervo muda — pela ASSINATURA, nao pelo relogio."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        padrao = os.environ.get("IL_AMBITO_PADRAO") or (list(A)[0] if A else None)
        ultimo, fim = None, time.time() + 3600
        try:
            while time.time() < fim:
                if padrao:
                    d = retrato(A[padrao])
                    atual = d["assinatura"]
                else:
                    d, atual = {}, "?"
                if atual != ultimo:
                    mudou, ultimo = ultimo is not None, atual
                    self.wfile.write(("data: %s\n\n" % json.dumps(
                        dict(d, mudou=mudou), ensure_ascii=False)).encode())
                    self.wfile.flush()
                time.sleep(2)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    A = ambitos()
    porta = int(os.environ.get("IL_PORTA") or os.environ.get("BOLHA_PORT") or
                (sys.argv[1] if len(sys.argv) > 1 else "8791"))
    if not A:
        print("defina IL_AMBITOS, ex: IL_AMBITOS=il=/root/il-prototipo-lean,ilts=/root/ilts",
              file=sys.stderr)
        sys.exit(2)
    print("servidor em http://127.0.0.1:%d — ambitos: %s" % (porta, ", ".join(A)),
          file=sys.stderr)
    ThreadingHTTPServer(("127.0.0.1", porta), Mao).serve_forever()
