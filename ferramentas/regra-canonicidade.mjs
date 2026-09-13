// regra-canonicidade.mjs — a regra de texto canônico, CORRIGIDA e medida.
//
// O que a versão anterior errou: compor exige DECOMPOR e REORDENAR antes, e o
// "início" da composição é a posição no texto já decomposto — não o caractere
// cru. Aqui a normalização é reescrita com índice de início, e as regras são
// comparadas com a referência do mundo (ICU, via node) até ZERO discordância.
//
// Também mede o ATRITO da regra estrita em texto REAL (prosa dos repositórios,
// letra de música, amostras de coreano e japonês).
import { readFileSync, existsSync } from 'node:fs';
const U = process.env.HOME + '/projetos/bancada/unicode/';
const ler = (f) => readFileSync(U + f, 'utf8');

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
const ccc = (cp) => cccDe.get(cp) || 0;

const SB = 0xAC00, LB = 0x1100, VB = 0x1161, TB = 0x11A7, VC = 21, TC = 28, NC = VC * TC;
const compor = (a, b) => {
  if (a >= LB && a < LB + 19 && b >= VB && b < VB + VC) return SB + ((a - LB) * VC + (b - VB)) * TC;
  if (a >= SB && a < SB + NC && (a - SB) % TC === 0 && b > TB && b < TB + TC) return a + (b - TB);
  return comp.get(a + ',' + b);
};
const decompor = (cp, fora) => {
  if (cp >= SB && cp < SB + NC) {
    const i = cp - SB, l = LB + Math.floor(i / NC), v = VB + Math.floor((i % NC) / TC), t = i % TC;
    fora.push(l, v); if (t) fora.push(TB + t); return;
  }
  const d = dec.get(cp);
  if (!d) { fora.push(cp); return; }
  for (const x of d) decompor(x, fora);
};
const ordenar = (cp) => {
  for (let i = 1; i < cp.length; i++) {
    const c = ccc(cp[i]);
    if (c === 0) continue;
    let j = i;
    while (j > 0 && ccc(cp[j - 1]) > c) { const t = cp[j - 1]; cp[j - 1] = cp[j]; cp[j] = t; j--; }
  }
};
// NFC: decompor, ordenar, compor com ÍNDICE de início (era o defeito)
const normalizar = (s) => {
  const d = []; for (const ch of s) decompor(ch.codePointAt(0), d);
  ordenar(d);
  const saida = []; let ini = -1, uccc = 0;
  for (const cp of d) {
    const c = ccc(cp);
    if (ini >= 0 && (uccc < c || uccc === 0)) {
      const k = compor(saida[ini], cp);
      if (k !== undefined) { saida[ini] = k; continue; }
    }
    if (c === 0) ini = saida.length;
    uccc = c;
    saida.push(cp);
  }
  return String.fromCodePoint(...saida);
};
const referencia = (s) => s.normalize('NFC');

// REGRA ESTRITA (A″): recusa qualquer combinante e qualquer faixa No/Maybe.
// É mais estreita que NFC — logo recusa texto VÁLIDO às vezes. O atrito é medido.
const estrita = (s) => ![...s].some((ch) => { const n = ch.codePointAt(0); return cccDe.has(n) || valQC(n) !== 'Y'; });
// REGRA C: verificação rápida + recurso à normalização quando a rápida não decide.
const rapida = (s) => {
  const cps = [...s].map((c) => c.codePointAt(0));
  let uccc = 0;
  for (let i = 0; i < cps.length; i++) {
    const c = ccc(cps[i]), v = valQC(cps[i]);
    if (uccc > c && c !== 0) return false;
    if (v === 'N') return false;
    if (v === 'M') return null;          // NÃO DECIDE
    uccc = c;
  }
  return true;
};
const C = (s) => { const r = rapida(s); return r === null ? (normalizar(s) === s) : r; };

