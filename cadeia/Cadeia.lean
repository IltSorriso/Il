/-
A CADEIA — definida UMA vez, executada em qualquer máquina.

Por que existe (herdado do `reproduzir-cadeia.sh`): a cadeia do juiz estava
escrita nos passos do GitHub Actions — logo só existia lá. Aqui ela é definida
UMA vez, e quem executa é quem tiver a máquina.

Uso:
  lean --run cadeia/Cadeia.lean --etapa juiz|prosa|tudo
-/

namespace Cadeia

def padDir (n : Nat) (s : String) : String :=
  if s.length ≥ n then s else String.ofList (s.toList ++ List.replicate (n - s.length) ' ')

def padEsq (n : Nat) (s : String) : String :=
  if s.length ≥ n then s else String.ofList (List.replicate (n - s.length) ' ' ++ s.toList)

/-- Um passo: rótulo e o comando de shell que o executa. Passar pelo `sh -c`
    deixa `cd` e variáveis de ambiente por conta do shell — o Lean só mede. -/
structure Passo where
  rotulo : String
  comando : String

/-- Mede um passo. O MARCO DE FALHA vem ANTES do retorno: estava depois, e por
    isso nunca era escrito — o canal de erro publicava sempre o ÚLTIMO passo, e
    o erro apontava para o lugar errado. Erro que aponta errado é pior que erro. -/
