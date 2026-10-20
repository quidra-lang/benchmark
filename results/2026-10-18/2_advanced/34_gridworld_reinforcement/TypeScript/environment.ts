import { readFileSync } from 'node:fs';
export const ACTIONS = ['N', 'E', 'S', 'W'] as const;
export type Ending = 'goal' | 'pit' | 'timeout';
export interface Terminal { cell: number; number: number; reward: number; ending: 'goal' | 'pit'; symbol: string }
export interface Arrival { cell: number; next: number; reward: number }
export interface Transition extends Arrival { weight: number }
export class World {
  cells: string[];
  states: number[] = [];
  terminals: Terminal[] = [];
  index: number[];
  terminalAt: (Terminal | null)[];
  start = 0;
  startIndex: number;
  moves: number[][];
  constructor(public height: number, public width: number, rows: string[], public wind: number[], rewards: number[]) {
    this.cells = rows.join('').split('');
    this.index = Array(this.cells.length).fill(-1);
    this.terminalAt = Array(this.cells.length).fill(null);
    this.cells.forEach((terrain, cell) => {
      if (terrain === '#') return;
      if (terrain === 'G' || terrain === 'P') {
        const number = this.terminals.length;
        const terminal: Terminal = { cell, number, reward: rewards[number], ending: terrain === 'G' ? 'goal' : 'pit', symbol: String.fromCharCode(97 + number) };
        this.terminals.push(terminal); this.terminalAt[cell] = terminal;
      } else { this.index[cell] = this.states.length; this.states.push(cell); if (terrain === 'S') this.start = cell; }
    });
    this.startIndex = this.index[this.start];
    this.moves = this.states.map(cell => ACTIONS.map((_, a) => this.move(cell, a)));
  }
  move(cell: number, action: number): number {
    let y = cell + [-this.width, 1, this.width, -1][action];
    if (this.cells[y] === '#') y = cell;
    if (this.terminalAt[y] !== null) return y;
    for (let k = 0; k < this.wind[cell % this.width]; k++) {
      if (this.cells[y - this.width] === '#') break;
      y -= this.width;
      if (this.terminalAt[y] !== null) break;
    }
    return y;
  }
}
export function readWorld(): World {
  const lines = readFileSync('input/world.txt', 'ascii').slice(0, -1).split('\n');
  const h = +lines[0].split(' ')[1], w = +lines[1].split(' ')[1];
  return new World(h, w, lines.slice(2, h + 2), [...lines[h + 2].split(' ')[1]].map(Number), lines[h + 3].split(' ').slice(1).map(Number));
}
export class Minstd {
  constructor(private state: number) {}
  draw(): number { this.state = 48271 * this.state % 2147483647; return this.state; }
}
export class TransitionModel {
  transitions: Transition[][][];
  constructor(public world: World, public denominator: number, public floorSlip: number, public iceSlip: number, public stepReward: number) {
    this.transitions = world.states.map((_, state) => ACTIONS.map((__, a) => {
      const p = this.slip(state), outcomes: [number, number][] = [[a, denominator - 2 * p], [(a + 1) % 4, p], [(a + 3) % 4, p]];
      return outcomes.filter(([, weight]) => weight > 0).map(([d, weight]) => ({ ...this.arrival(state, d), weight }));
    }));
  }
  slip(state: number): number { return this.world.cells[this.world.states[state]] === '~' ? this.iceSlip : this.floorSlip; }
  arrival(state: number, direction: number): Arrival {
    const cell = this.world.moves[state][direction], terminal = this.world.terminalAt[cell];
    return { cell, next: this.world.index[cell], reward: terminal === null ? this.stepReward : terminal.reward };
  }
  step(state: number, action: number, generator: Minstd): Arrival {
    const t = generator.draw() % this.denominator, p = this.slip(state);
    return this.arrival(state, t < this.denominator - 2 * p ? action : t < this.denominator - p ? (action + 1) % 4 : (action + 3) % 4);
  }
}
