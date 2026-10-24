export const SYMBOLS = '$#ACGT';
export interface SuffixArray { sa: number[]; rounds: number[] }

export function countingSort(positions: number[], key: (position: number) => number, classes: number): number[] {
  const counts: number[] = Array(classes).fill(0);
  const offsets: number[] = Array(classes).fill(0);
  const result: number[] = Array(positions.length);
  for (const position of positions) counts[key(position)]++;
  for (let i = 1; i < classes; i++) offsets[i] = offsets[i - 1] + counts[i - 1];
  for (const position of positions) result[offsets[key(position)]++] = position;
  return result;
}

export function build(text: string): SuffixArray {
  const positions = Array.from({ length: text.length }, (_, i) => i);
  let order = countingSort(positions, i => SYMBOLS.indexOf(text[i]), 6);
  let rank: number[] = Array(text.length);
  let classes = 0;
  for (let i = 0; i < order.length; i++) {
    if (i === 0 || text[order[i]] !== text[order[i - 1]]) classes++;
    rank[order[i]] = classes - 1;
  }
  const rounds = [classes];
  for (let prefix = 1; classes < text.length; prefix *= 2) {
    const second = (i: number): number => i + prefix < text.length ? rank[i + prefix] + 1 : 0;
    order = countingSort(countingSort(positions, second, classes + 1), i => rank[i], classes);
    const next: number[] = Array(text.length);
    let count = 0;
    for (let i = 0; i < order.length; i++) {
      if (i === 0 || rank[order[i]] !== rank[order[i - 1]] || second(order[i]) !== second(order[i - 1])) count++;
      next[order[i]] = count - 1;
    }
    rank = next;
    classes = count;
    rounds.push(classes);
  }
  return { sa: order, rounds };
}

export function check(text: string, sa: number[]) {
  let ordered = 0, lcpSum = 0, maximum = -1, row = 1;
  const lcp = [0];
  for (let i = 1; i < sa.length; i++) {
    let length = 0;
    while (text[sa[i - 1] + length] === text[sa[i] + length]) length++;
    if (SYMBOLS.indexOf(text[sa[i - 1] + length]) < SYMBOLS.indexOf(text[sa[i] + length])) ordered++;
    lcp.push(length);
    lcpSum += length;
    if (length > maximum) { maximum = length; row = i; }
  }
  return { ordered, lcp, lcpSum, maximum, row };
}

export function direct(text: string): number[] {
  return Array.from({ length: text.length }, (_, i) => i).sort((a, b) => {
    const first = text.slice(a), second = text.slice(b);
    return first < second ? -1 : first > second ? 1 : 0;
  });
}
