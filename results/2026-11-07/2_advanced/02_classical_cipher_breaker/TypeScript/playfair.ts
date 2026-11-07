import { mod } from './substitution.ts';

export function square(key: string): string {
  return [...new Set(key + 'ABCDEFGHIKLMNOPQRSTUVWXYZ')].join('');
}
export function validPlayfair(text: string): boolean {
  text = text.replaceAll('J', 'I');
  if (text.length % 2) return false;
  for (let i = 0; i < text.length; i += 2) if (text[i] === text[i + 1]) return false;
  return true;
}
export function prepare(text: string): string {
  text = text.replaceAll('J', 'I');
  let result = '';
  for (let i = 0; i < text.length;) {
    const a = text[i++];
    const b = i < text.length && text[i] !== a ? text[i++] : a === 'X' ? 'Q' : 'X';
    result += a + b;
  }
  return result;
}
export function playfair(text: string, key: string, decrypt: boolean): string {
  const grid = square(key);
  text = decrypt ? text.replaceAll('J', 'I') : prepare(text);
  let result = '';
  const shift = decrypt ? 4 : 1;
  for (let i = 0; i < text.length; i += 2) {
    const a = grid.indexOf(text[i]);
    const b = grid.indexOf(text[i + 1]);
    const ra = Math.floor(a / 5);
    const ca = a % 5;
    const rb = Math.floor(b / 5);
    const cb = b % 5;
    if (ra === rb) result += grid[ra * 5 + mod(ca + shift, 5)] + grid[rb * 5 + mod(cb + shift, 5)];
    else if (ca === cb) {
      result += grid[mod(ra + shift, 5) * 5 + ca] + grid[mod(rb + shift, 5) * 5 + cb];
    } else result += grid[ra * 5 + cb] + grid[rb * 5 + ca];
  }
  return result;
}
