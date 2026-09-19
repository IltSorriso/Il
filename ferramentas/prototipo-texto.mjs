// prototipo-texto.mjs — compara as REGRAS de forma canônica de texto, com dados.
// Mede: buracos (aceita o que não devia), atrito (recusa o que devia aceitar),
// tamanho de tabela e custo de tempo. Fontes: UCD oficial.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const U = process.env.HOME + '/projetos/bancada/unicode/';
const ler = (f) => readFileSync(U + f, 'utf8');

// ── tabelas ────────────────────────────────────────────────────────────────
const cccDe = new Map(), decomp = new Map();
for (const l of ler('UnicodeData.txt').split('\n')) {
  if (!l) continue;
  const f = l.split(';'), cp = parseInt(f[0], 16), c = parseInt(f[3], 10) || 0;
  if (c) cccDe.set(cp, c);
  const d = f[5];
  if (d && !d.startsWith('<')) {
    const alvos = d.split(' ').map((x) => parseInt(x, 16));
    if (alvos.length === 2) decomp.set(cp, alvos);
  }
}
const excluidos = new Set(ler('CompositionExclusions.txt').split('\n')
  .filter((l) => l && !l.startsWith('#')).map((l) => parseInt(l.trim().split(/\s|#/)[0], 16)));
const composicao = new Map();     // "a,b" -> composto
for (const [cp, [a, b]] of decomp) if (!excluidos.has(cp)) composicao.set(a + ',' + b, cp);

const qc = [];
for (const l of ler('DerivedNormalizationProps.txt').split('\n')) {
  const m = l.match(/^([0-9A-F]{4,6})(?:\.\.([0-9A-F]{4,6}))?\s*;\s*NFC_QC\s*;\s*([NM])/);
  if (m) qc.push([parseInt(m[1], 16), parseInt(m[2] || m[1], 16), m[3]]);
}
const valorQC = (cp) => { for (const [a, b, v] of qc) if (cp >= a && cp <= b) return v; return 'Y'; };

// Hangul algorítmico (a composição coreana não está na tabela)
const S_BASE = 0xAC00, L_BASE = 0x1100, V_BASE = 0x1161, T_BASE = 0x11A7, V_CNT = 21, T_CNT = 28;
const compor = (a, b) => {
  if (a >= L_BASE && a < L_BASE + 19 && b >= V_BASE && b < V_BASE + V_CNT)
    return S_BASE + ((a - L_BASE) * V_CNT + (b - V_BASE)) * T_CNT;
  if (a >= S_BASE && a < S_BASE + 11172 && (a - S_BASE) % T_CNT === 0 && b > T_BASE && b < T_BASE + T_CNT)
    return a + (b - T_BASE);
  return composicao.get(a + ',' + b);
};

// ── as quatro regras ───────────────────────────────────────────────────────
// A' — a registrada no contrato: recusar U+0300–U+036F + singleton
const A = (s) => ![...s].some((ch) => { const n = ch.codePointAt(0); return n >= 0x300 && n <= 0x36F; });

// A'' — recusar TODO combinante (CCC≠0) e toda faixa No/Maybe. Fecha buracos, cria atrito.
const App = (s) => ![...s].some((ch) => { const n = ch.codePointAt(0); return cccDe.has(n) || valorQC(n) !== 'Y'; });

// C — VERIFICAR NFC de verdade: ordenação canônica + Quick_Check + bloqueio
const C = (s) => {
  const cps = [...s].map((c) => c.codePointAt(0));
  let ultimoInicio = -1, ultimoCCC = 0;
  for (let i = 0; i < cps.length; i++) {
    const cp = cps[i], ccc = cccDe.get(cp) || 0, v = valorQC(cp);
    if (ultimoCCC > ccc && ccc !== 0) return false;          // fora de ordem canônica
    if (v === 'N') return false;
    if (v === 'M' && ultimoInicio >= 0) {
      const anterior = i > 0 ? (cccDe.get(cps[i - 1]) || 0) : 0;
      const bloqueado = anterior >= ccc && ccc !== 0;
      if (!bloqueado && compor(ultimoInicio, cp) !== undefined) return false;
    }
    if (ccc === 0) ultimoInicio = cp;
    ultimoCCC = ccc;
  }
  return true;
};

// B — normalizar (o juiz produz a forma). Aqui uso o normalizador do node como
// referência CORRETA; o custo de tabela do Lean é medido à parte.
const B = (s) => s.normalize('NFC');
const Baceita = (s) => true;   // normalizando, o juiz aceita qualquer texto

// ── corpus ─────────────────────────────────────────────────────────────────
const casos = [];
const add = (nome, texto, canonico) => casos.push({ nome, texto, canonico });
// reais
add('real: prosa do ateliê', 'Primeira anotação da Linguagem-Bolha — importada pela mão, marcada como uso-privado.', true);
add('real: prosa da pindorama', 'Exemplo canônico da Linguagem-Bolha — uma anotação de verdade.\n', true);
// hostis: mesma coisa, outra grafia
add('HOSTIL pt NFD', 'cano\u0302nico e anotac\u0327a\u0303o', false);
add('HOSTIL grego NFD', '\u03B1\u0301\u03B2\u03B3', false);
add('HOSTIL cirílico NFD', '\u0438\u0306', false);
add('HOSTIL coreano decomposto', '\u1112\u1161\u11AB', false);
add('HOSTIL japonês decomposto', '\u30AB\u3099\u30AD\u3099', false);
add('HOSTIL Hangul LVT', '\u1100\u1161\u11A8', false);
add('HOSTIL ligadura', '\uFB01m', false);
add('HOSTIL largura cheia', '\uFF41\uFF42\uFF43', false);
add('HOSTIL singleton Ohm', '\u2126', false);
// atrito: NFC legítimo que contém combinante sem composto (deve ser ACEITO)
add('ATRITO q + acento (NFC válido)', 'q\u0301', true);
add('ATRITO f + trema (NFC válido)', 'f\u0308', true);
add('ATRITO xi + acento (NFC válido)', '\u03BE\u0301', true);
add('ATRITO dois acentos empilhados em NFC', 'e\u0301\u0323', true);

// ── medição ────────────────────────────────────────────────────────────────
const end = (s) => createHash('sha256').update(s, 'utf8').digest('hex').slice(0, 12);
const classes = new Map();
for (const c of casos) {
  const nfc = B(c.texto);
  if (!classes.has(nfc)) classes.set(nfc, []);
  classes.get(nfc).push(c);
}
let buracos = 0, atritos = 0;
const linhas = [];
for (const c of casos) {
  const a = A(c.texto), app = App(c.texto), cc = C(c.texto);
  if (!c.canonico && a) buracos++;
  if (c.canonico && (!a || !app || !cc)) atritos++;
  linhas.push({ nome: c.nome, a, app, cc, ok: c.canonico, endereco: end(c.texto), nfc: c.canonico ? '—' : 'normalizaria para ' + end(B(c.texto)) });
}
console.log('\n═══ REGRA × CASO ═══');
console.log('  ' + 'caso'.padEnd(36) + 'A (contrato)'.padEnd(14) + 'A\'\' (faixas)'.padEnd(14) + 'C (verificar NFC)'.padEnd(19) + 'canônico?');
for (const l of linhas) {
  console.log('  ' + l.nome.padEnd(34) +
    (l.a ? 'aceita' : 'RECUSA').padEnd(14) +
    (l.app ? 'aceita' : 'RECUSA').padEnd(14) +
    (l.cc ? 'aceita' : 'RECUSA').padEnd(19) +
    (l.ok ? 'sim' : 'NÃO'));
}
console.log('\n═══ SILÊNCIO: quantos endereços para a MESMA coisa? ═══');
for (const [nfc, grupo] of classes) {
  if (grupo.length < 2) continue;
  const aceitos = grupo.filter((c) => A(c.texto));
  const distintos = new Set(grupo.filter((c) => A(c.texto)).map((c) => end(c.texto)));
  console.log('  grupo "' + grupo[0].nome.replace('HOSTIL ', '').replace('real: ', '') + '" (' + grupo.length + ' grafias)');
  console.log('     sob A: ' + distintos.size + ' endereço(s) distinto(s) aceito(s)  →  ' + (distintos.size > 1 ? 'SILÊNCIO' : 'ok'));
  console.log('     sob C: ' + new Set(grupo.filter((c) => C(c.texto)).map((c) => end(c.texto))).size + ' endereço(s)');
}
console.log('\n═══ PLACAR ═══');
console.log('  regra A  (contrato)   buracos: ' + buracos + ' | atrito: ' + atritos);
const buracosRestantes = casos.filter((c) => !c.canonico && App(c.texto)).length;
console.log('  regra A\'\' (faixas)    buracos: ' + buracosRestantes + ' | atrito: ' + casos.filter((c) => c.canonico && !App(c.texto)).length);
console.log('  regra C  (NFC real)   buracos: ' + casos.filter((c) => !c.canonico && C(c.texto)).length + ' | atrito: ' + casos.filter((c) => c.canonico && !C(c.texto)).length);
console.log('\n═══ CUSTO DE TABELA (em Lean, estimado do UCD) ═══');
const kb = (n) => (n / 1024).toFixed(1) + ' KB';
console.log('  CCC:              ' + cccDe.size + ' entradas ≈ ' + kb(cccDe.size * 6));
console.log('  NFC_QC (No+Maybe): ' + qc.length + ' faixas ≈ ' + kb(qc.length * 10));
console.log('  composição:       ' + composicao.size + ' pares ≈ ' + kb(composicao.size * 10));
console.log('  → A\'\' precisa de: ' + kb((cccDe.size * 6) + (qc.length * 10)) + '   (sem lógica de composição)');
console.log('  → C precisa de:   ' + kb((cccDe.size * 6) + (qc.length * 10) + (composicao.size * 10)) + '   (+ lógica de bloqueio)');
console.log('  → B precisa de C + produzir + PROVAR idempotência');
console.log('\n═══ TEMPO (node; proxy — o Lean não roda aqui) ═══');
const amostra = casos.map((c) => c.texto).join(' ');
const t0 = process.hrtime.bigint();
for (let i = 0; i < 100000; i++) { A(amostra); }
const t1 = process.hrtime.bigint();
for (let i = 0; i < 100000; i++) { App(amostra); }
const t2 = process.hrtime.bigint();
for (let i = 0; i < 100000; i++) { C(amostra); }
const t3 = process.hrtime.bigint();
for (let i = 0; i < 100000; i++) { amostra.normalize('NFC'); }
const t4 = process.hrtime.bigint();
const us = (a, b) => (Number(b - a) / 1000 / 100000).toFixed(2) + ' µs/texto';
console.log('  A (faixa):        ' + us(t0, t1));
console.log('  A\'\' (mapas):      ' + us(t1, t2));
console.log('  C (verificar):    ' + us(t2, t3));
console.log('  B (normalizar):   ' + us(t3, t4));
