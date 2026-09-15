import Ponte

/-
CONFORMIDADE — TDD sobre os artefatos REAIS.

- `exemplos/deposito/`   → cada anotação DEVE verificar;
- `exemplos/quebrados/`  → cada anotação DEVE reprovar (regressão do portão);
- `deposito/` (se houver) → a instância LOCAL (ex.: o ateliê) também é conferida.
  AUSÊNCIA é legítima e é DITA em voz alta; o que este juiz não aceita é o
  silêncio — um teste que passa sem olhar o objeto não é teste.

Fatia "b": além disso, o juiz RECALCULA o sha256 de cada objeto e confere
contra o endereço (o nome do arquivo). Duas implementações independentes
(arreio em Python, juiz em Lean) têm de concordar.
Sai ≠ 0 se qualquer expectativa for contrariada.
-/

open Bolha Ponte

def lerDeposito (dir : String) : IO Deposito := do
  let entries ← System.FilePath.readDir dir
  let mut acc : Deposito := []
  for e in entries do
    let bytes ← IO.FS.readBinFile e.path
    acc := acc ++ [(e.fileName, bytes)]
  pure acc

/-- A VISTA de texto de um objeto lido do disco. Objeto que não é texto não é
    bolha — bolha se lê —, e por isso a mídia crua não vira manifesto. -/
def textoDe (b : ByteArray) : String := (String.fromUTF8? b).getD ""

/-- Lê um depósito OPCIONAL — distinguindo AUSENTE de PRESENTE.
    Ausência é legítima (a pindorama só tem `exemplos/`). O que não é legítimo é o
    silêncio: um erro que não seja ausência é PROPAGADO, não engolido —
    falha por erro, nunca por omissão. -/
def lerDepositoOpcional (dir : String) : IO (Option Deposito) := do
  let existe ← System.FilePath.pathExists dir
  if existe then
    some <$> lerDeposito dir
  else
    pure none

/-- A bolha é JULGÁVEL? Só as espécies com campo de conteúdo, segundo o spec:
    o vocabulário não é reescrito aqui. A bolha de licença aponta para um
    catálogo — não é manifesto de conteúdo, e o juiz não a julga como tal. -/
def ehJulgavel (txt : String) : Bool :=
  match tipoDe txt with
  | some t => (campoDeConteudo t).isSome
  | none   => false

/-- Hash bem-formado só para o teste negativo de canonicidade. -/
def hashDeTeste : String := String.ofList (List.replicate 64 'a')

/- ============ A REUNIÃO: as partes e o todo ============ -/

-- Esta seção NÃO tem regra própria. Até 2026-09-13 tinha: `partesDe`,
-- `textoDaParte` e `letraInteira` reimplementavam aqui a regra que define a
-- canção, e o veredito não a conhecia — a mesma regra em dois lugares, e só um
-- deles decidia. Agora ela vive no SPEC (`registroReuniao`, `contribuicao`,
-- `reunir`, `reuniaoOkB`) e o CONFORMIDADE só a confere sobre os artefatos
-- reais. Regra que mora num lugar só não tem como divergir de si mesma.

/-- A espécie declara uma reunião? — pergunta feita ao SPEC, não a uma cópia. -/
def temReuniao (txt : String) : Bool :=
  match campo (parseCampos txt) "tipo" with
  | none   => false
  | some t => (List.lookup t registroReuniao).isSome

