/-
O JUÍZ — especificação da Bolha válida (Lean 4)

Modelo SIMPLIFICADO (2026-09-11):
- A licença é EXPLÍCITA: ou o estado `reservado` (nenhum direito concedido —
  a ausência deliberada de licença), ou a referência (hash) a uma bolha-licença
  de catálogo real (Creative Commons p/ conteúdo, SPDX p/ programa).
- O endereçamento é SEMPRE por hash: o eixo "teto" (hash vs ref) morreu.
  Era decisão técnica de reprodutibilidade vestida de permissão.
- Consequência honesta: o juiz fica mais fino. Ele prova a FORMA (conteúdo
  endereçado por hash; licença sempre explícita), não mais sobre tetos.
-/

namespace Bolha

/-- A licença declarada por uma bolha.
    `reservado` = estado padrão (nada concedido); `referencia h` = bolha-licença
    de catálogo real, apontada pelo hash sha256. -/
inductive Licenca where
  | reservado
  | referencia : String → Licenca
  deriving BEq, Repr, DecidableEq

/-- O manifesto (os campos vão crescer com as espécies). -/
structure Manifesto where
  tipo     : String
  conteudo : String   /- SEMPRE um hash sha256 (endereçado por conteúdo) -/
  licenca  : Licenca
  deriving Repr

/-- c é dígito hexadecimal? -/
def ehHex (c : Char) : Bool :=
  c.isDigit || ('a' <= c && c <= 'f') || ('A' <= c && c <= 'F')

/-- s é um hash sha256 (64 hex)? -/
def ehHashSha256 (s : String) : Bool :=
  s.length == 64 && s.all ehHex

/-- O conteúdo está endereçado por hash? -/
def conteudoOk (m : Manifesto) : Bool :=
  ehHashSha256 m.conteudo

/-- A licença é explícita e bem-formada? `reservado` sempre vale;
    uma referência precisa ser um hash sha256. -/
def licencaOk : Licenca → Bool
  | .reservado    => true
  | .referencia h => ehHashSha256 h

/-- Bolha válida = conteúdo endereçado por hash E licença explícita. -/
def valida (m : Manifesto) : Bool :=
  conteudoOk m && licencaOk m.licenca

/-
  TEOREMA 1 (determinismo): toda bolha válida carrega conteúdo endereçado
  por um hash sha256. Não há referência "viva" — o endereço é o conteúdo.
-/
theorem valida_conteudo_hash (m : Manifesto) (h : valida m = true) :
    ehHashSha256 m.conteudo = true := by
  simp [valida, conteudoOk] at h
  exact h.1

/-
  TEOREMA 2 (licença explícita): `reservado` nunca coincide com uma
  referência a bolha-licença. Os dois estados são disjuntos por construção.
-/
theorem reservado_nao_e_referencia (h : String) :
    Licenca.reservado ≠ Licenca.referencia h := by
  intro hc
  cases hc

/-- `reservado` é sempre uma licença válida (não depende de hash algum). -/
theorem reservado_valido : licencaOk Licenca.reservado = true := rfl

/- Demonstração legível. -/
#eval valida ⟨"anotacao", String.ofList (List.replicate 64 'a'), .reservado⟩
#eval valida ⟨"anotacao", "nao-e-hash", .reservado⟩
#eval valida ⟨"anotacao", String.ofList (List.replicate 64 'a'), .referencia "curto"⟩

end Bolha
