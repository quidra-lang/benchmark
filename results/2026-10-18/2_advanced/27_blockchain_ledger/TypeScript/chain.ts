import { Block } from './blocks.ts';
import type { Utxo } from './transactions.ts';

export interface ChainRules {
  difficulty: number; retarget: number; targetTime: number; reward: number; halving: number;
}

export class StoredBlock extends Block {
  readonly work: number;
  constructor(block: Block, readonly parent: StoredBlock | null, readonly utxo: Utxo,
    readonly fees: number, readonly transactionFees: number[], readonly source: string) {
    super(block.height, block.previous, block.root, block.timestamp, block.difficulty, block.nonce, block.transactions);
    this.work = parent === null ? 1 : parent.work + 16 ** block.difficulty;
  }
}

export function reward(height: number, settings: ChainRules): number {
  let value = settings.reward;
  for (let i = 0; i < Math.floor(height / settings.halving); i++) value = Math.floor(value / 2);
  return value;
}
export function ancestor(block: StoredBlock, height: number): StoredBlock {
  while (block.height > height) block = block.parent!;
  return block;
}
export function sequence(tip: StoredBlock): StoredBlock[] {
  const blocks: StoredBlock[] = [];
  for (let current: StoredBlock | null = tip; current !== null; current = current.parent) blocks.push(current);
  return blocks.reverse();
}
export function forkPoint(first: StoredBlock, second: StoredBlock): StoredBlock {
  first = ancestor(first, Math.min(first.height, second.height));
  second = ancestor(second, first.height);
  while (first.hash !== second.hash) { first = first.parent!; second = second.parent!; }
  return first;
}
export function medianTime(block: StoredBlock): number {
  const times: number[] = [];
  let current: StoredBlock | null = block;
  for (let i = 0; i < 3 && current !== null; i++, current = current.parent) times.push(current.timestamp);
  times.sort((a, b) => a - b);
  return times[Math.floor((times.length - 1) / 2)];
}
export function requiredDifficulty(parent: StoredBlock, settings: ChainRules): number {
  const height = parent.height + 1;
  if (height === 1) return settings.difficulty;
  if (height % settings.retarget !== 0) return parent.difficulty;
  const span = parent.timestamp - ancestor(parent, height - settings.retarget).timestamp;
  const expected = settings.targetTime * (settings.retarget - 1);
  if (2 * span < expected) return Math.min(parent.difficulty + 1, 2);
  if (span > 2 * expected) return Math.max(parent.difficulty - 1, 0);
  return parent.difficulty;
}
