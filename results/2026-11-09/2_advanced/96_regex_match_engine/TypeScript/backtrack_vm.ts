import * as charset from './charset.ts';
import type { Pattern, Instruction, Captures, SearchResult } from './types.ts';

export class TooManySteps extends Error {}

export class BacktrackVM {
  program: Instruction[];
  groups: number;
  flags: string;
  text: string;
  steps: number;
  full: boolean;
  constructor(pattern: Pattern, text: string) {
    this.program = pattern.program;
    this.groups = pattern.groups;
    this.flags = pattern.flags;
    this.text = text;
    this.steps = 0;
    this.full = false;
  }

  execute(startInstruction: number, startPosition: number, captures: Captures, partial: boolean): SearchResult | null {
    const stack: {p: number; q: number; captures: Captures; visited: Set<number>}[] =
      [{p: startInstruction, q: startPosition, captures: captures.slice(), visited: new Set<number>()}];
    while (stack.length > 0) {
      let {p, q, captures: current, visited} = stack.pop()!;
      let failed = false;
      while (!failed) {
        this.steps++;
        if (this.steps > 200000) throw new TooManySteps();
        const instruction = this.program[p];
        switch (instruction.op) {
          case 'CHAR': case 'ANY': case 'CLASS':
            if (!charset.consumes(instruction, this.text, q, this.flags)) { failed = true; break; }
            q++;
            p++;
            visited = new Set<number>();
            break;
          case 'SPLIT':
            if (visited.has(p)) { failed = true; break; }
            visited.add(p);
            stack.push({p: instruction.y!, q, captures: current.slice(), visited: new Set(visited)});
            p = instruction.x!;
            break;
          case 'JMP': p = instruction.x!; break;
          case 'SAVE': current[instruction.group!] = q; p++; break;
          case 'ASSERT':
            if (charset.assertion(instruction.assertion!, this.text, q, this.flags)) p++;
            else failed = true;
            break;
          case 'BACKREF': {
            const first = current[2 * instruction.group!];
            const last = current[2 * instruction.group! + 1];
            if (first === null || last === null || first > last || q + last - first > this.text.length) {
              failed = true;
              break;
            }
            const length = last - first;
            for (let index = 0; index < length; index++) {
              if (!charset.same(this.text.charCodeAt(q + index), this.text.charCodeAt(first + index), this.flags)) {
                failed = true;
                break;
              }
            }
            if (!failed) {
              q += length;
              p++;
              if (length > 0) visited = new Set<number>();
            }
            break;
          }
          case 'LOOK': {
            const result = this.execute(p + 1, q, current, true);
            if (instruction.kind === 'NOT') {
              if (result === null) p = instruction.x!;
              else failed = true;
            } else if (result === null) failed = true;
            else {
              current = result.captures;
              if (instruction.kind === 'ATOMIC') {
                if (result.position > q) visited = new Set<number>();
                q = result.position;
              }
              p = instruction.x!;
            }
            break;
          }
          case 'MATCH':
            if (partial || !this.full || q === this.text.length) return {captures: current, position: q};
            failed = true;
            break;
        }
      }
    }
    return null;
  }

  search(start: number, full: boolean): Captures | null {
    this.full = full;
    const first = full ? 0 : start;
    const last = full ? 0 : this.text.length;
    for (let position = first; position <= last; position++) {
      const captures = Array(2 * this.groups + 2).fill(null);
      const result = this.execute(0, position, captures, false);
      if (result !== null) return result.captures;
    }
    return null;
  }
}

