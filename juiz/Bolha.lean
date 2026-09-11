import Sha256

/-
O JUÍZ — especificação da Bolha válida (Lean 4)

FONTE ÚNICA DE VERDADE: aqui vivem (1) o FORMATO do manifesto (a linguagem),
(2) os PORTÕES da validade, cada um com sua versão executável (Bool) E sua
versão lógica (Prop), acopladas por um TEOREMA DE REFINAMENTO. O executável
(ex.: Ponte.lean) IMPORTA estes nomes — não reimplementa nada.

Modelo simplificado (2026-09-11):
- Licença: `reservado` (ausência deliberada de direito) ou referência (hash)
  a uma bolha-licença de catálogo real (CC / SPDX).
- Endereçamento SEMPRE por hash sha256 canônico (minúsculo). O eixo "teto"
  (hash vs ref) morreu.
-/

namespace Bolha

/- ============ FORMATO: a linguagem do manifesto ============ -/

/-- trim ASCII → String (sem deprecação). -/
def trimStr (s : String) : String := (s.trimAscii).toString

def parseLinha (linha : String) : Option (String × String) :=
  match linha.splitOn ":" with
  | [chave, valor] => some (trimStr chave, trimStr valor)
  | _ => none

def parseCampos (texto : String) : List (String × String) :=
  let linhas := (texto.splitOn "\n").filter (fun l => trimStr l != "")
  linhas.filterMap parseLinha

def campo (m : List (String × String)) (chave : String) : Option String :=
  match m.find? (fun p => p.1 == chave) with
  | some p => some p.2
  | none => none

/-- O `tipo` declarado num texto de manifesto. -/
def tipoDe (texto : String) : Option String := campo (parseCampos texto) "tipo"

/- ============ ENDEREÇO: hash sha256 CANÔNICO (minúsculo) ============ -/

/-- c é dígito hexadecimal MINÚSCULO? (o endereço canônico só tem minúsculas) -/
def ehHexMinusculo (c : Char) : Bool :=
  c.isDigit || ('a' <= c && c <= 'f')

/-- s é endereço sha256 canônico (64 hex minúsculos)? -/
def ehHashSha256 (s : String) : Bool :=
  s.length == 64 && s.all ehHexMinusculo

/- ============ LICENÇA ============ -/

inductive Licenca where
  | reservado
  | referencia : String → Licenca
  deriving BEq, Repr, DecidableEq

/-- TEOREMA (estados disjuntos): `reservado` nunca é uma referência. -/
theorem reservado_nao_e_referencia (h : String) :
    Licenca.reservado ≠ Licenca.referencia h := by
  intro hc; cases hc

def parseLicenca (s : String) : Option Licenca :=
  let s := trimStr s
  if s == "reservado" then some .reservado
  else if ehHashSha256 s then some (.referencia s)
  else none

/- ============ DEPÓSITO: endereçamento por conteúdo ============ -/

/-- Um depósito por conteúdo: pares (endereço, texto do objeto). -/
abbrev Deposito := List (String × String)

def objeto (dep : Deposito) (h : String) : Option String :=
  match dep.find? (fun p => p.1 == h) with
  | some p => some p.2
  | none => none

def noDeposito (dep : Deposito) (h : String) : Bool :=
  dep.any (fun p => p.1 == h)

def Presente (dep : Deposito) (h : String) : Prop :=
  ∃ p ∈ dep, p.1 = h

/-- REFINAMENTO: o check executável (Bool) ≡ a especificação lógica (Prop). -/
theorem noDeposito_iff (dep : Deposito) (h : String) :
    noDeposito dep h = true ↔ Presente dep h := by
  simp [noDeposito, Presente, List.any_eq_true]

theorem ausente_nao_presente (dep : Deposito) (h : String)
    (hh : noDeposito dep h = false) : ¬ Presente dep h := by
  intro hp
  rw [← noDeposito_iff] at hp
  rw [hp] at hh
  exact Bool.noConfusion hh

/- ============ PORTÃO 1: o objeto existe E seus bytes batem o endereço ============ -/

def enderecoConfere (dep : Deposito) (h : String) : Bool :=
  dep.any (fun p => p.1 == h && Sha256.endereco p.2 == h)

