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

/--
  Um depósito por conteúdo: pares (endereço, BYTES do objeto).

  Os BYTES são a verdade; o TEXTO é uma VISTA deles. Era a última coisa que
  prendia o juiz ao texto: a MÃO (`arreio.py`) sempre gravou bytes
  (`gravar_objeto(dados: bytes)`) e o endereço sempre foi o sha256 dos bytes —
  o juiz é que decodificava antes de olhar, e por isso não sabia guardar áudio,
  imagem ou vídeo.
-/
abbrev Deposito := List (String × ByteArray)

def objeto (dep : Deposito) (h : String) : Option ByteArray :=
  match dep.find? (fun p => p.1 == h) with
  | some p => some p.2
  | none => none

/-- A VISTA de TEXTO de um objeto. `none` quando os bytes não são UTF-8 válido —
    e objeto que não é texto não é bolha: bolha se lê. -/
def objetoTexto (dep : Deposito) (h : String) : Option String :=
  (objeto dep h).bind String.fromUTF8?

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
  dep.any (fun p => p.1 == h && Sha256.enderecoBytes p.2 == h)

def EnderecoConfere (dep : Deposito) (h : String) : Prop :=
  ∃ p ∈ dep, p.1 = h ∧ Sha256.enderecoBytes p.2 = h

/-- REFINAMENTO do endereçamento: o juiz recalcula o sha256 — com prova. -/
theorem enderecoConfere_iff (dep : Deposito) (h : String) :
    enderecoConfere dep h = true ↔ EnderecoConfere dep h := by
  simp [enderecoConfere, EnderecoConfere, List.any_eq_true, Bool.and_eq_true]

/-- O `tipo` do objeto apontado por um endereço (none se ausente). -/
def objTipo (dep : Deposito) (h : String) : Option String :=
  match objetoTexto dep h with
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

/--
  O MANIFESTO de uma bolha julgável: o tipo, TODOS os campos declarados e o
  texto da licença.

  Até 2026-09-13 este registro tinha três campos FIXOS — tipo, conteúdo,
  licença — e por isso o VEREDITO NÃO ENXERGAVA o resto. A regra que define a
  canção ("a letra inteira é a REUNIÃO das partes, na ordem") não cabia no spec
  e teve de viver no teste: uma SEGUNDA verdade. O ramo `spec/especies-audio-imagem-video`
  mediu isso e o declarou; carregar todos os campos é o que devolve ao spec o
  direito de decidir.

  Isto é forma INTERNA do juiz. A forma da bolha não mudou — logo nenhum
  endereço mudou.
-/
structure Manifesto where
  tipo         : String
  campos       : List (String × String)
  licencaTexto : String
  deriving Repr, BEq

/--
  O QUE cada espécie julgável CARREGA — duas colunas: ONDE vive o endereço do
  conteúdo, e SE aquele conteúdo é TEXTO.

  A coluna `texto` não é enfeite. A PORTA DO TEXTO CANÔNICO (`textoOk`) existe
  para impedir o SILÊNCIO: a mesma palavra em duas grafias dando dois endereços
  para a mesma coisa. Ela só faz sentido sobre TEXTO — aplicá-la a mídia seria
  julgar o que a mídia não se propõe, e não aplicá-la a texto reabriria o buraco
  que ela fechou. Por isso a espécie DECLARA o que carrega.

  Espécie fora deste registro não carrega conteúdo — a bolha de `licenca` aponta
  para um catálogo, não para um texto, e o juiz não a julga como manifesto.

  Este registro e o VOCABULÁRIO da fatia "d" (`camposDe`) têm de CONCORDAR: o
  campo declarado aqui existe no vocabulário daquela espécie. A concordância não
  é pedida por confiança — é conferida pelo Conformidade sobre os artefatos.
-/
structure Conteudo where
  campo : String
  /-- O conteúdo desta espécie é TEXTO? — e é isto que decide se a PORTA DO
      TEXTO CANÔNICO (`textoOk`) se aplica. -/
  texto : Bool
  deriving Repr, BEq

def registroConteudo : List (String × Conteudo) :=
  [ ("anotacao", { campo := "conteudo", texto := true }),
    ("musica",   { campo := "letra",    texto := true }),
    ("parte",    { campo := "letra",    texto := true }),
    ("declaracao", { campo := "texto",   texto := true }) ]

def campoDeConteudo (s : String) : Option String :=
  (List.lookup s registroConteudo).map (fun c => c.campo)

/-- O conteúdo desta espécie é TEXTO? — falso para espécie desconhecida, que por
    isso não tem porta de texto a aplicar. -/
def conteudoEhTexto (s : String) : Bool :=
  match List.lookup s registroConteudo with
  | some c => c.texto
  | none   => false

