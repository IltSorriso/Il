import Bolha

/-
A PONTE — o juiz confere manifestos REAIS contra um DEPÓSITO.

FONTE ÚNICA DE VERDADE: importa `Bolha`; não redefine nada.

UNIFICAÇÃO (2026-09-11): a "coleção" não é uma estrutura à parte — um manifesto
TAMBÉM é conteúdo endereçado. Então existe UM depósito (hash → texto), e ele
guarda tanto os objetos de conteúdo quanto os manifestos. Achar uma bolha =
achar o objeto por hash e conferir que ele é um manifesto do tipo certo.

Fatia "a": além da forma, o juiz confere o ENDEREÇAMENTO — o hash de conteúdo
declarado tem de existir no depósito. O Bool desse check está provado
equivalente à especificação lógica (Bolha.noDeposito_iff).
-/

open Bolha

namespace Ponte

/-- O veredito do juiz sobre um manifesto real. -/
inductive Veredito where
  | verificado
  | reprovado : String → Veredito
  deriving Repr

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

/-- O texto do objeto cujo endereço é `h`, se existir no depósito. -/
def acharObjeto (dep : Deposito) (h : String) : Option String :=
  match dep.find? (fun p => p.1 == h) with
  | some (_, txt) => some txt
  | none => none

/-- "reservado" | <hash sha256> → Licenca (tipo do spec). -/
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
Verifica uma anotação real contra o DEPÓSITO. Portões (cada um reprova):
  1. conteúdo é hash sha256 bem-formado?                      (forma)
  2. o objeto existe no depósito?                             (endereçamento — fatia "a")
  3. a licença é `reservado`, ou o hash de um objeto que existe no depósito
     E é um manifesto do tipo `licenca`?
-/
def verifica (anotacao : String) (dep : Deposito) : Veredito :=
  let ma := parseManifesto anotacao
  match campo ma "tipo", campo ma "conteudo", campo ma "licenca" with
  | some "anotacao", some c, some l =>
      if !(ehHashSha256 c) then .reprovado "conteúdo não é hash sha256 válido"
      else if !(noDeposito dep c) then .reprovado "objeto ausente do depósito (endereço quebrado)"
      else
        match parseLicenca l with
        | none => .reprovado "licença nem 'reservado' nem hash sha256"
        | some .reservado => .verificado
        | some (.referencia h) =>
            match acharObjeto dep h with
            | none => .reprovado "licença não encontrada no depósito"
            | some licTexto =>
                if campo (parseManifesto licTexto) "tipo" == some "licenca"
                then .verificado
                else .reprovado "objeto referenciado como licença não é do tipo licenca"
  | _, _, _ => .reprovado "manifesto mal-formado ou tipo desconhecido"

/- ============ fixtures sintéticas (TDD de unidade) ============ -/
def hashDe (c : Char) : String := String.ofList (List.replicate 64 c)

def hashConteudo : String := hashDe 'a'
def hashOutro    : String := hashDe 'b'
def hashLicCC    : String := hashDe '1'
def hashNaoLic   : String := hashDe '2'
def hashAusente  : String := hashDe '9'

def bolhaLicCC  : String := "tipo: licenca\ncatalogo: CC\nnome: CC0-1.0\n"
def bolhaNaoLic : String := "tipo: anotacao\nconteudo: " ++ hashConteudo ++ "\nlicenca: reservado\n"

/-- O depósito: conteúdo + a licença + um objeto que não é licença. -/
def deposito : Deposito :=
  [(hashConteudo, "o texto do objeto"), (hashLicCC, bolhaLicCC), (hashNaoLic, bolhaNaoLic)]

def anot (conteudo licenca : String) : String :=
  "tipo: anotacao\nconteudo: " ++ conteudo ++ "\nlicenca: " ++ licenca ++ "\n"

/- ============ TDD: 7 testes ============ -/
-- 1. reservado + objeto no depósito → verifica
example : passou (verifica (anot hashConteudo "reservado") deposito) = true := by native_decide
-- 2. licença por hash de objeto tipo licenca + objeto no depósito → verifica
example : passou (verifica (anot hashConteudo hashLicCC) deposito) = true := by native_decide
-- 3. objeto AUSENTE do depósito → reprova   [fatia "a"]
example : passou (verifica (anot hashOutro "reservado") deposito) = false := by native_decide
-- 4. licença cujo hash não existe no depósito → reprova
example : passou (verifica (anot hashConteudo hashAusente) deposito) = false := by native_decide
-- 5. licença nem 'reservado' nem hash → reprova
example : passou (verifica (anot hashConteudo "xyz") deposito) = false := by native_decide
-- 6. conteúdo não é hash → reprova
example : passou (verifica (anot "nao-e-hash" "reservado") deposito) = false := by native_decide
-- 7. hash aponta p/ objeto que NÃO é do tipo licenca → reprova
example : passou (verifica (anot hashConteudo hashNaoLic) deposito) = false := by native_decide

/- Demonstração legível. -/
#eval verifica (anot hashConteudo "reservado") deposito
#eval verifica (anot hashOutro "reservado") deposito
#eval verifica (anot hashConteudo hashLicCC) deposito

end Ponte
