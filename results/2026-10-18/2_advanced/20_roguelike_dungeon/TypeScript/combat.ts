import type { Minstd } from './minstd.ts';

export interface Dice {
  count: number;
  sides: number;
}
export function parseDice(text: string): Dice {
  const [count, sides] = text.split('d').map(Number);
  return { count, sides };
}
export interface Attack {
  hit: boolean;
  critical: boolean;
  damage: number;
}
export function attack(
  rng: Minstd,
  modifier: number,
  defense: number,
  dice: Dice,
  bonus: number,
): Attack {
  const roll = 1 + rng.rnd(20);
  if (roll === 1 || (roll !== 20 && roll + modifier < defense)) {
    return { hit: false, critical: false, damage: 0 };
  }
  const critical = roll === 20;
  let damage = rng.roll(dice);
  if (critical) damage += rng.roll(dice);
  return { hit: true, critical, damage: Math.max(1, damage + bonus) };
}