/--
  O VALOR do campo de conteúdo da espécie — DERIVADO dos campos, nunca guardado
  à parte. Assim não há como os dois discordarem: o manifesto guarda UMA coisa,
  e o conteúdo é uma leitura dela.
-/
def Manifesto.conteudo (m : Manifesto) : String :=
  match campoDeConteudo m.tipo with
  | some chave => (campo m.campos chave).getD ""
  | none       => ""

/- ============ A REUNIÃO — o eixo ÁUDIO · IMAGEM · VÍDEO ============ -/

/--
  A REGRA DA REUNIÃO, como DADO: espécie → (campo da UNIÃO, campo das PARTES).

  Uma bolha que carrega uma reunião declara DOIS endereços: o da coisa INTEIRA
  (o prato) e o das PARTES que a compõem, na ordem (a receita). A regra é uma
  só, e é geral:

      o campo declarado é a REUNIÃO, na ordem, dos endereços listados.

  Ela não é "a regra da canção": é a forma que a canção já tinha. Canção é
  `letra` = reunião das `partes`; áudio é `mix` = reunião das `faixas`; vídeo é
  `edicao` = reunião das `faixas`; um corte social (vídeo curto, vídeo longo,
  post em texto) é a reunião das MESMAS peças, noutra ordem e noutro recorte.
  Uma forma, muitos usos — e por isso ela mora aqui, e não encravada num caso
  particular, que viraria três regras parecidas e três verdades.

  Que a mesma peça apareça em VÁRIAS reuniões não é ambiguidade: o endereço diz
  o CONTEÚDO, e a bolha que o referencia diz a FUNÇÃO. Um arquivo com duas
  funções são duas bolhas sobre um endereço só.

  Espécie fora deste registro não tem reunião a conferir: para ela nada muda.
-/
structure Reuniao where
  /-- O campo que carrega o endereço da coisa INTEIRA (o prato). -/
  uniao  : String
  /-- O campo que LISTA os endereços das partes, na ordem (a receita). -/
  partes : String
  deriving Repr, BEq

def registroReuniao : List (String × Reuniao) :=
  [ ("musica", { uniao := "letra", partes := "partes" }) ]

/-- Os endereços listados num campo: separados por vírgula, sem vazios. -/
def enderecosDeCampo (cs : List (String × String)) (chave : String) : List String :=
  match campo cs chave with
  | some s => (s.splitOn ",").filter (fun h => h != "")
  | none   => []

/- ============ O LEITOR DO VOCABULÁRIO (fatia "v", passo 1) ============ -/

/-- Os endereços do depósito cujo `tipo` é o pedido. -/
def objetosDeTipo (dep : Deposito) (t : String) : List String :=
  (dep.filter (fun p => objTipo dep p.1 == some t)).map (fun p => p.1)

/-- O `nome` de um objeto `campo`. -/
def nomeDoCampo (dep : Deposito) (h : String) : String :=
  match objetoTexto dep h with
  | some t => (campo (parseCampos t) "nome").getD ""
  | none   => ""

/-- Os NOMES dos `campo` citados por uma `especie`, na ORDEM em que ela os cita.
    `none` se o objeto não é legível, não é uma `especie`, ou se algum endereço
    citado não resolve para um `campo` — a natureza `referencia` exige que o
    endereço RESOLVA, e a ordem É a forma canônica. -/
def camposDaEspecie (dep : Deposito) (h : String) : Option (List String) :=
  match objetoTexto dep h with
  | none => none
  | some txt =>
      if tipoDe txt == some "especie" then
        let hs := enderecosDeCampo (parseCampos txt) "campos"
        if hs.all (fun k => objTipo dep k == some "campo") then
          some (hs.map (nomeDoCampo dep))
        else none
      else none

/-- O VOCABULÁRIO INTEIRO, LIDO DO DEPÓSITO: espécie -> campos, na ordem.
    `none` se o depósito não tem EXATAMENTE UM vocabulário legível.
    Zero é erro; dois é ambiguidade. É o depósito que declara o seu vocabulário.
    Este leitor NÃO substitui o registro literal: ele existe AO LADO dele, para
    que os dois possam ser COMPARADOS antes de qualquer troca. -/
def lerVocabulario (dep : Deposito) : Option (List (String × List String)) :=
  match objetosDeTipo dep "vocabulario" with
  | [h] =>
      match objetoTexto dep h with
      | none => none
      | some txt =>
          some ((enderecosDeCampo (parseCampos txt) "especies").map
            (fun he => (nomeDoCampo dep he, (camposDaEspecie dep he).getD [])))
  | _ => none

