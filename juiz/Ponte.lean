import Std

/-
A PONTE — o juiz confere manifestos REAIS (o texto que a mão escreve).

Fatia 2 (SDD + TDD):
- resolver a licença POR HASH: a anotação aponta `licenca: <hash>`; a ponte
  acha a bolha-licença na COLEÇÃO pelo hash e lê o teto dela;
- já não se passa a licença como texto à parte.
- (o hash em si ainda não é conferido por sha256 — fatia seguinte)
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

/-- Uma coleção de bolhas: pares (hash, manifesto-texto). -/
abbrev Colecao := List (String × String)

/-- trim ASCII → String (sem deprecação). -/
def trimStr (s : String) : String := (s.trimAscii).toString

/-- "chave: valor" → (chave, valor). -/
def parseLinha (linha : String) : Option (String × String) :=
  match linha.splitOn ":" with
  | [chave, valor] => some (trimStr chave, trimStr valor)
  | _ => none

/-- Manifesto (texto) → lista de pares chave/valor. -/
def parseManifesto (texto : String) : List (String × String) :=
  let linhas := (texto.splitOn "\n").filter (fun l => trimStr l != "")
  linhas.filterMap parseLinha

/-- Busca o valor de um campo. -/
def campo (m : List (String × String)) (chave : String) : Option String :=
  match m.find? (fun p => p.1 == chave) with
  | some (_, v) => some v
  | none => none

/-- Acha o manifesto-texto de uma bolha na coleção pelo seu hash. -/
def acharBolha (c : Colecao) (h : String) : Option String :=
  match c.find? (fun p => p.1 == h) with
  | some (_, txt) => some txt
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

/-- O teto declarado por uma bolha-licença (a partir do texto dela). -/
def tetoDeTexto (texto : String) : Option Teto :=
  campo (parseManifesto texto) "teto" >>= parseTeto

/-- conteúdo: um hash, ou "ref <alvo>". -/
def parseReferencia (s : String) : Option Referencia :=
  if s.startsWith "ref " then some (.ref (s.drop 4).toString)
  else if ehHashSha256 s then some (.hash s)
  else none

/-- a referência respeita o teto? -/
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
Verifica uma anotação real contra a COLEÇÃO de bolhas.
A licença é resolvida POR HASH: a anotação diz `licenca: <hash>`.
-/
def verifica (anotacao : String) (colecao : Colecao) : Veredito :=
  let ma := parseManifesto anotacao
  match campo ma "tipo", campo ma "conteudo", campo ma "licenca" with
  | some "anotacao", some c, some l =>
      if !(ehHashSha256 l) then .reprovado "licença não é um hash sha256 válido"
      else
        match acharBolha colecao l with
        | none => .reprovado "licença não encontrada na coleção (hash sem bolha)"
        | some licTexto =>
            match tetoDeTexto licTexto with
            | none => .reprovado "bolha-licença sem teto válido"
            | some t =>
                match parseReferencia c with
                | none => .reprovado "conteúdo não é hash nem referência válida"
                | some r => if respeita t r then .verificado else .reprovado "ref sob teto 'hash' (restrito): não segue"
  | _, _, _ => .reprovado "manifesto mal-formado ou tipo desconhecido"

/- Fixtures PÚBLICAS (sintéticas). -/
def hashDe (c : Char) : String := String.ofList (List.replicate 64 c)

def hashRestrito    : String := hashDe '1'
def hashPrivado     : String := hashDe '2'
def hashInexistente : String := hashDe '9'

def licUsoRestrito : String := "tipo: licenca\nnome: uso-restrito\nteto: hash\nescopo: restrito\n"
def licUsoPrivado  : String := "tipo: licenca\nnome: uso-privado\nteto: hash,ref\nescopo: privado\n"

def colecao : Colecao := [(hashRestrito, licUsoRestrito), (hashPrivado, licUsoPrivado)]

def anotacaoHashSobPrivado : String := "tipo: anotacao\nconteudo: " ++ hashDe 'a' ++ "\nlicenca: " ++ hashPrivado ++ "\n"
def anotacaoRefSobRestrito : String := "tipo: anotacao\nconteudo: ref outra-bolha\nlicenca: " ++ hashRestrito ++ "\n"
def anotacaoRefSobPrivado  : String := "tipo: anotacao\nconteudo: ref outra-bolha\nlicenca: " ++ hashPrivado ++ "\n"
def anotacaoLicencaAusente : String := "tipo: anotacao\nconteudo: " ++ hashDe 'a' ++ "\nlicenca: " ++ hashInexistente ++ "\n"

/- TDD: anotação sob uso-privado (licença resolvida por hash) → verifica. -/
example : passou (verifica anotacaoHashSobPrivado colecao) = true := by native_decide

/- TDD: ref sob uso-restrito (teto hash) → reprova. -/
example : passou (verifica anotacaoRefSobRestrito colecao) = false := by native_decide

/- TDD: ref sob uso-privado (teto hash,ref) → verifica. -/
example : passou (verifica anotacaoRefSobPrivado colecao) = true := by native_decide

/- TDD: licença cujo hash NÃO está na coleção → reprova. -/
example : passou (verifica anotacaoLicencaAusente colecao) = false := by native_decide

/- Demonstração legível. -/
#eval verifica anotacaoHashSobPrivado colecao
#eval verifica anotacaoRefSobRestrito colecao
#eval verifica anotacaoLicencaAusente colecao

end Ponte
