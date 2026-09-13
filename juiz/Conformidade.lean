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
    let txt ← IO.FS.readFile e.path
    acc := acc ++ [(e.fileName, txt)]
  pure acc

/-- Lê um depósito OPCIONAL — distinguindo AUSENTE de PRESENTE.
    Ausência é legítima (o tronco só tem `exemplos/`). O que não é legítimo é o
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

/- ============ A CANÇÃO: as partes e a letra inteira ============ -/

/-- Os endereços das partes: o campo `partes`, separado por vírgula. -/
def partesDe (txt : String) : List String :=
  match campo (parseCampos txt) "partes" with
  | some s => (s.splitOn ",").filter (fun h => h != "")
  | none   => []

/-- O TEXTO de uma parte. A parte é uma bolha do tipo `parte`, e o texto dela
    mora no objeto apontado pelo campo `letra`. `none` quando a parte está
    ausente, é de outro tipo, ou aponta para um texto que não existe. -/
def textoDaParte (dep : Deposito) (h : String) : Option String :=
  match objeto dep h with
  | none => none
  | some txt =>
      if tipoDe txt == some "parte" then
        match campo (parseCampos txt) "letra" with
        | some hc => objeto dep hc
        | none    => none
      else none

/-- A LETRA INTEIRA: a reunião das partes, NA ORDEM que a bolha declara. A
    receita é a bolha; isto é o prato. Como o prato também tem endereço, ele é
    conferível contra a receita — e é isso que impede duas verdades sobre a
    mesma canção. -/
def letraInteira (dep : Deposito) (h : String) : Option String :=
  match objeto dep h with
  | none => none
  | some txt =>
      let textos := (partesDe txt).map (textoDaParte dep)
      if textos.all (fun t => t.isSome) then
        some (textos.foldl (fun acc t => acc ++ t.getD "") "")
      else none

def main : IO UInt32 := do
  let bom       ← lerDeposito  "exemplos/deposito/objetos"
  let queb      ← lerDeposito  "exemplos/quebrados/objetos"
  let instancia? ← lerDepositoOpcional "deposito/objetos"
  let instancia := instancia?.getD []
  let dep := bom ++ queb ++ instancia
  let mut falhas := 0
  let mut total := 0

  IO.println s!"depósito: {bom.length} canônicos + {instancia.length} locais + {queb.length} quebrados"
  match instancia? with
  | some d => IO.println s!"  instância local `deposito/objetos`: PRESENTE — {d.length} objeto(s) conferido(s)"
  | none   => IO.println "  instância local `deposito/objetos`: AUSENTE — nada a conferir (dito em voz alta, não silenciado)"

  IO.println "--- ENDEREÇAMENTO (sha256 do texto == chave?) ---"
  for (h, txt) in dep do
    total := total + 1
    let recalc := Sha256.endereco txt
    if recalc == h then
      IO.println s!"  {h.take 12}… confere"
    else
      IO.println s!"  {h.take 12}… NÃO CONFERE (recalculado {recalc.take 12}…)"
      falhas := falhas + 1
  IO.println s!"  depósito inteiro endereçado? {depositoEnderecado dep}"

  IO.println "--- DEVEM verificar ---"
  for (h, txt) in bom ++ instancia do
    if ehJulgavel txt then
      total := total + 1
      let v := verifica txt dep
      IO.println s!"  {h.take 12}… → {repr v}"
      if !passou v then falhas := falhas + 1

  IO.println "--- DEVEM reprovar ---"
  for (h, txt) in queb do
    if ehJulgavel txt then
      total := total + 1
      let v := verifica txt dep
      IO.println s!"  {h.take 12}… → {repr v}"
      if passou v then falhas := falhas + 1

  IO.println "--- FORMA CANÔNICA (fatia \"d\") ---"
  let mut fora := 0
  for (h, txt) in dep do
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

  IO.println "--- A CANÇÃO (espécie `musica`): as partes e a letra inteira ---"
  let mut cancoes := 0
  for (h, txt) in bom ++ instancia do
    if tipoDe txt == some "musica" then
      cancoes := cancoes + 1
      let partes := partesDe txt
      IO.println s!"  {h.take 12}… {partes.length} parte(s)"
      for p in partes do
        total := total + 1
        if noDeposito dep p && objTipo dep p == some "parte" then
          IO.println s!"    {p.take 12}… presente, do tipo `parte`"
        else
          IO.println s!"    {p.take 12}… AUSENTE ou de outro tipo — não é parte de nada"
          falhas := falhas + 1
      total := total + 1
      match campo (parseCampos txt) "letra", letraInteira dep h with
      | some declarada, some reunida =>
          if Sha256.endereco reunida == declarada then
            IO.println "    a letra inteira é a reunião das partes, na ordem — endereço confere"
          else
            IO.println "    a letra inteira NÃO é a reunião das partes — endereço não confere"
            falhas := falhas + 1
      | _, _ =>
          IO.println "    não consegui reunir a letra inteira (parte ou texto ausente)"
          falhas := falhas + 1
  if cancoes == 0 then
    IO.println "  nenhuma bolha da espécie `musica` neste depósito (dito em voz alta)"

  IO.println "--- OS DOIS REGISTROS DO SPEC CONCORDAM? ---"
  for (especie, chave) in registroConteudo do
    total := total + 1
    match camposDe especie with
    | some chaves =>
        if chaves.any (fun k => k == chave) then
          IO.println s!"  {especie}: o campo de conteúdo `{chave}` está no vocabulário"
        else
          IO.println s!"  {especie}: o campo de conteúdo `{chave}` NÃO está no vocabulário"
          falhas := falhas + 1
    | none =>
        IO.println s!"  {especie}: tem campo de conteúdo, mas não está no registro de espécies"
        falhas := falhas + 1


  IO.println "--- A FORMA DO TEXTO (a porta de uma mão do texto canônico) ---"
  let mut textosConferidos := 0
  for (h, txt) in bom ++ instancia do
    match tipoDe txt with
    | none => pure ()
    | some t =>
        match List.lookup t registroConteudo with
        | none => pure ()
        | some chave =>
            match campo (parseCampos txt) chave with
            | none => pure ()
            | some enderecoConteudo =>
                total := total + 1
                textosConferidos := textosConferidos + 1
                match objeto dep enderecoConteudo with
                | none =>
                    IO.println s!"  {h.take 12}… o texto apontado NÃO está no depósito"
                    falhas := falhas + 1
                | some corpo =>
                    if textoOk corpo then
                      IO.println s!"  {h.take 12}… texto canônico ({corpo.length} caracteres)"
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