/-- A CONTRIBUIÇÃO de uma parte: o objeto apontado pelo CAMPO DE CONTEÚDO da
    bolha que aquele endereço nomeia. É o que torna a regra GERAL — a parte não
    precisa ser de uma espécie específica; precisa ser uma bolha julgável. -/
def contribuicao (dep : Deposito) (endereco : String) : Option ByteArray :=
  match objetoTexto dep endereco with
  | none => none
  | some txt =>
      match tipoDe txt with
      | none => none
      | some t =>
          match campoDeConteudo t with
          | none => none
          | some k =>
              match campo (parseCampos txt) k with
              | some hc => objeto dep hc
              | none    => none

/-- A REUNIÃO: as contribuições concatenadas, NA ORDEM declarada.
    `none` se qualquer parte faltar — reunir pela metade não é reunir. -/
def reunir (dep : Deposito) (enderecos : List String) : Option ByteArray :=
  let textos := enderecos.map (contribuicao dep)
  if textos.all (fun t => t.isSome) then
    some (textos.foldl (fun acc t => acc ++ t.getD ByteArray.empty) ByteArray.empty)
  else none

/-- A REUNIÃO CONFERE? — CHECK EXECUTÁVEL.
    Espécie sem reunião declarada não tem o que conferir: é `true`, não recusa. -/
def reuniaoOkB (m : Manifesto) (dep : Deposito) : Bool :=
  match List.lookup m.tipo registroReuniao with
  | none => true
  | some r =>
      match campo m.campos r.uniao with
      | none => false
      | some declarado =>
          match reunir dep (enderecosDeCampo m.campos r.partes) with
          | none         => false
          | some reunida => decide (declarado = Sha256.enderecoBytes reunida)

/-- A REUNIÃO CONFERE? — ESPECIFICAÇÃO LÓGICA. -/
def ReuniaoOk (m : Manifesto) (dep : Deposito) : Prop :=
  match List.lookup m.tipo registroReuniao with
  | none => True
  | some r =>
      match campo m.campos r.uniao with
      | none => False
      | some declarado =>
          match reunir dep (enderecosDeCampo m.campos r.partes) with
          | none         => False
          | some reunida => declarado = Sha256.enderecoBytes reunida

/-- REFINAMENTO: o check executável (Bool) ≡ a especificação lógica (Prop). -/
theorem reuniaoOkB_iff (m : Manifesto) (dep : Deposito) :
    reuniaoOkB m dep = true ↔ ReuniaoOk m dep := by
  unfold reuniaoOkB ReuniaoOk
  cases h : List.lookup m.tipo registroReuniao with
  | none => simp [h]
  | some r =>
      cases h1 : campo m.campos r.uniao with
      | none => simp [h, h1]
      | some declarado =>
          cases h2 : reunir dep (enderecosDeCampo m.campos r.partes) with
          | none         => simp [h, h1, h2]
          | some reunida => simp [h, h1, h2, decide_eq_true_eq]

/- ============ A REGRA DO PRAZO (a declaração A5 como dado) ============ -/

/-- Quatro caracteres são dígitos? — a forma que o check e a prova COMPARTILHAM. -/
def digitos4 (a b c d : Char) : Bool := a.isDigit && b.isDigit && c.isDigit && d.isDigit
def Digitos4 (a b c d : Char) : Prop :=
  ((a.isDigit = true ∧ b.isDigit = true) ∧ c.isDigit = true) ∧ d.isDigit = true

theorem digitos4_iff (a b c d : Char) :
    digitos4 a b c d = true ↔ Digitos4 a b c d := by
  simp [digitos4, Digitos4, Bool.and_eq_true]

/-- Dois dígitos como número: `(a - 48) * 10 + (b - 48)`. -/
def doisDigitos (a b : Char) : Nat := (a.toNat - 48) * 10 + (b.toNat - 48)

/--
  O PRAZO de uma declaração é uma data `AAAA-MM-DD`? — CHECK EXECUTÁVEL.

  A declaração A5 viveu como PROSA no compromisso, lida por expressão regular: uma
  regra de máquina morando como texto livre. Como CAMPO de bolha, ela passa a ter
  FORMA — e forma se recusa.
-/
def prazoOk (s : String) : Bool :=
  match s.toList with
  | [a, b, c, d, '-', e, f, '-', g, h] =>
      digitos4 a b c d && digitos4 e f g h
      && decide (1 ≤ doisDigitos e f ∧ doisDigitos e f ≤ 12)
      && decide (1 ≤ doisDigitos g h ∧ doisDigitos g h ≤ 31)
  | _ => false

