import * as fs from 'node:fs';
import {lexFile, punct} from './lexer.ts';

function findGuard(logicalLines) {
  const lines = logicalLines.filter(line => line.tokens.length);
  if (!lines.length) return null;
  const first = lines[0].tokens;
  const last = lines.at(-1).tokens;
  if (first.length !== 3 || !punct(first[0], '#') || first[1].spelling !== 'ifndef'
      || first[2].kind !== 'identifier' || last.length !== 2
      || !punct(last[0], '#') || last[1].spelling !== 'endif') return null;
  let depth = 0;
  for (let index = 0; index < lines.length; index++) {
    const name = lines[index].name;
    if (['if', 'ifdef', 'ifndef'].includes(name)) depth++;
    else if (['elif', 'elifdef', 'elifndef', 'else'].includes(name) && depth === 1) return null;
    else if (name === 'endif') {
      depth--;
      if (depth === 0 && index !== lines.length - 1) return null;
    }
  }
  return depth === 0 ? first[2].spelling : null;
}

class IncludeManager {
  declare files: any;
  declare order: any;
  constructor() {
    this.files = new Map();
    this.order = [];
  }

  search(name, quoted) {
    const candidates = quoted ? [name, `include/${name}`] : [`include/${name}`];
    for (const path of candidates) {
      if (fs.existsSync(`input/${path}`)) return path;
    }
    return null;
  }

  enter(path) {
    if (!this.files.has(path)) {
      const lexical = lexFile(fs.readFileSync(`input/${path}`, 'utf8'));
      this.files.set(path, {path, lines: lexical.lines, physicalLines: lexical.physicalLines,
        guard: findGuard(lexical.lines), once: false, entered: 0, skipped: 0,
        outputLines: 0, skippedLines: 0});
      this.order.push(path);
    }
    const file = this.files.get(path);
    file.entered++;
    return file;
  }
}

export {IncludeManager};
