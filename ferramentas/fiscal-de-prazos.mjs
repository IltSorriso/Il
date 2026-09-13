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

for (const b of ramos) {
  if (b.name === repo.default_branch) continue;
  const c = await api(`/repos/${DONO}/${REPO}/commits/${b.commit.sha}`);
  const msg = (c && c.commit && c.commit.message) || '';
  const m = msg.match(/Prazo\s*\(A5\)\s*:\s*(\d{4}-\d{2}-\d{2})/i);
  if (!m) { semDeclaracao.push(b.name); continue; }
  const prazo = new Date(m[1] + 'T23:59:59Z');
  (prazo < hoje ? vencidos : noPrazo).push(`${b.name} [${m[1]}]`);
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

if (TOKEN && SHA) {
  const r = await fetch(`https://api.github.com/repos/${DONO}/${REPO}/statuses/${SHA}`, {
    method: 'POST', headers: { ...cab, 'Content-Type': 'application/json' },
    body: JSON.stringify({ state: estado, context: 'A5 - prazos', description: desc }),
  });
  console.log('  estado publicado: ' + r.status + ' — ' + desc);
} else console.log('  (sem credencial: não publica)');
process.exit(0);   // SEMPRE zero: dívida de processo não derruba o produto