def EnderecoConfere (dep : Deposito) (h : String) : Prop :=
  ∃ p ∈ dep, p.1 = h ∧ Sha256.endereco p.2 = h

/-- REFINAMENTO do endereçamento: o juiz recalcula o sha256 — com prova. -/
theorem enderecoConfere_iff (dep : Deposito) (h : String) :
    enderecoConfere dep h = true ↔ EnderecoConfere dep h := by
  simp [enderecoConfere, EnderecoConfere, List.any_eq_true, Bool.and_eq_true]

/-- O `tipo` do objeto apontado por um endereço (none se ausente). -/
def objTipo (dep : Deposito) (h : String) : Option String :=
  match objeto dep h with
  | some txt => tipoDe txt
  | none => none

/- ============ PORTÃO 2: a licença ============ -/

def licencaOk (dep : Deposito) : Licenca → Bool
  | .reservado     => true
  | .referencia h  => enderecoConfere dep h && (objTipo dep h == some "licenca")

def LicencaValida (dep : Deposito) : Licenca → Prop
  | .reservado     => True
  | .referencia h  => EnderecoConfere dep h ∧ objTipo dep h = some "licenca"

theorem licencaOk_iff (dep : Deposito) (l : Licenca) :
    licencaOk dep l = true ↔ LicencaValida dep l := by
  cases l with
  | reservado    => simp [licencaOk, LicencaValida]
  | referencia h => simp [licencaOk, LicencaValida, Bool.and_eq_true, enderecoConfere_iff]

/- ============ O MANIFESTO E A VALIDADE PLENA ============ -/

structure Manifesto where
  tipo        : String
  conteudo    : String
  licencaTexto : String
  deriving Repr, BEq

/-- Interpreta o texto de uma bolha. Hoje só a espécie `anotacao`. -/
def parseManifesto (texto : String) : Option Manifesto :=
  let cs := parseCampos texto
  match campo cs "tipo", campo cs "conteudo", campo cs "licenca" with
  | some "anotacao", some c, some l => some { tipo := "anotacao", conteudo := c, licencaTexto := l }
  | _, _, _ => none

/-- CHECK EXECUTÁVEL da validade plena (todos os portões). -/
def manifestoOkB (m : Manifesto) (dep : Deposito) : Bool :=
  match parseLicenca m.licencaTexto with
  | none => false
  | some lic =>
      ehHashSha256 m.conteudo && noDeposito dep m.conteudo
      && enderecoConfere dep m.conteudo && licencaOk dep lic

/-- ESPECIFICAÇÃO LÓGICA da validade plena. -/
def ManifestoValido (m : Manifesto) (dep : Deposito) : Prop :=
  match parseLicenca m.licencaTexto with
  | none => False
  | some lic =>
      ((ehHashSha256 m.conteudo = true ∧ Presente dep m.conteudo)
        ∧ EnderecoConfere dep m.conteudo) ∧ LicencaValida dep lic

/-- REFINAMENTO pleno: o check do manifesto inteiro ≡ a especificação. -/
theorem manifestoOkB_iff (m : Manifesto) (dep : Deposito) :
    manifestoOkB m dep = true ↔ ManifestoValido m dep := by
  unfold manifestoOkB ManifestoValido
  cases hp : parseLicenca m.licencaTexto with
  | none => simp [hp]
  | some lic =>
      simp only [hp, Bool.and_eq_true, noDeposito_iff, enderecoConfere_iff, licencaOk_iff]

/-- Consequência direta: bolha válida carrega conteúdo endereçado por hash. -/
theorem valido_implica_conteudo_hash (m : Manifesto) (dep : Deposito)
    (h : ManifestoValido m dep) : ehHashSha256 m.conteudo = true := by
  unfold ManifestoValido at h
  split at h
  · exact absurd h (by simp)
  · exact h.1.1.1

/- ============ O DEPÓSITO INTEIRO (hash de cada objeto) ============ -/

def objetoEnderecado (p : String × String) : Bool :=
  Sha256.endereco p.2 == p.1

def depositoEnderecado (dep : Deposito) : Bool :=
  dep.all objetoEnderecado

