/-
O JUÍZ — especificação da Bolha válida (Lean 4)
-/

namespace Bolha

/-- O teto: o que uma licença permite ao referenciar. -/
inductive Teto where
  | soHash    /- congelar: só esta versão exata -/
  | hashOuRef /- seguir: a história viva -/
  deriving BEq, Repr

/-- As três licenças fundadoras (bolhas-primeiras). -/
inductive LicencaId where
  | usoRestrito | usoLivre | usoPrivado
  deriving BEq, Repr

/-- O teto declarado por cada licença fundadora. -/
def tetoDe : LicencaId → Teto
  | .usoRestrito => .soHash
  | .usoLivre    => .hashOuRef
  | .usoPrivado  => .hashOuRef  /- por ora, clone de uso-livre -/

/-- Referência a sub-bolha: congelada (hash) ou viva (ref). -/
inductive Referencia where
  | hash : String → Referencia
  | ref  : String → Referencia
  deriving BEq, Repr

/-- O manifesto (os campos vão crescer com as espécies). -/
structure Manifesto where
  tipo     : String
  conteudo : Referencia
  licenca  : LicencaId

/-- A referência respeita o teto da licença que a governa? -/
def respeitaTeto (lic : LicencaId) (r : Referencia) : Prop :=
  match tetoDe lic, r with
  | .soHash, .ref _ => False
  | _, _            => True

/-- Bolha válida = toda referência respeita o teto da licença. -/
def valida (m : Manifesto) : Prop :=
  respeitaTeto m.licenca m.conteudo

/--
  TEOREMA 1: uma bolha `uso-restrito` NUNCA segue a história (ref).
  Se é válida, seu conteúdo é necessariamente um hash.
-/
theorem restrito_nao_segue (m : Manifesto) (h : m.licenca = .usoRestrito) :
    valida m → ∃ s, m.conteudo = .hash s := by
  intro hv
  rcases m with ⟨tipo, conteudo, licenca⟩
  simp at h
  subst licenca
  simp [valida, respeitaTeto, tetoDe] at hv
  cases conteudo with
  | hash s => exact ⟨s, rfl⟩
  | ref s  => contradiction

/--
  TEOREMA 2: uma bolha `uso-livre` PODE seguir (ref) sem quebrar a validade.
  Construção explícita: conteúdo = ref "algo" é válido sob uso-livre.
-/
theorem livre_pode_seguir :
    valida ⟨"anotacao", .ref "algo", .usoLivre⟩ := by
  simp [valida, respeitaTeto, tetoDe]

end Bolha