def main : IO UInt32 := do
  let bom       ← lerDeposito  "exemplos/deposito/objetos"
  let queb      ← lerDeposito  "exemplos/quebrados/objetos"
  let instancia? ← lerDepositoOpcional "deposito/objetos"
  let instancia := instancia?.getD []
  let dep := bom ++ queb ++ instancia
  -- (c) A PROCEDENCIA. `bom ++ queb ++ instancia` apaga de ONDE cada objeto veio,
  -- e sem isso a lei escrita no Bolha.md (2026-09-13) nao tem por onde olhar:
  -- quem decide e o RECIPIENTE, e o recipiente e o caminho.
  let origens : List (String × Deposito) :=
    [ ("exemplos/deposito/objetos", bom),
      ("exemplos/quebrados/objetos", queb),
      ("deposito/objetos", instancia) ]
  let mut falhas := 0
  let mut total := 0

  IO.println s!"depósito: {bom.length} canônicos + {instancia.length} locais + {queb.length} quebrados"
  match instancia? with
  | some d => IO.println s!"  instância local `deposito/objetos`: PRESENTE — {d.length} objeto(s) conferido(s)"
  | none   => IO.println "  instância local `deposito/objetos`: AUSENTE — nada a conferir (dito em voz alta, não silenciado)"

  IO.println "--- ENDEREÇAMENTO (sha256 dos BYTES == chave?) ---"
  for (h, bytes) in dep do
    total := total + 1
    let recalc := Sha256.enderecoBytes bytes
    if recalc == h then
      IO.println s!"  {h.take 12}… confere"
    else
      IO.println s!"  {h.take 12}… NÃO CONFERE (recalculado {recalc.take 12}…)"
      falhas := falhas + 1
  IO.println s!"  depósito inteiro endereçado? {depositoEnderecado dep}"

  IO.println "\n--- A LEI: bolha privada nao mora em caminho publico ---"
  -- O sigilo do RECIPIENTE vem da bolha `caminho` do canone — lida, nao repetida
  -- como texto literal. E o sigilo da BOLHA vem da licenca dela.
  let caminhoCom (padrao : String) : Option String :=
    (objetosDeTipo bom "caminho").find? (fun h =>
      match objetoTexto bom h with
      | some txt => (campo (parseCampos txt) "padrao").getD "" == padrao
      | none     => false)
  let sigiloDoCaminho (padrao : String) : Option String :=
    (caminhoCom padrao).bind (fun h =>
      campo (parseCampos ((objetoTexto bom h).getD "")) "sigilo")
  for (caminho, objs) in origens do
    match sigiloDoCaminho caminho with
    | none =>
      IO.println s!"  {caminho}: NAO DECLARADO em bolha `caminho` — sigilo desconhecido"
    | some sc =>
      IO.println s!"  {caminho}: `sigilo: {sc}` — {objs.length} objeto(s)"
      for (h, bytes) in objs do
        match campo (parseCampos (textoDe bytes)) "licenca" with
        | some lic =>
          if lic.length == 64 then
            total := total + 1
            let sig := match objetoTexto objs lic with
              | some lt => (campo (parseCampos lt) "sigilo").getD "(sem sigilo)"
              | none    => "(licenca ausente neste deposito)"
            if sc == "publico" && sig == "privado" then
              if caminho == "exemplos/quebrados/objetos" then
                IO.println s!"    {h.take 12}… o fixture quebrado FOI recusado pela lei (privada em caminho publico)"
              else
                IO.println s!"    {h.take 12}… FALHA: bolha privada em caminho publico"
                falhas := falhas + 1
            else
              IO.println s!"    {h.take 12}… concorda (licenca: {sig})"
          else
            total := total + 1
            IO.println s!"    {h.take 12}… {lic}: nao afirma visibilidade — o recipiente decide"
        | none => pure ()

  IO.println "--- DEVEM verificar ---"
  for (h, bytes) in bom ++ instancia do
    let txt := textoDe bytes
    if ehJulgavel txt then
      total := total + 1
      let v := verifica txt dep
      IO.println s!"  {h.take 12}… → {repr v}"
      if !passou v then falhas := falhas + 1

  IO.println "--- DEVEM reprovar ---"
  for (h, bytes) in queb do
    let txt := textoDe bytes
    if ehJulgavel txt then
      total := total + 1
      let v := verifica txt dep
      IO.println s!"  {h.take 12}… → {repr v}"
      if passou v then falhas := falhas + 1

  IO.println "--- FORMA CANÔNICA (fatia \"d\") ---"
  let mut fora := 0
  for (h, bytes) in dep do
    let txt := textoDe bytes
    if (tipoDe txt).isSome then
      total := total + 1
      if canonicidadeOk txt then
        IO.println s!"  {h.take 12}… canônico"
      else
        IO.println s!"  {h.take 12}… FORA DA FORMA CANÔNICA"
        fora := fora + 1
        falhas := falhas + 1
  IO.println s!"  objetos fora da forma canônica: {fora}"

  IO.println "--- CANÔNICO? (teste negativo: campos fora de ordem) ---"
  total := total + 1
  let torto := "tipo: anotacao\nlicenca: reservado\nconteudo: " ++ hashDeTeste ++ "\n"
  if canonicidadeOk torto then
    IO.println "  ERRO: texto fora de ordem passou como canônico"
    falhas := falhas + 1
  else
    IO.println "  texto fora de ordem → corretamente rejeitado (não é canônico)"

  IO.println "--- A REUNIÃO (o eixo áudio · imagem · vídeo): o todo é a união das partes? ---"
  let mut comReuniao := 0
  for (h, bytes) in bom ++ instancia do
    let txt := textoDe bytes
    if temReuniao txt then
      comReuniao := comReuniao + 1
      match parseManifesto txt with
      | none =>
          IO.println s!"  {h.take 12}… declara reunião, mas não vira manifesto"
          falhas := falhas + 1
      | some m =>
          match List.lookup m.tipo registroReuniao with
          | none => pure ()
          | some r =>
              let partes := enderecosDeCampo m.campos r.partes
              IO.println s!"  {h.take 12}… espécie `{m.tipo}`: {partes.length} parte(s), união em `{r.uniao}`"
              for p in partes do
                total := total + 1
                if noDeposito dep p && (objTipo dep p).isSome then
                  IO.println s!"    {p.take 12}… presente, bolha julgável"
                else
                  IO.println s!"    {p.take 12}… AUSENTE — não é parte de nada"
                  falhas := falhas + 1
              total := total + 1
              if reuniaoOkB m dep then
                IO.println "    o campo declarado É a reunião das partes, na ordem — endereço confere"
              else
                IO.println "    o campo declarado NÃO é a reunião das partes — o veredito tem de reprovar"
                falhas := falhas + 1
  if comReuniao == 0 then
    IO.println "  nenhuma bolha declara reunião neste depósito (dito em voz alta)"

  IO.println "--- A REUNIÃO REPROVA O QUE A QUEBRA? (teste negativo, do juiz) ---"
  for (h, bytes) in queb do
    let txt := textoDe bytes
    if temReuniao txt then
      total := total + 1
      if passou (verifica txt dep) then
        IO.println s!"  {h.take 12}… ERRO: bolha que quebra a reunião passou no veredito"
        falhas := falhas + 1
      else
        IO.println s!"  {h.take 12}… corretamente reprovada (a reunião não confere)"

  IO.println "--- OS DOIS REGISTROS DO SPEC CONCORDAM? ---"
  for (especie, c) in registroConteudo do
    total := total + 1
    match camposDe especie with
    | some chaves =>
        if chaves.any (fun k => k == c.campo) then
          IO.println s!"  {especie}: o campo de conteúdo `{c.campo}` está no vocabulário"
        else
          IO.println s!"  {especie}: o campo de conteúdo `{c.campo}` NÃO está no vocabulário"
          falhas := falhas + 1
    | none =>
        IO.println s!"  {especie}: tem campo de conteúdo, mas não está no registro de espécies"
        falhas := falhas + 1

  IO.println "--- O VOCABULÁRIO LIDO CONCORDA COM O REGISTRO LITERAL? ---"
  -- O registro literal é o ESPERADO; o vocabulário lido é o OBTIDO. O veredito é
  -- a comparação — a migração vira teste, não fé de que os dois concordam.
  match lerVocabulario (bom ++ instancia) with
  | none =>
      IO.println "  o depósito não tem EXATAMENTE UM vocabulário legível — nada a comparar"
      falhas := falhas + 1
  | some pares =>
      for (nome, chaves) in pares do
        total := total + 1
        match List.lookup nome registroEspecies with
        | none =>
            IO.println s!"  {nome}: está no vocabulário e NÃO está no registro literal"
            falhas := falhas + 1
        | some esperadas =>
            if chaves == esperadas then
              IO.println s!"  {nome}: idêntico ({chaves.length} campos)"
            else
              IO.println s!"  {nome}: DIFERENTE — o vocabulário diz {chaves}, o registro diz {esperadas}"
              falhas := falhas + 1


  IO.println "--- A FORMA DO TEXTO (a porta de uma mão do texto canônico) ---"
  let mut textosConferidos := 0
  for (h, bytes) in bom ++ instancia do
    let txt := textoDe bytes
    match tipoDe txt with
    | none => pure ()
    | some t =>
        if !conteudoEhTexto t then
          -- MÍDIA: a porta do texto canônico não julga o que não é texto.
          pure ()
        else
          match List.lookup t registroConteudo with
          | none => pure ()
          | some c =>
              match campo (parseCampos txt) c.campo with
              | none => pure ()
              | some enderecoConteudo =>
                  total := total + 1
                  textosConferidos := textosConferidos + 1
                  match objeto dep enderecoConteudo with
                  | none =>
                      IO.println s!"  {h.take 12}… o texto apontado NÃO está no depósito"
                      falhas := falhas + 1
                  | some corpo =>
                      if bytesTextoOk corpo then
                        IO.println s!"  {h.take 12}… texto canônico ({corpo.size} bytes)"
                      else
                        IO.println s!"  {h.take 12}… TEXTO FORA DA FORMA CANÔNICA — outra grafia, outro endereço"
                        falhas := falhas + 1
  if textosConferidos == 0 then
    IO.println "  nenhum texto a conferir neste depósito (dito em voz alta)"

  IO.println "--- CANÔNICO? (teste negativo: acento decomposto) ---"
  total := total + 1
  let decomposto := "cano\u0302nico"
  if textoOk decomposto then
    IO.println "  ERRO: texto com acento decomposto passou como canônico"
    falhas := falhas + 1
  else
    IO.println "  acento decomposto → corretamente recusado (outra grafia, outro endereço)"

  IO.println s!"\n{total} conferências, {falhas} falhas"


  if falhas == 0 then pure 0 else pure 1
