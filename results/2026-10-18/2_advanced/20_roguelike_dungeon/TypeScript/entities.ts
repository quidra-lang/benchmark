import { parseDice, type Dice } from './combat.ts';

interface TypeBase {
  name: string;
  minDepth: number;
  maxDepth: number;
  weight: number;
}
export interface MonsterType extends TypeBase {
  symbol: string;
  hp: Dice;
  toHit: number;
  defense: number;
  damage: Dice;
  speed: number;
  xp: number;
  traits: string;
}
export interface Position {
  x: number;
  y: number;
}
export interface Monster extends Position {
  id: number;
  type: MonsterType;
  hp: number;
  maxHp: number;
  asleep: boolean;
  energy: number;
  wasVisible: boolean;
}
type PotionEffect =
  { effect: 'heal'; dice: Dice } | { effect: 'poison'; turns: number } | { effect: 'level' };
export type ItemType = TypeBase &
  (
    | { kind: 'weapon'; damage: Dice; toHit: number }
    | { kind: 'armor'; armor: number }
    | ({ kind: 'potion' } & PotionEffect)
    | { kind: 'scroll'; effect: 'mapping' | 'teleport' | 'enchant_weapon' | 'enchant_armor' }
    | { kind: 'food'; satiation: number }
    | { kind: 'gold'; dice: Dice }
    | { kind: 'amulet' }
  );
export interface Item extends Position {
  type: ItemType;
  bonus: number;
  amount: number;
}
export function monsterType(line: string): MonsterType {
  const t = line.split(' ');
  return {
    name: t[0],
    symbol: t[1],
    minDepth: +t[2],
    maxDepth: +t[3],
    weight: +t[4],
    hp: parseDice(t[5]),
    toHit: +t[6],
    defense: +t[7],
    damage: parseDice(t[8]),
    speed: +t[9],
    xp: +t[10],
    traits: t[11],
  };
}
export function itemType(line: string): ItemType {
  const t = line.split(' ');
  const base = { name: t[1], minDepth: +t[2], maxDepth: +t[3], weight: +t[4] };
  switch (t[0]) {
    case 'weapon':
      return { ...base, kind: 'weapon', damage: parseDice(t[5]), toHit: +t[6] };
    case 'armor':
      return { ...base, kind: 'armor', armor: +t[5] };
    case 'food':
      return { ...base, kind: 'food', satiation: +t[5] };
    case 'gold':
      return { ...base, kind: 'gold', dice: parseDice(t[5]) };
    case 'potion':
      if (t[5] === 'heal') {
        return { ...base, kind: 'potion', effect: 'heal', dice: parseDice(t[6]) };
      }
      if (t[5] === 'poison') return { ...base, kind: 'potion', effect: 'poison', turns: +t[6] };
      return { ...base, kind: 'potion', effect: 'level' };
    case 'scroll': {
      const effect = t[5];
      if (
        effect === 'mapping' ||
        effect === 'teleport' ||
        effect === 'enchant_weapon' ||
        effect === 'enchant_armor'
      ) {
        return { ...base, kind: 'scroll', effect };
      }
    }
  }
  throw new Error('Unknown item type');
}
export function makeItem(type: ItemType, x = -1, y = -1): Item {
  return { type, x, y, bonus: 0, amount: 0 };
}
export function symbol(item: Item): string {
  return { weapon: ')', armor: '[', potion: '!', scroll: '?', food: '%', gold: '$', amulet: '"' }[
    item.type.kind
  ];
}
export function displayName(item: Item): string {
  const name = item.type.name.replaceAll('_', ' ');
  if (item.type.kind === 'weapon' || item.type.kind === 'armor') return `+${item.bonus} ${name}`;
  return item.type.kind === 'gold' ? `${item.amount} gold` : name;
}
export function referenceName(item: Item): string {
  return (item.type.kind === 'gold' ? '' : 'the ') + displayName(item);
}
