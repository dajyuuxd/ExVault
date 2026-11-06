#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const filePath = path.join(__dirname, '..', 'Web', 'js', 'i18n.js');
if (!fs.existsSync(filePath)) {
  console.error('File not found: ' + filePath);
  process.exit(1);
}

const code = fs.readFileSync(filePath, 'utf8');

const sandbox = {
  window: {},
  localStorage: { getItem: () => null, setItem: () => {} },
  navigator: { language: 'en-US' },
  console: console
};
vm.createContext(sandbox);
vm.runInContext(code, sandbox);

const EX = sandbox.window.EX;
if (!EX || !EX.i18nTables) {
  console.error('Failed to load i18nTables from i18n.js');
  process.exit(1);
}

const viKeys = new Set(Object.keys(EX.i18nTables.vi || {}));
const enKeys = new Set(Object.keys(EX.i18nTables.en || {}));

let hasMismatch = false;

for (const k of viKeys) {
  if (!enKeys.has(k)) {
    console.error(`Key "${k}" exists in 'vi' but missing in 'en'`);
    hasMismatch = true;
  }
}

for (const k of enKeys) {
  if (!viKeys.has(k)) {
    console.error(`Key "${k}" exists in 'en' but missing in 'vi'`);
    hasMismatch = true;
  }
}

if (hasMismatch) {
  console.error('i18n verification FAILED: tables are not symmetric');
  process.exit(1);
}

console.log(`✓ i18n check passed: ${viKeys.size} keys matched between 'vi' and 'en'`);
process.exit(0);