/-- O prazo é uma data `AAAA-MM-DD`? — ESPECIFICAÇÃO LÓGICA. -/
def PrazoValido (s : String) : Prop :=
  match s.toList with
  | [a, b, c, d, '-', e, f, '-', g, h] =>
      ((Digitos4 a b c d ∧ Digitos4 e f g h)
        ∧ (1 ≤ doisDigitos e f ∧ doisDigitos e f ≤ 12))
        ∧ (1 ≤ doisDigitos g h ∧ doisDigitos g h ≤ 31)
  | _ => False

/-- REFINAMENTO: o check executável (Bool) ≡ a especificação lógica (Prop). -/
theorem prazoOk_iff (s : String) : prazoOk s = true ↔ PrazoValido s := by
  unfold prazoOk PrazoValido
  split <;> simp_all [digitos4_iff, decide_eq_true_eq]

/-- SÓ a espécie `declaracao` tem prazo a conferir — e é este portão que o diz. -/
def prazoOkB (m : Manifesto) : Bool :=
  if m.tipo == "declaracao" then prazoOk ((campo m.campos "prazo").getD "") else true

def PrazoOk (m : Manifesto) : Prop :=
  (m.tipo == "declaracao") = true → PrazoValido ((campo m.campos "prazo").getD "")

theorem prazoOkB_iff (m : Manifesto) : prazoOkB m = true ↔ PrazoOk m := by
  unfold prazoOkB PrazoOk
  by_cases h : (m.tipo == "declaracao") = true
  · simp [h, prazoOk_iff]
  · simp [h]

/-- Interpreta o texto de uma bolha. Julgáveis são as espécies COM campo de
    conteúdo; as outras não viram manifesto — e o que não vira manifesto não
    recebe veredito. -/
def parseManifesto (texto : String) : Option Manifesto :=
  let cs := parseCampos texto
  match campo cs "tipo", campo cs "licenca" with
  | some t, some l =>
      match campoDeConteudo t with
      | some chave =>
          match campo cs chave with
          | some _ => some { tipo := t, campos := cs, licencaTexto := l }
          | none   => none
      | none => none
  | _, _ => none

/-- CHECK EXECUTÁVEL da validade plena (todos os portões). -/
def manifestoOkB (m : Manifesto) (dep : Deposito) : Bool :=
  match parseLicenca m.licencaTexto with
  | none => false
  | some lic =>
      ehHashSha256 m.conteudo && noDeposito dep m.conteudo
      && enderecoConfere dep m.conteudo && reuniaoOkB m dep && prazoOkB m && licencaOk dep lic

/-- ESPECIFICAÇÃO LÓGICA da validade plena. -/
def ManifestoValido (m : Manifesto) (dep : Deposito) : Prop :=
  match parseLicenca m.licencaTexto with
  | none => False
  | some lic =>
      ((((ehHashSha256 m.conteudo = true ∧ Presente dep m.conteudo)
        ∧ EnderecoConfere dep m.conteudo) ∧ ReuniaoOk m dep) ∧ PrazoOk m) ∧ LicencaValida dep lic

/-- REFINAMENTO pleno: o check do manifesto inteiro ≡ a especificação. -/
theorem manifestoOkB_iff (m : Manifesto) (dep : Deposito) :
    manifestoOkB m dep = true ↔ ManifestoValido m dep := by
  unfold manifestoOkB ManifestoValido
  cases hp : parseLicenca m.licencaTexto with
  | none => simp [hp]
  | some lic =>
      simp only [hp, Bool.and_eq_true, noDeposito_iff, enderecoConfere_iff,
        reuniaoOkB_iff, prazoOkB_iff, licencaOk_iff]

/-- Consequência direta: bolha válida carrega conteúdo endereçado por hash. -/
theorem valido_implica_conteudo_hash (m : Manifesto) (dep : Deposito)
    (h : ManifestoValido m dep) : ehHashSha256 m.conteudo = true := by
  unfold ManifestoValido at h
  split at h
  · exact absurd h (by simp)
  · exact h.1.1.1.1.1

/- ============ O DEPÓSITO INTEIRO (hash de cada objeto) ============ -/

def objetoEnderecado (p : String × ByteArray) : Bool :=
  Sha256.enderecoBytes p.2 == p.1

def depositoEnderecado (dep : Deposito) : Bool :=
  dep.all objetoEnderecado

def DepositoEnderecado (dep : Deposito) : Prop :=
  ∀ p ∈ dep, Sha256.enderecoBytes p.2 = p.1

/-- REFINAMENTO do endereçamento do depósito inteiro. -/
theorem depositoEnderecado_iff (dep : Deposito) :
    depositoEnderecado dep = true ↔ DepositoEnderecado dep := by
  simp [depositoEnderecado, DepositoEnderecado, objetoEnderecado, List.all_eq_true]


