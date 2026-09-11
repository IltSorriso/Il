import Bolha

/-
A PONTE — o juiz confere manifestos REAIS contra um DEPÓSITO.

FONTE ÚNICA DE VERDADE: importa `Bolha`; não redefine nada.

UNIFICAÇÃO: um manifesto TAMBÉM é conteúdo endereçado. Há UM depósito
(hash → texto) com tudo — achar bolha = achar o objeto por hash.

Fatia "b": o juiz RECALCULA o sha256 dos bytes do objeto (Sha256.endereco)
e confere contra o endereço declarado. Não confia na ferramenta que escreveu.
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

def parseLinha (linha : String) : Option (String × String) :=
  match linha.splitOn ":" with
  | [chave, valor] => some (trimStr chave, trimStr valor)
  | _ => none

def parseManifesto (texto : String) : List (String × String) :=
  let linhas := (texto.splitOn "\n").filter (fun l => trimStr l != "")
  linhas.filterMap parseLinha

def campo (m : List (String × String)) (chave : String) : Option String :=
  match m.find? (fun p => p.1 == chave) with
  | some (_, v) => some v
  | none => none

def acharObjeto (dep : Deposito) (h : String) : Option String :=
  match dep.find? (fun p => p.1 == h) with
  | some (_, txt) => some txt
  | none => none

def parseLicenca (s : String) : Option Licenca :=
  let s := trimStr s
  if s == "reservado" then some .reservado
  else if ehHashSha256 s then some (.referencia s)
  else none

def passou (v : Veredito) : Bool :=
  match v with
  | .verificado => true
  | .reprovado _ => false

/-- O objeto existe E seus bytes hasheiam para o endereço declarado. -/
def enderecoConfere (dep : Deposito) (h : String) : Bool :=
  match acharObjeto dep h with
  | none => false
  | some txt => Sha256.endereco txt == h

/--
Verifica uma anotação real contra o DEPÓSITO. Portões:
  1. conteúdo é hash sha256 bem-formado?                (forma)
  2. o objeto existe no depósito?                       (endereçamento)
  3. os bytes do objeto hasheiam para o endereço?       (fatia "b" — determinismo)
  4. a licença é `reservado`, ou hash de objeto existente, endereço conforme,
     e do tipo `licenca`?
-/
def verifica (anotacao : String) (dep : Deposito) : Veredito :=
  let ma := parseManifesto anotacao
  match campo ma "tipo", campo ma "conteudo", campo ma "licenca" with
  | some "anotacao", some c, some l =>
      if !(ehHashSha256 c) then .reprovado "conteúdo não é hash sha256 válido"
      else if !(noDeposito dep c) then .reprovado "objeto ausente do depósito (endereço quebrado)"
      else if !(enderecoConfere dep c) then .reprovado "o endereço não bate com os bytes do objeto"
      else
        match parseLicenca l with
        | none => .reprovado "licença nem 'reservado' nem hash sha256"
        | some .reservado => .verificado
        | some (.referencia h) =>
            if !(enderecoConfere dep h) then .reprovado "licença não encontrada ou endereço não confere"
            else
              match acharObjeto dep h with
              | none => .reprovado "licença não encontrada no depósito"
              | some licTexto =>
                  if campo (parseManifesto licTexto) "tipo" == some "licenca"
                  then .verificado
                  else .reprovado "objeto referenciado como licença não é do tipo licenca"
  | _, _, _ => .reprovado "manifesto mal-formado ou tipo desconhecido"

/- ============ fixtures com HASHES REAIS (o portão "b" os exige) ============ -/
def textoObj   : String := "o texto do objeto"
def bolhaLicCC : String := "tipo: licenca\ncatalogo: CC\nnome: CC0-1.0\n"

def hashObj   : String := "52e787efa9975672e759c540d8e69e86246a4198a17359df312be0de9f359594"
def hashLicCC : String := "05ea755230dae1fe011459465f162a8de31bebdff3810b2894a39648cdc4a4b0"

def textoNaoLic : String := "tipo: anotacao\nconteudo: " ++ hashObj ++ "\nlicenca: reservado\n"
def hashNaoLic  : String := "cdd055d7a7651abff09b3a1b2be1705a49f00726af59113e17d925e6568695a3"

/-- Objeto presente cuja chave NÃO é o sha256 do texto (endereço forjado). -/
def hashForjado : String := "5555555555555555555555555555555555555555555555555555555555555555"
def textoForjado : String := "um texto cujo endereco nao confere"

def hashAusente : String := String.ofList (List.replicate 64 '9')

def deposito : Deposito :=
  [ (hashObj, textoObj)
  , (hashLicCC, bolhaLicCC)
  , (hashNaoLic, textoNaoLic)
  , (hashForjado, textoForjado) ]

def anot (conteudo licenca : String) : String :=
  "tipo: anotacao\nconteudo: " ++ conteudo ++ "\nlicenca: " ++ licenca ++ "\n"

/- ============ TDD ============ -/
-- 1. reservado + objeto endereçado corretamente → verifica
example : passou (verifica (anot hashObj "reservado") deposito) = true := by native_decide
-- 2. licença por hash de objeto tipo licenca → verifica
example : passou (verifica (anot hashObj hashLicCC) deposito) = true := by native_decide
-- 3. objeto AUSENTE do depósito → reprova
example : passou (verifica (anot hashAusente "reservado") deposito) = false := by native_decide
-- 4. objeto presente mas ENDEREÇO FORJADO (bytes não hasheiam) → reprova  [fatia "b"]
example : passou (verifica (anot hashForjado "reservado") deposito) = false := by native_decide
-- 5. licença cujo hash não existe no depósito → reprova
example : passou (verifica (anot hashObj hashAusente) deposito) = false := by native_decide
-- 6. licença nem 'reservado' nem hash → reprova
example : passou (verifica (anot hashObj "xyz") deposito) = false := by native_decide
-- 7. conteúdo não é hash → reprova
example : passou (verifica (anot "nao-e-hash" "reservado") deposito) = false := by native_decide
-- 8. hash aponta p/ objeto que NÃO é do tipo licenca → reprova
example : passou (verifica (anot hashObj hashNaoLic) deposito) = false := by native_decide

#eval verifica (anot hashObj "reservado") deposito
#eval verifica (anot hashForjado "reservado") deposito
#eval verifica (anot hashObj hashLicCC) deposito

end Ponte
