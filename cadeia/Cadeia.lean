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


/-- A ORDEM DA CADEIA — e não a alfabética. "conformidade" vem antes de "ponte"
    no alfabeto, e por isso o canal publicava a CONSEQUÊNCIA (falta o
    Ponte.olean) em vez da CAUSA (o erro que quebrou o Bolha.lean). -/
def ordemDaCadeia : List String :=
  ["versao-do-lean", "hash-sha256", "spec-bolha", "ponte",
   "mao-escreve-a-cancao", "conformidade", "higiene-da-prosa"]

/-- Apaga TODA prova e TODO marco — não só os da etapa pedida. Antes, `--etapa
    juiz` deixava de pé a `prova-higiene-da-prosa.txt` da corrida anterior, e o
    recibo a apresentava como se tivesse sido medida agora. Pior: com `--etapa
    nada` o recibo dizia "PASSOU, 183 conferências" sem ter rodado NADA.
    Número não medido nesta corrida não é número. -/
def limparTudo (raiz : String) : IO Unit := do
  for r in ordemDaCadeia do
    for f in [raiz ++ "/prova-" ++ r ++ ".txt", raiz ++ "/.falhou-" ++ r] do
      if ← System.FilePath.pathExists f then IO.FS.removeFile f

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

/-- Le' o `.env` da raiz: linhas `CHAVE=valor`, `#` comenta, e a ULTIMA
    definicao de uma chave VENCE — e' assim que o atelie troca `IL_REMOTO` sem
    tocar no bloco que veio do Il. Nao le' segredo nenhum: o arquivo declara
    NOMES, e so'. -/
def doEnv (raiz chave : String) : IO (Option String) := do
  let p := raiz ++ "/.env"
  if !(← System.FilePath.pathExists p) then return none
  let texto ← IO.FS.readFile p
  let mut achado : Option String := none
  for linha in texto.splitOn "\n" do
    let l := linha.trimAscii.toString
    match l.toList with
    | '#' :: _ => pure ()
    | _ =>
        let partes := l.splitOn "="
        if partes.length >= 2 then
          if (partes.headD "").trimAscii.toString == chave then
            achado := some ((String.intercalate "=" (partes.drop 1)).trimAscii.toString)
  return achado

/-- O RECIBO LOCAL — o que o estado do GitHub carregava, mas morando AQUI.
    O projeto NÃO usa Actions: a prova é local, e o portão é o `pre-push`.
    Diz com que máquina, que ramo e que compromisso o número foi medido — sem
    isso, um número sozinho não diz de onde veio. -/
def recibo (raiz maquina etapa : String) (ok : Bool)
    (juiz prosa : Option String) : IO Unit := do
  let quando ← lerCmd "date -u +%Y-%m-%dT%H:%M:%SZ"
  let head ← lerCmd "git rev-parse --short HEAD 2>/dev/null || echo desconhecido"
  let ramo ← lerCmd "git rev-parse --abbrev-ref HEAD 2>/dev/null || echo desconhecido"
  -- CADA REPOSITORIO TEM O SEU. No atelie o ramo principal e' `atelie`, nao
  -- `pindorama` — ler `IL_RAMO` nos dois acusaria o atelie de estar no ramo
  -- errado em TODA corrida. O que e' do atelie vence; o do Il fica de padrao.
  let nome ←
    match ← doEnv raiz "ILTS_REPO" with
    | some r => pure r
    | none => pure ((← doEnv raiz "IL_REPO").getD "?")
  let principal ←
    match ← doEnv raiz "ILTS_RAMO" with
    | some r => pure r
    | none => pure ((← doEnv raiz "IL_RAMO").getD "?")
  let mut falha : List String := []
  if !ok then
    match ← primeiroQueFalhou raiz with
    | some passo =>
        let cauda ← linhaDeErro (raiz ++ "/prova-" ++ passo ++ ".txt")
        falha := [s!"falhou em:   {passo}", s!"erro:        {cauda}"]
    | none => pure ()
  let linhas :=
    [ s!"recibo:       {if ok then "PASSOU" else "FALHOU"}",
      s!"etapa:        {etapa}",
      s!"maquina:      {maquina}",
      s!"repositorio:  {nome} · principal {principal}",
      s!"ramo medido:  {ramo}",
      s!"compromisso:  {head}",
      s!"quando (UTC): {quando}" ]
    ++ (if ramo == principal then [] else
          [s!"ATENCAO:      o ramo medido NAO e' o principal declarado em .env"])
    ++ falha
    ++ (match juiz with | some n => [s!"juiz:         {n}"] | none => [])
    ++ (match prosa with | some n => [s!"prosa:        {n}"] | none => [])
  IO.FS.writeFile (raiz ++ "/recibo-" ++ etapa ++ ".txt")
    (String.intercalate "\n" linhas ++ "\n")
  IO.println ""
  IO.println s!"=== RECIBO (gravado em recibo-{etapa}.txt) ==="
  for l in linhas do IO.println s!"  {l}"

def main (args : List String) : IO Unit := do
  -- A RAIZ, ABSOLUTA. Um passo faz `cd juiz`, e `.` deixaria de apontar para a
  -- raiz do repositório — foi assim que quatro provas foram parar em `juiz/`.
  let raizF ← IO.FS.realPath "."
  let raiz : String := raizF.toString
  limparTudo raiz
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
  let nomeRep ←
    match ← doEnv raiz "ILTS_REPO" with
    | some r => pure r
    | none => pure ((← doEnv raiz "IL_REPO").getD "?")
  let ramRep ←
    match ← doEnv raiz "ILTS_RAMO" with
    | some r => pure r
    | none => pure ((← doEnv raiz "IL_RAMO").getD "?")
  let caudaRep := if (← doEnv raiz "ILTS_REPO").isSome then " · atelie (puxa de il)" else ""
  IO.println s!"  repositorio: {nomeRep} ({ramRep}){caudaRep}"
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
  recibo raiz maquina etapa ok juiz prosa
  if !ok then
    IO.println "  A CADEIA FALHOU — ver .falhou-<rotulo>"
    IO.Process.exit 1

end Cadeia

def main (args : List String) : IO Unit := Cadeia.main args
