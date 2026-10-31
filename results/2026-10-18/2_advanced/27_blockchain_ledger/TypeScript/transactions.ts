import { hash } from './hashing.ts';
import { sign } from './wallets.ts';
import type { Wallet } from './wallets.ts';

export interface OutputReference {
  txid: string;
  index: number;
}
export interface Input extends OutputReference {
  key: string;
}
export interface Output {
  address: string;
  amount: number;
}
export interface Coin extends Output, OutputReference {
  height: number;
  coinbase: boolean;
}
export type Utxo = Map<string, Coin>;
export type TransactionReason =
  'bad-output' | 'double-spend' | 'missing-input' | 'immature' | 'bad-sig' | 'overspend';
export type CheckResult = { ok: false; reason: TransactionReason } | { ok: true; fee: number };

export class Transaction {
  readonly txid: string;
  readonly size: number;
  readonly coinbase: boolean;
  readonly outputs: Output[];
  readonly inputs: Input[];
  readonly signatures: string[];
  readonly body: string;
  readonly height: number;

  constructor(readonly text: string) {
    this.txid = hash(text);
    this.size = text.length;
    const fields = text.split(';');
    this.coinbase = text.startsWith('cb=');
    this.outputs = fields[1]
      .slice(4)
      .split(',')
      .map((output) => {
        const [address, amount] = output.split(':');
        return { address, amount: Number(amount) };
      });
    this.inputs = this.coinbase
      ? []
      : fields[0]
          .slice(3)
          .split(',')
          .map((key) => {
            const [txid, index] = key.split(':');
            return { txid, index: Number(index), key };
          });
    this.signatures = this.coinbase ? [] : fields[2].slice(4).split(',');
    this.body = this.coinbase ? '' : text.slice(0, text.indexOf(';sig='));
    this.height = this.coinbase ? Number(fields[0].slice(3)) : -1;
  }
}

const outputText = (outputs: Output[]) => outputs.map((o) => `${o.address}:${o.amount}`).join(',');

export function payment(inputs: OutputReference[], outputs: Output[], secret: string): Transaction {
  const body =
    'in=' + inputs.map((i) => `${i.txid}:${i.index}`).join(',') + ';out=' + outputText(outputs);
  return new Transaction(body + ';sig=' + inputs.map((_, i) => sign(secret, i, body)).join(','));
}
export const coinbase = (height: number, outputs: Output[]): Transaction =>
  new Transaction(`cb=${height};out=${outputText(outputs)}`);
export const mature = (coin: Coin, height: number, maturity: number): boolean =>
  !coin.coinbase || coin.height === 0 || height >= coin.height + maturity;

export function outputTotal(transaction: Transaction): number {
  let total = 0;
  for (const output of transaction.outputs) total += output.amount;
  return total;
}

export function check(
  transaction: Transaction,
  utxo: Utxo,
  spent: Set<string>,
  height: number,
  maturity: number,
  owners: Map<string, Wallet>,
): CheckResult {
  if (transaction.outputs.some((o) => !owners.has(o.address) || o.amount === 0)) {
    return { ok: false, reason: 'bad-output' };
  }
  const seen = new Set<string>();
  let inputTotal = 0;
  for (let i = 0; i < transaction.inputs.length; i++) {
    const input = transaction.inputs[i];
    if (spent.has(input.key) || seen.has(input.key)) return { ok: false, reason: 'double-spend' };
    seen.add(input.key);
    const coin = utxo.get(input.key);
    if (!coin) return { ok: false, reason: 'missing-input' };
    if (!mature(coin, height, maturity)) return { ok: false, reason: 'immature' };
    if (transaction.signatures[i] !== sign(owners.get(coin.address)!.secret, i, transaction.body)) {
      return { ok: false, reason: 'bad-sig' };
    }
    inputTotal += coin.amount;
  }
  const outputs = outputTotal(transaction);
  return inputTotal < outputs
    ? { ok: false, reason: 'overspend' }
    : { ok: true, fee: inputTotal - outputs };
}

export function apply(transaction: Transaction, utxo: Utxo, height: number): void {
  for (const input of transaction.inputs) utxo.delete(input.key);
  transaction.outputs.forEach((output, index) =>
    utxo.set(`${transaction.txid}:${index}`, {
      ...output,
      txid: transaction.txid,
      index,
      height,
      coinbase: transaction.coinbase,
    }),
  );
}
