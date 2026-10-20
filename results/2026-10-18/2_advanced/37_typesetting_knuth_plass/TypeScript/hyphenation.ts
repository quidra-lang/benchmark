export interface SplitPoint { position: number; hyphen: boolean }
export class Dictionary {
  readonly words = new Map<string, number[]>();
  constructor(lines: string[], additions: string[]) {
    for (const line of [...lines, ...additions]) {
      let word = '';
      const points: number[] = [];
      for (const character of line) {
        if (character === '-') points.push(word.length);
        else word += character;
      }
      this.words.set(word, points);
    }
  }
  splitPoints(word: string, leftMinimum: number, rightMinimum: number): SplitPoint[] {
    const points: SplitPoint[] = [];
    let first = 0, last = word.length;
    while (first < last && !/[A-Za-z]/.test(word[first])) first++;
    while (last > first && !/[A-Za-z]/.test(word[last - 1])) last--;
    const core = word.slice(first, last);
    if (/^[A-Za-z]+$/.test(core)) for (const position of this.words.get(core.toLowerCase()) ?? []) {
      if (position >= leftMinimum && core.length - position >= rightMinimum) points.push({ position: first + position, hyphen: true });
    }
    for (let i = 1; i + 1 < word.length; i++) {
      if (word[i] === '-' && /[A-Za-z]/.test(word[i - 1]) && /[A-Za-z]/.test(word[i + 1])) points.push({ position: i + 1, hyphen: false });
    }
    return points.sort((a, b) => a.position - b.position);
  }
}
