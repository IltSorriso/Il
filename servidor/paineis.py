"""paineis — os quatro quadros: tempo, peso, forma, alcance.

REGRA QUE OS QUATRO SEGUEM: nenhum guarda estado. Todos sao SAIDA, calculada
na hora — do deposito, e no caso do tempo tambem do proprio git. E' por isso
que nenhum deles apodrece: nao ha copia para divergir.
"""
import os
import re
import subprocess
import time
from collections import defaultdict

HEX = re.compile(r"[0-9a-f]{64}")


# ---------------------------------------------------------------- FORMA
def forma(objs):
    """A forma do vocabulario: as especies e os campos que cada uma carrega.

    Confere tambem o que o juiz confere do outro lado: todo endereco declarado
    em `campos:` RESOLVE para um objeto de especie `campo`? Endereco declarado
    que nao resolve e' vocabulario quebrado, e o painel diz em voz alta.
    """
    campos = {}
    for o in objs:
        if o["tipo"] == "campo":
            c = o["campos"]
            campos[o["endereco"]] = {"nome": c.get("nome", "?"),
                                     "relacao": c.get("relacao", "?"),
                                     "bytes": o["bytes"]}
    usados, especies, faltando = defaultdict(list), [], []
    for o in objs:
        if o["tipo"] != "especie":
            continue
        c = o["campos"]
        lista = []
        for end in [x.strip() for x in c.get("campos", "").split(",") if x.strip()]:
            f = campos.get(end)
            if f is None:
                faltando.append({"especie": c.get("nome"), "endereco": end})
                lista.append({"endereco": end, "nome": "?", "relacao": "?",
                              "aponta": False, "existe": False})
                continue
            usados[f["nome"]].append(c.get("nome"))
            lista.append({"endereco": end, "nome": f["nome"], "relacao": f["relacao"],
                          "aponta": f["relacao"] != "nenhuma", "existe": True})
        especies.append({"especie": c.get("nome"), "endereco": o["endereco"],
                         "conteudo": c.get("conteudo"),
                         "licenca_exigida": c.get("licenca_exigida"),
                         "campos": lista})
    especies.sort(key=lambda e: e["especie"] or "")
    alcancados = set()
    for o in objs:
        if o["tipo"] == "especie":
            for end in [x.strip() for x in o["campos"].get("campos", "").split(",") if x.strip()]:
                alcancados.add(end)
    orfaos = [{"endereco": e, "nome": c["nome"], "relacao": c["relacao"]}
              for e, c in sorted(campos.items()) if e not in alcancados]
    return {
        "especies": especies,
        "contagem": {"especies": len(especies), "campos": len(campos),
                     "campos_usados": len(usados), "campos_orfaos": len(orfaos)},
        "campos_orfaos": orfaos,
        "campos_mais_reusados": [{"nome": n, "em": len(v), "especies": sorted(set(v))}
                                 for n, v in sorted(usados.items(),
                                                    key=lambda kv: -len(kv[1]))[:8]
                                 if len(v) > 1],
        "enderecos_que_nao_resolvem": faltando,
        "como_ler": ("`aponta: true` = o campo carrega o ENDERECO de outro objeto, "
                     "e' onde a tela poe seletor em vez de texto. "
                     "`existe: false` = vocabulario quebrado."),
    }


# ----------------------------------------------------------------- PESO
LIMIAR_ARVORE = 8192  # o modo-arvore de um resumo em arvore so' engata daqui


