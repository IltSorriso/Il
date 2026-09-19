<!-- doc: tipo=capa autoridade=pitch -->

# Il — Individuação Livre

*English: [`README.md`](README.md) · 中文: [`LEIAME.zh.md`](LEIAME.zh.md)*

**Il** (*individuação livre*) é um projeto para **tornar-se si mesmo** através de
**tecnologia livre** — feito para que nenhum império, plataforma ou porteiro detenha
as chaves da sua cultura, da sua memória ou das suas ferramentas.

Seu primeiro fruto é **Bolha**, um formato de arquivo determinístico que agrupa e
referencia mídia (textos, imagens, vídeos, áudio) carregando a **licença de uso de
cada componente**.

## Por que isso importa

A maioria dos formatos trata licença como metadado — uma etiqueta que se pode ignorar.
Bolha torna a licença **estrutural**: não se referencia um componente sem declarar o
que pode ser feito com ele, e a mesma máquina escala de conteúdo para programas e
serviços.

- **A licença é ela mesma uma bolha** — ou o estado `reservado` (ausência deliberada de
  direitos). Uma bolha-licença aponta para um **catálogo real** — Creative Commons para
  conteúdo, SPDX para programas — de modo que o sistema nunca inventa termos jurídicos,
  e não há documento de prosa para divergir da verdade.
- **Endereçado por conteúdo, sempre** — toda referência é um sha256. A bolha é o
  manifesto determinístico das suas partes; a renderização é subproduto.
- **Mão e juiz** — o arreio (`arreio/Arreio.lean`) escreve o manifesto; a mesma base de
  código **Lean 4** guarda também o juiz, que prova a *forma*; uma pessoa confirma a
  *verdade*.

## O ciclo local (não há runner de CI)

A cadeia é **definida uma vez**, em `cadeia/Cadeia.lean`, e rodada pela máquina que você
tiver. GitHub Actions não faz parte do desenho — foi um runner possível, nunca a fonte.

    lean --run cadeia/Cadeia.lean --etapa tudo      # a cadeia inteira: juiz + prosa
    lean --run cadeia/Cadeia.lean --etapa juiz      # só o juiz
    lean --run cadeia/Cadeia.lean --etapa prosa     # só a prosa

Cada corrida escreve `recibo-<etapa>.txt`: o resultado, a máquina, o ramo, o compromisso
e a hora UTC. Um número solto não diz de onde veio; o recibo diz. Recibos e provas são
**gerados — nunca versionados**.

O portão é `.githooks/pre-push`. Ligue uma vez por clone:

    git config core.hooksPath .githooks

Compilar o arreio inteiro leva cerca de meio minuto. `arreio/Correr.lean` existe para
isso: ele importa o `.olean` já compilado em vez de reconstruir, e custa uma fração.

## A forma mora no juiz (veja `juiz/`)

A especificação é executável, não prosa:

- `juiz/Bolha.lean` — a bolha válida abstrata: endereçada por hash, licença sempre
  explícita.
- `juiz/Ponte.lean` — a ponte: confere manifestos reais contra uma coleção de bolhas.

## Onde mora o quê

- `juiz/` — a especificação em Lean 4 (abstrata + ponte para manifestos reais).
- `arreio/` — o arreio, em Lean 4: cria bolha-licença a partir de catálogo real, importa
  conteúdo por hash, e carrega o **fluxo da música** — um arquivo de letra entra, saem
  bolhas `parte` numeradas e a bolha `musica`.
- `higiene/` — o juiz da prosa, em Lean 4: cada documento declara tipo e autoridade,
  caminho citado tem de existir, e só a capa mora na raiz.
- `cadeia/` — a cadeia, definida uma vez, rodada por qualquer máquina.
- `ferramentas/` — **legado**, do ciclo Python/JS. Nenhum programa da cadeia chama nada
  aqui. Parte está substituída por `juiz/Bolha.lean`; parte ainda guarda capacidade que
  nunca foi portada, e nesse caso o arquivo é o único registro que existe.
- `.githooks/pre-push` — **o portão**. A cadeia roda antes de cada empurrão, na sua
  máquina, localmente. Não há GitHub Actions aqui: a prova mora onde é produzida.
  `git push --no-verify` o pula.

## Estado

Protótipo inicial. O juiz está verificado localmente (`exit 0`) com Lean 4.34.0, fixado
em `lean-toolchain`. Não há runner de CI: a cadeia roda na máquina que você tiver.

## Os dois repositórios

- **Il** (este) — a pindorama pública: o produto. O código nasce aqui primeiro.
- **IltS** — o ateliê privado (um garfo): o diário, o plano e o conteúdo pessoal. Ele
  puxa daqui e nunca empurra de volta.

## Licença

AGPL-3.0 — veja `LICENSE`.
