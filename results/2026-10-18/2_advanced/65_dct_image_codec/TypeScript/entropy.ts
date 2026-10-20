export interface HuffmanTable { class: number; id: number; counts: number[]; values: number[] }
export interface Code { length: number; value: number }
export function category(a: number): number { let n = 0; for (let value = Math.abs(a); value > 0; value = Math.floor(value / 2)) n++; return n; }
export function extra(a: number, n: number): number { return a >= 0 ? a : a + 2 ** n - 1; }
export function signed(w: number, n: number): number { return n === 0 ? 0 : w >= 2 ** (n - 1) ? w : w - 2 ** n + 1; }
export function assign(table: HuffmanTable) {
  const encode = new Map<number, Code>(), decode = new Map<string, number>(); let code = 0, index = 0;
  for (let length = 1; length <= 16; length++) { for (let j = 0; j < table.counts[length - 1]; j++) { const symbol = table.values[index++]; encode.set(symbol, { length, value: code }); decode.set(`${length}:${code}`, symbol); code++; } code *= 2; }
  return { encode, decode };
}
export function optimized(frequencies: number[], tableClass: number, id: number): HuffmanTable {
  const freq = [...frequencies, 1], codesize = Array<number>(257).fill(0), others = Array<number>(257).fill(-1);
  while (true) {
    let c1 = -1, c2 = -1;
    for (let i = 0; i <= 256; i++) if (freq[i] > 0 && (c1 < 0 || freq[i] <= freq[c1])) c1 = i;
    for (let i = 0; i <= 256; i++) if (i !== c1 && freq[i] > 0 && (c2 < 0 || freq[i] <= freq[c2])) c2 = i;
    if (c2 < 0) break;
    freq[c1] += freq[c2]; freq[c2] = 0;
    codesize[c1]++; while (others[c1] !== -1) { c1 = others[c1]; codesize[c1]++; } others[c1] = c2;
    codesize[c2]++; while (others[c2] !== -1) { c2 = others[c2]; codesize[c2]++; }
  }
  const count = Array<number>(258).fill(0); for (const length of codesize) if (length > 0) count[length]++;
  for (let length = count.length - 1; length >= 17; length--) while (count[length] > 0) { let j = length - 2; while (count[j] === 0) j--; count[length] -= 2; count[length - 1]++; count[j + 1] += 2; count[j]--; }
  let last = 16; while (count[last] === 0) last--; count[last]--;
  const values = frequencies.map((_, i) => i).filter(i => codesize[i] > 0).sort((a, b) => codesize[a] - codesize[b] || a - b);
  return { class: tableClass, id, counts: count.slice(1, 17), values };
}
