import Ponte

/-
CONFORMIDADE — TDD sobre os artefatos REAIS.

Sem fixture sintética: lê os depósitos do disco e roda o juiz (Ponte.verifica).
- `exemplos/deposito/`   → cada anotação DEVE verificar;
- `exemplos/quebrados/`  → cada anotação DEVE reprovar (regressão do portão);
- `deposito/` (se existir) → a instância LOCAL (ex.: o ateliê) também é conferida.
Sai ≠ 0 se qualquer expectativa for contrariada.
-/

open Bolha Ponte

/-- Lê um depósito (nome do arquivo = hash; texto = objeto). -/
def lerDeposito (dir : String) : IO Deposito := do
  let entries ← System.FilePath.readDir dir
  let mut acc : Deposito := []
  for e in entries do
    let txt ← IO.FS.readFile e.path
    acc := acc ++ [(e.fileName, txt)]
  pure acc

/-- Igual, mas tolera diretório ausente. -/
def lerDeposito? (dir : String) : IO Deposito := do
  try lerDeposito dir catch _ => pure []

def ehAnotacao (txt : String) : Bool :=
  campo (parseManifesto txt) "tipo" == some "anotacao"

def main : IO UInt32 := do
  let bom    ← lerDeposito  "exemplos/deposito/objetos"
  let queb   ← lerDeposito  "exemplos/quebrados/objetos"
  let instancia ← lerDeposito? "deposito/objetos"
  let dep := bom ++ queb ++ instancia
  let mut falhas := 0
  let mut total := 0

  IO.println s!"depósito: {bom.length} canônicos + {instancia.length} locais + {queb.length} quebrados"

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

  IO.println s!"\n{total} manifestos conferidos, {falhas} falhas"
  if falhas == 0 then pure 0 else pure 1
