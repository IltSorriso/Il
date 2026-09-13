import Bolha

/-
A PONTE — o juiz confere manifestos REAIS contra um DEPÓSITO.

FONTE ÚNICA DE VERDADE: importa `Bolha`; NÃO redefine nada. Cada portão usado
aqui (ehHashSha256, noDeposito, enderecoConfere, licencaOk) é o portão do spec,
cuja versão executável já está provada equivalente à versão lógica.

PORTÃO 0 — A FORMA CANÔNICA (fatia "d"): o juiz só julga texto na forma
canônica. Fecha o buraco de determinismo do MANIFESTO: sem isso a mesma bolha
teria duas grafias e, logo, dois endereços.

PORTÃO 3 — A REUNIÃO (2026-09-13): quando a espécie declara uma reunião, o
veredito confere que o campo da coisa INTEIRA é a união das partes, na ordem.
Antes desta fatia a regra vivia só no TESTE — uma segunda verdade —, e uma
canção que a quebrasse passava no veredito. Agora o veredito É o predicado do
spec (`reuniaoOkB` / `ReuniaoOk`, ligados por `reuniaoOkB_iff`).

TEOREMA DE CORREÇÃO (o que faltava para o SDD fechar):
`verifica_sound` — se o juiz diz `verificado`, então (1) o texto está na forma
canônica e (2) o manifesto satisfaz a ESPECIFICAÇÃO (`Bolha.ManifestoValido`).
O veredito deixa de descansar só em teste: descansa em prova.
-/

open Bolha

namespace Ponte

/-- O veredito do juiz sobre um manifesto real. -/
inductive Veredito where
  | verificado
  | reprovado : String → Veredito
  deriving Repr, BEq

/-- `.reprovado` nunca é `.verificado`. -/
theorem reprovado_ne_verificado (s : String) :
    Veredito.reprovado s ≠ Veredito.verificado := by
  intro hc; cases hc

def passou (v : Veredito) : Bool :=
  match v with
  | .verificado   => true
  | .reprovado _  => false

/-- O primeiro portão que falha, ou `none` se todos passam.
    Usa SÓ os portões do spec — não reimplementa nenhum. -/
def diagnostico (m : Manifesto) (dep : Deposito) : Option String :=
  if ehHashSha256 m.conteudo then
    if noDeposito dep m.conteudo then
      if enderecoConfere dep m.conteudo then
        if reuniaoOkB m dep then
          match parseLicenca m.licencaTexto with
          | none => some "licença nem 'reservado' nem hash sha256"
          | some lic =>
              if licencaOk dep lic then none
              else some "licença inválida (ausente do depósito, endereço não confere, ou não é do tipo licenca)"
        else some "o campo declarado não é a REUNIÃO das partes, na ordem (ou falta uma parte)"
      else some "o endereço não bate com os bytes do objeto"
    else some "objeto ausente do depósito (endereço quebrado)"
  else some "conteúdo não é hash sha256 válido"

/-- O juiz: texto real → veredito.
    O PORTÃO 0 é a FORMA CANÔNICA (fatia "d"): fora dela o texto nem é julgado —
    senão a mesma bolha teria duas grafias e, portanto, dois endereços. -/
def verifica (texto : String) (dep : Deposito) : Veredito :=
  if canonicidadeOk texto then
    match parseManifesto texto with
    | none => .reprovado "manifesto mal-formado ou tipo desconhecido"
    | some m =>
        match diagnostico m dep with
        | none    => .verificado
        | some msg => .reprovado msg
  else .reprovado "manifesto fora da forma canônica (campos fora de ordem, sintaxe não normalizada, espécie desconhecida ou campo faltando)"

/-- Ligação entre "sem diagnóstico" e o check booleano pleno do spec. -/
theorem diagnostico_none_iff (m : Manifesto) (dep : Deposito) :
    diagnostico m dep = none ↔ manifestoOkB m dep = true := by
  unfold diagnostico manifestoOkB
  cases hp : parseLicenca m.licencaTexto with
  | none =>
      cases h1 : ehHashSha256 m.conteudo <;>
      cases h2 : noDeposito dep m.conteudo <;>
      cases h3 : enderecoConfere dep m.conteudo <;>
      cases h4 : reuniaoOkB m dep <;>
      simp_all
  | some lic =>
      cases h1 : ehHashSha256 m.conteudo <;>
      cases h2 : noDeposito dep m.conteudo <;>
      cases h3 : enderecoConfere dep m.conteudo <;>
      cases h4 : reuniaoOkB m dep <;>
      cases h5 : licencaOk dep lic <;>
      simp_all

/-- O juiz responde `verificado` exatamente quando o texto é CANÔNICO e o
    diagnóstico é vazio. -/
