import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { attack, parseDice, type Attack } from './combat.ts';
import { Level, type RoomCell } from './dungeon_gen.ts';
import {
  displayName,
  itemType,
  makeItem,
  monsterType,
  referenceName,
  symbol,
  type Monster,
} from './entities.ts';
import { canMove, directions, distances, fieldOfView, passable } from './fov.ts';
import { Minstd } from './minstd.ts';

function lines(path: string): string[] {
  return readFileSync(path, 'ascii').trimEnd().split('\n');
}
const config = lines('input/config.txt').map((line) => line.split(' ').slice(1));
const numbers = (i: number) => config[i].map(Number);
const [generationSeed, gameSeed] = numbers(0);
const [width, height] = numbers(1);
const [minimum, splits] = numbers(2);
const [roomMin, roomMax] = numbers(3);
const [levelCount] = numbers(4);
const [monsterBase, monsterStep] = numbers(5);
const [itemBase, itemStep] = numbers(6);
const [sleepChance, wakeChance] = numbers(7);
const [radius] = numbers(8);
const [initialHp, regenInterval] = numbers(9);
const hitdie = parseDice(config[10][0]);
const [initialFood, maximumFood, hungryAt, weakAt] = numbers(11);
const [packLimit] = numbers(12);
const thresholds = numbers(14);
const checkpoints = new Set(numbers(15));
const generation = new Minstd(generationSeed);
const game = new Minstd(gameSeed);
const monsterTypes = lines('input/monsters.txt').map(monsterType);
const itemTypes = lines('input/items.txt').map(itemType);
const commands: string[][] = [];
for (const line of lines('input/commands.txt')) {
  const parts = line.split(' ');
  const repetitions =
    parts[0] === 'move' ? +(parts[2] ?? 1) : parts[0] === 'wait' ? +(parts[1] ?? 1) : 1;
  for (let i = 0; i < repetitions; i++) commands.push(parts);
}
const levels: Level[] = [];
for (let d = 1; d <= levelCount; d++) {
  const level = new Level(
    width,
    height,
    { width, height, minimum, splits, roomMin, roomMax },
    generation,
  );
  const target = level.target;
  if (d < levelCount) level.terrain[level.index(target.x, target.y)] = '>';
  else {
    level.items.push(
      makeItem(
        { kind: 'amulet', name: 'amulet', minDepth: d, maxDepth: d, weight: 1 },
        target.x,
        target.y,
      ),
    );
  }
  const candidates = monsterTypes.filter((type) => type.minDepth <= d && d <= type.maxDepth);
  level.created = monsterBase + monsterStep * (d - 1);
  for (let id = 1; id <= level.created; id++) {
    const type = generation.select(candidates);
    let cell: RoomCell;
    do {
      cell = level.drawCell(generation);
    } while (
      cell.room === level.arrival.room ||
      level.at(cell.x, cell.y) !== '.' ||
      level.monsterAt(cell.x, cell.y)
    );
    const hp = generation.roll(type.hp);
    const asleep = generation.rnd(100) < sleepChance;
    level.monsters.push({ ...cell, id, type, hp, maxHp: hp, asleep, energy: 0, wasVisible: false });
  }
  const itemCandidates = itemTypes.filter((type) => type.minDepth <= d && d <= type.maxDepth);
  const count = itemBase + itemStep * (d - 1);
  for (let i = 0; i < count; i++) {
    const type = generation.select(itemCandidates);
    let cell: RoomCell;
    do {
      cell = level.drawCell(generation);
    } while (level.at(cell.x, cell.y) !== '.' || level.itemAt(cell.x, cell.y));
    const item = makeItem(type, cell.x, cell.y);
    if (type.kind === 'gold') item.amount = generation.roll(type.dice);
    level.items.push(item);
  }
  level.placed = level.items.length;
  levels.push(level);
}
const pack = config[13].map((name) => {
  const type = itemTypes.find((type) => type.name === name);
  if (!type) throw new Error('Unknown starting item');
  return makeItem(type);
});
let weapon = pack.find((item) => item.type.kind === 'weapon');
let armor = pack.find((item) => item.type.kind === 'armor');
let depth = 1;
let px = levels[0].arrival.x;
let py = levels[0].arrival.y;
let hp = initialHp;
let maxHp = initialHp;
let playerLevel = 1;
let xp = 0;
let gold = 0;
let food = initialFood;
let poison = 0;
let turn = 1;
let succeeded = 0;
let failed = 0;
let unused = 0;
let moves = 0;
let picked = 0;
let quaffed = 0;
let read = 0;
let eaten = 0;
let wielded = 0;
let worn = 0;
let poisonDamage = 0;
let starvationDamage = 0;
let result: 'alive' | 'won' | 'died' = 'alive';
let cause = 'commands_exhausted';
let visible = new Set<number>();
const messages: string[] = [];
const maps: string[] = [];
const kills = new Map<string, number>();
interface AttackStats {
  count: number;
  hits: number;
  criticals: number;
  damage: number;
}
const playerAttacks: AttackStats = { count: 0, hits: 0, criticals: 0, damage: 0 };
const monsterAttacks: AttackStats = { count: 0, hits: 0, criticals: 0, damage: 0 };
const current = () => levels[depth - 1];
const log = (message: string) => {
  messages.push(`${String(turn).padStart(4, '0')} ${message}`);
};
const defense = () => 10 + (armor?.type.kind === 'armor' ? armor.type.armor + armor.bonus : 0);
const hunger = () =>
  food === 0 ? 'starving' : food <= weakAt ? 'weak' : food <= hungryAt ? 'hungry' : 'normal';
