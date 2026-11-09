export function rail(position: number, rails: number): number {
  const cycle = 2 * rails - 2;
  const u = position % cycle;
  return Math.min(u, cycle - u);
}

export function railfence(text: string, rails: number, decrypt: boolean): string {
  const positions: number[] = [];
  for (let r = 0; r < rails; r++) {
    for (let p = 0; p < text.length; p++) if (rail(p, rails) === r) positions.push(p);
  }
  if (!decrypt) return positions.map((p) => text[p]).join('');
  const result = Array<string>(text.length);
  positions.forEach((p, i) => {
    result[p] = text[i];
  });
  return result.join('');
}

export function columnOrder(key: string): number[] {
  return [...key].map((_, i) => i).sort((a, b) => key.charCodeAt(a) - key.charCodeAt(b) || a - b);
}
export function rankString(key: string): string {
  const ranks = Array<number>(key.length);
  columnOrder(key).forEach((column, i) => {
    ranks[column] = i + 1;
  });
  return ranks.join('');
}
export function columnar(text: string, key: string, decrypt: boolean): string {
  const order = columnOrder(key);
  if (!decrypt) {
    return order
      .map((column) => {
        let value = '';
        for (let p = column; p < text.length; p += key.length) value += text[p];
        return value;
      })
      .join('');
  }
  const columns = Array<string>(key.length);
  let start = 0;
  for (const column of order) {
    const length =
      Math.floor(text.length / key.length) + (column < text.length % key.length ? 1 : 0);
    columns[column] = text.slice(start, start + length);
    start += length;
  }
  return [...text].map((_, p) => columns[p % key.length][Math.floor(p / key.length)]).join('');
}
