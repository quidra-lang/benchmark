import type {GroundedModel,GroundedAction,Settings,SearchNode,SearchResult} from './types.ts';
import type {Engine} from './heuristics.ts';

export function bit(number:number):bigint {
  return 1n << BigInt(number);
}

export function mask(numbers:Iterable<number>):bigint {
  let result = 0n;
  for (const number of numbers) result |= bit(number);
  return result;
}

export function numbers(value:bigint):number[] {
  const result:number[] = [];
  for (let number = 0; value !== 0n; number++, value >>= 1n) if ((value & 1n) !== 0n) result.push(number);
  return result;
}

export function contains(state:bigint,facts:bigint):boolean {
  return (state & facts) === facts;
}

export function applicable(state:bigint,action:GroundedAction):boolean {
  return contains(state, action.pre) && (state & action.neg) === 0n;
}

export function apply(state:bigint,action:GroundedAction):bigint {
  return (state & ~action.del) | action.add;
}

class Heap {
  items:SearchNode[];
  constructor() {
    this.items = [];
  }

  compare(a:SearchNode,b:SearchNode):number {
    return a.f - b.f || a.h - b.h || a.serial - b.serial;
  }

  push(value:SearchNode):void {
    let index = this.items.length;
    this.items.push(value);
    while (index > 0) {
      const parent = Math.floor((index - 1) / 2);
      if (this.compare(this.items[parent], value) <= 0) break;
      this.items[index] = this.items[parent];
      index = parent;
    }
    this.items[index] = value;
  }

  pop():SearchNode {
    const first = this.items[0];
    const last = this.items.pop()!;
    if (this.items.length === 0) return first;
    let index = 0;
    while (index * 2 + 1 < this.items.length) {
      let child = index * 2 + 1;
      if (child + 1 < this.items.length && this.compare(this.items[child + 1], this.items[child]) < 0) child++;
      if (this.compare(last, this.items[child]) <= 0) break;
      this.items[index] = this.items[child];
      index = child;
    }
    this.items[index] = last;
    return first;
  }
}

function bestFirst(problem:GroundedModel,start:bigint,algorithm:string,heuristic:string,settings:Settings,engine:Engine):SearchResult {
  let expanded = 0;
  let generated = 0;
  const finish = (result:string,plan:GroundedAction[]|null = null):SearchResult => ({result, plan, expanded, generated});
  const initialH = engine.value(start, heuristic);
  if (initialH === Infinity) return finish('dead end');
  const priority = (g:number,d:number,h:number):number => algorithm === 'bfs' ? d : algorithm === 'ucs' ? g : algorithm === 'gbfs' ? h :
    g + (algorithm === 'wastar' ? settings.weight : 1) * h;
  const best = new Map<bigint,number>([[start,0]]);
  const open = new Heap();
  let serial = 0;
  open.push({state: start, g: 0, d: 0, h: initialH, f: priority(0, 0, initialH), serial: serial++, parent: null, action: null});
  const revisits = ['ucs', 'astar', 'wastar'].includes(algorithm);
  while (open.items.length > 0) {
    const node = open.pop();
    if (revisits && node.g > best.get(node.state)!) continue;
    if (contains(node.state, problem.goal)) {
      const plan:GroundedAction[] = [];
      for (let current:SearchNode = node; current.parent !== null; current = current.parent) plan.push(current.action!);
      return finish('solved', plan.reverse());
    }
    if (expanded === settings.budget) return finish('budget');
    expanded++;
    for (const action of problem.actions) {
      if (!applicable(node.state, action)) continue;
      generated++;
      const state = apply(node.state, action);
      const g = node.g + action.cost;
      if (best.has(state) && (!revisits || best.get(state) <= g)) continue;
      best.set(state, g);
      const h = engine.value(state, heuristic);
      if (h === Infinity) continue;
      const d = node.d + 1;
      open.push({state, g, d, h, f: priority(g, d, h), serial: serial++, parent: node, action});
    }
  }
  return finish('exhausted');
}

function hillClimb(problem:GroundedModel,start:bigint,heuristic:string,settings:Settings,engine:Engine):SearchResult {
  let expanded = 0;
  let generated = 0;
  let plan:GroundedAction[] = [];
  let current = start;
  let currentH = engine.value(start, heuristic);
  const finish = (result:string):SearchResult => ({result, plan: result === 'solved' ? plan : null, expanded, generated});
  if (currentH === Infinity) return finish('dead end');
  climbing: while (true) {
    if (contains(current, problem.goal)) return finish('solved');
    const queue:{state:bigint;path:GroundedAction[]}[] = [{state:current,path:[]}];
    const visited = new Set<bigint>([current]);
    for (let index = 0; index < queue.length; index++) {
      const node = queue[index];
      if (expanded === settings.budget) return finish('budget');
      expanded++;
      for (const action of engine.relaxedPlan(node.state).helpful) {
        const state = apply(node.state, action);
        generated++;
        if (visited.has(state)) continue;
        visited.add(state);
        const h = engine.value(state, heuristic);
        if (h === Infinity) continue;
        const path = node.path.concat(action);
        if (h < currentH) {
          plan = plan.concat(path);
          current = state;
          currentH = h;
          continue climbing;
        }
        queue.push({state, path});
      }
    }
    return finish('stuck');
  }
}

export function run(problem:GroundedModel,start:bigint,algorithm:string,heuristic:string,settings:Settings,engine:Engine):SearchResult {
  return algorithm === 'ehc' ? hillClimb(problem, start, heuristic, settings, engine) :
    bestFirst(problem, start, algorithm, heuristic, settings, engine);
}

