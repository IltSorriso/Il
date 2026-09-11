import Sha256

/-
O JUÍZ — especificação da Bolha válida (Lean 4)

FONTE ÚNICA DE VERDADE: a ponte (Ponte.lean) IMPORTA este arquivo; ela não
redefine nada. Se o spec mudar, a ponte muda por consequência.

Modelo simplificado (2026-09-11):
- Licença explícita: `reservado` (ausência deliberada de direito) ou referência
  (hash) a uma bolha-licença de catálogo real (CC / SPDX).
- Endereçamento SEMPRE por hash (o eixo "teto" morreu).
-/

namespace Bolha

/-- A licença declarada por uma bolha. -/
inductive Licenca where
  | reservado
  | referencia : String → Licenca
  deriving BEq, Repr, DecidableEq

/-- O manifesto (os campos vão crescer com as espécies). -/
structure Manifesto where
  tipo     : String
  conteudo : String   /- hash sha256 (endereçado por conteúdo) -/
  licenca  : Licenca
  deriving Repr

/-- c é dígito hexadecimal? -/
def ehHex (c : Char) : Bool :=
  c.isDigit || ('a' <= c && c <= 'f') || ('A' <= c && c <= 'F')

/-- s é um hash sha256 (64 hex)? -/
def ehHashSha256 (s : String) : Bool :=
  s.length == 64 && s.all ehHex

def conteudoOk (m : Manifesto) : Bool := ehHashSha256 m.conteudo

def licencaOk : Licenca → Bool
  | .reservado    => true
  | .referencia h => ehHashSha256 h

/-- FORMA da bolha: conteúdo endereçado por hash E licença explícita. -/
def valida (m : Manifesto) : Bool := conteudoOk m && licencaOk m.licenca

/-
  TEOREMA 1 (determinismo): toda bolha válida carrega conteúdo endereçado
  por um hash sha256. Não há referência "viva".
-/
theorem valida_conteudo_hash (m : Manifesto) (h : valida m = true) :
    ehHashSha256 m.conteudo = true := by
  simp [valida, conteudoOk] at h
  exact h.1

/-- TEOREMA 2 (estados disjuntos): `reservado` nunca é uma referência. -/
theorem reservado_nao_e_referencia (h : String) :
    Licenca.reservado ≠ Licenca.referencia h := by
  intro hc; cases hc

theorem reservado_valido : licencaOk Licenca.reservado = true := rfl

/- ============ O DEPÓSITO (endereçamento por conteúdo) ============ -/

/-- Um depósito por conteúdo: pares (hash, texto do objeto). -/
abbrev Deposito := List (String × String)

/-- O objeto está presente no depósito? — CHECK EXECUTÁVEL. -/
def noDeposito (dep : Deposito) (h : String) : Bool :=
  dep.any (fun p => p.1 == h)

/-- O objeto está presente no depósito? — ESPECIFICAÇÃO LÓGICA. -/
def Presente (dep : Deposito) (h : String) : Prop :=
  ∃ p ∈ dep, p.1 = h

/-
  TEOREMA 3 (REFINAMENTO) — o núcleo confiável do juiz:
  o check executável (Bool) equivale à especificação lógica (Prop).
  Isto é o que faz o veredito ser PROVA, não fé na implementação.
-/
theorem noDeposito_iff (dep : Deposito) (h : String) :
    noDeposito dep h = true ↔ Presente dep h := by
  simp [noDeposito, Presente, List.any_eq_true]

/-- Corolário: hash ausente do depósito não está presente (contrapositiva). -/
theorem ausente_nao_presente (dep : Deposito) (h : String)
    (hh : noDeposito dep h = false) : ¬ Presente dep h := by
  intro hp
  rw [← noDeposito_iff] at hp
  rw [hp] at hh
  exact Bool.noConfusion hh

/- ============ ENDEREÇAMENTO POR CONTEÚDO (fatia "b") ============ -/

/-- O objeto está endereçado corretamente? O hash do TEXTO tem de ser a chave.
    Aqui o juiz RECALCULA o sha256 (Sha256.endereco) — não confia em ninguém. -/
def objetoEnderecado (p : String × String) : Bool :=
  Sha256.endereco p.2 == p.1

/-- O depósito inteiro é endereçado por conteúdo? — CHECK EXECUTÁVEL. -/
def depositoEnderecado (dep : Deposito) : Bool :=
  dep.all objetoEnderecado

/-- O depósito inteiro é endereçado por conteúdo? — ESPECIFICAÇÃO LÓGICA. -/
def DepositoEnderecado (dep : Deposito) : Prop :=
  ∀ p ∈ dep, Sha256.endereco p.2 = p.1

/-
  TEOREMA 4 (REFINAMENTO do endereçamento): o check executável equivale à
  especificação lógica. Fecha a promessa "determinístico": o juiz recalcula
  o hash dos bytes e confere contra o endereço — com prova, não com fé.
-/
theorem depositoEnderecado_iff (dep : Deposito) :
    depositoEnderecado dep = true ↔ DepositoEnderecado dep := by
  simp [depositoEnderecado, DepositoEnderecado, objetoEnderecado, List.all_eq_true]

end Bolha

