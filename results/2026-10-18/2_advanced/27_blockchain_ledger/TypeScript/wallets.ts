import { readFileSync } from 'node:fs';
import { hash } from './hashing.ts';

export interface Wallet {
  name: string;
  secret: string;
  address: string;
}

export function readWallets(): Wallet[] {
  return readFileSync('input/wallets.txt', 'ascii')
    .trimEnd()
    .split('\n')
    .map((line) => {
      const [name, secret] = line.split(' ');
      return { name, secret, address: hash('addr:' + secret).slice(0, 16) };
    });
}

export const sign = (secret: string, input: number, body: string): string =>
  hash(`${secret}:${input}:${body}`).slice(0, 16);
