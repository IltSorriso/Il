// fiscal-de-prazos.mjs — cobra a A5: ramo sem declaração de prazo, ou prazo vencido.
//
// NÃO derruba o tronco. A A6 manda o tronco nunca quebrar, e ramo vencido não é
// defeito do produto — é dívida de processo. Logo ele PUBLICA ESTADO e sai com 0.
//
// A declaração A5 vive no compromisso (é onde o contrato a pede):
//     Prazo (A5): 2026-09-26
import { execFileSync } from 'node:child_process';
const DONO = 'IltSorriso', REPO = 'Il';
const TOKEN = process.env.GITHUB_TOKEN || '';
const SHA = process.env.GITHUB_SHA || '';
const cab = { 'Accept': 'application/vnd.github+json', 'User-Agent': 'fiscal-de-prazos' };
if (TOKEN) cab['Authorization'] = 'Bearer ' + TOKEN;

import { existsSync as fsExists, readFileSync } from "node:fs";
const readTexto = (f) => { try { return readFileSync(f, "utf8"); } catch (e) { return ""; } };

const api = async (u) => {
  for (let k = 0; k < 3; k++) {
    try { const r = await fetch('https://api.github.com' + u, { headers: cab }); if (r.ok) return r.json(); }
    catch (e) { await new Promise((s) => setTimeout(s, 1500)); }
  }
  return null;
};

const repo = await api(`/repos/${DONO}/${REPO}`);
if (!repo) { console.log('não alcancei a API — nada a cobrar hoje.'); process.exit(0); }
const ramos = (await api(`/repos/${DONO}/${REPO}/branches`)) || [];
const hoje = new Date();
const noPrazo = [], vencidos = [], semDeclaracao = [];

// Onde mora o objeto da declaração no ramo. É o mesmo depósito dos exemplos.
const CAMINHO_DECL = 'exemplos/deposito/objetos/';

for (const b of ramos) {
  if (b.name === repo.default_branch) continue;
  const c = await api(`/repos/${DONO}/${REPO}/commits/${b.commit.sha}`);
  const msg = (c && c.commit && c.commit.message) || '';
  // CANAL 1 — a declaração é uma BOLHA: o compromisso carrega o ENDEREÇO, e o
  // prazo é um CAMPO lido do objeto, não um palpite sobre prosa.
  const end = msg.match(/declaracao\s*:\s*([0-9a-f]{64})/i);
  if (end) {
    const obj = await api(`/repos/${DONO}/${REPO}/contents/${CAMINHO_DECL}${end[1]}?ref=${b.name}`);
    if (!obj || !obj.content) { semDeclaracao.push(`${b.name} (o endereço não resolve)`); continue; }
    const texto = Buffer.from(obj.content, 'base64').toString('utf8');
    const campo = texto.match(/^prazo:\s*(\d{4}-\d{2}-\d{2})\s*$/m);
    if (!campo) { semDeclaracao.push(`${b.name} (a bolha não declara prazo)`); continue; }
    const prazo = new Date(campo[1] + 'T23:59:59Z');
    (prazo < hoje ? vencidos : noPrazo).push(`${b.name} [${campo[1]}] bolha`);
    continue;
  }

  // CANAL 2 (transição) — a prosa de antes, lida por expressão regular. Fica
  // enquanto houver ramo declarado do jeito velho; o número diz QUAL canal falou.
  const m = msg.match(/Prazo\s*\(A5\)\s*:\s*(\d{4}-\d{2}-\d{2})/i);
  if (!m) { semDeclaracao.push(b.name); continue; }
  const prazo = new Date(m[1] + 'T23:59:59Z');
  (prazo < hoje ? vencidos : noPrazo).push(`${b.name} [${m[1]}] prosa`);
}

const fora = ramos.filter((b) => b.name !== repo.default_branch);
console.log(`ramos fora do tronco: ${fora.length}`);
if (noPrazo.length) console.log('  no prazo: ' + noPrazo.join(' | '));
if (vencidos.length) console.log('  VENCIDOS: ' + vencidos.join(' | '));
if (semDeclaracao.length) console.log('  SEM DECLARAÇÃO DE PRAZO: ' + semDeclaracao.join(' | '));
if (!fora.length) console.log('  nenhum ramo paralelo — nada a enterrar.');

const partes = [`${noPrazo.length} no prazo`];
if (vencidos.length) partes.push(`${vencidos.length} vencido(s)`);
if (semDeclaracao.length) partes.push(`${semDeclaracao.length} sem declaracao`);
const desc = partes.join(', ').slice(0, 130);
// SEMPRE success: o ESTADO do compromisso verde quer dizer "o produto está de pé".
// Dívida de processo vai na DESCRIÇÃO, não na cor — senão o tronco pareceria quebrado
// (A6) e o vermelho deixaria de significar o que significa.
const estado = 'success';

// ─── A SEGUNDA DÍVIDA: O DIÁRIO ATRÁS DO TRABALHO ─────────────────────────
// O contrato já admite a sombra: "o diário fica para trás". Aqui ela vira número.
// O diário vive no ATELIÊ (privado); no tronco não existe, e isso é dito em voz alta.
const DIARIO = "conversa/Bolha.md";
let diarioAtraso = null;
if (fsExists(DIARIO)) {
  const texto = readTexto(DIARIO);
  const datas = [...texto.matchAll(/^##\s+(\d{4}-\d{2}-\d{2})/gm)].map((m) => m[1]).sort();
  const ultima = datas[datas.length - 1];
  const commits = await api(`/repos/${DONO}/${REPO}/commits?sha=${repo.default_branch}&per_page=1`);
  const ultimoCommit = (commits && commits[0] && commits[0].commit.author.date || "").slice(0, 10);
  if (!ultima) { console.log("  diário: nenhuma entrada DATADA (## AAAA-MM-DD) — dívida"); diarioAtraso = "sem entrada datada"; }
  else if (ultimoCommit && ultima < ultimoCommit) {
    const dias = Math.round((new Date(ultimoCommit) - new Date(ultima)) / 86400000);
    console.log(`  diário: última entrada ${ultima}, último compromisso ${ultimoCommit} — ${dias} dia(s) atrás`);
    diarioAtraso = `${dias} dia(s) atras`;
  } else console.log(`  diário: última entrada ${ultima} — em dia com o compromisso ${ultimoCommit}`);
} else console.log("  diário: não existe aqui (é do ateliê) — nada a cobrar neste repositório");
if (TOKEN && SHA) {
  const r = await fetch(`https://api.github.com/repos/${DONO}/${REPO}/statuses/${SHA}`, {
    method: 'POST', headers: { ...cab, 'Content-Type': 'application/json' },
    body: JSON.stringify({ state: estado, context: 'A5 - prazos', description: desc }),
  });
  console.log('  estado publicado: ' + r.status + ' — ' + desc);
  const descDiario = diarioAtraso ? `diario atras: ${diarioAtraso}` : 'diario em dia (ou ausente neste repositorio)';
  const r2 = await fetch(`https://api.github.com/repos/${DONO}/${REPO}/statuses/${SHA}`, {
    method: 'POST', headers: { ...cab, 'Content-Type': 'application/json' },
    body: JSON.stringify({ state: 'success', context: 'Diario - atraso', description: descDiario.slice(0,130) }),
  });
  console.log('  estado publicado: ' + r2.status + ' — ' + descDiario);
} else console.log('  (sem credencial: não publica)');
process.exit(0);   // SEMPRE zero: dívida de processo não derruba o produto