def peso(objs):
    """Bytes por especie, e o limiar que decide se um resumo em arvore faria algo."""
    por, faixas = {}, {"<64": 0, "64-255": 0, "256-1023": 0, "1K-8K": 0, ">=8K": 0}
    for o in objs:
        k = o["tipo"] or "(conteudo)"
        d = por.setdefault(k, {"objetos": 0, "bytes": 0, "maior": 0})
        d["objetos"] += 1
        d["bytes"] += o["bytes"]
        d["maior"] = max(d["maior"], o["bytes"])
        b = o["bytes"]
        faixas["<64" if b < 64 else "64-255" if b < 256 else "256-1023" if b < 1024
               else "1K-8K" if b < LIMIAR_ARVORE else ">=8K"] += 1
    total = sum(o["bytes"] for o in objs)
    for k, d in por.items():
        d["media"] = round(d["bytes"] / d["objetos"], 1) if d["objetos"] else 0
    lista = sorted([{"especie": k, **v} for k, v in por.items()],
                   key=lambda x: -x["bytes"])
    maior = max(objs, key=lambda o: o["bytes"]) if objs else None
    return {
        "por_especie": lista,
        "faixas": faixas,
        "total": {"objetos": len(objs), "bytes": total,
                  "media": round(total / len(objs), 1) if objs else 0},
        "maior": {"endereco": maior["endereco"], "tipo": maior["tipo"] or "(conteudo)",
                  "bytes": maior["bytes"], "nome": maior["nome"]} if maior else None,
        "limiar_arvore": LIMIAR_ARVORE,
        "acima_do_limiar": sum(1 for o in objs if o["bytes"] >= LIMIAR_ARVORE),
        "como_ler": (f"todo objeto abaixo de {LIMIAR_ARVORE} bytes: um resumo em arvore "
                     "nunca engataria nestes dados."),
    }


# -------------------------------------------------------------- ALCANCE
def alcance(objs, grau):
    """Quem aponta quem. O grau, o compartilhado e o que ninguem alcanca."""
    por = {o["endereco"]: o for o in objs}
    faixas = {"0": 0, "1": 0, "2-3": 0, "4+": 0}
    for o in objs:
        g = grau.get(o["endereco"], {}).get("total", 0)
        faixas["0" if g == 0 else "1" if g == 1 else "2-3" if g <= 3 else "4+"] += 1
    apontados = []
    for e, g in grau.items():
        o = por.get(e)
        if o is None:
            continue
        apontados.append({"endereco": e, "tipo": o["tipo"] or "(conteudo)",
                          "nome": o["nome"], "grau": g["total"],
                          "bytes": o["bytes"],
                          "por": sorted({p for p in g["por"]}),
                          "quem": sorted(g["de"])})
    apontados.sort(key=lambda x: -x["grau"])
    orfaos = [{"endereco": o["endereco"], "tipo": o["tipo"] or "(conteudo)",
               "bytes": o["bytes"], "procedencia": o["procedencia"]}
              for o in objs
              if grau.get(o["endereco"], {}).get("total", 0) == 0
              and o["tipo"] is None]
    compartilhados = [a for a in apontados if a["grau"] > 1]
    return {
        "faixas": faixas,
        "mais_apontados": apontados[:10],
        "compartilhados": {"quantos": len(compartilhados), "lista": compartilhados[:6]},
        "sem_alcance": {"quantos": len(orfaos), "lista": orfaos[:10]},
        "como_ler": ("grau > 1 = o mesmo conteudo serve a mais de um objeto: mexer ali "
                     "move todos. Sem tipo e sem alcance = artefato ate' prova em contrario."),
    }


# ---------------------------------------------------------------- TEMPO
def _git_log(raiz, rel):
    """Quando cada objeto ENTROU no deposito.

    O tempo de GUARDAR vem do git, que ja' o sabe. Copia-lo para a bolha seria
    segunda fonte — e a segunda fonte diverge. Le'-se, nao se guarda.

    Duas armadilhas, as duas medidas:
      * `-m` e' obrigatorio. Sem ele o git NAO lista o que entrou por fusao, e
        o proprio vocabulario do projeto entrou assim.
      * sem `--diff-filter=A`, que esconde as mesmas fusoes.
    O objeto e' endereçado por conteudo, entao NUNCA e' reescrito: a ocorrencia
    MAIS ANTIGA e' a entrada. O git log vem do novo para o velho, logo o ULTIMO
    visto e' o que vale.
    """
    try:
        r = subprocess.run(
            ["git", "-C", raiz, "log", "-m", "--no-renames",
             "--format=@@%ct %h", "--name-only", "--", rel],
            capture_output=True, text=True, timeout=25)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    quando, atual = {}, None
    for linha in r.stdout.splitlines():
        if linha.startswith("@@"):
            partes = linha[2:].split()
            atual = (int(partes[0]), partes[1]) if partes else None
        elif linha.strip() and atual:
            n = os.path.basename(linha.strip())
            if len(n) == 64:
                quando[n] = atual
    return quando