/- ============ FATIA "d": A FORMA CANÔNICA DO MANIFESTO ============ -/

/--
  O REGISTRO DE ESPÉCIES da Linguagem-Bolha.

  Cada espécie é um par: o nome, e os seus campos NA ORDEM CANÔNICA — que é
  declarada, não alfabética (`tipo` vem sempre primeiro).

  Espécie é DADO, não código: acrescentar uma espécie é acrescentar uma linha
  aqui, sem tocar em nenhuma prova. Um registro que se enumera é o primeiro
  pedaço do alicerce Médio — e, mais adiante, o que a semente precisará ler
  para o sistema se descrever.

  A lista é FINITA e FECHADA de propósito: espécie que não está aqui não tem
  forma canônica, e é isso que impede grafias livres.

  A CANÇÃO (2026-09-12) são duas espécies, e só duas:

  - `musica` — a canção inteira. `letra` é o endereço do TEXTO INTEIRO, que é
    o RENDER da reunião das `partes`, na ordem declarada. A bolha é a receita;
    a letra inteira é o prato — e o prato também tem endereço, porque é
    conferível contra a receita.
  - `parte` — a parte NUMERADA da canção: intro, verso, refrão, ponte, outro.
    Cada parte é uma bolha, logo tem ENDEREÇO PRÓPRIO: trocar uma palavra de
    uma parte muda o endereço DELA — e só dela.
-/
def registroEspecies : List (String × List String) :=
  [ ("licenca",  ["tipo", "catalogo", "nome", "sigilo"]),
    ("anotacao", ["tipo", "conteudo", "licenca"]),
    ("musica",   ["tipo", "titulo", "interprete", "letra", "partes", "licenca"]),
    ("parte",    ["tipo", "numero", "papel", "letra", "licenca"]),
    ("declaracao", ["tipo", "ramo", "prazo", "texto", "licenca"]),
    ("agente",     ["tipo", "nome", "papel", "texto", "licenca"]),
    ("proposito",  ["tipo", "nome", "papel", "texto", "licenca"]),
    -- O LEITOR. Estas quatro NÃO podem virar bolha: são o que LÊ uma bolha.
    -- Sem elas não há por onde começar, e é a única parte do vocabulário que
    -- mora no Lean para sempre. Tudo o que está ACIMA delas é dado.
    ("campo",        ["tipo", "nome", "relacao", "licenca"]),
    ("especie",      ["tipo", "nome", "campos", "conteudo", "licenca_exigida", "licenca"]),
    ("caminho",      ["tipo", "nome", "padrao", "licenca"]),
    ("vocabulario",  ["tipo", "nome", "especies", "caminhos", "licenca"]) ]

/--
  O VOCABULÁRIO de uma espécie: seus campos, na ordem canônica.
  `none` se a espécie é desconhecida — e espécie desconhecida não tem forma
  canônica, o que é o mesmo que dizer que ela não existe para o juiz.

  O VOCABULÁRIO mora AQUI, e SÓ AQUI. A mão (`arreio/Arreio.lean`) IMPORTA
  esta tabela — não a copia. Enquanto houve um espelho em `arreio.py`, ele
  divergiu em SILÊNCIO: conhecia 4 espécies contra 11, e a licença sem o campo
  `sigilo` produzia o endereço `05ea7552…`, que nunca existiu no depósito.

  A defesa que este comentário prometia — "a concordância é conferida pelo
  ENDEREÇO" — NÃO funcionou, e vale registrar por quê: o endereço só pega
  divergência naquilo que as DUAS mãos escrevem. `criar_bolha_licenca` era
  chamada só no caminho-demo, nunca dos dois lados. Duas cópias não se
  conferem por existirem; conferem-se por serem exercitadas juntas.
-/
def camposDe (s : String) : Option (List String) :=
  List.lookup s registroEspecies


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

/- ============ A PORTA DE UMA MÃO DO TEXTO (o "buraco E") ============ -/

