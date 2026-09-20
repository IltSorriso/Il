#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
servidor.py - a janela de contexto do acervo de bolhas (Il / IltS)

A forma das especies e lida DO PROPRIO DADO (bolhas de tipo 'especie' e 'campo'),
nunca de uma tabela propria deste programa. Se o dado mudar, a janela muda.

  GET  /                  a pagina (painel + conversa + compor)
  GET  /api/estado        retrato do acervo, com assinatura (tempo real)
  GET  /api/objeto/<hex>  o texto cru de um objeto
  POST /api/compor        compoe a partir da especie e devolve o ENDERECO
  POST /api/chat          responde sobre o acervo
  GET  /api/eventos       fluxo SSE: avisa quando o acervo muda

Variaveis: BOLHA_RAIZ, BOLHA_DEPOSITOS (':' separa), BOLHA_PORT
"""
import os, re, json, time, hashlib, unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RAIZ = os.path.abspath(os.environ.get("BOLHA_RAIZ", os.getcwd()))
DEPOSITOS = [d for d in os.environ.get(
    "BOLHA_DEPOSITOS", "exemplos/deposito/objetos:deposito/objetos").split(":") if d]
PORT = int(os.environ.get("BOLHA_PORT", "8787"))
AQUI = os.path.dirname(os.path.abspath(__file__))
LINHA = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):[ ]?(.*)$")
HEX = re.compile(r"^[0-9a-f]{64}$")

AJUDA = (
    "Consultas que eu entendo (todas medidas no acervo, nenhuma inventada):\n"
    "  quantos            - o tamanho do acervo, por especie e por deposito\n"
    "  especies           - as especies declaradas em bolha\n"
    "  campos <especie>   - os campos da especie, na ordem canonica, com a relacao\n"
    "  mostra <hex>       - o texto cru de um objeto (basta o comeco do endereco)\n"
    "  procura <texto>    - em quais objetos este texto aparece\n"
    "  aponta <hex>       - quem aponta para este endereco (referencia reversa)\n"
    "  prazos             - as declaracoes, com o prazo e os dias que faltam\n"
    "  ramos              - os ramos declarados, e quantas declaracoes cada um tem\n"
    "  caminhos           - os depositos que o acervo declara a si mesmo\n"
    "  licencas           - a distribuicao das licencas\n"
    "  itinerario         - as secoes do itinerario e onde ele mora\n"
    "  ajuda              - isto\n"
    "Nao sou um modelo de linguagem: sou um interpretador de consultas sobre as bolhas."
)


def achar(rel):
    return rel if os.path.isabs(rel) else os.path.join(RAIZ, rel)


def ler_acervo():
    objs = {}
    for rel in DEPOSITOS:
        d = achar(rel)
        if not os.path.isdir(d):
            continue
        for nome in sorted(os.listdir(d)):
            if len(nome) != 64:
                continue
            p = os.path.join(d, nome)
            if not os.path.isfile(p):
                continue
            try:
                with open(p, "rb") as fh:
                    b = fh.read()
            except OSError:
                continue
            t = b.decode("utf-8", "replace")
            campos, ordem = {}, []
            for ln in t.split("\n"):
                m = LINHA.match(ln)
                if m and m.group(1) not in campos:
                    campos[m.group(1)] = m.group(2)
                    ordem.append(m.group(1))
            objs[nome] = {"nome": nome, "deposito": rel, "texto": t,
                          "campos": campos, "ordem": ordem, "bytes": len(b),
                          "mtime": int(os.path.getmtime(p)),
                          "especie": campos.get("tipo") or "conteudo"}
    return objs


def especies(objs):
    saida = {}
    for o in objs.values():
        if o["especie"] != "especie":
            continue
        nomes = []
        for h in o["campos"].get("campos", "").split(","):
            h = h.strip()
            if not h:
                continue
            alvo = objs.get(h)
            nomes.append(alvo["campos"].get("nome", h[:12]) if alvo else h[:12])
        saida[o["campos"].get("nome", o["nome"][:12])] = {
            "objeto": o["nome"], "campos": nomes,
            "conteudo": o["campos"].get("conteudo", ""),
            "licenca_exigida": o["campos"].get("licenca_exigida", ""),
            "licenca": o["campos"].get("licenca", ""),
        }
    return saida


def relacoes(objs):
    r = {}
    for o in objs.values():
        if o["especie"] == "campo":
            r[o["campos"].get("nome", "?")] = o["campos"].get("relacao", "nenhuma")
    return r


def assinatura(objs):
    m = max([o["mtime"] for o in objs.values()] or [0])
    s = "%d|%d|%d" % (len(objs), sum(o["bytes"] for o in objs.values()), m)
    return hashlib.sha256(s.encode()).hexdigest()[:16]


def achar_itinerario(objs):
    alvo = None
    for o in objs.values():
        if o["especie"] != "conteudo":
            continue
        if "ITINER" in o["texto"][:4000].upper():
            if alvo is None or o["bytes"] > alvo["bytes"]:
                alvo = o
    if alvo is None:
        return None
    secoes = []
    for i, ln in enumerate(alvo["texto"].split("\n")):
        m = re.match(r"^(#+)[ ]*(.*)$", ln)
        if m:
            secoes.append({"nivel": len(m.group(1)), "titulo": m.group(2), "linha": i + 1})
    return {"endereco": alvo["nome"], "bytes": alvo["bytes"], "deposito": alvo["deposito"],
            "secoes": secoes,
            "apontado_por": [x["nome"] for x in objs.values()
                             if x["campos"].get("conteudo") == alvo["nome"]]}


def retrato():
    objs = ler_acervo()
    esp = especies(objs)
    hoje = time.strftime("%Y-%m-%d")
    por_especie, por_deposito, licencas = {}, {}, {}
    declaracoes, caminhos = [], []
    for o in objs.values():
        c, e = o["campos"], o["especie"]
        por_especie[e] = por_especie.get(e, 0) + 1
        por_deposito[o["deposito"]] = por_deposito.get(o["deposito"], 0) + 1
        if c.get("licenca"):
            k = c["licenca"] if HEX.match(c["licenca"]) else "reservado"
            licencas[k] = licencas.get(k, 0) + 1
        if e == "declaracao":
            p, dias = c.get("prazo", ""), None
            try:
                dias = int(round((time.mktime(time.strptime(p, "%Y-%m-%d"))
                                  - time.mktime(time.strptime(hoje, "%Y-%m-%d"))) / 86400.0))
            except ValueError:
                pass
            declaracoes.append({"objeto": o["nome"], "ramo": c.get("ramo", ""),
                                "prazo": p, "dias": dias, "texto": c.get("texto", ""),
                                "licenca": c.get("licenca", ""), "deposito": o["deposito"]})
        elif e == "caminho":
            caminhos.append({"objeto": o["nome"], "nome": c.get("nome", ""),
                             "padrao": c.get("padrao", ""), "sigilo": c.get("sigilo"),
                             "licenca": c.get("licenca", "")})
    declaracoes.sort(key=lambda d: (d["prazo"] or "9999-99-99"))
    return {"assinatura": assinatura(objs), "quando": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "total": len(objs), "bytes": sum(o["bytes"] for o in objs.values()),
            "por_especie": por_especie, "por_deposito": por_deposito,
            "declaracoes": declaracoes, "caminhos": caminhos, "licencas": licencas,
            "especies": {k: v["campos"] for k, v in sorted(esp.items())},
            "relacoes": relacoes(objs), "itinerario": achar_itinerario(objs),
            "raiz": RAIZ, "depositos": DEPOSITOS}


def compor(objs, especie, valores):
    esp = especies(objs)
    if especie not in esp:
        return {"erro": "especie desconhecida: %s" % especie}
    nomes, linhas, faltando = esp[especie]["campos"], [], []
    for n in nomes:
        v = (valores.get(n) or "").strip()
        if not v:
            if n == "tipo":
                v = especie
            elif n == "licenca":
                v = "reservado"
            else:
                faltando.append(n)
                continue
        linhas.append("%s: %s" % (n, unicodedata.normalize("NFC", v)))
    texto = "".join(l + "\n" for l in linhas)
    b = texto.encode("utf-8")
    end = hashlib.sha256(b).hexdigest()
    return {"especie": especie, "texto": texto, "endereco": end, "bytes": len(b),
            "faltando": faltando, "ordem": nomes, "ja_existe": end in objs,
            "licenca_exigida": esp[especie]["licenca_exigida"],
            "permitido": esp[especie]["licenca_exigida"] == "sem_licenca"}


def responder(objs, q):
    ql = (q or "").strip().lower()
    if not ql or ql in ("ajuda", "help", "?"):
        return AJUDA
    if ql.startswith("quantos"):
        r = retrato()
        l = ["acervo: %d objetos, %d bytes" % (r["total"], r["bytes"]), "por deposito:"]
        l += ["  %-32s %3d" % (k, v) for k, v in sorted(r["por_deposito"].items())]
        l.append("por especie:")
        l += ["  %-28s %3d" % (k, v) for k, v in sorted(r["por_especie"].items(),
                                                         key=lambda x: -x[1])]
        return "\n".join(l)
    if ql.startswith("especie"):
        esp = especies(objs)
        l = ["%d especies declaradas em bolha:" % len(esp)]
        for k, v in sorted(esp.items()):
            l.append("  %-14s %2d campos · conteudo: %-9s · exige: %s"
                     % (k, len(v["campos"]), v["conteudo"] or "nenhum", v["licenca_exigida"]))
        return "\n".join(l)
    if ql.startswith("campos"):
        nome = ql.split(None, 1)[1].strip() if len(ql.split(None, 1)) > 1 else ""
        esp, rel = especies(objs), relacoes(objs)
        if nome not in esp:
            return "nao ha especie '%s'. Ha: %s" % (nome, ", ".join(sorted(esp)))
        l = ["especie %s - campos na ordem canonica:" % nome]
        for c in esp[nome]["campos"]:
            l.append("  %-16s relacao: %s" % (c, rel.get(c, "?")))
        l.append("conteudo: %s · licenca_exigida: %s"
                 % (esp[nome]["conteudo"] or "nenhum", esp[nome]["licenca_exigida"]))
        return "\n".join(l)
    if ql.startswith("mostra"):
        p = ql.split(None, 1)[1].strip() if len(ql.split(None, 1)) > 1 else ""
        alvos = [o for n, o in objs.items() if n.startswith(p)]
        if not alvos:
            return "nenhum objeto comeca com '%s'" % p
        o = alvos[0]
        return ("--- %s (%d bytes, em %s)\n%s" % (o["nome"], o["bytes"], o["deposito"], o["texto"]))
    if ql.startswith("procura"):
        t = (q or "").split(None, 1)[1].strip() if len(q.split(None, 1)) > 1 else ""
        if not t:
            return "procura o que? ex: procura ITINERARIO"
        achados = [o for o in objs.values() if t.lower() in o["texto"].lower()]
        if not achados:
            return "'%s' nao aparece em nenhum objeto" % t
        l = ["'%s' aparece em %d objeto(s):" % (t, len(achados))]
        for o in achados[:25]:
            l.append("  %s  %-12s %6d B  %s"
                     % (o["nome"][:12], o["especie"], o["bytes"], o["deposito"]))
        return "\n".join(l)
    if ql.startswith("aponta"):
        p = ql.split(None, 1)[1].strip() if len(ql.split(None, 1)) > 1 else ""
        achados = [o for o in objs.values()
                   if any(v.startswith(p) for v in o["campos"].values() if HEX.match(v))]
        if not achados:
            return "ninguem aponta para '%s'" % p
        l = ["quem aponta para '%s' (%d):" % (p, len(achados))]
        for o in achados[:25]:
            campo = [k for k, v in o["campos"].items() if v.startswith(p)]
            l.append("  %s  %-12s pelo campo '%s'" % (o["nome"][:12], o["especie"], campo[0]))
        return "\n".join(l)
    if ql.startswith("prazo") or ql.startswith("declara"):
        r = retrato()
        if not r["declaracoes"]:
            return "nenhuma declaracao no acervo lido."
        l = ["%d declaracoes, por prazo:" % len(r["declaracoes"])]
        for d in r["declaracoes"]:
            x = "sem prazo" if d["dias"] is None else "%d dia(s)" % d["dias"]
            l.append("  %s  %-42s %s  (%s)  %s"
                     % (d["objeto"][:12], d["ramo"], d["prazo"], x, d["deposito"]))
        return "\n".join(l)
    if ql.startswith("ramo"):
        r = retrato()
        ramos = {}
        for d in r["declaracoes"]:
            ramos.setdefault(d["ramo"], []).append(d["prazo"])
        if not ramos:
            return "nenhum ramo declarado em bolha."
        l = ["ramos com declaracao (%d):" % len(ramos)]
        for k, v in sorted(ramos.items()):
            l.append("  %-44s prazo %s" % (k, ", ".join(sorted(v))))
        return "\n".join(l)
    if ql.startswith("caminho"):
        r = retrato()
        if not r["caminhos"]:
            return "o acervo nao declara caminho nenhum."
        l = ["depositos que o acervo declara:"]
        for c in r["caminhos"]:
            l.append("  %-12s padrao: %-28s sigilo: %s"
                     % (c["nome"], c["padrao"], c["sigilo"] if c["sigilo"] else "(campo nao existe)"))
        return "\n".join(l)
    if ql.startswith("licenca"):
        r = retrato()
        l = ["distribuicao das licencas (%d objetos com licenca):" % sum(r["licencas"].values())]
        for k, v in sorted(r["licencas"].items(), key=lambda x: -x[1]):
            l.append("  %-16s %3d" % (k[:12] if len(k) == 64 else k, v))
        return "\n".join(l)
    if ql.startswith("itiner"):
        it = achar_itinerario(objs)
        if not it:
            return "nao achei um itinerario no acervo lido."
        l = ["itinerario: %s (%d bytes, em %s)" % (it["endereco"], it["bytes"], it["deposito"]),
             "apontado por: %d objeto(s)" % len(it["apontado_por"]),
             "%d secoes:" % len(it["secoes"])]
        for s in it["secoes"]:
            l.append("  %s%s" % (("  " * (s["nivel"] - 1)), s["titulo"]))
        return "\n".join(l)
    return ("nao entendi '%s'.\n\n" % q) + AJUDA


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _envia(self, code, ctype, corpo):
        if isinstance(corpo, str):
            corpo = corpo.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(corpo)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(corpo)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, obj, code=200):
        self._envia(code, "application/json; charset=utf-8",
                    json.dumps(obj, ensure_ascii=False))

    def _corpo(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        if n <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}

    def do_GET(self):
        p = urlparse_path(self.path)
        if p == "/" or p == "/index.html":
            with open(os.path.join(AQUI, "pagina.html"), "r", encoding="utf-8") as fh:
                html = fh.read()
            html = html.replace("__SNAPSHOT__",
                                json.dumps(retrato(), ensure_ascii=False))
            self._envia(200, "text/html; charset=utf-8", html)
        elif p == "/api/estado":
            self._json(retrato())
        elif p.startswith("/api/objeto/"):
            h = p[len("/api/objeto/"):].strip().lower()
            objs = ler_acervo()
            alvos = [o for n, o in objs.items() if n.startswith(h)]
            if not alvos:
                self._json({"erro": "nao achei objeto comecando com " + h}, 404)
            else:
                self._envia(200, "text/plain; charset=utf-8", alvos[0]["texto"])
        elif p == "/api/eventos":
            self._sse()
        else:
            self._json({"erro": "rota desconhecida", "rota": p}, 404)

    def do_POST(self):
        p = urlparse_path(self.path)
        b = self._corpo()
        if p == "/api/chat":
            self._json({"resposta": responder(ler_acervo(), b.get("q", ""))})
        elif p == "/api/compor":
            self._json(compor(ler_acervo(), b.get("especie", ""), b.get("valores") or {}))
        else:
            self._json({"erro": "rota desconhecida", "rota": p}, 404)

    def _sse(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        ultimo = None
        fim = time.time() + 3600
        try:
            while time.time() < fim:
                r = retrato()
                if r["assinatura"] != ultimo:
                    r["mudou"] = ultimo is not None
                    ultimo = r["assinatura"]
                    self.wfile.write(("data: " + json.dumps(r, ensure_ascii=False)
                                      + "\n\n").encode("utf-8"))
                else:
                    self.wfile.write(b": batida\n\n")
                self.wfile.flush()
                time.sleep(2)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass


def urlparse_path(caminho):
    return caminho.split("?")[0]


if __name__ == "__main__":
    print("janela de contexto do acervo")
    print("  raiz:      %s" % RAIZ)
    for d in DEPOSITOS:
        print("  deposito:  %s%s" % (achar(d), "" if os.path.isdir(achar(d)) else "   (NAO EXISTE)"))
    r = retrato()
    print("  %d objetos, %d bytes, assinatura %s" % (r["total"], r["bytes"], r["assinatura"]))
    print("  http://127.0.0.1:%d/" % PORT)
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