// ─── MEDIÇÃO ───────────────────────────────────────────────────────────────
console.log('═══ 1. A NORMALIZAÇÃO CORRIGIDA bate com a referência? ═══');
let nd = 0, nt = 0, ex = [];
const inicios = [...new Set([...comp.keys()].map((k) => parseInt(k.split(',')[0])))];
const combinantes = [...cccDe.keys()];
for (let cp = 0; cp <= 0x10FFFF; cp++) {
  if (cp >= 0xD800 && cp <= 0xDFFF) continue;
  const s = String.fromCodePoint(cp); nt++;
  if (normalizar(s) !== referencia(s)) { nd++; if (ex.length < 5) ex.push('U+' + cp.toString(16)); }
}
for (const a of inicios) for (const b of combinantes) {
  const s = String.fromCodePoint(a, b); nt++;
  if (normalizar(s) !== referencia(s)) { nd++; if (ex.length < 5) ex.push('U+' + a.toString(16) + '+U+' + b.toString(16)); }
}
for (const [k] of comp) {   // os pares que COMPÕEM, nas duas ordens de decomposição
  const [a, b] = k.split(',').map(Number);
  const alvo = compor(a, b);
  const s = String.fromCodePoint(a, b); nt++;
  if (normalizar(s) !== referencia(s)) { nd++; if (ex.length < 5) ex.push('U+' + a.toString(16) + '+U+' + b.toString(16)); }
  if (alvo !== undefined && normalizar(String.fromCodePoint(alvo)) !== referencia(String.fromCodePoint(alvo))) nd++;
}
console.log('  casos:', nt, '| DISCORDÂNCIAS:', nd, ex.length ? '| ex: ' + ex.join(' ') : '');

console.log('\n═══ 2. A REGRA C (rápida + recurso) bate com a referência? ═══');
let cd = 0, ct = 0, cex = [];
for (let cp = 0; cp <= 0x10FFFF; cp++) {
  if (cp >= 0xD800 && cp <= 0xDFFF) continue;
  const s = String.fromCodePoint(cp); ct++;
  if (C(s) !== (referencia(s) === s)) { cd++; if (cex.length < 5) cex.push('U+' + cp.toString(16)); }
}
for (const a of inicios) for (const b of combinantes) {
  const s = String.fromCodePoint(a, b); ct++;
  if (C(s) !== (referencia(s) === s)) { cd++; if (cex.length < 5) cex.push('U+' + a.toString(16) + '+U+' + b.toString(16)); }
}
console.log('  casos:', ct, '| DISCORDÂNCIAS:', cd, cex.length ? '| ex: ' + cex.join(' ') : '');

console.log('\n═══ 3. A REGRA RÁPIDA SOZINHA decidiria? (a pergunta do custo) ═══');
let talvez = 0, ttal = 0;
for (const a of inicios) for (const b of combinantes) { ttal++; if (rapida(String.fromCodePoint(a, b)) === null) talvez++; }
console.log('  pares em que a verificação rápida NÃO DECIDE:', talvez, 'de', ttal, '(' + ((talvez / ttal) * 100).toFixed(1) + '%)');

console.log('\n═══ 4. ATRITO EM TEXTO REAL ═══');
const arquivos = [
  [process.env.HOME + '/projetos/il-final/README.md', 'capa do tronco'],
  [process.env.HOME + '/projetos/il-final/exemplos/musica/letra.txt', 'letra de música (tronco)'],
  [process.env.HOME + '/projetos/IltS/conversa/PLANO.md', 'contrato (ateliê)'],
  [process.env.HOME + '/projetos/IltS/conversa/Bolha.md', 'diário (ateliê)'],
];
let linhas = 0, recusadasE = 0, recusadasC = 0, exE = [];
for (const [caminho, nome] of arquivos) {
  if (!existsSync(caminho)) { console.log('  (falta:', nome, ')'); continue; }
  const texto = readFileSync(caminho, 'utf8');
  const ls = texto.split('\n');
  linhas += ls.length;
  for (const l of ls) {
    if (!l.trim()) continue;
    if (!estrita(l)) { recusadasE++; if (exE.length < 4) exE.push([nome, l.slice(0, 60)]); }
    if (!C(l)) recusadasC++;
  }
  console.log('  ', nome.padEnd(24), ls.length, 'linhas | estrita recusa', ls.filter((l) => l.trim() && !estrita(l)).length, '| C recusa', ls.filter((l) => l.trim() && !C(l)).length);
}
console.log('  TOTAL:', linhas, 'linhas reais');
console.log('  regra estrita recusaria:', recusadasE, 'linha(s)');
console.log('  regra C recusaria:      ', recusadasC, 'linha(s)  ← NFC válido nunca é recusado');
exE.forEach(([n, l]) => console.log('     estrita recusaria em', n, ':', JSON.stringify(l)));
console.log('\n  coreano NFC:', estrita('한글') ? 'aceita' : 'RECUSA', '| japonês NFC:', estrita('ガギ') ? 'aceita' : 'RECUSA');
console.log('  coreano decomposto:', estrita('\u1112\u1161\u11AB') ? 'aceita' : 'RECUSA', '| japonês decomposto:', estrita('\u30AB\u3099') ? 'aceita' : 'RECUSA');
