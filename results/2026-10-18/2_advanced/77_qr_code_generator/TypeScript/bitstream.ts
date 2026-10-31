export const ALPHANUMERIC = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

export function append(bits: number[], value: number, width: number): void {
  for (let bit = width - 1; bit >= 0; bit--) bits.push(Math.floor(value / 2 ** bit) % 2);
}

export function fromCodewords(codewords: number[]): number[] {
  const bits = [];
  for (const value of codewords) append(bits, value, 8);
  return bits;
}

export function toCodewords(bits: number[]): number[] {
  const codewords = [];
  for (let i = 0; i < bits.length; i += 8) {
    let value = 0;
    for (let j = 0; j < 8; j++) value = 2 * value + bits[i + j];
    codewords.push(value);
  }
  return codewords;
}

export class BitReader {
  bits: number[];
  position: number;
  constructor(bits: number[]) { this.bits = bits; this.position = 0; }
  get remaining(): number { return this.bits.length - this.position; }
  read(width: number): number {
    let value = 0;
    for (let i = 0; i < width; i++) value = 2 * value + this.bits[this.position++];
    return value;
  }
}

export const binary = (value: number, width: number): string => value.toString(2).padStart(width, '0');

