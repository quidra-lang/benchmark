import {bit,numbers,contains} from './search.ts';
import type {GroundedAction,GraphplanAction,TransformAction,ActionLevel,GraphPlanResult} from './types.ts';

interface ExtractFrame {kind:'extract';level:number;goals:bigint;stage:'start'|'return';key?:string}
interface AssignFrame {
  kind:'assign';level:number;goals:number[];stage:'start'|'choose'|'assigned'|'lower';
  next:number;chosen:GraphplanAction[];covered:bigint;
  choices?:GraphplanAction[];choice?:number;
}
type Frame = ExtractFrame | AssignFrame;


export class Mutexes {
  rows:bigint[];
  count:number;
  constructor(size:number) {
    this.rows = Array(size).fill(0n);
    this.count = 0;
  }

  add(first:number,second:number):void {
    this.rows[first] |= bit(second);
    this.rows[second] |= bit(first);
    this.count++;
  }

  has(first:number,second:number):boolean {
    return (this.rows[first] & bit(second)) !== 0n;
  }

  compatible(facts:bigint):boolean {
    for (const fact of numbers(facts)) if ((this.rows[fact] & facts) !== 0n) return false;
    return true;
  }
}

export function buildActionLevel(actions:TransformAction[],facts:bigint,mutexes:Mutexes,factCount:number):ActionLevel {
  const elements:GraphplanAction[] = [];
  for (const action of actions) {
    if (contains(facts, action.pre) && mutexes.compatible(action.pre)) elements.push({...action, index: elements.length});
  }
  const actionCount = elements.length;
  for (const fact of numbers(facts)) {
    elements.push({number: null, fact, pre: bit(fact), add: bit(fact), del: 0n, original: null, index: elements.length});
  }
  const exclusive = new Mutexes(elements.length);
  for (let first = 0; first < elements.length; first++) {
    const x = elements[first];
    for (let second = first + 1; second < elements.length; second++) {
      const y = elements[second];
      const interference = (x.del & (y.pre | y.add)) !== 0n || (y.del & (x.pre | x.add)) !== 0n;
      const competing = numbers(x.pre).some(fact => (mutexes.rows[fact] & y.pre) !== 0n);
      if (interference || competing) exclusive.add(first, second);
    }
  }
  const achievers:GraphplanAction[][] = Array.from({length: factCount},():GraphplanAction[]=>[]);
  let nextFacts = 0n;
  for (const element of elements) {
    nextFacts |= element.add;
    for (const fact of numbers(element.add)) {
      if (element.original === null) achievers[fact].unshift(element);
      else achievers[fact].push(element);
    }
  }
  const nextMutexes = new Mutexes(factCount);
  const present = numbers(nextFacts);
  for (let first = 0; first < present.length; first++) {
    const p = present[first];
    for (let second = first + 1; second < present.length; second++) {
      const q = present[second];
      if (achievers[p].every(x => achievers[q].every(y => x.index !== y.index && exclusive.has(x.index, y.index)))) {
        nextMutexes.add(p, q);
      }
    }
  }
  return {elements, actionCount, mutexes: exclusive, achievers, nextFacts, nextMutexes};
}

export class Extractor {
  levels:ActionLevel[];
  memo:Set<string>;
  searched:number;
  memoHits:number;
  tried:number;
  constructor(actionLevels:ActionLevel[]) {
    this.levels = actionLevels;
    this.memo = new Set<string>();
    this.searched = 0;
    this.memoHits = 0;
    this.tried = 0;
  }

