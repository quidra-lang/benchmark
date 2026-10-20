import { isLetter } from './scoring.ts';

export type SubstitutionCipher = 'caesar' | 'affine' | 'vigenere' | 'autokey';
export const affineMultipliers = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25];
export function mod(value: number, modulus = 26): number { return (value % modulus + modulus) % modulus; }

export function substitute(text: string, cipher: SubstitutionCipher, key: string, decrypt: boolean): string {
  const plain: number[] = [];
  const values = [...key].map(c => c.charCodeAt(0) - 65);
  const [a, b] = key.split(',').map(Number);
  let inverse = 1;
  if (cipher === 'affine') while ((a * inverse) % 26 !== 1) inverse++;
  let index = 0;
  let result = '';
  for (const c of text) {
    if (!isLetter(c)) { result += c; continue; }
    const upper = c >= 'A' && c <= 'Z';
    const x = c.toUpperCase().charCodeAt(0) - 65;
    let y: number;
    if (cipher === 'caesar') y = mod(x + (decrypt ? -Number(key) : Number(key)));
    else if (cipher === 'affine') y = decrypt ? mod(inverse * (x - b)) : mod(a * x + b);
    else {
      const shift = cipher === 'vigenere' ? values[index % values.length]
        : index < values.length ? values[index] : plain[index - values.length];
      y = mod(x + (decrypt ? -shift : shift));
    }
    plain.push(decrypt ? y : x);
    result += String.fromCharCode((upper ? 65 : 97) + y);
    index++;
  }
  return result;
}
