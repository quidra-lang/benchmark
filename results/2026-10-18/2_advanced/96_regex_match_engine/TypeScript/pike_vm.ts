import * as charset from './charset.ts';
import type { Pattern, Instruction, Captures } from './types.ts';

interface Thread {p: number; captures: Captures}
interface ThreadList {threads: Thread[]; marks: Set<number>}
function threadList(): ThreadList { return {threads: [], marks: new Set<number>()}; }

export class PikeVM {
  program: Instruction[];
  groups: number;
  flags: string;
  text: string;
  steps: number;
  constructor(pattern: Pattern, text: string) {
    this.program = pattern.program;
    this.groups = pattern.groups;
    this.flags = pattern.flags;
    this.text = text;
    this.steps = 0;
  }

  add(list: ThreadList, instructionNumber: number, captures: Captures, position: number): void {
    const pending: Thread[] = [{p: instructionNumber, captures: captures.slice()}];
    while (pending.length > 0) {
      const {p, captures: current} = pending.pop()!;
      if (list.marks.has(p)) continue;
      list.marks.add(p);
      this.steps++;
      const instruction = this.program[p];
      switch (instruction.op) {
        case 'JMP': pending.push({p: instruction.x!, captures: current}); break;
        case 'SPLIT':
          pending.push({p: instruction.y!, captures: current.slice()}, {p: instruction.x!, captures: current.slice()});
          break;
        case 'SAVE': {
          const changed = current.slice();
          changed[instruction.group!] = position;
          pending.push({p: p + 1, captures: changed});
          break;
        }
        case 'ASSERT':
          if (charset.assertion(instruction.assertion!, this.text, position, this.flags)) pending.push({p: p + 1, captures: current});
          break;
        default: list.threads.push({p, captures: current.slice()});
      }
    }
  }

  search(start: number, full: boolean): Captures | null {
    let match: Captures | null = null;
    let list = threadList();
    let position = start;
    for (;;) {
      if (match === null && (!full || position === start)) this.add(list, 0, Array(2 * this.groups + 2).fill(null), position);
      const next = threadList();
      for (const thread of list.threads) {
        this.steps++;
        const instruction = this.program[thread.p];
        if (instruction.op === 'MATCH') {
          if (!full || position === this.text.length) { match = thread.captures.slice(); break; }
        } else if (charset.consumes(instruction, this.text, position, this.flags)) {
          this.add(next, thread.p + 1, thread.captures, position + 1);
        }
      }
      if (position === this.text.length) break;
      if (next.threads.length === 0 && (match !== null || full)) break;
      list = next;
      position++;
    }
    return match;
  }
}

