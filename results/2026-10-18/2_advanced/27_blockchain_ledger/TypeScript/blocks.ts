import { hash, merkle } from './hashing.ts';
import { Transaction } from './transactions.ts';

export class Block {
  hash: string;
  readonly size: number;
  constructor(readonly height: number, readonly previous: string, readonly root: string,
    readonly timestamp: number, readonly difficulty: number, public nonce: number,
    readonly transactions: Transaction[]) {
    this.hash = hash(header(this));
    this.size = 0;
    for (const transaction of transactions.slice(1)) this.size += transaction.size;
  }
}

export const header = (block: Block): string =>
  [block.height, block.previous, block.root, block.timestamp, block.difficulty, block.nonce].join('|');
export const proofOfWork = (block: Block): boolean => block.hash.startsWith('0'.repeat(block.difficulty));

export function parseBlock(fields: string[], transactionLines: string[]): Block {
  return new Block(Number(fields[3]), fields[4], fields[5], Number(fields[6]), Number(fields[7]), Number(fields[8]),
    transactionLines.map(text => new Transaction(text)));
}

export function mine(height: number, previous: string, timestamp: number, difficulty: number,
  transactions: Transaction[]): Block {
  const block = new Block(height, previous, merkle(transactions.map(t => t.txid)), timestamp, difficulty, 0, transactions);
  while (!proofOfWork(block)) {
    block.nonce++;
    block.hash = hash(header(block));
  }
  return block;
}

export type ContextReason = 'bad-pow' | 'bad-merkle' | 'bad-structure' | 'too-large';
export function contextFreeCheck(block: Block, maximumSize: number): ContextReason | null {
  if (!proofOfWork(block)) return 'bad-pow';
  if (merkle(block.transactions.map(t => t.txid)) !== block.root) return 'bad-merkle';
  if (!block.transactions[0].coinbase || block.transactions[0].height !== block.height
    || block.transactions.slice(1).some(t => t.coinbase)) return 'bad-structure';
  if (block.size > maximumSize) return 'too-large';
  return null;
}