  extract(level:number,goals:bigint):GroundedAction[][]|null {
    const stack:Frame[] = [{kind:'extract',level,goals,stage:'start'}];
    let returned:GroundedAction[][]|null = null;
    const finish = (result:GroundedAction[][]|null):void => {
      returned = result;
      stack.pop();
    };
    while (stack.length > 0) {
      const frame = stack.at(-1)!;
      if (frame.kind === 'extract') {
        if (frame.stage === 'start') {
          if (frame.level === 0) {
            finish([]);
            continue;
          }
          frame.key = `${frame.level}:${frame.goals}`;
          if (this.memo.has(frame.key!)) {
            this.memoHits++;
            finish(null);
            continue;
          }
          this.searched++;
          frame.stage = 'return';
          stack.push({kind: 'assign', level: frame.level, goals: numbers(frame.goals), next: 0,
            chosen: [], covered: 0n, stage: 'start'});
        } else {
          if (returned === null) this.memo.add(frame.key!);
          finish(returned);
        }
        continue;
      }
      if (frame.stage === 'start') {
        while (frame.next < frame.goals.length && (frame.covered & bit(frame.goals[frame.next])) !== 0n) frame.next++;
        if (frame.next === frame.goals.length) {
          let preconditions = 0n;
          for (const element of frame.chosen) preconditions |= element.pre;
          frame.stage = 'lower';
          stack.push({kind: 'extract', level: frame.level - 1, goals: preconditions, stage: 'start'});
        } else {
          frame.choices = this.levels[frame.level - 1].achievers[frame.goals[frame.next]];
          frame.choice = 0;
          frame.stage = 'choose';
        }
      } else if (frame.stage === 'choose') {
        let selected:GraphplanAction|null = null;
        const mutexes = this.levels[frame.level - 1].mutexes;
        while (frame.choice! < frame.choices!.length) {
          const candidate = frame.choices![frame.choice!];
          frame.choice = frame.choice! + 1;
          if (frame.chosen.every(element => !mutexes.has(candidate.index, element.index))) {
            selected = candidate;
            break;
          }
        }
        if (selected === null) finish(null);
        else {
          this.tried++;
          frame.stage = 'assigned';
          stack.push({kind: 'assign', level: frame.level, goals: frame.goals, next: frame.next + 1,
            chosen: frame.chosen.concat(selected), covered: frame.covered | selected.add, stage: 'start'});
        }
      } else if (frame.stage === 'assigned') {
        if (returned === null) frame.stage = 'choose';
        else finish(returned);
      } else {
        if (returned === null) finish(null);
        else {
          const layer = frame.chosen.filter(element => element.original !== null)
            .sort((a, b) => a.number! - b.number!).map(element => element.original!);
          finish(returned.concat([layer]));
        }
      }
    }
    return returned;
  }
}

export function solve(actions:TransformAction[],factCount:number,initial:bigint,goal:bigint,limit:number):GraphPlanResult {
  const actionLevels:ActionLevel[] = [];
  const extractor = new Extractor(actionLevels);
  const logs:string[] = [];
  let facts = initial;
  let mutexes = new Mutexes(factCount);
  let previousFactCount = -1;
  let previousMutexCount = -1;
  const finish = (result:string,layers:GroundedAction[][]|null = null):GraphPlanResult => ({result, layers, plan: layers === null ? null : layers.flat(), logs,
    expanded: extractor.searched, generated: extractor.tried, memoHits: extractor.memoHits});
  for (let level = 0; ; level++) {
    const count = numbers(facts).length;
    logs.push(`fact level ${level}: facts=${count} mutexes=${mutexes.count}`);
    let attempted = false;
    if (contains(facts, goal) && mutexes.compatible(goal)) {
      attempted = true;
      const beforeSearch = extractor.searched;
      const beforeHits = extractor.memoHits;
      const layers = extractor.extract(level, goal);
      logs.push(`extract level ${level}: ${layers === null ? 'fail' : 'success'} ` +
        `searched=${extractor.searched - beforeSearch} memo_hits=${extractor.memoHits - beforeHits}`);
      if (layers !== null) return finish('solved', layers);
    }
    if (!attempted && level >= 1 && count === previousFactCount && mutexes.count === previousMutexCount) return finish('unreachable');
    if (level === limit) return finish('level limit');
    const next = buildActionLevel(actions, facts, mutexes, factCount);
    actionLevels.push(next);
    logs.push(`action level ${level}: actions=${next.actionCount} noops=${count} mutexes=${next.mutexes.count}`);
    previousFactCount = count;
    previousMutexCount = mutexes.count;
    facts = next.nextFacts;
    mutexes = next.nextMutexes;
  }
}