function die(reason: string): void {
  cause = reason;
  result = 'died';
  log('You die.');
}
function experience(amount: number): void {
  xp += amount;
  while (playerLevel <= thresholds.length && xp >= thresholds[playerLevel - 1]) {
    playerLevel++;
    const gain = game.roll(hitdie);
    maxHp += gain;
    hp += gain;
    log(`Welcome to level ${playerLevel}.`);
  }
}
function updateView(): void {
  const level = current();
  visible = fieldOfView(level, px, py, radius);
  for (const i of visible) {
    const item = level.itemAt(i % width, Math.floor(i / width));
    level.memory[i] = item ? symbol(item) : level.terrain[i];
  }
  for (const monster of level.monsters) {
    const seen = visible.has(level.index(monster.x, monster.y));
    if (seen && !monster.wasVisible) log(`You see the ${monster.type.name}.`);
    monster.wasVisible = seen;
  }
}
function countAttack(stats: AttackStats, outcome: Attack): void {
  stats.count++;
  if (outcome.hit) stats.hits++;
  if (outcome.critical) stats.criticals++;
  stats.damage += outcome.damage;
}
function playerAttack(monster: Monster): void {
  monster.asleep = false;
  let modifier = playerLevel;
  let bonus = 0;
  let dice = parseDice('1d2');
  if (weapon?.type.kind === 'weapon') {
    modifier += weapon.type.toHit + weapon.bonus;
    bonus = weapon.bonus;
    dice = weapon.type.damage;
  }
  if (hunger() === 'weak' || hunger() === 'starving') modifier -= 2;
  const outcome = attack(game, modifier, monster.type.defense, dice, bonus);
  countAttack(playerAttacks, outcome);
  if (!outcome.hit) {
    log(`You miss the ${monster.type.name}.`);
    return;
  }
  log(`You hit the ${monster.type.name}${outcome.critical ? ' hard' : ''} for ${outcome.damage}.`);
  monster.hp -= outcome.damage;
  if (monster.hp <= 0) {
    log(`You kill the ${monster.type.name}.`);
    const level = current();
    level.monsters.splice(level.monsters.indexOf(monster), 1);
    level.killed++;
    kills.set(monster.type.name, (kills.get(monster.type.name) ?? 0) + 1);
    experience(monster.type.xp);
  }
}
function monsterAttack(monster: Monster): void {
  const outcome = attack(game, monster.type.toHit, defense(), monster.type.damage, 0);
  countAttack(monsterAttacks, outcome);
  if (!outcome.hit) {
    log(`The ${monster.type.name} misses you.`);
    return;
  }
  log(`The ${monster.type.name} hits you${outcome.critical ? ' hard' : ''} for ${outcome.damage}.`);
  hp -= outcome.damage;
  if (hp <= 0) die(`killed_by ${monster.type.name}`);
  else if (monster.type.traits.includes('P')) {
    poison += 5;
    log('You are poisoned.');
  }
}
function execute(command: string[]): boolean {
  const [verb, argument] = command;
  const level = current();
  if (verb === 'wait') return true;
  if (verb === 'move') {
    const direction = directions.find((d) => d.name === argument);
    if (!direction) throw new Error('Unknown direction');
    const x = px + direction.x;
    const y = py + direction.y;
    if (!passable(level, x, y)) {
      log('You bump into a wall.');
      return false;
    }
    if (!canMove(level, px, py, direction.x, direction.y)) {
      log('You cannot move diagonally through a door.');
      return false;
    }
    const monster = level.monsterAt(x, y);
    if (monster) playerAttack(monster);
    else {
      px = x;
      py = y;
      moves++;
      const item = level.itemAt(x, y);
      if (item) log(`You see ${referenceName(item)} here.`);
      else if (level.at(x, y) === '>') log('There is a staircase down here.');
    }
    return true;
  }
  if (verb === 'descend') {
    if (level.at(px, py) !== '>') {
      log('There are no stairs here.');
      return false;
    }
    depth++;
    px = current().arrival.x;
    py = current().arrival.y;
    log(`You descend to depth ${depth}.`);
    return true;
  }
  if (verb === 'pickup') {
    const item = level.itemAt(px, py);
    if (!item) {
      log('There is nothing here.');
      return false;
    }
    if (item.type.kind === 'gold') {
      gold += item.amount;
      log(`You pick up ${displayName(item)}.`);
    } else if (item.type.kind === 'amulet') {
      log('You pick up the amulet.');
      log('You win!');
      result = 'won';
      cause = 'amulet';
    } else {
      if (pack.length === packLimit) {
        log('Your pack is full.');
        return false;
      }
      pack.push(item);
      log(`You pick up the ${displayName(item)} (${pack.length}).`);
    }
    level.items.splice(level.items.indexOf(item), 1);
    level.picked++;
    picked++;
    return true;
  }
  const index = +argument - 1;
  const item = pack[index];
  if (!item) {
    log('You do not have that item.');
    return false;
  }
  const required: Record<string, string> = {
    quaff: 'potion',
    read: 'scroll',
    wield: 'weapon',
    wear: 'armor',
    eat: 'food',
  };
  if (item.type.kind !== required[verb]) {
    log(`You cannot ${verb} that.`);
    return false;
  }
  const type = item.type;
  if (verb === 'quaff' && type.kind === 'potion') {
    pack.splice(index, 1);
    quaffed++;
    log(`You quaff the ${displayName(item)}.`);
    if (type.effect === 'heal') {
      hp += game.roll(type.dice);
      if (hp > maxHp) {
        maxHp++;
        hp = maxHp;
      }
      poison = 0;
      log('You feel better.');
    } else if (type.effect === 'poison') {
      poison += type.turns;
      log('You feel very sick.');
    } else {
      log('You feel more experienced.');
      if (playerLevel <= thresholds.length) experience(thresholds[playerLevel - 1] - xp);
    }
  } else if (verb === 'read' && type.kind === 'scroll') {
    pack.splice(index, 1);
    read++;
    log(`You read the ${displayName(item)}.`);
    if (type.effect === 'mapping') {
      for (let i = 0; i < level.terrain.length; i++) {
        if (level.terrain[i] !== ' ' && level.memory[i] === ' ') level.memory[i] = level.terrain[i];
      }
      log('A map forms in your mind.');
    } else if (type.effect === 'teleport') {
      let cell: RoomCell;
      do {
        cell = level.drawCell(game);
      } while ((cell.x === px && cell.y === py) || level.monsterAt(cell.x, cell.y));
      px = cell.x;
      py = cell.y;
      log('You are teleported.');
    } else if (type.effect === 'enchant_weapon') {
      if (weapon) {
        log(`Your ${displayName(weapon)} glows blue.`);
        weapon.bonus++;
      } else log('Your hands twitch.');
    } else {
      if (armor) {
        log(`Your ${displayName(armor)} glows silver.`);
        armor.bonus++;
      } else log('Your skin tingles.');
    }
  } else if (verb === 'wield') {
    if (weapon === item) {
      log('You are already wielding that.');
      return false;
    }
    weapon = item;
    wielded++;
    log(`You are now wielding the ${displayName(item)}.`);
  } else if (verb === 'wear') {
    if (armor === item) {
      log('You are already wearing that.');
      return false;
    }
    armor = item;
    worn++;
    log(`You are now wearing the ${displayName(item)}.`);
  } else if (verb === 'eat' && type.kind === 'food') {
    pack.splice(index, 1);
    eaten++;
    food = Math.min(food + type.satiation, maximumFood);
    log(`You eat the ${displayName(item)}.`);
  }
  return true;
}
function monsterAction(monster: Monster, dist: number[]): void {
  const level = current();
  const sees = visible.has(level.index(monster.x, monster.y));
  const canAttack =
    Math.max(Math.abs(px - monster.x), Math.abs(py - monster.y)) === 1 &&
    canMove(level, monster.x, monster.y, px - monster.x, py - monster.y);
  if (monster.asleep) {
    if (sees && game.rnd(100) < wakeChance) {
      monster.asleep = false;
      log(`The ${monster.type.name} wakes up.`);
    }
    return;
  }
  if (monster.type.traits.includes('S')) {
    if (canAttack) monsterAttack(monster);
    return;
  }
  const erratic = monster.type.traits.includes('E') && game.rnd(2) === 0;
  if (erratic || !sees) {
    const d = directions[game.rnd(8)];
    const x = monster.x + d.x;
    const y = monster.y + d.y;
    if (!canMove(level, monster.x, monster.y, d.x, d.y)) return;
    if (x === px && y === py) monsterAttack(monster);
    else if (!level.monsterAt(x, y)) {
      monster.x = x;
      monster.y = y;
    }
    return;
  }
  if (canAttack) {
    monsterAttack(monster);
    return;
  }
  let best: { x: number; y: number } | undefined;
  let bestDistance = width * height;
  const here = dist[level.index(monster.x, monster.y)];
  for (const d of directions) {
    const x = monster.x + d.x;
    const y = monster.y + d.y;
    if (
      !canMove(level, monster.x, monster.y, d.x, d.y) ||
      level.monsterAt(x, y) ||
      (x === px && y === py)
    ) {
      continue;
    }
    const value = dist[level.index(x, y)];
    if (value < 0 || (here >= 0 && value >= here) || value >= bestDistance) continue;
    bestDistance = value;
    best = { x, y };
  }
  if (best) {
    monster.x = best.x;
    monster.y = best.y;
  }
}
function endTurn(): void {
  for (const monster of current().monsters) {
    if (monster.type.traits.includes('R') && monster.hp < monster.maxHp) monster.hp++;
  }
  if (poison > 0) {
    hp--;
    poisonDamage++;
    if (hp <= 0) {
      die('poison');
      return;
    }
    poison--;
    if (poison === 0) log('You feel less sick.');
  }
  if (food === 0) {
    hp--;
    starvationDamage++;
    if (hp <= 0) {
      die('starvation');
      return;
    }
  } else {
    const previous = hunger();
    food--;
    const state = hunger();
    if (state !== previous) {
      log(
        state === 'hungry'
          ? 'You are getting hungry.'
          : state === 'weak'
            ? 'You feel weak from hunger.'
            : 'You are starving.',
      );
    }
  }
  if (turn % regenInterval === 0 && poison === 0 && food > 0 && hp < maxHp) hp++;
}
const status = () =>
  `STATUS hp ${hp}/${maxHp} level ${playerLevel} xp ${xp} defense ${defense()} gold ${gold} food ${food} ${hunger()} poison ${poison}`;
