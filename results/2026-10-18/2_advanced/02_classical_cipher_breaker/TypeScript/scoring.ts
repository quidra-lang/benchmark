export interface Weights { mono: number[]; bigram: number[][] }

export function parseWeights(text: string): Weights {
  const lines = text.trimEnd().split('\n');
  return { mono: lines[1].split(' ').map(Number), bigram: lines.slice(3).map(line => line.split(' ').map(Number)) };
}

export function isLetter(char: string): boolean { return /^[A-Za-z]$/.test(char); }
export function letters(text: string): string { return (text.match(/[A-Za-z]/g) ?? []).join('').toUpperCase(); }
export function mono(text: string, weights: Weights): number {
  let score = 0;
  for (const c of text) score += weights.mono[c.charCodeAt(0) - 65];
  return score;
}
export function bigram(text: string, weights: Weights): number {
  let score = 0;
  for (let i = 1; i < text.length; i++) score += weights.bigram[text.charCodeAt(i - 1) - 65][text.charCodeAt(i) - 65];
  return score;
}