def medir (raiz : String) (p : Passo) : IO Bool := do
  let t0 ← IO.monoNanosNow
  let out ← IO.Process.output
    { cmd := "sh", args := #["-c", p.comando], cwd := some raiz }
  let t1 ← IO.monoNanosNow
  let ms := (t1 - t0) / 1000000
  let ok := out.exitCode == 0
  IO.println s!"  {padDir 30 p.rotulo} {padEsq 8 (toString ms)} ms  {if ok then "ok" else s!"FALHA({out.exitCode})"}"
  if !ok then IO.FS.writeFile (raiz ++ "/.falhou-" ++ p.rotulo) ""
  pure ok

/-- O juiz: compila o spec e roda as duas mãos. -/
def passosJuiz : List Passo :=
  [ ⟨"versao-do-lean", "cd juiz && lean --version"⟩,
    ⟨"hash-sha256", "cd juiz && lean -o Sha256.olean Sha256.lean"⟩,
    ⟨"spec-bolha", "cd juiz && LEAN_PATH=. lean -o Bolha.olean Bolha.lean"⟩,
    ⟨"ponte", "cd juiz && LEAN_PATH=. lean -o Ponte.olean Ponte.lean"⟩,
    ⟨"mao-escreve-a-cancao",
      "LEAN_PATH=juiz:arreio lean --run arreio/Correr.lean musica "
        ++ "exemplos/musica/letra.txt --titulo \"Canção de exemplo\" --interprete Exemplo"⟩,
    ⟨"conformidade", "LEAN_PATH=juiz lean --run juiz/Conformidade.lean"⟩ ]

/-- A prosa: o juiz da forma dos documentos. -/
def passosProsa : List Passo :=
  [ ⟨"higiene-da-prosa", "lean --run higiene/Higiene.lean --mapa"⟩ ]

/-- O `stdout` de um comando, aparado. -/
def lerCmd (cmd : String) : IO String := do
  let out ← IO.Process.output { cmd := "sh", args := #["-c", cmd] }
  pure out.stdout.trim

/-- Apaga a prova e o marco de falha ANTES de rodar. Sem isto, um número de uma
    corrida antiga sobrevive e a etapa que NÃO rodou parece ter dado resultado —
    foi o que aconteceu: a etapa `prosa` imprimiu `juiz: 181 conferências`. -/
def limpar (raiz : String) (p : Passo) : IO Unit := do
  for f in [raiz ++ "/prova-" ++ p.rotulo ++ ".txt", raiz ++ "/.falhou-" ++ p.rotulo] do
    if ← System.FilePath.pathExists f then IO.FS.removeFile f

/-- Roda uma etapa inteira. Cada passo escreve a sua prova em
    `prova-<rotulo>.txt` — artefato GERADO, nunca versionado. -/
def rodar (raiz : String) (ps : List Passo) : IO Bool := do
  for p in ps do limpar raiz p
  let mut falhou := false
  for p in ps do
    -- A prova vai para a RAIZ, com caminho absoluto: um passo que faz `cd juiz`
    -- gravaria a prova DENTRO de juiz/ se o destino fosse relativo.
    let ok ← medir raiz { p with comando := p.comando ++ s!" > {raiz}/prova-{p.rotulo}.txt 2>&1" }
    if !ok then falhou := true
  pure (!falhou)

/-- Extrai `N ... falhas?` de um arquivo de prova. -/
def numero (raiz sufixo : String) : IO (Option String) := do
  let p := raiz ++ "/prova-" ++ sufixo ++ ".txt"
  if !(← System.FilePath.pathExists p) then pure none
  else
    let texto ← IO.FS.readFile p
    let linhas := texto.splitOn "\n"
    let alvo := linhas.filter (fun l =>
      l.contains 'c' || l.contains 'd' || l.contains 'f')
    pure (match alvo.reverse.find? (fun l => l.contains 'f') with
          | some l => some (l.trim)
          | none => none)


-- ── PUBLICAR O NÚMERO ───────────────────────────────────────────────────────
-- O número sozinho é caixa preta: "183 conferências" não diz de onde veio.
-- Publicá-lo como ESTADO DO COMPROMISSO o torna legível por qualquer um, sem
-- credencial. O rótulo leva o NOME DE QUEM PROVOU: no CI sai o rótulo canônico;
-- em qualquer outra máquina sai com o nome dela — assim se lê, sem credencial,
-- se a prova existe só no atalho ou também numa máquina sua.

/-- A ORDEM DA CADEIA — e não a alfabética. "conformidade" vem antes de "ponte"
    no alfabeto, e por isso o canal publicava a CONSEQUÊNCIA (falta o
    Ponte.olean) em vez da CAUSA (o erro que quebrou o Bolha.lean). -/
def ordemDaCadeia : List String :=
  ["versao-do-lean", "hash-sha256", "spec-bolha", "ponte",
   "mao-escreve-a-cancao", "conformidade", "higiene-da-prosa"]

def primeiroQueFalhou (raiz : String) : IO (Option String) := do
  let mut achado : Option String := none
  for cand in ordemDaCadeia do
    if achado.isNone then
      if ← System.FilePath.pathExists (raiz ++ "/.falhou-" ++ cand) then achado := some cand
  pure achado

/-- A PRIMEIRA linha de erro é a que diz o defeito; as últimas linhas de um
    compilador são o eco dele. -/
def linhaDeErro (arq : String) : IO String := do
  if !(← System.FilePath.pathExists arq) then pure "(sem saida capturada)"
  else
    let ls := (← IO.FS.readFile arq).splitOn "\n"
    match (ls.filter (fun l => (l.splitOn "error").length > 1)).head? with
    | some l => pure ((l.trim.take 130).toString)
    | none =>
        let uteis := (ls.filter (fun l => !l.trim.isEmpty)).reverse
        let tres := (uteis.take 3).reverse
        pure ((String.intercalate " " tres |>.take 130).toString)

def achatado (s : String) : String :=
  let a := (s.replace "\n" " ").replace "\r" " "
  let b := a.replace "\\" "\\\\"
  b.replace "\"" "\\\""

def publicar (maquina emCi : String) (ctxBase desc estado : String) : IO Unit := do
  let ctx := if emCi == "1" then ctxBase else s!"{ctxBase} [{maquina}]"
  let abre := "{"
  let fecha := "}"
  let corpo := abre ++ "\"state\":\"" ++ estado ++ "\",\"context\":\"" ++ ctx
                ++ "\",\"description\":\"" ++ achatado desc ++ "\"" ++ fecha
  let repo := (← IO.getEnv "GITHUB_REPOSITORY").getD "IltSorriso/Il"
  let sha := (← IO.getEnv "GITHUB_SHA").getD (← lerCmd "git rev-parse HEAD 2>/dev/null || echo desconhecido")
  let token := (← IO.getEnv "GITHUB_TOKEN").getD ""
  IO.FS.writeFile "corpo.json" corpo
  let _ ← IO.Process.output
    { cmd := "curl",
      args := #["-sS", "-o", "/dev/null", "-w", "%{http_code}", "-X", "POST",
                "-H", s!"Authorization: Bearer {token}",
                "-H", "Accept: application/vnd.github+json",
                s!"https://api.github.com/repos/{repo}/statuses/{sha}",
                "--data", "@corpo.json"] }
  IO.println s!"  publicado: {ctx}"

def fluxoPublicar (raiz maquina emCi : String) (ok : Bool)
    (numJuiz numProsa : Option String) : IO Unit := do
  let token := (← IO.getEnv "GITHUB_TOKEN").getD ""
  if token.isEmpty then
    IO.println "  PUBLICAR pedido, mas sem GITHUB_TOKEN — nada publicado."
  else
    let estado := if ok then "success" else "failure"
    let rj := (← IO.getEnv "PROVA_ROTULO_JUIZ").getD "juiz - numero"
    let rp := (← IO.getEnv "PROVA_ROTULO_PROSA").getD "prosa - numero"
    match numJuiz with
    | some n => publicar maquina emCi rj n estado
    | none => pure ()
    match numProsa with
    | some n => publicar maquina emCi rp n estado
    | none => pure ()
    if !ok then
      match ← primeiroQueFalhou raiz with
      | some passo =>
          let cauda ← linhaDeErro (raiz ++ "/prova-" ++ passo ++ ".txt")
          publicar maquina emCi s!"cadeia - ERRO em {passo}" cauda "failure"
      | none => pure ()

def main (args : List String) : IO Unit := do
  -- A RAIZ, ABSOLUTA. Um passo faz `cd juiz`, e `.` deixaria de apontar para a
  -- raiz do repositório — foi assim que quatro provas foram parar em `juiz/`.
  let raizF ← IO.FS.realPath "."
  let raiz : String := raizF.toString
  let etapa :=
    match args.dropWhile (fun a => a != "--etapa") with
    | _ :: v :: _ => v
    | _ => "tudo"
  let maquina := (← IO.getEnv "CADEIA_MAQUINA").getD (← lerCmd "uname -n")
  let cores := ← lerCmd "getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo ?"
  IO.println "=== cadeia do juiz ==="
  IO.println s!"  etapa:    {etapa}"
  IO.println s!"  máquina:  {maquina}"
  IO.println s!"  núcleos:  {cores}"
  IO.println s!"  Lean fixado: {(← IO.FS.readFile (raiz ++ "/lean-toolchain")).trim}"
  IO.println ""
  let mut ok := true
  if etapa == "juiz" || etapa == "tudo" then
    if !(← rodar raiz passosJuiz) then ok := false
  if etapa == "prosa" || etapa == "tudo" then
    if !(← rodar raiz passosProsa) then ok := false
  IO.println ""
  IO.println "=== NÚMEROS ==="
  let juiz ← numero raiz "conformidade"
  let prosa ← numero raiz "higiene-da-prosa"
  match juiz with
  | some l => IO.println s!"  juiz:  {l}"
  | none => pure ()
  match prosa with
  | some l => IO.println s!"  prosa: {l}"
  | none => pure ()
  if args.contains "--publicar" then
    fluxoPublicar raiz maquina (if (← IO.getEnv "GITHUB_ACTIONS").isSome then "1" else "0")
      ok juiz prosa
  if !ok then
    IO.println "  A CADEIA FALHOU — ver .falhou-<rotulo>"
    IO.Process.exit 1

end Cadeia

def main (args : List String) : IO Unit := Cadeia.main args