def _rastreados(raiz):
    """O que o git RASTREIA, mesmo sem data de adicao."""
    try:
        r = subprocess.run(["git", "-C", raiz, "ls-files"],
                           capture_output=True, text=True, timeout=25)
    except Exception:
        return set()
    if r.returncode != 0:
        return set()
    return {os.path.basename(x.strip()) for x in r.stdout.splitlines() if x.strip()}


def tempo(raiz, objs):
    """A linha do tempo — e as DUAS naturezas de tempo, ditas separadas.

    O tempo de GUARDAR e' lido do git. O tempo do MUNDO vem dos objetos da
    especie `carimbo`: cada um aponta (`objeto`) para o que carimba e diz
    (`tempo`) quando. O carimbo mora FORA da coisa carimbada — por isso
    carimbar nao muda o endereco de quem foi carimbado.
    """
    quando = {}
    for rel in sorted({o["caminho_rel"] for o in objs}):
        q = _git_log(raiz, rel)
        if q is None:
            return {"erro": "git indisponivel", "raiz": raiz}
        quando.update(q)
    rastreados = _rastreados(raiz)
    carimbos = {}
    for o in objs:
        if o["tipo"] == "carimbo":
            bruto = o["campos"].get("tempo", "?")
            # O deposito guarda o INSTANTE (segundos de epoca, sem dois-pontos —
            # o formato nao os admite). A tela devolve a forma legivel: e' uma
            # PROJECAO, nao um segundo dado guardado.
            try:
                legivel = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime(int(bruto)))
            except (ValueError, OverflowError):
                legivel = "?"
            carimbos.setdefault(o["campos"].get("objeto", "?"), []).append(
                {"tempo": bruto, "legivel": legivel, "endereco": o["endereco"]})
    dias, sem_git, sem_data = defaultdict(list), [], []
    for o in objs:
        e = o["endereco"]
        if e in quando:
            ts, h = quando[e]
            dias[time.strftime("%Y-%m-%d", time.gmtime(ts))].append(
                {"endereco": e, "tipo": o["tipo"] or "(conteudo)", "nome": o["nome"],
                 "bytes": o["bytes"], "compromisso": h, "ts": ts,
                 "procedencia": o["procedencia"]})
        elif e in rastreados:
            sem_data.append({"endereco": e, "tipo": o["tipo"] or "(conteudo)",
                             "procedencia": o["procedencia"]})
        else:
            sem_git.append({"endereco": e, "tipo": o["tipo"] or "(conteudo)",
                            "nome": o["nome"], "bytes": o["bytes"],
                            "procedencia": o["procedencia"]})
    linha = [{"dia": d, "quantos": len(v), "bytes": sum(x["bytes"] for x in v),
              "compromisso": v[0]["compromisso"],
              "objetos": sorted(v, key=lambda x: -x["bytes"])}
             for d, v in sorted(dias.items())]
    return {
        "linha": linha,
        "sem_registro_no_git": sem_git,
        "versionado_sem_data": sem_data,
        "naturezas": {
            "de_guardar": "lido do git a cada chamada, nunca copiado para a bolha",
            "do_mundo": ("dos objetos `carimbo` — `objeto` diz o que foi carimbado e "
                         "`tempo` diz quando, no mundo; o git nao sabe disso, so' sabe "
                         "quando o objeto ENTROU no deposito"),
        },
        "carimbos": carimbos,
        "como_ler": ("cada dia e' o compromisso em que aqueles objetos ENTRARAM no deposito. "
                     "Reordenar por tempo e' reordenar esta lista — e a data sai do git, "
                     "nao de um campo, por isso ela nao pode divergir do fato."),
    }


def tudo(raiz, objs, grau):
    return {"ambito": raiz,
            "forma": forma(objs),
            "peso": peso(objs),
            "alcance": alcance(objs, grau),
            "tempo": tempo(raiz, objs)}
