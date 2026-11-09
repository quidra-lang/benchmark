'use strict';

function category(value) {
  let n = 0;
  while (Math.abs(value) >= 2 ** n) n++;
  return n;
}

function extra(value, n = category(value)) { return value >= 0 ? value : value + 2 ** n - 1; }
function restore(value, n) { return n === 0 ? 0 : value >= 2 ** (n - 1) ? value : value - 2 ** n + 1; }

function assign(table) {
  const codes = new Map(), decode = Array.from({ length: 17 }, () => new Map());
  let code = 0, at = 0;
  for (let length = 1; length <= 16; length++) {
    for (let i = 0; i < table.bits[length - 1]; i++) {
      const symbol = table.values[at++];
      codes.set(symbol, { code, length }); decode[length].set(code, symbol); code++;
    }
    code *= 2;
  }
  return { ...table, codes, decode };
}

function optimized(frequencies, tableClass, id) {
  const freq = [...frequencies, 1], sizes = Array(257).fill(0), others = Array(257).fill(-1);
  while (true) {
    let first = -1, second = -1;
    for (let v = 0; v <= 256; v++) if (freq[v] > 0 && (first < 0 || freq[v] <= freq[first])) first = v;
    for (let v = 0; v <= 256; v++) if (v !== first && freq[v] > 0 && (second < 0 || freq[v] <= freq[second])) second = v;
    if (second < 0) break;
    freq[first] += freq[second]; freq[second] = 0;
    sizes[first]++;
    while (others[first] !== -1) { first = others[first]; sizes[first]++; }
    others[first] = second;
    sizes[second]++;
    while (others[second] !== -1) { second = others[second]; sizes[second]++; }
  }
  const counts = Array(257).fill(0);
  for (const size of sizes) if (size > 0) counts[size]++;
  for (let length = 256; length >= 17; length--) while (counts[length] > 0) {
    let shorter = length - 2;
    while (counts[shorter] === 0) shorter--;
    counts[length] -= 2; counts[length - 1]++; counts[shorter + 1] += 2; counts[shorter]--;
  }
  let longest = 16;
  while (counts[longest] === 0) longest--;
  counts[longest]--;
  const values = [];
  for (let v = 0; v <= 255; v++) if (sizes[v] > 0) values.push(v);
  values.sort((a, b) => sizes[a] - sizes[b] || a - b);
  return assign({ tableClass, id, bits: counts.slice(1, 17), values });
}

module.exports = { category, extra, restore, assign, optimized };
