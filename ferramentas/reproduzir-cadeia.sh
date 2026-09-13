#!/usr/bin/env bash
# reproduzir-cadeia.sh — A CADEIA, DEFINIDA UMA VEZ, EXECUTADA EM QUALQUER MÁQUINA.
#
# Por que existe: a cadeia do juiz estava escrita nos passos do fluxo do GitHub
# Actions — logo só existia lá. Aqui ela é definida UMA vez, e quem executa é
# quem tiver a máquina: o Actions hoje (atalho), o Codespaces depois, a máquina
# própria quando houver. O CI passa a chamar este programa em vez de repetir os
# passos: uma definição, nenhuma divergência.
#
# O número publicado leva o NOME DE QUEM PROVOU. No Actions sai o rótulo
# canônico (`juiz - numero`); em qualquer outra máquina sai com o nome dela
# (`juiz - numero [minha-maquina]`). Assim se lê, sem credencial, se a prova
# existe só no atalho ou também numa máquina sua. (A1: o CI avisa cedo; ele não
# substitui a fonte.)
#
# Uso:
#   ferramentas/reproduzir-cadeia.sh [--etapa juiz|prosa|tudo] [--sem-instalar] [--publicar]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
RAIZ="$(pwd)"

ETAPA="tudo"; PUBLICAR=0; INSTALAR=1
while [ $# -gt 0 ]; do
  case "$1" in
    --etapa) ETAPA="${2:-tudo}"; shift 2 ;;
    --publicar) PUBLICAR=1; shift ;;
    --sem-instalar) INSTALAR=0; shift ;;
    *) shift ;;
  esac
done

EM_CI=0; [ "${GITHUB_ACTIONS:-}" = "true" ] && EM_CI=1
MAQUINA="$(hostname 2>/dev/null || echo maquina-desconhecida)"
[ "$EM_CI" = "1" ] && MAQUINA="github-actions"

echo "=== cadeia do juiz ==="
echo "  etapa:    $ETAPA"
echo "  máquina:  $MAQUINA$([ "$EM_CI" = "1" ] && echo '  (ATALHO de velocidade — não é a fonte)')"
echo "  sistema:  $(uname -srm 2>/dev/null)"
echo "  núcleos:  $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')"
echo "  Lean fixado: $(sed 's|.*:||' lean-toolchain 2>/dev/null)"

if [ "$ETAPA" = "juiz" ] || [ "$ETAPA" = "tudo" ]; then
  if ! command -v lean >/dev/null 2>&1; then
    if [ "$INSTALAR" = "0" ]; then echo "FALHA: lean não instalado"; exit 1; fi
    echo "  instalando elan..."
    curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y || { echo "FALHA ao instalar elan"; exit 1; }
    export PATH="$HOME/.elan/bin:$PATH"
  fi
fi

medir() {
  local rotulo="$1"; shift
  local t0 t1 rc
  t0=$(date +%s%N 2>/dev/null || echo 0)
  "$@" > "$RAIZ/prova-$rotulo.txt" 2>&1; rc=$?
  t1=$(date +%s%N 2>/dev/null || echo 0)
  printf "  %-30s %8s ms  %s\n" "$rotulo" "$(( (t1 - t0) / 1000000 ))" "$([ $rc -eq 0 ] && echo ok || echo "FALHA($rc)")"
  # O MARCO VEM ANTES DO RETURN. Estava DEPOIS, e por isso nunca era escrito: o
  # canal de erro publicava sempre o ULTIMO passo, nao o que falhou — e o erro
  # apontava para o lugar errado. Erro que aponta errado e' pior que erro.
  [ $rc -ne 0 ] && : > "$RAIZ/.falhou-$rotulo"
  return $rc
}

FALHOU=0
if [ "$ETAPA" = "juiz" ] || [ "$ETAPA" = "tudo" ]; then
  ( cd juiz && medir versao-do-lean lean --version ) || FALHOU=1
  ( cd juiz && medir hash-sha256 lean -o Sha256.olean Sha256.lean ) || FALHOU=1
  ( cd juiz && LEAN_PATH=. medir spec-bolha lean -o Bolha.olean Bolha.lean ) || FALHOU=1
  ( cd juiz && LEAN_PATH=. medir ponte lean -o Ponte.olean Ponte.lean ) || FALHOU=1
  medir mao-escreve-a-cancao python3 arreio.py musica exemplos/musica/letra.txt \
        --titulo "Canção de exemplo" --interprete "Exemplo" || FALHOU=1
  ( LEAN_PATH=juiz medir conformidade lean --run juiz/Conformidade.lean ) || FALHOU=1
