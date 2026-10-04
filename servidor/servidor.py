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
import hashlib, json, os, re, sys, time, unicodedata
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
    return {"ambito": raiz, "quando": time.strftime("%Y-%m-%dT%H:%M:%S"),
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
            return self.responder({"ambito": raiz,
                                   "rotas": ["estado", "diagnostico", "formulario", "grafo", "painel[/tempo|peso|forma|alcance]",
                                             "bytes/<e>", "objeto/<e>", "agentes",
                                             "recorte/<agente>", "compor (POST)"]})
        verbo, args = resto[0], resto[1:]
        try:
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
            if verbo == "grafo" and not args:
                return self.responder(grafo(raiz))
            if verbo == "painel":
                objs = objetos(raiz)
                g = alcance(objs)
                if not args:
                    return self.responder(paineis.tudo(raiz, objs, g))
                if args[0] not in ("tempo", "peso", "forma", "alcance"):
                    return self.responder({"erro": "painel desconhecido",
                                           "pedido": args[0],
                                           "conhecidos": ["tempo", "peso", "forma", "alcance"]}, 404)
                f = {"tempo":   lambda: paineis.tempo(raiz, objs),
                     "peso":    lambda: paineis.peso(objs),
                     "forma":   lambda: paineis.forma(objs),
                     "alcance": lambda: paineis.alcance(objs, g)}[args[0]]
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
                return self.bruto(200, "application/octet-stream", b)
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
