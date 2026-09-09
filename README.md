# Il — a Linguagem-Bolha

Formato de arquivo **determinístico** que agrupa e referencia mídias (textos, imagens, vídeos, áudios), carregando a **licença de uso de cada componente**. A bolha é a **receita** (o manifesto), não o prato renderizado.

Protótipo em construção — grupo RB-Il (Individuação Livre / Interface Livre).

## O que há neste repositório

- `juiz/Bolha.lean` — especificação em Lean 4 do tipo "bolha válida": teto de licença (`hash`/`ref`), as três licenças fundadoras, e 2 teoremas provados: *uso-restrito nunca segue referência viva*; *uso-livre pode seguir*. Verificação local exit 0; CI pendente.
- `arreio.py` — a mão: importa uma anotação, calcula o hash, grava no depósito e gera o manifesto referenciando conteúdo e licença por hash.
- `LICENCAS.md` — as três licenças fundadoras (`uso-restrito`, `uso-livre`, `uso-privado`).
- `.forgejo/workflows/verificar.yml` — integração contínua (Forgejo Actions) que roda o Lean sobre o juiz.

## Ideias centrais

- **Conteúdo endereçado por hash** (sha256), imutável, em depósito separado — o git versiona o manifesto (a receita), não os bytes.
- **Licença como bolha**: cada licença é também uma bolha (manifesto + hash), referenciada por hash — modular para generalizar a conteúdo, programa e serviço.
- **Teto**: a licença define o teto da referência — congelar na versão exata (`hash`) ou seguir a história (`ref`).
- **Mão e juiz**: o arreio escreve o manifesto; o Lean confere a forma; a pessoa confirma a verdade.

## Licença

AGPL-3.0 — ver `LICENSE`.
