/-
HIGIENE DA PROSA — o juiz da FORMA dos documentos, em Lean 4.

O juiz em Lean prova a forma das BOLHAS. Este prova a forma dos DOCUMENTOS.

  1. todo documento .md declara o seu TIPO e a sua AUTORIDADE num cabeçalho;
  2. documento que AFIRMA O PRESENTE não usa TERMO MORTO (o diário pode
     narrar o que morreu, porque é datado);
  3. todo caminho apontado entre crases EXISTE — renomear arquivo sem atualizar
     a prosa deixa de ser silêncio e vira build vermelho;
  4. SÓ a capa pode morar na raiz;
  5. o mapa é GERADO, nunca escrito à mão e nunca versionado.

Portado de `higiene.py` (160 linhas). As três regexes foram escritas à mão:
CABECALHO `<!--\s*doc:\s*([^>]*?)-->`, CAMPO `(\w+)\s*=\s*(\S+)`,
CRASE `` `([^`\n]+)` ``.
-/

namespace Higiene

def pular : List String := [".git", "node_modules", "deposito", "bolhas"]

/-- tipo -> (autoridade exigida, afirma o presente?, pode morar na raiz?) -/
def naturezas : List (String × String × Bool × Bool) :=
  [("capa",      "pitch",         true,  true),
   ("apontador", "gerado",        true,  false),
   ("contrato",  "retrospectiva", true,  false),
   ("conversa",  "historico",     false, false)]

/-- Termos que o código não usa mais. Lista curta e datada de propósito:
    ela só cresce, e cada linha aqui é uma mentira que a prosa não pode contar. -/
def termosMortos : List (String × String × String) :=
  [("uso-restrito", "2026-09-11", "virou `reservado` ou hash de bolha-licenca"),
   ("uso-livre",    "2026-09-11", "idem"),
   ("uso-privado",  "2026-09-11", "idem"),
   ("sem-registro", "2026-09-11", "idem"),
   ("LICENCAS.md",  "2026-09-11", "documento-sombra, removido")]

def extensoes : List String :=
  [".lean", ".py", ".md", ".yml", ".yaml", ".bolha", ".txt", ".json"]

-- ── os pedaços de string que o Lean não traz prontos ────────────────────────

def comecaCom (pre s : String) : Bool := s.toList.take pre.length == pre.toList

def terminaCom (suf s : String) : Bool :=
  if suf.length > s.length then false
  else s.toList.drop (s.length - suf.length) == suf.toList

/-- Acha `sub` dentro de `s`. -/
partial def contemSub (sub s : String) : Bool :=
  let n := sub.length
  if n == 0 then true
  else
    let rec go : List Char → Bool
      | [] => false
      | c :: rest => if (c :: rest).take n == sub.toList then true else go rest
    go s.toList

def ehPalavra (c : Char) : Bool := c.isAlphanum || c == '_'
def ehEspaco (c : Char) : Bool := c == ' ' || c == '\t' || c == '\r'

-- ── as três regexes, à mão ──────────────────────────────────────────────────

/-- `<!--` … `doc:` … `-->` — devolve o que vem depois de `doc:`. -/
def acharCabecalho (linha : String) : Option String :=
  match (linha.splitOn "<!--").drop 1 with
  | [] => none
  | resto :: _ =>
      match resto.splitOn "-->" with
      | [] => none
      | dentro :: _ =>
          match (dentro.splitOn "doc:").drop 1 with
          | [] => none
          | corpo :: _ => some corpo

/-- `(\w+)\s*=\s*(\S+)` — todos os pares do cabeçalho. -/
partial def campos : List Char → List (String × String)
  | [] => []
  | c :: resto =>
      if ehPalavra c then
        let palavra := (c :: resto).takeWhile ehPalavra
        let r1 := (c :: resto).dropWhile ehPalavra
        let r2 := r1.dropWhile ehEspaco
        match r2 with
        | '=' :: r3 =>
            let r4 := r3.dropWhile ehEspaco
            let valor := r4.takeWhile (fun x => !ehEspaco x && x != '\n')
            (String.ofList palavra, String.ofList valor) :: campos (r4.dropWhile (fun x => !ehEspaco x && x != '\n'))
        | _ => campos r1
      else campos resto

/-- `` `([^`\n]+)` `` — os trechos entre crases. -/
partial def crases : List Char → List String
  | [] => []
  | '`' :: resto =>
      let dentro := resto.takeWhile (fun c => c != '`' && c != '\n')
      let sobra := (resto.dropWhile (fun c => c != '`' && c != '\n')).drop 1
      if dentro.isEmpty then crases sobra else String.ofList dentro :: crases sobra
  | _ :: resto => crases resto

-- ── a varredura ────────────────────────────────────────────────────────────

/-- Todo `.md` sob a raiz, menos o que precisa ser pulado. Caminhos relativos. -/
partial def documentos (dir rel : String) : IO (List String) := do
  let es ← System.FilePath.readDir dir
  let mut achados : List String := []
  for e in es do
    let filho := if rel.isEmpty then e.fileName else rel ++ "/" ++ e.fileName
    if ← System.FilePath.isDir e.path then
      if pular.any (fun d => d == e.fileName) || comecaCom "." e.fileName then continue
      achados := achados ++ (← documentos e.path.toString filho)
    else
      if terminaCom ".md" e.fileName then achados := achados ++ [filho]
  pure achados

/-- Lê o cabeçalho nas primeiras 10 linhas. -/
def lerCabecalho (caminho : String) : IO (Option (List (String × String))) := do
  let texto ← IO.FS.readFile caminho
  let mut res : Option (List (String × String)) := none
  for linha in (texto.splitOn "\n").take 10 do
    if res.isNone then
      match acharCabecalho linha with
      | some dentro => res := some (campos dentro.toList)
      | none => pure ()
  pure res

/-- Insere `x` numa lista já ordenada. -/
def inserir (x : String) : List String → List String
  | [] => [x]
  | y :: ys => if compare x y != .gt then x :: y :: ys else y :: inserir x ys

def ordenar : List String → List String
  | [] => []
  | x :: xs => inserir x (ordenar xs)

/-- Caminhos entre crases com separador de pasta e extensão conhecida. -/
def caminhosCitados (caminho : String) : IO (List String) := do
  let texto ← IO.FS.readFile caminho
  let achados := (crases texto.toList).filter (fun c =>
    let c := c.trim
    contemSub "/" c && !contemSub "<" c && !contemSub "*" c
      && extensoes.any (fun e => terminaCom e c))
  pure (ordenar (achados.map (fun c => c.trim)))

def distintos : List String → List String
  | [] => []
  | x :: xs => if xs.contains x then distintos xs else x :: distintos xs

/-- A verificação inteira. Devolve a lista de falhas e as linhas do mapa. -/
def verificar (raiz : String) (mostrarMapa : Bool) : IO UInt32 := do
  let mut falhas : List String := []
  let docs ← documentos raiz ""
  let mut linhasMapa : List (String × String × String) := []
  for rel in ordenar docs do
    let caminho := raiz ++ "/" ++ rel
    match ← lerCabecalho caminho with
    | none =>
        falhas := falhas ++ [s!"{rel}: sem cabecalho `<!-- doc: tipo=... autoridade=... -->`"]
    | some cab =>
        let g (k : String) : Option String := (cab.find? (fun p => p.1 == k)).map Prod.snd
        match g "tipo" with
        | none => falhas := falhas ++ [s!"{rel}: sem cabecalho"]
        | some tipo =>
          let nat := naturezas.find? (fun n => n.1 == tipo)
          match nat with
          | none =>
              falhas := falhas ++ [s!"{rel}: tipo desconhecido '{tipo}' (validos: capa, apontador, contrato, conversa)"]
          | some (_, esperada, afirmaPresente, naRaiz) =>
              let autoridade := (g "autoridade").getD ""
              if autoridade != esperada then
                falhas := falhas ++ [s!"{rel}: tipo={tipo} exige autoridade={esperada}, veio '{autoridade}'"]
              if !(contemSub "/" rel) && !naRaiz then
                falhas := falhas ++ [s!"{rel}: tipo={tipo} nao mora na raiz — a raiz e o produto (so a capa fica nela)"]
              if afirmaPresente then
                let texto ← IO.FS.readFile caminho
                for (termo, quando, oQue) in termosMortos do
                  if contemSub termo texto then
                    falhas := falhas ++ [s!"{rel}: usa termo morto '{termo}' (morreu em {quando}: {oQue})"]
                -- A checagem de CAMINHO segue a mesma regra da de TERMO MORTO: só
                -- vale para documento que AFIRMA O PRESENTE. Um diário datado citar
                -- `arreio.py` numa passagem de 2026-09-15 é VERDADE daquela data —
                -- cobrar dele o caminho de hoje seria falsificar o registro, que é
                -- o mesmo defeito que renomear o diário. Contrato, capa e apontador
                -- afirmam o presente, e é deles que se cobra.
                for citado in ← caminhosCitados caminho do
                  if !(← System.FilePath.pathExists (raiz ++ "/" ++ citado)) then
                    falhas := falhas ++ [s!"{rel}: aponta para `{citado}` — nao existe"]
              linhasMapa := linhasMapa ++ [(rel, tipo, autoridade)]
  if mostrarMapa then
    IO.println "--- MAPA: onde a verdade mora (GERADO, nunca versionado) ---"
    IO.println ""
    IO.println "| documento | tipo | autoridade |"
    IO.println "|---|---|---|"
    for (rel, tipo, autoridade) in linhasMapa do
      IO.println s!"| `{rel}` | {tipo} | {autoridade} |"
    IO.println ""
    IO.println s!"{linhasMapa.length} documento(s) declarado(s)."
    IO.println "--- fim do mapa ---"
    IO.println ""
  IO.println s!"higiene da prosa: {docs.length} documento(s) varrido(s), {falhas.length} falha(s)"
  for f in falhas do
    IO.println s!"  FALHA  {f}"
  pure (if falhas.isEmpty then 0 else 1)

def main (args : List String) : IO Unit := do
  let raiz := if (args.find? (fun a => a == "--raiz")).isSome
              then (args.dropWhile (fun a => a != "--raiz")).drop 1 |>.head?.getD "."
              else "."
  -- O CÓDIGO DE SAÍDA IMPORTA. `discard` o jogava fora: o higiene dizia
  -- "3 falha(s)" e saía com 0 — falha reportada que não reprova o build é
  -- pior que falha silenciosa, porque PARECE conferida.
  let rc ← verificar raiz (args.contains "--mapa")
  if rc != 0 then IO.Process.exit rc.toUInt8

end Higiene

def main (args : List String) : IO Unit := Higiene.main args
