// medir-vasos.mjs — a RÉGUA ÚNICA sobre os vasos, pela definição do SPEC.
// Três faces: QUALIDADE DE USO (atrito), RECURSOS (bytes), TEMPO (µs).
//
// Correção do medidor anterior: `bolhas/*.bolha` são JANELAS humanas — o nome é o
// hash do CONTEÚDO, por convenção do arreio.py — logo não se cobra delas o próprio
// endereço. Quem se cobra é o objeto no depósito, cujo nome É o seu sha256.
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
const C = process.env.HOME;
const U = C + '/projetos/bancada/unicode/';

const cccDe = new Set(); const qcNao = [];
for (const l of readFileSync(U + 'UnicodeData.txt', 'utf8').split('\n')) {
  if (!l) continue; const f = l.split(';'); if ((parseInt(f[3], 10) || 0) !== 0) cccDe.add(parseInt(f[0], 16));
}
for (const l of readFileSync(U + 'DerivedNormalizationProps.txt', 'utf8').split('\n')) {
  const m = l.match(/^([0-9A-F]{4,6})(?:\.\.([0-9A-F]{4,6}))?\s*;\s*NFC_QC\s*;\s*([NM])/);
  if (m) qcNao.push([parseInt(m[1], 16), parseInt(m[2] || m[1], 16)]);
}
const recusado = (s) => [...s].some((ch) => { const n = ch.codePointAt(0); return cccDe.has(n) || qcNao.some(([a, b]) => n >= a && n <= b); });

// O REGISTRO DE ESPÉCIES, lido do próprio spec (fonte única de verdade)
const spec = readFileSync(C + '/projetos/il-final/juiz/Bolha.lean', 'utf8');
const registro = [...spec.matchAll(/\("(\w+)",\s*\[/g)].map((m) => m[1]);
console.log('  registro de espécies (do spec):', registro.join(', '));

const end = (b) => createHash('sha256').update(b).digest('hex');
const tipoDe = (txt) => (txt.match(/^tipo:\s*(\S+)/m) || [])[1] || null;

const ONDE = [
  ['pindorama', C + '/projetos/il-final/exemplos/deposito/objetos'],
  ['pindorama/quebrados', C + '/projetos/il-final/exemplos/quebrados/objetos'],
  ['ateliê', C + '/projetos/IltS/deposito/objetos'],
];
const JANELAS = [C + '/projetos/IltS/bolhas'];

console.log('\n═══ OS VASOS, POR ESPÉCIE (a régua do spec) ═══');
console.log('  ' + 'espécie'.padEnd(12) + 'peças'.padEnd(7) + 'bytes'.padEnd(8) + 'endereço'.padEnd(11) + 'canônico'.padEnd(10) + 'µs/peça');
const porEspecie = new Map();
const amostras = [];
for (const [origem, d] of ONDE) {
  if (!existsSync(d)) continue;
  for (const f of readdirSync(d)) {
    const b = readFileSync(d + '/' + f), txt = b.toString('utf8'), t = tipoDe(txt) || '(sem tipo)';
    if (!porEspecie.has(t)) porEspecie.set(t, { pecas: 0, bytes: 0, endereco: 0, canonico: 0 });
    const v = porEspecie.get(t);
    v.pecas++; v.bytes += b.length;
    if (end(b) === f) v.endereco++;
    if (!recusado(txt)) v.canonico++;
    amostras.push(txt);
  }
}
for (const [t, v] of [...porEspecie].sort()) {
  const t0 = process.hrtime.bigint();
  for (let i = 0; i < 2000; i++) recusado(t);
  const t1 = process.hrtime.bigint();
  const noRegistro = registro.includes(t);
  console.log('  ' + (t + (noRegistro ? '' : ' ⚠')).padEnd(12) + String(v.pecas).padEnd(7) + String(v.bytes).padEnd(8) +
    (v.endereco + '/' + v.pecas + (v.endereco === v.pecas ? ' ✅' : '')).padEnd(11) +
    (v.canonico + '/' + v.pecas).padEnd(10) + (Number(t1 - t0) / 2000 / 1000).toFixed(1));
}

console.log('\n═══ AS JANELAS HUMANAS (bolhas/*.bolha) — a convenção do arreio.py ═══');
for (const d of JANELAS) {
  if (!existsSync(d)) continue;
  for (const f of readdirSync(d)) {
    const txt = readFileSync(d + '/' + f, 'utf8');
    const conteudoApontado = (txt.match(/^conteudo:\s*(\S+)/m) || [])[1] || '';
    const nome = f.replace(/^\w+-/, '').replace(/\.bolha$/, '');
    const certo = conteudoApontado.startsWith(nome);
    console.log('  ' + f.slice(0, 30).padEnd(32) + 'aponta para ' + conteudoApontado.slice(0, 12) +
      ' | nome casa com o conteúdo? ' + (certo ? 'sim ✅' : 'NÃO'));
  }
}

console.log('\n═══ ATRITO (intervenção humana necessária) ═══');
let atrito = 0;
for (const [t, v] of porEspecie) {
  const foraDoRegistro = registro.includes(t) ? 0 : v.pecas;
  const semEndereco = v.pecas - v.endereco;
  const naoCanonico = v.pecas - v.canonico;
  const a = foraDoRegistro + semEndereco + naoCanonico;
  atrito += a;
  console.log('  ' + t.padEnd(12) + 'espécie fora do registro: ' + foraDoRegistro +
    ' | sem endereço: ' + semEndereco + ' | fora da forma canônica: ' + naoCanonico);
}
console.log('  TOTAL de atrito: ' + atrito);
console.log('\n  V3 biografia: vaso ainda NÃO EXISTE — nada a medir. Criá-lo é decisão do criador.');
