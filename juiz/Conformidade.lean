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

def ehAnotacao (txt : String) : Bool :=
  tipoDe txt == some "anotacao"

/-- Hash bem-formado só para o teste negativo de canonicidade. -/
def hashDeTeste : String := String.ofList (List.replicate 64 'a')

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
    if ehAnotacao txt then
      total := total + 1
      let v := verifica txt dep
      IO.println s!"  {h.take 12}… → {repr v}"
      if !passou v then falhas := falhas + 1

  IO.println "--- DEVEM reprovar ---"
  for (h, txt) in queb do
    if ehAnotacao txt then
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

  IO.println s!"\n{total} conferências, {falhas} falhas"
  if falhas == 0 then pure 0 else pure 1