theorem verifica_verificado_iff (texto : String) (dep : Deposito) :
    verifica texto dep = Veredito.verificado ↔
      canonicidadeOk texto = true ∧
      ∃ m', parseManifesto texto = some m' ∧ diagnostico m' dep = none := by
  unfold verifica
  by_cases hc : canonicidadeOk texto = true
  · rw [if_pos hc]
    cases hp : parseManifesto texto with
    | none => simp [hc, hp, reprovado_ne_verificado]
    | some m =>
        cases hd : diagnostico m dep with
        | none => simp [hc, hp, hd]
        | some msg => simp [hc, hp, hd, reprovado_ne_verificado]
  · rw [if_neg hc]
    simp [hc, reprovado_ne_verificado]

/--
  TEOREMA DE CORREÇÃO (soundness) — fecha o limiar SDD:
  se o juiz executável diz `verificado`, então o manifesto satisfaz o spec.
-/
theorem verifica_sound (texto : String) (dep : Deposito)
    (h : verifica texto dep = Veredito.verificado) :
    canonicidadeOk texto = true ∧
    ∃ m, parseManifesto texto = some m ∧ ManifestoValido m dep := by
  obtain ⟨hc, m, hm, hd⟩ := (verifica_verificado_iff texto dep).mp h
  exact ⟨hc, m, hm, (manifestoOkB_iff m dep).mp ((diagnostico_none_iff m dep).mp hd)⟩

/- ============ fixtures com HASHES REAIS (o portão do endereço os exige) ============ -/

def textoObj   : String := "o texto do objeto"
def bolhaLicCC : String := "tipo: licenca\ncatalogo: CC\nnome: CC0-1.0\n"

def hashObj    : String := "52e787efa9975672e759c540d8e69e86246a4198a17359df312be0de9f359594"
def hashLicCC  : String := "05ea755230dae1fe011459465f162a8de31bebdff3810b2894a39648cdc4a4b0"

def textoNaoLic : String := "tipo: anotacao\nconteudo: " ++ hashObj ++ "\nlicenca: reservado\n"
def hashNaoLic  : String := "cdd055d7a7651abff09b3a1b2be1705a49f00726af59113e17d925e6568695a3"

/-- Objeto presente cuja chave NÃO é o sha256 do texto (endereço forjado). -/
def hashForjado : String := "5555555555555555555555555555555555555555555555555555555555555555"
def textoForjado : String := "um texto cujo endereco nao confere"

def hashAusente : String := String.ofList (List.replicate 64 '9')

/-- O depósito de prova. O TEXTO entra como BYTES — é o mesmo que a mão faz
    (`gravar_objeto(dados: bytes)`), e nenhum endereço muda por isso: o endereço
    sempre foi o sha256 dos bytes. -/
def deposito : Deposito :=
  [ (hashObj, textoObj.toUTF8)
  , (hashLicCC, bolhaLicCC.toUTF8)
  , (hashNaoLic, textoNaoLic.toUTF8)
  , (hashForjado, textoForjado.toUTF8) ]

def anot (conteudo licenca : String) : String :=
  "tipo: anotacao\nconteudo: " ++ conteudo ++ "\nlicenca: " ++ licenca ++ "\n"

/- ============ TDD: os portões do juiz ============ -/
-- 1. reservado + objeto endereçado corretamente → verifica
example : passou (verifica (anot hashObj "reservado") deposito) = true := by native_decide
-- 2. licença por hash de objeto tipo licenca → verifica
example : passou (verifica (anot hashObj hashLicCC) deposito) = true := by native_decide
-- 3. objeto AUSENTE do depósito → reprova
example : passou (verifica (anot hashAusente "reservado") deposito) = false := by native_decide
-- 4. objeto presente mas ENDEREÇO FORJADO (bytes não hasheiam) → reprova
example : passou (verifica (anot hashForjado "reservado") deposito) = false := by native_decide
-- 5. licença cujo hash não existe no depósito → reprova
example : passou (verifica (anot hashObj hashAusente) deposito) = false := by native_decide
-- 6. licença nem 'reservado' nem hash → reprova
example : passou (verifica (anot hashObj "xyz") deposito) = false := by native_decide
-- 7. conteúdo não é hash → reprova
example : passou (verifica (anot "nao-e-hash" "reservado") deposito) = false := by native_decide
-- 8. hash aponta p/ objeto que NÃO é do tipo licenca → reprova
example : passou (verifica (anot hashObj hashNaoLic) deposito) = false := by native_decide
-- 9. hash em MAIÚSCULAS não é endereço canônico → reprova  [canonicidade]
example : passou (verifica (anot (hashObj.toUpper) "reservado") deposito) = false := by native_decide
-- 10. campos em ORDEM não-canônica → reprova  [forma canônica — fatia "d"]
example : passou (verifica ("tipo: anotacao\nlicenca: reservado\nconteudo: " ++ hashObj ++ "\n") deposito) = false := by native_decide

#eval verifica (anot hashObj "reservado") deposito
#eval verifica (anot hashForjado "reservado") deposito
#eval verifica (anot hashObj (hashLicCC.toUpper)) deposito

end Ponte