function mapLines(level: Level, live: boolean): string[] {
  const border = '+' + '-'.repeat(width) + '+';
  const output = [border];
  for (let y = 0; y < height; y++) {
    let row = '|';
    for (let x = 0; x < width; x++) {
      const i = level.index(x, y);
      if (!live || !visible.has(i)) row += level.memory[i];
      else if (x === px && y === py) row += '@';
      else {
        const monster = level.monsterAt(x, y);
        const item = level.itemAt(x, y);
        row += monster ? monster.type.symbol : item ? symbol(item) : level.terrain[i];
      }
    }
    output.push(row + '|');
  }
  output.push(border);
  return output;
}
updateView();
for (const command of commands) {
  if (result !== 'alive') {
    unused++;
    continue;
  }
  if (!execute(command)) {
    failed++;
    continue;
  }
  succeeded++;
  if (result !== 'alive') continue;
  updateView();
  const level = current();
  const dist = distances(level, px, py);
  for (const monster of level.monsters) {
    monster.energy += monster.type.speed;
    while (monster.energy >= 2 && result === 'alive') {
      monster.energy -= 2;
      monsterAction(monster, dist);
    }
    if (result !== 'alive') break;
  }
  if (result !== 'alive') continue;
  endTurn();
  if (result !== 'alive') continue;
  if (checkpoints.has(turn)) {
    maps.push(`CHECKPOINT turn ${turn} depth ${depth}`, ...mapLines(current(), true), status());
  }
  turn++;
}
function explored(level: Level): [number, number] {
  let seen = 0;
  let total = 0;
  level.terrain.forEach((cell, i) => {
    if (cell !== ' ') {
      total++;
      if (level.memory[i] !== ' ') seen++;
    }
  });
  return [seen, total];
}
function decimal(a: number, b: number): string {
  if (!b) return '-';
  const z = Math.floor((20 * a + b) / (2 * b));
  return `${Math.floor(z / 10)}.${z % 10}`;
}
maps.push(`FINAL turn ${succeeded} depth ${depth}`);
for (let d = 1; d <= depth; d++) {
  const level = levels[d - 1];
  const [seen, total] = explored(level);
  maps.push(`LEVEL ${d} explored ${seen}/${total}`, ...mapLines(level, d === depth));
}
maps.push(status());
const stats = [
  `result ${result}`,
  `cause ${cause}`,
  `turns ${succeeded}`,
  `depth ${depth}`,
  `level ${playerLevel}`,
  `xp ${xp}`,
  `hp ${hp}/${maxHp}`,
  `defense ${defense()}`,
  `gold ${gold}`,
  `food ${food} ${hunger()}`,
  `poison ${poison}`,
  `weapon ${weapon ? displayName(weapon) : '-'}`,
  `armor ${armor ? displayName(armor) : '-'}`,
  `commands ${commands.length} executed ${succeeded} failed ${failed} unused ${unused}`,
  `moves ${moves}`,
];
for (const [name, counts] of [
  ['player_attacks', playerAttacks],
  ['monster_attacks', monsterAttacks],
] as const) {
  stats.push(
    `${name} ${counts.count} hits ${counts.hits} criticals ${counts.criticals} damage ${counts.damage} accuracy ${decimal(100 * counts.hits, counts.count)}`,
  );
}
stats.push(
  `poison_damage ${poisonDamage} starvation_damage ${starvationDamage}`,
  `picked ${picked} quaffed ${quaffed} read ${read} eaten ${eaten} wielded ${wielded} worn ${worn}`,
  `kills ${levels.reduce((sum, level) => sum + level.killed, 0)}`,
);
for (const type of monsterTypes) {
  if (kills.has(type.name)) stats.push(`KILL ${type.name} ${kills.get(type.name)}`);
}
levels.forEach((level, i) => {
  const [seen, total] = explored(level);
  stats.push(
    `LEVEL ${i + 1} rooms ${level.rooms.length} explored ${seen}/${total} ${decimal(100 * seen, total)} monsters ${level.killed}/${level.created} items ${level.picked}/${level.placed}`,
  );
});
pack.forEach((item, i) =>
  stats.push(
    `INVENTORY ${i + 1} ${displayName(item)}${item === weapon ? ' (wielded)' : ''}${item === armor ? ' (worn)' : ''}`,
  ),
);
mkdirSync('output', { recursive: true });
for (const [name, output] of [
  ['messages', messages],
  ['maps', maps],
  ['stats', stats],
] as const) {
  writeFileSync(`output/${name}.txt`, output.length ? output.join('\n') + '\n' : '', 'ascii');
}
