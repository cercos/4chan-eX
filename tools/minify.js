#!/usr/bin/env node
'use strict';

const fs = require('fs');
const {minify} = require('terser');
const pkg = require('../package.json');
const name = pkg.meta.path;

const USERSCRIPT_END = '// ==/UserScript==\n';

async function minifyFile(inPath, outPath, isUserscript) {
  const source = fs.readFileSync(inPath, 'utf8');

  let header = '';
  let body = source;

  if (isUserscript) {
    const idx = source.indexOf(USERSCRIPT_END);
    if (idx >= 0) {
      header = source.slice(0, idx + USERSCRIPT_END.length);
      body = source.slice(header.length);
    }
  }

  const result = await minify(body, {
    compress: true,
    mangle: true,
    format: {comments: false}
  });

  const output = header + result.code + '\n';
  fs.writeFileSync(outPath, output);

  const origKB = (Buffer.byteLength(source) / 1024).toFixed(0);
  const newKB  = (Buffer.byteLength(output) / 1024).toFixed(0);
  const pct    = ((1 - Buffer.byteLength(output) / Buffer.byteLength(source)) * 100).toFixed(0);
  console.log(`  ${inPath}: ${origKB}K -> ${newKB}K (-${pct}%)`);
}

(async () => {
  try {
    await Promise.all([
      minifyFile(`testbuilds/crx/script.js`,          `testbuilds/crx/script.js`,          false),
      minifyFile(`testbuilds/crx-beta/script.js`,     `testbuilds/crx-beta/script.js`,     false),
      minifyFile(`testbuilds/crx-noupdate/script.js`, `testbuilds/crx-noupdate/script.js`, false),
    ]);
    console.log('Done.');
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
})();
