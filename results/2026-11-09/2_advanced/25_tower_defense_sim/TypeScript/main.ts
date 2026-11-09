import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { readMap, type GridMap } from './grid_map.ts';
import { DIRECTIONS, distanceField, nextCell, spawnPath } from './pathing.ts';
import {
  isMode,
  parseTowerType,
  createTower,
  canAim,
  chooseTarget,
  type Tower,
  type TowerType,
} from './towers.ts';
import {
  parseEnemyType,
  parseGroup,
  spawnEnemy,
  splitEnemy,
  position,
  occupiedCell,
  slowedSpeed,
  type Enemy,
  type EnemyType,
  type Group,
} from './enemies.ts';
import {
  squaredDistance,
  advancePoint,
  receiveEffect,
  advanceEffect,
  armoredDamage,
  createProjectile,
  moveProjectile,
  type Projectile,
} from './combat.ts';
interface Wave {
  reward: number;
  groups: Group[];
}
interface Action {
  tick: number;
  command: string;
  arguments: string[];
}
interface Settings {
  gold: number;
  lives: number;
  interestRate: number;
  interestCap: number;
  sellRate: number;
  start: number;
  interval: number;
  early: number;
  snapshots: Set<number>;
}
interface Inputs {
  map: GridMap;
  towerTypes: Map<string, TowerType>;
  enemyTypes: Map<string, EnemyType>;
  waves: Wave[];
  actions: Action[];
  settings: Settings;
}
interface WaveRecord {
  number: number;
  wave: Wave;
  start: number;
  end: number | null;
  status: 'active' | 'cleared' | 'lost';
  spawned: number;
  peak: number;
  kills: number;
  leaks: number;
  livesLost: number;
  bounty: number;
  reward: number;
  interest: number;
  gold: number;
  lives: number;
  damage: Map<number, number>;
  groups: (Group & { appeared: number })[];
}
function readLines(path: string) {
  const text = readFileSync(path, 'ascii');
  return text === ''
    ? []
    : text
        .slice(0, -1)
        .split('\n')
        .map((line) => line.split(' '));
}
function readInputs(): Inputs {
  const map = readMap();
  const towerTypes = new Map<string, TowerType>();
  const towerLines = readLines('input/towers.txt');
  for (let index = 0; index < towerLines.length;) {
    const count = Number(towerLines[index][4]);
    const type = parseTowerType(towerLines[index], towerLines.slice(index + 1, index + count + 1));
    towerTypes.set(type.name, type);
    index += count + 1;
  }
  const enemyTypes = new Map<string, EnemyType>();
  const waves: Wave[] = [];
  for (const fields of readLines('input/waves.txt')) {
    if (fields[0] === 'enemy') {
      const type = parseEnemyType(fields, enemyTypes);
      enemyTypes.set(type.name, type);
    } else if (fields[0] === 'wave') waves.push({ reward: Number(fields[1]), groups: [] });
    else waves[waves.length - 1].groups.push(parseGroup(fields, enemyTypes));
  }
  const actions = readLines('input/actions.txt').map((f) => ({
    tick: Number(f[0]),
    command: f[1],
    arguments: f.slice(2),
  }));
  const params = new Map(readLines('input/params.txt').map((f) => [f[0], f.slice(1).map(Number)]));
  const settings: Settings = {
    gold: params.get('gold')![0],
    lives: params.get('lives')![0],
    interestRate: params.get('interest')![0],
    interestCap: params.get('interest')![1],
    sellRate: params.get('sell')![0],
    start: params.get('schedule')![0],
    interval: params.get('schedule')![1],
    early: params.get('early')![0],
    snapshots: new Set(params.get('snapshots')!),
  };
  return { map, towerTypes, enemyTypes, waves, actions, settings };
}
function decimalOne(a: number, b: number) {
  if (!b) return '-';
  const z = Math.floor((20 * a + b) / (2 * b));
  return `${Math.floor(z / 10)}.${z % 10}`;
}
const digit = (n: number) => (n === 0 ? '.' : n <= 9 ? String(n) : '*');
class Game {
  map: GridMap;
  settings: Settings;
  tick = 1;
  gold: number;
  lives: number;
  towers: Tower[] = [];
  standing = new Map<number, Tower>();
  enemies = new Map<number, Enemy>();
  projectiles = new Map<number, Projectile>();
  nextEnemy = 1;
  nextProjectile = 1;
  spawnCells: Map<number, number>;
  distances: number[];
  nextStart: number | null;
  started = 0;
  active: WaveRecord | null = null;
  waveRecords: WaveRecord[] = [];
  cleared = 0;
  perfect = 0;
  outcome: 'victory' | 'defeat' | null = null;
  actionIndex = 0;
  succeeded = 0;
  refused = 0;
  income = { bounty: 0, reward: 0, interest: 0, early: 0, refund: 0 };
  spent = 0;
  killCounts: number[];
  events: string[] = [];
  snapshots: string[] = [];
  constructor(public data: Inputs) {
    this.map = data.map;
    this.settings = data.settings;
    this.gold = data.settings.gold;
    this.lives = data.settings.lives;
    this.spawnCells = new Map(this.map.spawns.map((s) => [s.number, s.cell]));
    this.distances = distanceField(this.map, this.standing);
    this.nextStart = data.settings.start;
    this.killCounts = Array(this.map.cells.length).fill(0);
  }
  event(body: string) {
    this.events.push(`${this.tick} ${body}`);
  }
  standingTower(number: number) {
    const tower = this.towers[number - 1];
    return tower && tower.sold === null ? tower : null;
  }
  updateDistanceField() {
    const previous = this.distances;
    this.distances = distanceField(this.map, this.standing);
    for (const s of this.map.spawns) {
      if (previous[s.cell] !== this.distances[s.cell]) {
        this.event(`REPATH ${s.number} ${previous[s.cell]} ${this.distances[s.cell]}`);
      }
    }
  }
  build(name: string, x: number, y: number) {
    const type = this.data.towerTypes.get(name);
    const cell = this.map.cell(x, y);
    let reason: string | null = null;
    if (!type) reason = 'type';
    else if (!this.map.inside(x, y)) reason = 'bounds';
    else if (!this.map.buildable(cell)) reason = 'terrain';
    else if (this.standing.has(cell)) reason = 'tower';
    else if (this.gold < type.levels[0].cost) reason = 'gold';
    if (!reason) {
      for (const enemy of this.enemies.values()) {
        const t = enemy.travel;
        if (t.kind === 'ground' && (t.current === cell || t.next === cell)) {
          reason = 'enemy';
          break;
        }
      }
    }
    if (!reason) {
      const blocked = new Set(this.standing.keys());
      blocked.add(cell);
      const trial = distanceField(this.map, blocked);
      if (this.map.spawns.some((s) => trial[s.cell] < 0)) reason = 'blocked';
      for (const e of this.enemies.values()) {
        if (e.travel.kind === 'ground' && trial[e.travel.next] < 0) reason = 'blocked';
      }
    }
    if (reason) {
      this.event(`BUILD_REFUSED ${name} ${x} ${y} ${reason}`);
      return false;
    }
    const tower = createTower(this.towers.length + 1, type!, x, y, this.map, this.tick);
    const cost = type!.levels[0].cost;
    this.towers.push(tower);
    this.standing.set(cell, tower);
    this.gold -= cost;
    this.spent += cost;
    this.event(`BUILD T${tower.number} ${name} ${x} ${y} cost ${cost} gold ${this.gold}`);
    this.updateDistanceField();
    return true;
  }
  upgrade(number: number) {
    const tower = this.standingTower(number);
    let reason: string | null = null;
    if (!tower) reason = 'notower';
    else if (tower.level === tower.type.levels.length) reason = 'maxlevel';
    else if (this.gold < tower.type.levels[tower.level].cost) reason = 'gold';
    if (reason) {
      this.event(`UPGRADE_REFUSED T${number} ${reason}`);
      return false;
    }
    const cost = tower!.type.levels[tower!.level].cost;
    tower!.level++;
    tower!.investment += cost;
    this.gold -= cost;
    this.spent += cost;
    this.event(`UPGRADE T${number} level ${tower!.level} cost ${cost} gold ${this.gold}`);
    return true;
  }
  sell(number: number) {
    const tower = this.standingTower(number);
    if (!tower) {
      this.event(`SELL_REFUSED T${number} notower`);
      return false;
    }
    const refund = Math.floor(
      (tower.investment * (this.tick === tower.built ? 100 : this.settings.sellRate)) / 100,
    );
    tower.sold = this.tick;
    this.standing.delete(tower.cell);
    this.gold += refund;
    this.income.refund += refund;
    this.event(`SELL T${number} refund ${refund} gold ${this.gold}`);
    this.updateDistanceField();
    return true;
  }
  target(number: number, mode: string) {
    const tower = this.standingTower(number);
    if (!tower || !isMode(mode)) {
      this.event(`TARGET_REFUSED T${number} ${!tower ? 'notower' : 'mode'}`);
      return false;
    }
    tower.mode = mode;
    this.event(`TARGET T${number} ${mode}`);
    return true;
  }
  callWave() {
    if (this.active) {
      this.event('CALL_REFUSED active');
      return false;
    }
    const bonus = (this.nextStart! - this.tick) * this.settings.early;
    this.gold += bonus;
    this.income.early += bonus;
    this.nextStart = this.tick;
    this.event(`CALL ${this.started + 1} bonus ${bonus} gold ${this.gold}`);
    return true;
  }
  performAction(action: Action) {
    const a = action.arguments;
    switch (action.command) {
      case 'BUILD':
        return this.build(a[0], Number(a[1]), Number(a[2]));
      case 'UPGRADE':
        return this.upgrade(Number(a[0]));
      case 'SELL':
        return this.sell(Number(a[0]));
      case 'TARGET':
        return this.target(Number(a[0]), a[1]);
      case 'CALL':
        return this.callWave();
    }
    return false;
  }
  actions() {
    while (
      this.actionIndex < this.data.actions.length &&
      this.data.actions[this.actionIndex].tick === this.tick
    ) {
      if (this.performAction(this.data.actions[this.actionIndex++])) this.succeeded++;
      else this.refused++;
    }
  }
  registerEnemy(enemy: Enemy, origin: number | string) {
    this.enemies.set(enemy.number, enemy);
    enemy.type.spawned++;
    this.active!.spawned++;
    this.event(`SPAWN E${enemy.number} ${enemy.type.name} ${origin} hp ${enemy.hp}`);
  }
  startAndSpawn() {
    if (!this.active && this.tick === this.nextStart) {
      const wave = this.data.waves[this.started++];
      this.active = {
        number: this.started,
        wave,
        start: this.tick,
        end: null,
        status: 'active',
        spawned: 0,
        peak: 0,
        kills: 0,
        leaks: 0,
        livesLost: 0,
        bounty: 0,
        reward: 0,
        interest: 0,
        gold: 0,
        lives: 0,
        damage: new Map(),
        groups: wave.groups.map((g) => ({ ...g, appeared: 0 })),
      };
      this.waveRecords.push(this.active);
      this.nextStart = null;
      this.event(
        `WAVE_START ${this.started} enemies ${wave.groups.reduce((sum, g) => sum + g.count, 0)}`,
      );
    }
    if (!this.active) return;
    for (const group of this.active.groups) {
      if (
        group.appeared >= group.count ||
        this.active.start + group.delay + group.appeared * group.interval !== this.tick
      ) {
        continue;
      }
      const enemy = spawnEnemy(
        this.nextEnemy++,
        group.type,
        group.multiplier,
        this.spawnCells.get(group.spawn)!,
        this.map,
        this.distances,
      );
      group.appeared++;
      this.registerEnemy(enemy, group.spawn);
    }
    this.active.peak = Math.max(this.active.peak, this.enemies.size);
  }
  creditDamage(enemy: Enemy, tower: Tower, damage: number) {
    tower.damage += damage;
    enemy.type.damage += damage;
    this.active!.damage.set(tower.number, (this.active!.damage.get(tower.number) ?? 0) + damage);
  }
  kill(enemy: Enemy, tower: Tower) {
    enemy.alive = false;
    this.enemies.delete(enemy.number);
    this.killCounts[occupiedCell(enemy, this.map)]++;
    tower.kills++;
    this.active!.kills++;
    enemy.type.killed++;
    this.gold += enemy.type.bounty;
    this.active!.bounty += enemy.type.bounty;
    this.income.bounty += enemy.type.bounty;
    this.event(
      `KILL E${enemy.number} ${enemy.type.name} T${tower.number} bounty ${enemy.type.bounty} gold ${this.gold}`,
    );
    for (let i = 0; i < enemy.type.splitCount; i++) {
      this.registerEnemy(
        splitEnemy(this.nextEnemy++, enemy.type.splitInto!, enemy),
        `E${enemy.number}`,
      );
    }
  }
  leak(enemy: Enemy) {
    enemy.alive = false;
    this.enemies.delete(enemy.number);
    const lost = Math.min(this.lives, enemy.type.lives);
    this.lives -= lost;
    this.active!.leaks++;
    this.active!.livesLost += lost;
    enemy.type.leaked++;
    this.event(`LEAK E${enemy.number} ${enemy.type.name} lives ${this.lives}`);
    if (!this.lives) {
      this.active!.status = 'lost';
      this.active!.end = this.tick;
      this.active!.gold = this.gold;
      this.active!.lives = this.lives;
      this.outcome = 'defeat';
      this.event('DEFEAT');
    }
  }
  moveEnemies() {
    for (const enemy of [...this.enemies.values()]) {
      if (enemy.burn.remaining > 0) {
        const source = enemy.burn.source!;
        const damage = Math.min(enemy.hp, enemy.burn.strength);
        enemy.hp -= damage;
        this.creditDamage(enemy, source, damage);
        advanceEffect(enemy.burn);
        if (!enemy.hp) {
          this.kill(enemy, source);
          continue;
        }
      }
      enemy.hp = Math.min(enemy.maximum, enemy.hp + enemy.type.regen);
      let speed = slowedSpeed(enemy);
      let arrived = false;
      const t = enemy.travel;
      if (t.kind === 'air') {
        const moved = advancePoint(t.point, this.map.center(this.map.exit), speed);
        t.point = moved.point;
        arrived = moved.arrived;
      } else {
        if (this.map.water(occupiedCell(enemy, this.map))) speed = Math.floor(speed / 2);
        while (speed > 0) {
          const remaining = 100 - t.progress;
          if (speed < remaining) {
            t.progress += speed;
            speed = 0;
          } else {
            speed -= remaining;
            t.current = t.next;
            t.progress = 0;
            if (t.current === this.map.exit) {
              arrived = true;
              break;
            }
            t.next = nextCell(this.map, this.distances, t.current);
          }
        }
      }
      if (arrived) {
        this.leak(enemy);
        if (!this.lives) return;
      }
    }
  }
  fireTowers() {
    for (const tower of this.towers) {
      if (tower.sold !== null || this.tick < tower.ready) continue;
      const enemy = chooseTarget(tower, this.enemies.values(), this.map, this.distances);
      if (!enemy) continue;
      const p = createProjectile(
        this.nextProjectile++,
        tower,
        enemy,
        this.map.center(tower.cell),
        position(enemy, this.map),
      );
      this.projectiles.set(p.number, p);
      tower.shots++;
      tower.ready = this.tick + tower.type.levels[tower.level - 1].interval;
      this.event(`SHOT T${tower.number} E${enemy.number}`);
    }
  }
  moveProjectiles() {
    for (const p of this.projectiles.values()) {
      if (!moveProjectile(p, p.target.alive ? position(p.target, this.map) : null)) continue;
      this.projectiles.delete(p.number);
      const f = p.performance;
      const tower = p.tower;
      const victims =
        f.splash === 0
          ? p.target.alive
            ? [p.target]
            : []
          : [...this.enemies.values()].filter(
              (e) =>
                canAim(p.targets, e) &&
                squaredDistance(position(e, this.map), p.aim) <= f.splash * f.splash,
            );
      if (!victims.length) tower.fizzles++;
      for (const enemy of victims) {
        tower.hits++;
        const damage = armoredDamage(enemy.hp, f.power, enemy.type.armor);
        enemy.hp -= damage;
        this.creditDamage(enemy, tower, damage);
        if (!enemy.hp) this.kill(enemy, tower);
        else {
          if (f.slowRate > 0) receiveEffect(enemy.slow, f.slowRate, f.slowTime);
          if (f.burnAmount > 0) receiveEffect(enemy.burn, f.burnAmount, f.burnTime, tower);
        }
      }
    }
  }
  finishWave() {
    const r = this.active;
    if (!r || this.enemies.size || r.groups.some((g) => g.appeared < g.count)) return;
    r.reward = r.wave.reward;
    this.gold += r.reward;
    r.interest = Math.min(
      this.settings.interestCap,
      Math.floor((this.gold * this.settings.interestRate) / 100),
    );
    this.gold += r.interest;
    this.income.reward += r.reward;
    this.income.interest += r.interest;
    r.end = this.tick;
    r.status = 'cleared';
    r.gold = this.gold;
    r.lives = this.lives;
    this.cleared++;
    if (!r.leaks) this.perfect++;
    this.event(`WAVE_END ${r.number} reward ${r.reward} interest ${r.interest} gold ${this.gold}`);
    this.active = null;
    if (this.started === this.data.waves.length) {
      this.outcome = 'victory';
      this.event('VICTORY');
    } else this.nextStart = this.tick + this.settings.interval;
  }
  gridLines(cells: string[]) {
    const lines = ['  ' + Array.from({ length: this.map.width }, (_, x) => x % 10).join('')];
    for (let y = 0; y < this.map.height; y++) {
      lines.push(`${y % 10} ${cells.slice(y * this.map.width, (y + 1) * this.map.width).join('')}`);
    }
    return lines;
  }
  mapPicture() {
    const cells = this.map.cells.slice();
    for (const spawn of this.map.spawns) {
      for (const cell of spawnPath(this.map, this.distances, spawn.cell)) {
        if (this.map.cells[cell] === '.' || this.map.cells[cell] === '~') cells[cell] = '+';
      }
    }
    for (const tower of this.standing.values()) cells[tower.cell] = tower.type.symbol;
    const occupied = new Map<number, string>();
    for (const enemy of this.enemies.values()) {
      const cell = occupiedCell(enemy, this.map);
      occupied.set(cell, occupied.has(cell) ? '*' : enemy.type.symbol);
    }
    for (const [cell, symbol] of occupied) cells[cell] = symbol;
    return cells;
  }
  flowPicture() {
    return this.map.cells.map((terrain, cell) => {
      if (terrain === '#') return '#';
      if (cell === this.map.exit) return 'E';
      const tower = this.standing.get(cell);
      if (tower) return tower.type.symbol;
      if (this.distances[cell] < 0) return '?';
      const c = this.map.coordinates(cell);
      const n = this.map.coordinates(nextCell(this.map, this.distances, cell));
      return DIRECTIONS.find((d) => c.x + d.x === n.x && c.y + d.y === n.y)!.symbol;
    });
  }
  coveragePicture() {
    return this.map.cells.map((terrain, cell) => {
      if (terrain === '#') return '#';
      const tower = this.standing.get(cell);
      if (tower) return tower.type.symbol;
      let count = 0;
      for (const t of this.standing.values()) {
        const range = t.type.levels[t.level - 1].range;
        if (squaredDistance(this.map.center(cell), this.map.center(t.cell)) <= range * range) {
          count++;
        }
      }
      return digit(count);
    });
  }
  killsPicture() {
    return this.map.cells.map((terrain, cell) =>
      this.killCounts[cell] ? digit(this.killCounts[cell]) : terrain === '#' ? '#' : '.',
    );
  }
  snapshot(final: boolean) {
    const next = !this.active && !this.outcome ? this.nextStart : '-';
    const lines = [
      `${final ? 'FINAL' : 'SNAPSHOT'} ${this.tick} wave ${this.started} next ${next} gold ${this.gold} lives ${this.lives}`,
      ...this.gridLines(this.mapPicture()),
    ];
    for (const s of this.map.spawns) {
      lines.push(`PATH ${s.number} length ${this.distances[s.cell]}`);
    }
    for (const t of this.towers) {
      if (t.sold === null) {
        lines.push(
          `T${t.number} ${t.type.name} ${t.x} ${t.y} level ${t.level} mode ${t.mode} ready ${t.ready}`,
        );
      }
    }
    for (const e of this.enemies.values()) {
      const p = position(e, this.map);
      lines.push(
        `E${e.number} ${e.type.name} ${p.x} ${p.y} hp ${e.hp}/${e.maximum} slow ${e.slow.strength} ${e.slow.remaining} burn ${e.burn.strength} ${e.burn.remaining}`,
      );
    }
    for (const p of this.projectiles.values()) {
      lines.push(`P${p.number} T${p.tower.number} E${p.target.number} ${p.point.x} ${p.point.y}`);
    }
    if (final) {
      lines.push(
        'FLOW',
        ...this.gridLines(this.flowPicture()),
        'COVERAGE',
        ...this.gridLines(this.coveragePicture()),
        'KILLS',
        ...this.gridLines(this.killsPicture()),
      );
    }
    return lines;
  }
  wavesReport() {
    const lines = [
      [
        'wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives',
        ...this.towers.map((t) => `T${t.number}`),
      ].join(','),
    ];
    for (const r of this.waveRecords) {
      lines.push(
        [
          r.number,
          r.start,
          r.end,
          r.status,
          r.spawned,
          r.peak,
          r.kills,
          r.leaks,
          r.livesLost,
          r.bounty,
          r.reward,
          r.interest,
          r.gold,
          r.lives,
          ...this.towers.map((t) => r.damage.get(t.number) ?? 0),
        ].join(','),
      );
    }
    return lines;
  }
  summaryReport() {
    let spawned = 0;
    let killed = 0;
    let leaked = 0;
    let damage = 0;
    for (const t of this.data.enemyTypes.values()) {
      spawned += t.spawned;
      killed += t.killed;
      leaked += t.leaked;
    }
    let mvp: Tower | null = null;
    for (const t of this.towers) {
      damage += t.damage;
      if (!mvp || t.damage > mvp.damage) mvp = t;
    }
    const i = this.income;
    const lines = [
      `outcome ${this.outcome}`,
      `ticks ${this.tick}`,
      `waves ${this.cleared}/${this.data.waves.length} perfect ${this.perfect}`,
      `lives ${this.lives}/${this.settings.lives}`,
      `gold ${this.gold}`,
      `enemies spawned ${spawned} killed ${killed} leaked ${leaked}`,
      `income bounty ${i.bounty} reward ${i.reward} interest ${i.interest} early ${i.early} refund ${i.refund}`,
      `spent ${this.spent}`,
      `damage ${damage}`,
      `actions total ${this.data.actions.length} done ${this.succeeded} refused ${this.refused} unused ${this.data.actions.length - this.actionIndex}`,
      `score ${10 * killed + 100 * this.lives + 50 * this.perfect + this.gold}`,
      mvp ? `mvp T${mvp.number} damage ${mvp.damage}` : 'mvp -',
    ];
    for (const t of this.data.enemyTypes.values()) {
      lines.push(
        `ENEMY ${t.name} spawned ${t.spawned} killed ${t.killed} leaked ${t.leaked} damage ${t.damage}`,
      );
    }
    for (const t of this.towers) {
      const state = t.sold === null ? 'active' : `sold ${t.sold}`;
      lines.push(
        `TOWER T${t.number} ${t.type.name} ${t.x} ${t.y} level ${t.level} mode ${t.mode} ${state} shots ${t.shots} hits ${t.hits} fizzles ${t.fizzles} kills ${t.kills} damage ${t.damage} per_shot ${decimalOne(t.damage, t.shots)} share ${decimalOne(100 * t.damage, damage)} invested ${t.investment}`,
      );
    }
    return lines;
  }
  run() {
    while (!this.outcome) {
      this.actions();
      this.startAndSpawn();
      this.moveEnemies();
      if (!this.lives) break;
      this.fireTowers();
      this.moveProjectiles();
      this.finishWave();
      if (this.settings.snapshots.has(this.tick)) this.snapshots.push(...this.snapshot(false));
      if (this.outcome) break;
      this.tick++;
    }
    this.snapshots.push(...this.snapshot(true));
  }
  writeReports() {
    const reports: Record<string, string[]> = {
      'events.txt': this.events,
      'waves.csv': this.wavesReport(),
      'snapshots.txt': this.snapshots,
      'summary.txt': this.summaryReport(),
    };
    mkdirSync('output', { recursive: true });
    for (const [name, lines] of Object.entries(reports)) {
      writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
    }
  }
}
const game = new Game(readInputs());
game.run();
game.writeReports();
