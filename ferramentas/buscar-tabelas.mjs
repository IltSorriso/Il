// buscar-tabelas.mjs — traz as tabelas oficiais do Unicode (UCD).
// As tabelas NAO sao versionadas: sao dado de terceiro, grande e datado.
// Este programa as busca sob demanda, para o protótipo ser reproduzível.
import { mkdirSync, writeFileSync } from 'node:fs';
const DESTINO = process.env.HOME + '/projetos/bancada/unicode/';
mkdirSync(DESTINO, { recursive: true });
const ARQUIVOS = ['UnicodeData.txt', 'DerivedNormalizationProps.txt', 'CompositionExclusions.txt'];
for (const nome of ARQUIVOS) {
  const r = await fetch('https://www.unicode.org/Public/UCD/latest/ucd/' + nome);
  if (!r.ok) { console.log('falhou', nome, r.status); continue; }
  const b = Buffer.from(await r.arrayBuffer());
  writeFileSync(DESTINO + nome, b);
  console.log(nome, b.length, 'bytes');
}