/--
  AS FAIXAS PROIBIDAS do texto canônico — DADO, não código.

  São os pontos de código que podem mudar de forma sob a normalização NFC:

  - classe de combinação canônica diferente de zero (marcas que se juntam a
    outra letra e que a ordem canônica pode reordenar);
  - as faixas em que o NFC_QC é `No` (nunca compõem) ou `Maybe` (podem compor).

  Recusá-las é o que impede o SILÊNCIO: duas grafias do mesmo texto que geram
  dois endereços para a mesma coisa. O risco não é erro — é não haver erro.

  A régua foi medida contra uma implementação de referência independente (ICU)
  sobre 1.112.064 pontos de código e 380.424 pares: nas faixas acima não há
  falso negativo. A MÃO (arreio.py) normaliza o texto quando ele entra; o juiz
  RECUSA o que escapou. O juiz não normaliza: ele decide.

  PROCEDENCIA: as faixas foram CALCULADAS por `ferramentas/regra-canonicidade.mjs`, a
  partir do campo NFC_QC (No/Maybe) do `DerivedNormalizationProps.txt` — depois que
  `ferramentas/buscar-tabelas.mjs` baixou as tabelas do Unicode. A regra desta lista e'
  a "REGRA ESTRITA" daquele programa. As tabelas do UCD NAO sao versionadas (dado de
  terceiro, grande e datado) e NAO existem nesta maquina: a cadeia que produziu este
  dado passa por dois programas que nenhum outro programa chama. Sem estas linhas,
  ninguem saberia nem de onde o dado veio nem como refaze-lo.