fi
if [ "$ETAPA" = "prosa" ] || [ "$ETAPA" = "tudo" ]; then
  medir higiene-da-prosa python3 higiene.py --mapa || FALHOU=1
fi

NUM_JUIZ=$(grep -oiE '[0-9]+ *confer[^.]*falhas?' "$RAIZ/prova-conformidade.txt" 2>/dev/null | tail -1)
NUM_PROSA=$(grep -oiE '[0-9]+ *documento[^.]*falhas?' "$RAIZ/prova-higiene-da-prosa.txt" 2>/dev/null | tail -1)

echo
echo "=== NÚMEROS ==="
[ -n "$NUM_JUIZ" ]  && echo "  juiz:  $NUM_JUIZ"
[ -n "$NUM_PROSA" ] && echo "  prosa: $NUM_PROSA"
[ -z "$NUM_JUIZ$NUM_PROSA" ] && echo "  (nenhum número — a cadeia não chegou ao fim)"

publicar() {   # publicar <contexto-base> <descrição>
  local base="$1" desc="$2" ctx
  if [ "$EM_CI" = "1" ]; then ctx="$base"; else ctx="$base [$MAQUINA]"; fi
  estado=$([ "$FALHOU" = "0" ] && echo success || echo failure)
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg s "$estado" --arg c "$ctx" --arg d "$desc" \
      '{state:$s,context:$c,description:$d}' > corpo.json
  else
    limpo=$(printf '%s' "$desc" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"state":"%s","context":"%s","description":"%s"}' "$estado" "$ctx" "$limpo" > corpo.json
  fi
  curl -sS -o /dev/null -w "  publicado: $ctx -> %{http_code}\n" -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY:-IltSorriso/Il}/statuses/${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo desconhecido)}" \
    --data @corpo.json
}

if [ "$PUBLICAR" = "1" ]; then
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "  PUBLICAR pedido, mas sem GITHUB_TOKEN — nada publicado."
  else
    [ -n "$NUM_JUIZ" ] && publicar "juiz - numero" "$NUM_JUIZ"
    [ -n "$NUM_PROSA" ] && publicar "prosa - numero" "$NUM_PROSA"
    if [ "$FALHOU" != "0" ]; then
      # A ORDEM DA CADEIA, e nao a ordem alfabetica do glob. "conformidade" vem antes de
      # "ponte" e de "spec-bolha" no alfabeto, e por isso o canal publicava a CONSEQUENCIA
      # (falta o Ponte.olean) em vez da CAUSA (o erro que quebrou o Bolha.lean).
      alvo=""; passo="desconhecido"
      for cand in versao-do-lean hash-sha256 spec-bolha ponte mao-escreve-a-cancao conformidade higiene-da-prosa; do
        if [ -e "$RAIZ/.falhou-$cand" ]; then alvo="$RAIZ/.falhou-$cand"; passo="$cand"; break; fi
      done
      if [ -n "$alvo" ]; then arq="$RAIZ/prova-$passo.txt"; else arq=$(ls -t "$RAIZ"/prova-*.txt 2>/dev/null | head -1); fi
      # A PRIMEIRA linha de erro e' a que diz o defeito; as ultimas linhas de um
      # compilador sao o eco dele.
      cauda=$(grep -iE '(^|[^a-zA-Z])error' "$arq" 2>/dev/null | head -1 | tr -s ' ' | cut -c1-130)
      [ -z "$cauda" ] && cauda=$(grep -v '^$' "$arq" 2>/dev/null | tail -3 | tr '\n' ' ' | tr -s ' ' | cut -c1-130)
      [ -z "$cauda" ] && cauda="(sem saida capturada em $passo)"
      FALHOU_ANTES=$FALHOU; FALHOU=1
      publicar "cadeia - ERRO em $passo" "$cauda"
      FALHOU=$FALHOU_ANTES
    fi
  fi
fi

rm -f corpo.json "$RAIZ"/.falhou-*
exit $FALHOU