def DepositoEnderecado (dep : Deposito) : Prop :=
  ∀ p ∈ dep, Sha256.endereco p.2 = p.1

/-- REFINAMENTO do endereçamento do depósito inteiro. -/
theorem depositoEnderecado_iff (dep : Deposito) :
    depositoEnderecado dep = true ↔ DepositoEnderecado dep := by
  simp [depositoEnderecado, DepositoEnderecado, objetoEnderecado, List.all_eq_true]


/- ============ FATIA "d": A FORMA CANÔNICA DO MANIFESTO ============ -/

/--
  O VOCABULÁRIO de uma espécie: seus campos, na ORDEM canônica.
  A ordem é declarada pela espécie — não é alfabética. Assim `tipo` vem
  primeiro e os demais na ordem que a espécie define. Espécie desconhecida
  não tem forma canônica (é o que impede grafias livres).
-/
def camposDe : String → Option (List String)
  | "licenca"  => some ["tipo", "catalogo", "nome"]
  | "anotacao" => some ["tipo", "conteudo", "licenca"]
  | _          => none

/-- Um campo na sintaxe canônica: `chave: valor` (um espaço, sem sobras). -/
def linhaCanonica (chave valor : String) : String := chave ++ ": " ++ valor

/--
  A FORMA CANÔNICA de um manifesto: SOMENTE os campos que a espécie declara,
  na ordem canônica, com sintaxe normalizada e um `\n` final.
  `none` se a espécie é desconhecida ou falta campo obrigatório.
-/
def serializarCampos (cs : List (String × String)) : Option String :=
  match campo cs "tipo" with
  | none => none
  | some t =>
      match camposDe t with
      | none => none
      | some chaves =>
          if chaves.all (fun k => (campo cs k).isSome) then
            some (String.intercalate "\n"
              (chaves.map (fun k => linhaCanonica k ((campo cs k).getD ""))) ++ "\n")
          else none

/-- O texto está na forma canônica? — CHECK EXECUTÁVEL. -/
def canonicidadeOk (t : String) : Bool :=
  match serializarCampos (parseCampos t) with
  | some s => decide (s = t)
  | none   => false

/-- O texto está na forma canônica? — ESPECIFICAÇÃO LÓGICA. -/
def TextoCanonico (t : String) : Prop :=
  ∃ s, serializarCampos (parseCampos t) = some s ∧ s = t

/-- REFINAMENTO: o check executável (Bool) ≡ a especificação lógica (Prop). -/
theorem canonicidadeOk_iff (t : String) :
    canonicidadeOk t = true ↔ TextoCanonico t := by
  unfold canonicidadeOk TextoCanonico
  cases h : serializarCampos (parseCampos t) with
  | none   => simp [h]
  | some s => simp [h, decide_eq_true_eq]

/-- O endereço de uma BOLHA = sha256 do seu texto CANÔNICO. -/
def enderecoDeBolha (t : String) : Option String :=
  (serializarCampos (parseCampos t)).map Sha256.endereco

/--
  TEOREMA (determinismo do endereço da bolha): dois textos canônicos com os
  MESMOS campos são o MESMO texto. Fecha o buraco — não há duas grafias da
  mesma bolha, logo não há dois endereços para a mesma bolha.
-/
theorem canonico_igual_de_campos (t1 t2 : String)
    (h1 : TextoCanonico t1) (h2 : TextoCanonico t2)
    (hc : parseCampos t1 = parseCampos t2) : t1 = t2 := by
  obtain ⟨s1, hs1, he1⟩ := h1
  obtain ⟨s2, hs2, he2⟩ := h2
  rw [hc] at hs1
  rw [hs1] at hs2
  have hs : s1 = s2 := by simpa using hs2
  rw [← he1, ← he2, hs]

/-- COROLÁRIO: mesma informação canônica ⇒ mesmo endereço de bolha. -/
theorem enderecoDeBolha_igual_de_campos (t1 t2 : String)
    (h1 : TextoCanonico t1) (h2 : TextoCanonico t2)
    (hc : parseCampos t1 = parseCampos t2) :
    enderecoDeBolha t1 = enderecoDeBolha t2 := by
  rw [canonico_igual_de_campos t1 t2 h1 h2 hc]

end Bolha