-/
def faixasProibidas : List (Nat × Nat) :=
  [ (0x0300, 0x034E), (0x0350, 0x036F), (0x0374, 0x0374), (0x037E, 0x037E), (0x0387, 0x0387), (0x0483, 0x0487),
    (0x0591, 0x05BD), (0x05BF, 0x05BF), (0x05C1, 0x05C2), (0x05C4, 0x05C5), (0x05C7, 0x05C7), (0x0610, 0x061A),
    (0x064B, 0x065F), (0x0670, 0x0670), (0x06D6, 0x06DC), (0x06DF, 0x06E4), (0x06E7, 0x06E8), (0x06EA, 0x06ED),
    (0x0711, 0x0711), (0x0730, 0x074A), (0x07EB, 0x07F3), (0x07FD, 0x07FD), (0x0816, 0x0819), (0x081B, 0x0823),
    (0x0825, 0x0827), (0x0829, 0x082D), (0x0859, 0x085B), (0x0897, 0x089F), (0x08CA, 0x08E1), (0x08E3, 0x08FF),
    (0x093C, 0x093C), (0x094D, 0x094D), (0x0951, 0x0954), (0x0958, 0x095F), (0x09BC, 0x09BC), (0x09BE, 0x09BE),
    (0x09CD, 0x09CD), (0x09D7, 0x09D7), (0x09DC, 0x09DD), (0x09DF, 0x09DF), (0x09FE, 0x09FE), (0x0A33, 0x0A33),
    (0x0A36, 0x0A36), (0x0A3C, 0x0A3C), (0x0A4D, 0x0A4D), (0x0A59, 0x0A5B), (0x0A5E, 0x0A5E), (0x0ABC, 0x0ABC),
    (0x0ACD, 0x0ACD), (0x0B3C, 0x0B3C), (0x0B3E, 0x0B3E), (0x0B4D, 0x0B4D), (0x0B56, 0x0B57), (0x0B5C, 0x0B5D),
    (0x0BBE, 0x0BBE), (0x0BCD, 0x0BCD), (0x0BD7, 0x0BD7), (0x0C3C, 0x0C3C), (0x0C4D, 0x0C4D), (0x0C55, 0x0C56),
    (0x0CBC, 0x0CBC), (0x0CC2, 0x0CC2), (0x0CCD, 0x0CCD), (0x0CD5, 0x0CD6), (0x0D3B, 0x0D3C), (0x0D3E, 0x0D3E),
    (0x0D4D, 0x0D4D), (0x0D57, 0x0D57), (0x0DCA, 0x0DCA), (0x0DCF, 0x0DCF), (0x0DDF, 0x0DDF), (0x0E38, 0x0E3A),
    (0x0E48, 0x0E4B), (0x0EB8, 0x0EBA), (0x0EC8, 0x0ECB), (0x0F18, 0x0F19), (0x0F35, 0x0F35), (0x0F37, 0x0F37),
    (0x0F39, 0x0F39), (0x0F43, 0x0F43), (0x0F4D, 0x0F4D), (0x0F52, 0x0F52), (0x0F57, 0x0F57), (0x0F5C, 0x0F5C),
    (0x0F69, 0x0F69), (0x0F71, 0x0F76), (0x0F78, 0x0F78), (0x0F7A, 0x0F7D), (0x0F80, 0x0F84), (0x0F86, 0x0F87),
    (0x0F93, 0x0F93), (0x0F9D, 0x0F9D), (0x0FA2, 0x0FA2), (0x0FA7, 0x0FA7), (0x0FAC, 0x0FAC), (0x0FB9, 0x0FB9),
    (0x0FC6, 0x0FC6), (0x102E, 0x102E), (0x1037, 0x1037), (0x1039, 0x103A), (0x108D, 0x108D), (0x1161, 0x1175),
    (0x11A8, 0x11C2), (0x135D, 0x135F), (0x1714, 0x1715), (0x1734, 0x1734), (0x17D2, 0x17D2), (0x17DD, 0x17DD),
    (0x18A9, 0x18A9), (0x1939, 0x193B), (0x1A17, 0x1A18), (0x1A60, 0x1A60), (0x1A75, 0x1A7C), (0x1A7F, 0x1A7F),
    (0x1AB0, 0x1ABD), (0x1ABF, 0x1ADD), (0x1AE0, 0x1AEB), (0x1B34, 0x1B35), (0x1B44, 0x1B44), (0x1B6B, 0x1B73),
    (0x1BAA, 0x1BAB), (0x1BE6, 0x1BE6), (0x1BF2, 0x1BF3), (0x1C37, 0x1C37), (0x1CD0, 0x1CD2), (0x1CD4, 0x1CE0),
    (0x1CE2, 0x1CE8), (0x1CED, 0x1CED), (0x1CF4, 0x1CF4), (0x1CF8, 0x1CF9), (0x1DC0, 0x1DFF), (0x1F71, 0x1F71),
    (0x1F73, 0x1F73), (0x1F75, 0x1F75), (0x1F77, 0x1F77), (0x1F79, 0x1F79), (0x1F7B, 0x1F7B), (0x1F7D, 0x1F7D),
    (0x1FBB, 0x1FBB), (0x1FBE, 0x1FBE), (0x1FC9, 0x1FC9), (0x1FCB, 0x1FCB), (0x1FD3, 0x1FD3), (0x1FDB, 0x1FDB),
    (0x1FE3, 0x1FE3), (0x1FEB, 0x1FEB), (0x1FEE, 0x1FEF), (0x1FF9, 0x1FF9), (0x1FFB, 0x1FFB), (0x1FFD, 0x1FFD),
    (0x2000, 0x2001), (0x20D0, 0x20DC), (0x20E1, 0x20E1), (0x20E5, 0x20F0), (0x2126, 0x2126), (0x212A, 0x212B),
    (0x2329, 0x232A), (0x2ADC, 0x2ADC), (0x2CEF, 0x2CF1), (0x2D7F, 0x2D7F), (0x2DE0, 0x2DFF), (0x302A, 0x302F),
    (0x3099, 0x309A), (0xA66F, 0xA66F), (0xA674, 0xA67D), (0xA69E, 0xA69F), (0xA6F0, 0xA6F1), (0xA806, 0xA806),
    (0xA82C, 0xA82C), (0xA8C4, 0xA8C4), (0xA8E0, 0xA8F1), (0xA92B, 0xA92D), (0xA953, 0xA953), (0xA9B3, 0xA9B3),
    (0xA9C0, 0xA9C0), (0xAAB0, 0xAAB0), (0xAAB2, 0xAAB4), (0xAAB7, 0xAAB8), (0xAABE, 0xAABF), (0xAAC1, 0xAAC1),
    (0xAAF6, 0xAAF6), (0xABED, 0xABED), (0xF900, 0xFA0D), (0xFA10, 0xFA10), (0xFA12, 0xFA12), (0xFA15, 0xFA1E),
    (0xFA20, 0xFA20), (0xFA22, 0xFA22), (0xFA25, 0xFA26), (0xFA2A, 0xFA6D), (0xFA70, 0xFAD9), (0xFB1D, 0xFB1F),
    (0xFB2A, 0xFB36), (0xFB38, 0xFB3C), (0xFB3E, 0xFB3E), (0xFB40, 0xFB41), (0xFB43, 0xFB44), (0xFB46, 0xFB4E),
    (0xFE20, 0xFE2F), (0x101FD, 0x101FD), (0x102E0, 0x102E0), (0x10376, 0x1037A), (0x10A0D, 0x10A0D), (0x10A0F, 0x10A0F),
    (0x10A38, 0x10A3A), (0x10A3F, 0x10A3F), (0x10AE5, 0x10AE6), (0x10D24, 0x10D27), (0x10D69, 0x10D6D), (0x10EAB, 0x10EAC),
    (0x10EFA, 0x10EFB), (0x10EFD, 0x10EFF), (0x10F46, 0x10F50), (0x10F82, 0x10F85), (0x11046, 0x11046), (0x11070, 0x11070),
    (0x1107F, 0x1107F), (0x110B9, 0x110BA), (0x11100, 0x11102), (0x11127, 0x11127), (0x11133, 0x11134), (0x11173, 0x11173),
    (0x111C0, 0x111C0), (0x111CA, 0x111CA), (0x11235, 0x11236), (0x112E9, 0x112EA), (0x1133B, 0x1133C), (0x1133E, 0x1133E),
    (0x1134D, 0x1134D), (0x11357, 0x11357), (0x11366, 0x1136C), (0x11370, 0x11374), (0x113B8, 0x113B8), (0x113BB, 0x113BB),
    (0x113C2, 0x113C2), (0x113C5, 0x113C5), (0x113C7, 0x113C9), (0x113CE, 0x113D0), (0x11442, 0x11442), (0x11446, 0x11446),
    (0x1145E, 0x1145E), (0x114B0, 0x114B0), (0x114BA, 0x114BA), (0x114BD, 0x114BD), (0x114C2, 0x114C3), (0x115AF, 0x115AF),
    (0x115BF, 0x115C0), (0x1163F, 0x1163F), (0x116B6, 0x116B7), (0x1172B, 0x1172B), (0x11839, 0x1183A), (0x11930, 0x11930),
    (0x1193D, 0x1193E), (0x11943, 0x11943), (0x119E0, 0x119E0), (0x11A34, 0x11A34), (0x11A47, 0x11A47), (0x11A99, 0x11A99),
    (0x11C3F, 0x11C3F), (0x11D42, 0x11D42), (0x11D44, 0x11D45), (0x11D97, 0x11D97), (0x11F41, 0x11F42), (0x1611E, 0x16129),
    (0x1612F, 0x1612F), (0x16AF0, 0x16AF4), (0x16B30, 0x16B36), (0x16D67, 0x16D68), (0x16FF0, 0x16FF1), (0x1BC9E, 0x1BC9E),
    (0x1D15E, 0x1D169), (0x1D16D, 0x1D172), (0x1D17B, 0x1D182), (0x1D185, 0x1D18B), (0x1D1AA, 0x1D1AD), (0x1D1BB, 0x1D1C0),
    (0x1D242, 0x1D244), (0x1E000, 0x1E006), (0x1E008, 0x1E018), (0x1E01B, 0x1E021), (0x1E023, 0x1E024), (0x1E026, 0x1E02A),
    (0x1E08F, 0x1E08F), (0x1E130, 0x1E136), (0x1E2AE, 0x1E2AE), (0x1E2EC, 0x1E2EF), (0x1E4EC, 0x1E4EF), (0x1E5EE, 0x1E5EF),
    (0x1E6E3, 0x1E6E3), (0x1E6E6, 0x1E6E6), (0x1E6EE, 0x1E6EF), (0x1E6F5, 0x1E6F5), (0x1E8D0, 0x1E8D6), (0x1E944, 0x1E94A),
    (0x2F800, 0x2FA1D) ]

