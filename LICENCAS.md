# LICENÇAS — Linguagem-Bolha

Licenças iniciais do sistema. **Cada licença É uma bolha** — tem manifesto, hash e é
referenciada por hash pelas bolhas que a usam. Isso dá modularidade: a mesma estrutura
de licença se generaliza para qualquer domínio (conteúdo, programa, serviço...).

Duas dimensões que cada licença declara:
- **TETO de referência** — o permitido ao apontar para a bolha:
  - `hash` = congelar numa versão exata (determinístico)
  - `ref` = seguir a história viva (sempre a versão mais atual)
- **ESCOPO** — para quem a permissão vale (privado / livre)

---

## 1. Uso Restrito (`uso-restrito`) — CONSERVADORA

- **Teto:** `hash` apenas (congelar nesta versão exata)
- **Não pode:** seguir a história (`ref`)
- **Uso:** conteúdo sem registro de autoria/direitos; origem desconhecida/anônima
- *(antes chamada `sem-registro`)*

## 2. Uso Livre (`uso-livre`) — LIVRE

- **Teto:** `hash` + `ref`
- **Escopo:** liberado plenamente
- **Prioridade:** prevalece quando nenhuma outra licença implicar restrição

## 3. Uso Privado (`uso-privado`) — PRIVADA (recomendada do sistema)

- **Teto:** `hash` + `ref` (por hora, clone de `uso-livre`)
- **Escopo:** privado — uso pessoal, antes de liberar
- **Papel:** padrão recomendado ao criar bolhas (importação orgânica)

---

## Regra de prioridade

Em mistura de licenças, a mais restritiva prevalece sobre a livre. `uso-livre` é o
padrão quando nada mais restringe. `uso-privado` é o padrão de CRIAÇÃO (não de mistura).
