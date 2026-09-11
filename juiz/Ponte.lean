import Std

/-
A PONTE — o juiz confere manifestos REAIS (o texto que a mão escreve).

Primeira fatia (SDD + TDD):
- parsear o formato provisório "chave: valor";
- verificar a FORMA (campos presentes, hash sha256 bem-formado);
- resolver o teto da licença (DADO, não tabela fixa) e conferir que a
  referência o respeita.

As provas abstratas seguem em Bolha.lean; aqui a ponte liga o juiz ao dado real.
-/

namespace Ponte

/-- O teto (fiel a Bolha.Teto). -/
inductive Teto where
  | soHash
  | hashOuRef
  deriving BEq, Repr, DecidableEq

/-- Uma referência a sub-bolha: congelada (hash) ou viva (ref). -/
inductive Referencia where
  | hash : String → Referencia
  | ref  : String → Referencia
  deriving BEq, Repr, DecidableEq

/-- O veredito do juiz sobre um manifesto real. -/
inductive Veredito where
  | verificado
  | reprovado : String → Veredito
  deriving Repr

/-- trim ASCII → String (sem deprecação). -/
def trimStr (s : String) : String := (s.trimAscii).toString

/-- "chave: valor" → (chave, valor), ignorando espaços ao redor. -/
def parseLinha (linha : String) : Option (String × String) :=
  match linha.splitOn ":" with
  | [chave, valor] => some (trimStr chave, trimStr valor)
  | _ => none

/-- Manifesto (texto) → lista de pares chave/valor (linhas vazias ignoradas). -/
def parseManifesto (texto : String) : List (String × String) :=
  let linhas := (texto.splitOn "\n").filter (fun l => trimStr l != "")
  linhas.filterMap parseLinha

/-- Busca o valor de um campo. -/
def campo (m : List (String × String)) (chave : String) : Option String :=
  match m.find? (fun p => p.1 == chave) with
  | some (_, v) => some v
  | none => none

/-- c é dígito hexadecimal? -/
def ehHex (c : Char) : Bool :=
  c.isDigit || ('a' <= c && c <= 'f') || ('A' <= c && c <= 'F')

/-- s é um hash sha256 (64 hex)? -/
def ehHashSha256 (s : String) : Bool :=
  s.length == 64 && s.all ehHex

/-- "hash" | "hash,ref" → Teto. -/
def parseTeto (s : String) : Option Teto :=
  match s with
  | "hash" => some .soHash
  | "hash,ref" => some .hashOuRef
  | _ => none

/-- conteúdo: um hash, ou "ref <alvo>" (seguir a história). -/
def parseReferencia (s : String) : Option Referencia :=
  if s.startsWith "ref " then some (.ref (s.drop 4).toString)
  else if ehHashSha256 s then some (.hash s)
  else none

/-- a referência respeita o teto? (espelho de Bolha.respeitaTeto) -/
def respeita (teto : Teto) (r : Referencia) : Bool :=
  match teto, r with
  | .soHash, .ref _ => false
  | _, _ => true

/-- o veredito foi verde? -/
def passou (v : Veredito) : Bool :=
  match v with
  | .verificado => true
  | .reprovado _ => false

/--
Verifica uma anotação real contra o manifesto da licença que a governa.
Forma + teto (o teto vem do DADO da licença, não de uma tabela fixa).
-/
def verifica (anotacao : String) (licenca : String) : Veredito :=
  let ma := parseManifesto anotacao
  let ml := parseManifesto licenca
  let tipoA := campo ma "tipo"
  let conteudo := campo ma "conteudo"
  let licHash := campo ma "licenca"
  let teto := campo ml "teto" >>= parseTeto
  match tipoA, conteudo, licHash, teto with
  | some "anotacao", some c, some l, some t =>
      if !(ehHashSha256 l) then .reprovado "licença não é um hash sha256 válido"
      else match parseReferencia c with
        | none => .reprovado "conteúdo não é hash nem referência válida"
        | some r => if respeita t r then .verificado else .reprovado "ref sob teto 'hash' (restrito): não segue"
  | _, _, _, _ => .reprovado "manifesto mal-formado ou tipo desconhecido"

/- Fixtures PÚBLICAS (sintéticas; não vazam o diário). -/
def licUsoRestrito : String := "tipo: licenca\nnome: uso-restrito\nteto: hash\nescopo: restrito\n"
def licUsoPrivado  : String := "tipo: licenca\nnome: uso-privado\nteto: hash,ref\nescopo: privado\n"

def hashExemplo : String := "c6478dd844e67bbbb9b618a937323897c5fc9484f4131fdb52a2fc3bbb07ba6a"

def anotacaoHash : String := "tipo: anotacao\nconteudo: " ++ hashExemplo ++ "\nlicenca: " ++ hashExemplo ++ "\n"
def anotacaoRef  : String := "tipo: anotacao\nconteudo: ref outra-bolha\nlicenca: " ++ hashExemplo ++ "\n"
def anotacaoQuebrada : String := "tipo: anotacao\nconteudo: xyz\nlicenca: " ++ hashExemplo ++ "\n"

/- TDD: o caso verde. -/
example : passou (verifica anotacaoHash licUsoPrivado) = true := by native_decide

/- TDD: ref sob teto 'hash' (restrito) reprova. -/
example : passou (verifica anotacaoRef licUsoRestrito) = false := by native_decide

/- TDD: ref sob teto 'hash,ref' (privado/livre) passa. -/
example : passou (verifica anotacaoRef licUsoPrivado) = true := by native_decide

/- TDD: conteúdo malformado reprova. -/
example : passou (verifica anotacaoQuebrada licUsoPrivado) = false := by native_decide

/- TDD: manifesto sem tipo reprova. -/
example : passou (verifica ("conteudo: " ++ hashExemplo) licUsoPrivado) = false := by native_decide

/- Demonstração legível (não é teste de CI). -/
#eval verifica anotacaoHash licUsoPrivado
#eval verifica anotacaoRef licUsoRestrito
#eval verifica anotacaoRef licUsoPrivado

end Ponte