/-- O ponto de código é proibido no texto canônico? — CHECK EXECUTÁVEL. -/
def proibido (cp : Nat) : Bool :=
  faixasProibidas.any (fun r => decide (r.1 ≤ cp ∧ cp ≤ r.2))

/-- O TEXTO está na forma canônica? — CHECK EXECUTÁVEL. -/
def textoOk (t : String) : Bool :=
  t.toList.all (fun c => !proibido c.val.toNat)

/-- O TEXTO está na forma canônica? — ESPECIFICAÇÃO LÓGICA. -/
def TextoCanonicoDeTexto (t : String) : Prop :=
  ∀ c ∈ t.toList, ¬ (proibido c.val.toNat = true)

/-- REFINAMENTO: o check executável (Bool) ≡ a especificação lógica (Prop). -/
theorem textoOk_iff (t : String) :
    textoOk t = true ↔ TextoCanonicoDeTexto t := by
  simp [textoOk, TextoCanonicoDeTexto, List.all_eq_true, Bool.not_eq_true]

/-- A PORTA DO TEXTO CANÔNICO, sobre BYTES: decodifica e aplica `textoOk`.
    `false` se os bytes não são UTF-8 válido — o que não é texto não é texto
    canônico, e a porta não julga o que não se propõe a julgar. -/
def bytesTextoOk (b : ByteArray) : Bool :=
  match String.fromUTF8? b with
  | some s => textoOk s
  | none   => false

/-- A PORTA DO TEXTO CANÔNICO sobre bytes — ESPECIFICAÇÃO LÓGICA. -/
def BytesTextoOk (b : ByteArray) : Prop :=
  ∃ s, String.fromUTF8? b = some s ∧ TextoCanonicoDeTexto s

/-- REFINAMENTO: o check executável (Bool) ≡ a especificação lógica (Prop). -/
theorem bytesTextoOk_iff (b : ByteArray) :
    bytesTextoOk b = true ↔ BytesTextoOk b := by
  unfold bytesTextoOk BytesTextoOk
  cases h : String.fromUTF8? b with
  | none => simp [h]
  | some s => simp [h, textoOk_iff]


end Bolha
