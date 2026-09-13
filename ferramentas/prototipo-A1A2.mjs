// prototipo-A1A2.mjs
// A1 — o juiz puro que RECUSA: qual regra fecha o buraco E sem atrito?
// A2 — DOIS JULGADORES: a regra do juiz é conferida por um verificador INDEPENDENTE.
//
// A potenciação que o usuário apontou: A2 é o instrumento que MEDE A1. Sozinho,
// A1 escolhe uma regra no escuro. Com A2, a regra é comparada com a implementação
// de referência (ICU, via node) sobre TODO o repertório Unicode — e cada
// discordância é um achado, não ruído (é o que a A1 do contrato manda: comparar
// ordenações, não valores absolutos).
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const U = process.env.HOME + '/projetos/bancada/unicode/';
const ler = (f) => readFileSync(U + f, 'utf8');

// ─── tabelas (dado Lean, no mundo real) ─────────────────────────────────────
const cccDe = new Map(), dec = new Map();
for (const l of ler('UnicodeData.txt').split('\n')) {
  if (!l) continue;
  const f = l.split(';'), cp = parseInt(f[0], 16), c = parseInt(f[3], 10) || 0;
  if (c) cccDe.set(cp, c);
  const d = f[5];
  if (d && !d.startsWith('<')) dec.set(cp, d.split(' ').map((x) => parseInt(x, 16)));
}
const excl = new Set(ler('CompositionExclusions.txt').split('\n').filter((l) => l && !l.startsWith('#')).map((l) => parseInt(l.trim().split(/\s|#/)[0], 16)));
const comp = new Map();
for (const [cp, alvos] of dec) if (alvos.length === 2 && !excl.has(cp)) comp.set(alvos[0] + ',' + alvos[1], cp);
const qc = [];
for (const l of ler('DerivedNormalizationProps.txt').split('\n')) {
  const m = l.match(/^([0-9A-F]{4,6})(?:\.\.([0-9A-F]{4,6}))?\s*;\s*NFC_QC\s*;\s*([NM])/);
  if (m) qc.push([parseInt(m[1], 16), parseInt(m[2] || m[1], 16), m[3]]);
}
const valQC = (cp) => { for (const [a, b, v] of qc) if (cp >= a && cp <= b) return v; return 'Y'; };

// Hangul algorítmico
const SB = 0xAC00, LB = 0x1100, VB = 0x1161, TB = 0x11A7, VC = 21, TC = 28, NC = VC * TC;
const compor = (a, b) => {
  if (a >= LB && a < LB + 19 && b >= VB && b < VB + VC) return SB + ((a - LB) * VC + (b - VB)) * TC;
  if (a >= SB && a < SB + NC && (a - SB) % TC === 0 && b > TB && b < TB + TC) return a + (b - TB);
  return comp.get(a + ',' + b);
};

// ─── INDEPENDENTE 1: a regra do juiz (verificar NFC, sem produzir) ─────────
const ehNFC = (s) => {
  const cps = [...s].map((c) => c.codePointAt(0));
  let ini = -1, uccc = 0;
  for (let i = 0; i < cps.length; i++) {
    const cp = cps[i], c = cccDe.get(cp) || 0, v = valQC(cp);
    if (uccc > c && c !== 0) return false;
    if (v === 'N') return false;
    if (v === 'M' && ini >= 0) {
      const ant = i > 0 ? (cccDe.get(cps[i - 1]) || 0) : 0;
      if (!(ant >= c && c !== 0) && compor(ini, cp) !== undefined) return false;
    }
    if (c === 0) ini = cp;
    uccc = c;
  }
  return true;
};

// ─── INDEPENDENTE 2: normalizar de verdade a partir das tabelas ────────────
const decompor = (cp, fora) => {
  if (cp >= SB && cp < SB + NC) {                     // Hangul algorítmico
    const i = cp - SB, l = LB + Math.floor(i / NC), v = VB + Math.floor((i % NC) / TC), t = i % TC;
    fora.push(l, v); if (t) fora.push(TB + t); return;
  }
  const d = dec.get(cp);
  if (!d) { fora.push(cp); return; }
  for (const x of d) decompor(x, fora);
};
const normalizar = (s) => {
  const fora = [];
  for (const ch of s) decompor(ch.codePointAt(0), fora);
  // ordenação canônica: estável, por CCC, dentro de cada corrida
  for (let i = 1; i < fora.length; i++) {
    const c = cccDe.get(fora[i]) || 0;
    if (c === 0) continue;
    let j = i;
    while (j > 0 && (cccDe.get(fora[j - 1]) || 0) > c) { const t = fora[j - 1]; fora[j - 1] = fora[j]; fora[j] = t; j--; }
  }
  // composição canônica
  const saida = [];
  let ultimo = -1, uccc = 0;
  for (const cp of fora) {
    const c = cccDe.get(cp) || 0;
    if (ultimo >= 0 && (uccc < c || uccc === 0)) {
      const k = compor(ultimo, cp);
      if (k !== undefined) { saida[saida.length - 1] = k; ultimo = k; continue; }
    }
    if (c === 0) { ultimo = cp; }
    uccc = c;
    saida.push(cp);
  }
  return String.fromCodePoint(...saida);
};

// ─── INDEPENDENTE 3: a referência do mundo (ICU, nativa do node) ───────────
const referencia = (s) => s.normalize('NFC');

// ─── MEDIÇÃO 1: todo o repertório Unicode ─────────────────────────────────
let discord = [], iguais = 0;
for (let cp = 0; cp <= 0x10FFFF; cp++) {
  if (cp >= 0xD800 && cp <= 0xDFFF) continue;
  const s = String.fromCodePoint(cp);
  const a = ehNFC(s), b = referencia(s) === s;
  if (a === b) iguais++; else if (discord.length < 12) discord.push([cp, a, b]);
}
const total = 1114112 - 2048;
console.log('═══ A2 — o juiz confere com a referência do mundo? (repertório inteiro) ═══');
console.log('  pontos de código testados:', total);
console.log('  concordâncias:', iguais, '(' + ((iguais / total) * 100).toFixed(4) + '%)');
console.log('  DISCORDÂNCIAS:', total - iguais);
discord.forEach(([cp, a, b]) => console.log('    U+' + cp.toString(16).toUpperCase() + ': juiz diz ' + (a ? 'NFC' : 'não-NFC') + ', referência diz ' + (b ? 'NFC' : 'não-NFC')));

// ─── MEDIÇÃO 2: pares (início + combinante) — onde a composição vive ───────
let pd = 0, pt = 0, exemplos = [];
const combinantes = [...cccDe.keys()];
const inicios = [...new Set([...comp.keys()].map((k) => parseInt(k.split(',')[0])))];
for (const a of inicios) {
  for (const b of combinantes) {
    const s = String.fromCodePoint(a, b);
    const r = referencia(s) === s;
    if (ehNFC(s) !== r) { pd++; if (exemplos.length < 8) exemplos.push([a, b, r]); }
    pt++;
  }
}
console.log('\n  pares início+combinante testados:', pt);
console.log('  DISCORDÂNCIAS:', pd);
exemplos.forEach(([a, b, r]) => console.log('    U+' + a.toString(16).toUpperCase() + '+U+' + b.toString(16).toUpperCase() + ': juiz diz não-NFC, referência diz ' + (r ? 'NFC' : 'não-NFC')));

// ─── MEDIÇÃO 3: o normalizador das tabelas bate com a referência? ─────────
let nd = 0, nt = 0, nex = [];
for (let cp = 0; cp <= 0x10FFFF; cp++) {
  if (cp >= 0xD800 && cp <= 0xDFFF) continue;
  const s = String.fromCodePoint(cp);
  nt++;
  if (normalizar(s) !== referencia(s)) { nd++; if (nex.length < 8) nex.push(cp); }
}
for (const a of inicios) for (const b of combinantes) {
  const s = String.fromCodePoint(a, b); nt++;
  if (normalizar(s) !== referencia(s)) { nd++; if (nex.length < 8) nex.push('U+' + a.toString(16) + '+U+' + b.toString(16)); }
}
console.log('\n═══ o normalizador feito das tabelas bate com a referência? ═══');
console.log('  casos:', nt, '| discordâncias:', nd);
nex.forEach((x) => console.log('    ', typeof x === 'number' ? 'U+' + x.toString(16).toUpperCase() : x));

// ─── MEDIÇÃO 4: o corpus real, por classe de equivalência ─────────────────
const end = (s) => createHash('sha256').update(s, 'utf8').digest('hex').slice(0, 12);
const real = [
  'Primeira anotação da Linguagem-Bolha — importada pela mão, marcada como uso-privado.',
  'Exemplo canônico da Linguagem-Bolha — uma anotação de verdade.\n',
];
console.log('\n═══ SILÊNCIO no corpus REAL (com o par decomposto que faltava) ═══');
for (const t of real) {
  const par = t.normalize('NFD');
  const grupo = [t, par];
  const distintos = new Set(grupo.map(end));
  console.log('  texto: "' + t.slice(0, 42) + '…"');
  console.log('    NFC -> ' + end(t) + '   NFD -> ' + end(par) + '   bytes ' + Buffer.byteLength(t) + ' vs ' + Buffer.byteLength(par));
  console.log('    endereços distintos: ' + distintos.size + (distintos.size > 1 ? '  ← SILÊNCIO se a regra não recusar a segunda' : ''));
  console.log('    regra do juiz aceita a segunda? ' + (ehNFC(par) ? 'SIM — FALHA' : 'não — ok'));
}
