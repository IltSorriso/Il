import Std

/-
A PONTE — o juiz confere manifestos REAIS (o texto que a mão escreve).

Modelo simplificado (2026-09-11):
- O conteúdo é SEMPRE um hash sha256 (endereçamento por conteúdo).
- A licença é `reservado` OU o hash de uma bolha-licença que exista na coleção
  e seja do tipo `licenca` (catálogo real: CC / SPDX).
- O eixo "teto" (hash vs ref) morreu — não há mais checagem de teto.
- (o hash em si ainda não é conferido por sha256 — fatia seguinte)
-/

namespace Ponte

/-- O veredito do juiz sobre um manifesto real. -/
inductive Veredito where
  | verificado
  | reprovado : String → Veredito
  deriving Repr

/-- A licença declarada: `reservado` ou referência (hash) a uma bolha-licença. -/
inductive Licenca where
  | reservado
  | referencia : String → Licenca
  deriving BEq, Repr, DecidableEq

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

/-- "reservado" | <hash sha256> → Licenca. -/
def parseLicenca (s : String) : Option Licenca :=
  let s := trimStr s
  if s == "reservado" then some .reservado
  else if ehHashSha256 s then some (.referencia s)
  else none

/-- o veredito foi verde? -/
def passou (v : Veredito) : Bool :=
  match v with
  | .verificado => true
  | .reprovado _ => false

/--
Verifica uma anotação real contra a COLEÇÃO de bolhas.
- conteúdo: hash sha256 bem-formado (endereçamento por conteúdo, sempre);
- licença: `reservado`, OU hash de uma bolha que exista na coleção E seja do tipo licenca.
-/
def verifica (anotacao : String) (colecao : Colecao) : Veredito :=
  let ma := parseManifesto anotacao
  match campo ma "tipo", campo ma "conteudo", campo ma "licenca" with
  | some "anotacao", some c, some l =>
      if !(ehHashSha256 c) then .reprovado "conteúdo não é hash sha256 válido"
      else
        match parseLicenca l with
        | none => .reprovado "licença nem 'reservado' nem hash sha256"
        | some .reservado => .verificado
        | some (.referencia h) =>
            match acharBolha colecao h with
            | none => .reprovado "bolha-licença não encontrada na coleção"
            | some licTexto =>
                if campo (parseManifesto licTexto) "tipo" == some "licenca"
                then .verificado
                else .reprovado "bolha referenciada como licença não é do tipo licenca"
  | _, _, _ => .reprovado "manifesto mal-formado ou tipo desconhecido"

/- Fixtures PÚBLICAS (sintéticas). -/
def hashDe (c : Char) : String := String.ofList (List.replicate 64 c)

def hashConteudo : String := hashDe 'a'
def hashLicCC    : String := hashDe '1'
def hashNaoLic   : String := hashDe '2'
def hashAusente  : String := hashDe '9'

/-- Bolha-licença de catálogo real (Creative Commons). -/
def bolhaLicCC : String := "tipo: licenca\ncatalogo: CC\nnome: CC0-1.0\n"
/-- Uma bolha que NÃO é licença (para provar que o tipo é conferido). -/
def bolhaNaoLic : String := "tipo: anotacao\nconteudo: " ++ hashConteudo ++ "\nlicenca: reservado\n"

def colecao : Colecao := [(hashLicCC, bolhaLicCC), (hashNaoLic, bolhaNaoLic)]

def aReservado   : String := "tipo: anotacao\nconteudo: " ++ hashConteudo ++ "\nlicenca: reservado\n"
def aComLicenca  : String := "tipo: anotacao\nconteudo: " ++ hashConteudo ++ "\nlicenca: " ++ hashLicCC ++ "\n"
def aAusente     : String := "tipo: anotacao\nconteudo: " ++ hashConteudo ++ "\nlicenca: " ++ hashAusente ++ "\n"
def aInvalida    : String := "tipo: anotacao\nconteudo: " ++ hashConteudo ++ "\nlicenca: xyz\n"
def aConteudoRui : String := "tipo: anotacao\nconteudo: nao-e-hash\nlicenca: reservado\n"
def aNaoLicenca  : String := "tipo: anotacao\nconteudo: " ++ hashConteudo ++ "\nlicenca: " ++ hashNaoLic ++ "\n"

/- TDD:1 licença `reservado` → verifica. -/
example : passou (verifica aReservado colecao) = true := by native_decide
/- TDD:2 licença por hash de bolha tipo `licenca` → verifica. -/
example : passou (verifica aComLicenca colecao) = true := by native_decide
/- TDD:3 licença cujo hash NÃO está na coleção → reprova. -/
example : passou (verifica aAusente colecao) = false := by native_decide
/- TDD:4 licença nem 'reservado' nem hash → reprova. -/
example : passou (verifica aInvalida colecao) = false := by native_decide
/- TDD:5 conteúdo não é hash → reprova. -/
example : passou (verifica aConteudoRui colecao) = false := by native_decide
/- TDD:6 hash aponta p/ bolha que NÃO é do tipo licenca → reprova. -/
example : passou (verifica aNaoLicenca colecao) = false := by native_decide

/- Demonstração legível. -/
#eval verifica aReservado colecao
#eval verifica aComLicenca colecao
#eval verifica aAusente colecao

end Ponte
