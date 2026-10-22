import { readFileSync } from 'node:fs';

const DATA_COMMANDS = new Set(['FILE', 'PATCH', 'EDIT']);
const FORMATS_WITH_ARGUMENT = new Set(['IFDEF', 'UNIFIED', 'CONTEXT', 'SIDE']);
const OFFSETS = [0, 1, -1, 2, -2, 3, -3];
const GRAPH_WIDTH = 20;
const NUMBER_PAIR = /^([0-9]{1,4})(?:,([0-9]{1,4}))?$/;
const MARKER_PREFIXES = new Map([
  ['<<<<<<<', 'start'],
  ['|||||||', 'base'],
  ['>>>>>>>', 'end'],
]);
const SEPARATOR = '=======';

class CommandError extends Error {}

function rangeR(start, count) {
  if (count >= 2) {
    return `${start + 1},${start + count}`;
  }
  if (count === 1) {
    return String(start + 1);
  }
  return String(start);
}

function rangeU(start, count) {
  if (count >= 2) {
    return `${start + 1},${count}`;
  }
  if (count === 1) {
    return String(start + 1);
  }
  return `${start},0`;
}

function rangeM(start, count) {
  return `${start + 1},${count}`;
}

function comparisonKey(line, options) {
  let key = line;
  if (options.includes('ICASE')) {
    key = key.toLowerCase();
  }
  if (options.includes('IWHITE')) {
    key = key.replaceAll(' ', '');
  }
  if (options.includes('ISPACE')) {
    key = key.replace(/ {2,}/g, ' ');
  }
  return key;
}

function equalLines(first, second) {
  return first.length === second.length && first.every((line, index) => line === second[index]);
}

function matchedPairs(first, second) {
  const rows = first.length;
  const columns = second.length;
  const table = Array.from({ length: rows + 1 }, () => new Array(columns + 1).fill(0));
  for (let i = 1; i <= rows; i++) {
    for (let j = 1; j <= columns; j++) {
      if (first[i - 1] === second[j - 1]) {
        table[i][j] = table[i - 1][j - 1] + 1;
      } else {
        table[i][j] = Math.max(table[i - 1][j], table[i][j - 1]);
      }
    }
  }
  const pairs = [[rows + 1, columns + 1]];
  let i = rows;
  let j = columns;
  while (i >= 1 && j >= 1) {
    if (first[i - 1] === second[j - 1]) {
      pairs.push([i, j]);
      i--;
      j--;
    } else if (table[i - 1][j] >= table[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  pairs.push([0, 0]);
  return pairs.reverse();
}

class ChangeBlock {
  constructor(p, q, x, y) {
    this.p = p;
    this.q = q;
    this.x = x;
    this.y = y;
  }

  letter() {
    if (this.x >= 1 && this.y >= 1) {
      return 'c';
    }
    return this.y === 0 ? 'd' : 'a';
  }
}

function changeBlocks(first, second) {
  const pairs = matchedPairs(first, second);
  const blocks = [];
  for (let index = 0; index + 1 < pairs.length; index++) {
    const [i, j] = pairs[index];
    const [nextI, nextJ] = pairs[index + 1];
    if (nextI - i > 1 || nextJ - j > 1) {
      blocks.push(new ChangeBlock(i, j, nextI - i - 1, nextJ - j - 1));
    }
  }
  return blocks;
}

function walk(blocks, oldStart, newStart, oldEnd) {
  const steps = [];
  let oldIndex = oldStart;
  let newIndex = newStart;
  for (const block of blocks) {
    while (oldIndex < block.p) {
      steps.push({ oldIndex, newIndex, block: null });
      oldIndex++;
      newIndex++;
    }
    steps.push({ oldIndex, newIndex, block });
    oldIndex = block.p + block.x;
    newIndex = block.q + block.y;
  }
  while (oldIndex < oldEnd) {
    steps.push({ oldIndex, newIndex, block: null });
    oldIndex++;
    newIndex++;
  }
  return steps;
}

function sideRow(left, symbol, right, width) {
  return `${left.slice(0, width).padEnd(width)} ${symbol} ${right.slice(0, width)}`.trimEnd();
}

function statGraph(inserted, deleted) {
  const total = inserted + deleted;
  let plus = inserted;
  let minus = deleted;
  if (total > GRAPH_WIDTH) {
    plus = Math.floor((GRAPH_WIDTH * inserted) / total);
    minus = Math.floor((GRAPH_WIDTH * deleted) / total);
    if (inserted >= 1 && plus === 0) {
      plus = 1;
    }
    if (deleted >= 1 && minus === 0) {
      minus = 1;
    }
  }
  return '+'.repeat(plus) + '-'.repeat(minus);
}

class Hunk {
  constructor(blocks, context, oldTotal) {
    const first = blocks[0];
    const last = blocks.at(-1);
    const before = Math.min(context, first.p);
    const after = Math.min(context, oldTotal - last.p - last.x);
    this.blocks = blocks;
    this.oldStart = first.p - before;
    this.oldCount = last.p + last.x + after - this.oldStart;
    this.newStart = first.q - before;
    this.newCount = last.q + last.y + after - this.newStart;
  }

  steps() {
    return walk(this.blocks, this.oldStart, this.newStart, this.oldStart + this.oldCount);
  }
}

class LineDiff {
  constructor(oldLines, newLines, options = []) {
    this.oldLines = oldLines;
    this.newLines = newLines;
    this.blocks = changeBlocks(
      oldLines.map((line) => comparisonKey(line, options)),
      newLines.map((line) => comparisonKey(line, options)),
    );
  }

  deleted(block) {
    return this.oldLines.slice(block.p, block.p + block.x);
  }

  inserted(block) {
    return this.newLines.slice(block.q, block.q + block.y);
  }

  hunks(context) {
    const groups = [];
    for (const block of this.blocks) {
      const group = groups.at(-1);
      if (group) {
        const previous = group.at(-1);
        if (block.p - (previous.p + previous.x) <= 2 * context) {
          group.push(block);
          continue;
        }
      }
      groups.push([block]);
    }
    return groups.map((group) => new Hunk(group, context, this.oldLines.length));
  }

  normal() {
    const lines = [];
    for (const block of this.blocks) {
      const letter = block.letter();
      lines.push(rangeR(block.p, block.x) + letter + rangeR(block.q, block.y));
      lines.push(...this.deleted(block).map((line) => `< ${line}`));
      if (letter === 'c') {
        lines.push('---');
      }
      lines.push(...this.inserted(block).map((line) => `> ${line}`));
    }
    return lines;
  }

  ed() {
    const lines = [];
    for (const block of this.blocks.toReversed()) {
      const letter = block.letter();
      lines.push(rangeR(block.p, block.x) + letter);
      if (letter !== 'd') {
        lines.push(...this.inserted(block), '.');
      }
    }
    return lines;
  }

  rcs() {
    const lines = [];
    for (const block of this.blocks) {
      if (block.x >= 1) {
        lines.push(`d${block.p + 1} ${block.x}`);
      }
      if (block.y >= 1) {
        lines.push(`a${block.p + block.x} ${block.y}`, ...this.inserted(block));
      }
    }
    return lines;
  }

  ifdef(macro) {
    const lines = [];
    for (const { oldIndex, block } of walk(this.blocks, 0, 0, this.oldLines.length)) {
      if (block === null) {
        lines.push(this.oldLines[oldIndex]);
      } else if (block.x >= 1 && block.y >= 1) {
        lines.push(
          `#ifndef ${macro}`,
          ...this.deleted(block),
          `#else /* ${macro} */`,
          ...this.inserted(block),
          `#endif /* ${macro} */`,
        );
      } else if (block.y === 0) {
        lines.push(`#ifndef ${macro}`, ...this.deleted(block), `#endif /* ! ${macro} */`);
      } else {
        lines.push(`#ifdef ${macro}`, ...this.inserted(block), `#endif /* ${macro} */`);
      }
    }
    return lines;
  }

  unified(context, oldName, newName) {
    const lines = [`--- ${oldName}`, `+++ ${newName}`];
    for (const hunk of this.hunks(context)) {
      const oldRange = rangeU(hunk.oldStart, hunk.oldCount);
      const newRange = rangeU(hunk.newStart, hunk.newCount);
      lines.push(`@@ -${oldRange} +${newRange} @@`);
      for (const { oldIndex, block } of hunk.steps()) {
        if (block === null) {
          lines.push(` ${this.oldLines[oldIndex]}`);
        } else {
          lines.push(...this.deleted(block).map((line) => `-${line}`));
          lines.push(...this.inserted(block).map((line) => `+${line}`));
        }
      }
    }
    return lines;
  }

  context(context, oldName, newName) {
    const lines = [`*** ${oldName}`, `--- ${newName}`];
    for (const hunk of this.hunks(context)) {
      lines.push('*'.repeat(15), `*** ${rangeR(hunk.oldStart, hunk.oldCount)} ****`);
      if (hunk.blocks.some((block) => block.x >= 1)) {
        for (const { oldIndex, block } of hunk.steps()) {
          if (block === null) {
            lines.push(`  ${this.oldLines[oldIndex]}`);
          } else {
            const marker = block.y >= 1 ? '! ' : '- ';
            lines.push(...this.deleted(block).map((line) => marker + line));
          }
        }
      }
      lines.push(`--- ${rangeR(hunk.newStart, hunk.newCount)} ----`);
      if (hunk.blocks.some((block) => block.y >= 1)) {
        for (const { newIndex, block } of hunk.steps()) {
          if (block === null) {
            lines.push(`  ${this.newLines[newIndex]}`);
          } else {
            const marker = block.x >= 1 ? '! ' : '+ ';
            lines.push(...this.inserted(block).map((line) => marker + line));
          }
        }
      }
    }
    return lines;
  }

  sideBySide(width) {
    const lines = [];
    for (const { oldIndex, newIndex, block } of walk(this.blocks, 0, 0, this.oldLines.length)) {
      if (block === null) {
        lines.push(sideRow(this.oldLines[oldIndex], ' ', this.newLines[newIndex], width));
        continue;
      }
      for (let row = 0; row < Math.max(block.x, block.y); row++) {
        const left = row < block.x ? this.oldLines[block.p + row] : '';
        const right = row < block.y ? this.newLines[block.q + row] : '';
        let symbol = '>';
        if (row < block.x && row < block.y) {
          symbol = '|';
        } else if (row < block.x) {
          symbol = '<';
        }
        lines.push(sideRow(left, symbol, right, width));
      }
    }
    return lines;
  }
}

class TokenTotals {
  deleted = 0;
  inserted = 0;
  common = 0;
}

function splitTokens(line, byWord) {
  return byWord ? line.split(' ').filter((word) => word !== '') : [...line];
}

function deletion(tokens, separator) {
  return `[-${tokens.join(separator)}-]`;
}

function insertion(tokens, separator) {
  return `{+${tokens.join(separator)}+}`;
}

function compareTokens(oldTokens, newTokens, separator, totals) {
  const parts = [];
  const blocks = changeBlocks(oldTokens, newTokens);
  for (const { oldIndex, block } of walk(blocks, 0, 0, oldTokens.length)) {
    if (block === null) {
      parts.push(oldTokens[oldIndex]);
      totals.common++;
      continue;
    }
    if (block.x >= 1) {
      parts.push(deletion(oldTokens.slice(block.p, block.p + block.x), separator));
    }
    if (block.y >= 1) {
      parts.push(insertion(newTokens.slice(block.q, block.q + block.y), separator));
    }
    totals.deleted += block.x;
    totals.inserted += block.y;
  }
  return parts.join(separator);
}

class PatchHunk {
  constructor(lineNumber, oldStart, oldCount, newStart, newCount) {
    this.lineNumber = lineNumber;
    this.oldStart = oldStart;
    this.oldCount = oldCount;
    this.newStart = newStart;
    this.newCount = newCount;
    this.body = [];
  }

  sequences(reverse) {
    const oldKinds = reverse ? ' +' : ' -';
    const newKinds = reverse ? ' -' : ' +';
    const oldLines = this.body.filter(({ kind }) => oldKinds.includes(kind));
    const newLines = this.body.filter(({ kind }) => newKinds.includes(kind));
    return [oldLines.map(({ text }) => text), newLines.map(({ text }) => text)];
  }

  start(reverse) {
    return reverse ? this.newStart : this.oldStart;
  }

  leadingContext() {
    let count = 0;
    while (count < this.body.length && this.body[count].kind === ' ') {
      count++;
    }
    return count;
  }

  trailingContext() {
    let count = 0;
    while (count < this.body.length && this.body[this.body.length - 1 - count].kind === ' ') {
      count++;
    }
    return count;
  }
}

class HunkMatch {
  constructor(fuzz, delta, position, lines) {
    this.fuzz = fuzz;
    this.delta = delta;
    this.position = position;
    this.lines = lines;
  }

  report(number) {
    let text = `Hunk #${number} succeeded at ${this.position + 1}`;
    if (this.fuzz >= 1) {
      text += ` with fuzz ${this.fuzz}`;
    }
    if (Math.abs(this.delta) === 1) {
      text += ` (offset ${this.delta} line)`;
    } else if (this.delta !== 0) {
      text += ` (offset ${this.delta} lines)`;
    }
    return text;
  }
}

function parseRange(text, sign) {
  if (!text.startsWith(sign)) {
    return null;
  }
  const match = NUMBER_PAIR.exec(text.slice(1));
  if (match === null) {
    return null;
  }
  const start = Number(match[1]);
  const count = match[2] === undefined ? 1 : Number(match[2]);
  if (start === 0 && count !== 0) {
    return null;
  }
  return { start, count };
}

function parseHunkHeader(line, lineNumber) {
  const parts = line.split(' ');
  let oldRange = null;
  let newRange = null;
  if (parts.length === 4 && parts[0] === '@@' && parts[3] === '@@') {
    oldRange = parseRange(parts[1], '-');
    newRange = parseRange(parts[2], '+');
  }
  if (oldRange === null || newRange === null) {
    throw new CommandError(`PATCH ERROR line ${lineNumber}: bad hunk header`);
  }
  return new PatchHunk(lineNumber, oldRange.start, oldRange.count, newRange.start, newRange.count);
}

function parsePatch(patchLines) {
  let index = patchLines.findIndex((line) => line.startsWith('@@'));
  if (index === -1) {
    throw new CommandError('PATCH ERROR no hunks');
  }
  const hunks = [];
  while (index < patchLines.length) {
    const hunk = parseHunkHeader(patchLines[index], index + 1);
    index++;
    let oldSeen = 0;
    let newSeen = 0;
    while (oldSeen < hunk.oldCount || newSeen < hunk.newCount) {
      if (index === patchLines.length) {
        throw new CommandError(`PATCH ERROR line ${hunk.lineNumber}: truncated hunk`);
      }
      const line = patchLines[index];
      const kind = line[0];
      const inOld = kind === ' ' || kind === '-';
      const inNew = kind === ' ' || kind === '+';
      if (
        line.length < 2 ||
        !(inOld || inNew) ||
        (inOld && oldSeen === hunk.oldCount) ||
        (inNew && newSeen === hunk.newCount)
      ) {
        throw new CommandError(`PATCH ERROR line ${index + 1}: bad hunk line`);
      }
      hunk.body.push({ kind, text: line.slice(1) });
      if (inOld) {
        oldSeen++;
      }
      if (inNew) {
        newSeen++;
      }
      index++;
    }
    if (hunk.body.every(({ kind }) => kind === ' ')) {
      throw new CommandError(`PATCH ERROR line ${hunk.lineNumber}: no changes`);
    }
    hunks.push(hunk);
  }
  return hunks;
}

function searchHunk(hunk, lines, adjustment, reverse, maxFuzz) {
  const [oldLines, newLines] = hunk.sequences(reverse);
  const start = hunk.start(reverse);
  const expected = oldLines.length > 0 ? start - 1 + adjustment : start + adjustment;
  const leading = hunk.leadingContext();
  const trailing = hunk.trailingContext();
  for (let fuzz = 0; fuzz <= maxFuzz; fuzz++) {
    const head = Math.min(fuzz, leading);
    const tail = Math.min(fuzz, trailing);
    const oldPart = oldLines.slice(head, oldLines.length - tail);
    const newPart = newLines.slice(head, newLines.length - tail);
    for (const delta of OFFSETS) {
      const position = expected + head + delta;
      const end = position + oldPart.length;
      if (position < 0 || end > lines.length) {
        continue;
      }
      if (equalLines(lines.slice(position, end), oldPart)) {
        const result = [...lines.slice(0, position), ...newPart, ...lines.slice(end)];
        return new HunkMatch(fuzz, delta, position, result);
      }
    }
  }
  return null;
}

function parseEditCommand(line) {
  const instruction = line.at(-1);
  const match = NUMBER_PAIR.exec(line.slice(0, -1));
  if (!['a', 'c', 'd'].includes(instruction) || match === null) {
    return null;
  }
  if (instruction === 'a' && match[2] !== undefined) {
    return null;
  }
  const first = Number(match[1]);
  const last = match[2] === undefined ? first : Number(match[2]);
  return { instruction, first, last };
}

function runEditScript(original, script) {
  const lines = [...original];
  let executed = 0;
  let index = 0;
  while (index < script.length) {
    const lineNumber = index + 1;
    const command = parseEditCommand(script[index]);
    if (command === null) {
      throw new CommandError(`EDIT ERROR line ${lineNumber}: bad command`);
    }
    const { instruction, first, last } = command;
    const valid =
      instruction === 'a'
        ? first <= lines.length
        : 1 <= first && first <= last && last <= lines.length;
    if (!valid) {
      throw new CommandError(`EDIT ERROR line ${lineNumber}: bad range`);
    }
    index++;
    let text = [];
    if (instruction === 'a' || instruction === 'c') {
      let end = index;
      while (end < script.length && script[end] !== '.') {
        end++;
      }
      if (end === script.length) {
        throw new CommandError(`EDIT ERROR line ${lineNumber}: missing terminator`);
      }
      text = script.slice(index, end);
      index = end + 1;
    }
    if (instruction === 'a') {
      lines.splice(first, 0, ...text);
    } else if (instruction === 'c') {
      lines.splice(first - 1, last - first + 1, ...text);
    } else {
      lines.splice(first - 1, last - first + 1);
    }
    executed++;
  }
  return { lines, executed };
}

class Chunk {
  constructor(kind, baseStart, oursStart, theirsStart, base, ours, theirs) {
    this.kind = kind;
    this.baseStart = baseStart;
    this.oursStart = oursStart;
    this.theirsStart = theirsStart;
    this.base = base;
    this.ours = ours;
    this.theirs = theirs;
  }

  location() {
    return (
      `base ${rangeM(this.baseStart, this.base.length)}` +
      ` a ${rangeM(this.oursStart, this.ours.length)}` +
      ` b ${rangeM(this.theirsStart, this.theirs.length)}`
    );
  }
}

function chunkKind(base, ours, theirs) {
  if (equalLines(ours, base)) {
    return 'b';
  }
  if (equalLines(theirs, base)) {
    return 'a';
  }
  if (equalLines(ours, theirs)) {
    return 'both';
  }
  return 'conflict';
}

function matchTable(first, second) {
  const matches = new Array(first.length + 2).fill(0);
  for (const [i, j] of matchedPairs(first, second).slice(1, -1)) {
    matches[i] = j;
  }
  return matches;
}

function threeWayChunks(base, ours, theirs) {
  const oursMatch = matchTable(base, ours);
  const theirsMatch = matchTable(base, theirs);
  const chunks = [];
  let x = 0;
  let y = 0;
  let z = 0;
  while (x < base.length || y < ours.length || z < theirs.length) {
    if (x < base.length && oursMatch[x + 1] === y + 1 && theirsMatch[x + 1] === z + 1) {
      const stable = [base.slice(x, x + 1), ours.slice(y, y + 1), theirs.slice(z, z + 1)];
      chunks.push(new Chunk('stable', x, y, z, ...stable));
      x++;
      y++;
      z++;
      continue;
    }
    let anchor = x + 1;
    while (anchor <= base.length && (oursMatch[anchor] === 0 || theirsMatch[anchor] === 0)) {
      anchor++;
    }
    const [nextX, nextY, nextZ] =
      anchor <= base.length
        ? [anchor - 1, oursMatch[anchor] - 1, theirsMatch[anchor] - 1]
        : [base.length, ours.length, theirs.length];
    const basePart = base.slice(x, nextX);
    const oursPart = ours.slice(y, nextY);
    const theirsPart = theirs.slice(z, nextZ);
    const kind = chunkKind(basePart, oursPart, theirsPart);
    chunks.push(new Chunk(kind, x, y, z, basePart, oursPart, theirsPart));
    [x, y, z] = [nextX, nextY, nextZ];
  }
  return chunks;
}

function kindCounts(chunks) {
  const counts = { a: 0, b: 0, both: 0, conflict: 0 };
  for (const chunk of chunks) {
    if (chunk.kind !== 'stable') {
      counts[chunk.kind]++;
    }
  }
  return `a=${counts.a} b=${counts.b} both=${counts.both} conflicts=${counts.conflict}`;
}

function commonPrefixLength(first, second) {
  let length = 0;
  while (length < first.length && length < second.length && first[length] === second[length]) {
    length++;
  }
  return length;
}

function commonSuffixLength(first, second, limit) {
  let length = 0;
  while (
    length < limit &&
    first[first.length - 1 - length] === second[second.length - 1 - length]
  ) {
    length++;
  }
  return length;
}

function conflictLines(chunk, mode, baseName, oursName, theirsName) {
  const { base, ours, theirs } = chunk;
  if (mode === 'OURS') {
    return ours;
  }
  if (mode === 'THEIRS') {
    return theirs;
  }
  if (mode === 'DIFF3') {
    return [
      `<<<<<<< ${oursName}`,
      ...ours,
      `||||||| ${baseName}`,
      ...base,
      SEPARATOR,
      ...theirs,
      `>>>>>>> ${theirsName}`,
    ];
  }
  const head = commonPrefixLength(ours, theirs);
  const tail = commonSuffixLength(ours, theirs, Math.min(ours.length, theirs.length) - head);
  const oursMiddle = ours.slice(head, ours.length - tail);
  const theirsMiddle = theirs.slice(head, theirs.length - tail);
  const middle =
    mode === 'UNION'
      ? [...oursMiddle, ...theirsMiddle]
      : [
          `<<<<<<< ${oursName}`,
          ...oursMiddle,
          SEPARATOR,
          ...theirsMiddle,
          `>>>>>>> ${theirsName}`,
        ];
  return [...ours.slice(0, head), ...middle, ...ours.slice(ours.length - tail)];
}

function markerKind(line) {
  if (line === SEPARATOR) {
    return 'separator';
  }
  const prefix = line.slice(0, 7);
  if (MARKER_PREFIXES.has(prefix) && (line.length === 7 || line[7] === ' ')) {
    return MARKER_PREFIXES.get(prefix);
  }
  return null;
}

function nextMarker(lines, index) {
  let next = index + 1;
  while (next < lines.length && markerKind(lines[next]) === null) {
    next++;
  }
  return next;
}

class ConflictRegion {
  constructor(start, end, ours, base, theirs) {
    this.start = start;
    this.end = end;
    this.ours = ours;
    this.base = base;
    this.theirs = theirs;
  }

  part(side) {
    if (side === 'OURS') {
      return this.ours;
    }
    if (side === 'THEIRS') {
      return this.theirs;
    }
    if (side === 'BASE') {
      return this.base;
    }
    return [...this.ours, ...this.theirs];
  }
}

function regionAt(lines, start) {
  if (markerKind(lines[start]) !== 'start') {
    return null;
  }
  let middle = nextMarker(lines, start);
  let baseMarker = null;
  if (middle < lines.length && markerKind(lines[middle]) === 'base') {
    baseMarker = middle;
    middle = nextMarker(lines, middle);
  }
  if (middle === lines.length || markerKind(lines[middle]) !== 'separator') {
    return null;
  }
  const end = nextMarker(lines, middle);
  if (end === lines.length || markerKind(lines[end]) !== 'end') {
    return null;
  }
  const theirs = lines.slice(middle + 1, end);
  if (baseMarker === null) {
    return new ConflictRegion(start + 1, end + 1, lines.slice(start + 1, middle), null, theirs);
  }
  const ours = lines.slice(start + 1, baseMarker);
  const base = lines.slice(baseMarker + 1, middle);
  return new ConflictRegion(start + 1, end + 1, ours, base, theirs);
}

function conflictRegions(lines) {
  const regions = [];
  let index = 0;
  while (index < lines.length) {
    const region = regionAt(lines, index);
    if (region === null) {
      index++;
    } else {
      regions.push(region);
      index = region.end;
    }
  }
  return regions;
}

class Workspace {
  files = new Map();
  history = new Map();
  output = [];
  handlers = {
    FILE: (args, data) => this.loadFile(args, data),
    COPY: (args) => this.copy(args),
    PRINT: (args) => this.printFile(args),
    FILES: () => this.listFiles(),
    DIFF: (args) => this.diff(args),
    WORDDIFF: (args) => this.tokenDiff(args, true),
    CHARDIFF: (args) => this.tokenDiff(args, false),
    STAT: (args) => this.stat(args),
    PATCH: (args, data) => this.patch(args, data),
    EDIT: (args, data) => this.edit(args, data),
    DIFF3: (args) => this.diff3(args),
    MERGE: (args) => this.merge(args),
    CONFLICTS: (args) => this.conflicts(args),
    RESOLVE: (args) => this.resolve(args),
    UNDO: (args) => this.undo(args),
  };

  emit(...lines) {
    this.output.push(...lines);
  }

  contents(...names) {
    return names.map((name) => {
      if (!this.files.has(name)) {
        throw new CommandError(`ERROR no such file ${name}`);
      }
      return this.files.get(name);
    });
  }

  save(name, lines) {
    const states = this.history.get(name) ?? [];
    states.push(this.files.get(name) ?? null);
    this.history.set(name, states);
    this.files.set(name, [...lines]);
  }

  loadFile([name], data) {
    this.save(name, data);
    this.emit(`FILE ${name} lines=${data.length}`);
  }

  copy([source, target]) {
    const [lines] = this.contents(source);
    this.save(target, lines);
    this.emit(`COPY ${source} ${target} lines=${lines.length}`);
  }

  printFile([name]) {
    const [lines] = this.contents(name);
    this.emit(`PRINT ${name} lines=${lines.length}`);
    lines.forEach((line, index) => {
      this.emit(`${String(index + 1).padStart(3)}| ${line}`);
    });
  }

  listFiles() {
    this.emit(`FILES count=${this.files.size}`);
    for (const name of [...this.files.keys()].sort()) {
      const lines = this.files.get(name);
      this.emit(`${name} lines=${lines.length} undo=${this.history.get(name).length}`);
    }
  }

  undo([name]) {
    const state = this.history.get(name)?.pop();
    if (state === undefined) {
      throw new CommandError(`ERROR nothing to undo ${name}`);
    }
    if (state === null) {
      this.files.delete(name);
      this.emit(`UNDO ${name} removed`);
    } else {
      this.files.set(name, state);
      this.emit(`UNDO ${name} lines=${state.length}`);
    }
  }

  diff(args) {
    const [oldName, newName, form] = args;
    const [oldLines, newLines] = this.contents(oldName, newName);
    const hasParameter = FORMATS_WITH_ARGUMENT.has(form);
    const parameter = hasParameter ? args[3] : '';
    const diff = new LineDiff(oldLines, newLines, args.slice(hasParameter ? 4 : 3));
    if (diff.blocks.length === 0) {
      this.emit(`Files ${oldName} and ${newName} are identical`);
      return;
    }
    switch (form) {
      case 'BRIEF':
        this.emit(`Files ${oldName} and ${newName} differ`);
        break;
      case 'NORMAL':
        this.emit(...diff.normal());
        break;
      case 'ED':
        this.emit(...diff.ed());
        break;
      case 'RCS':
        this.emit(...diff.rcs());
        break;
      case 'IFDEF':
        this.emit(...diff.ifdef(parameter));
        break;
      case 'UNIFIED':
        this.emit(...diff.unified(Number(parameter), oldName, newName));
        break;
      case 'CONTEXT':
        this.emit(...diff.context(Number(parameter), oldName, newName));
        break;
      default:
        this.emit(...diff.sideBySide(Number(parameter)));
    }
  }

  tokenDiff([oldName, newName], byWord) {
    const [oldLines, newLines] = this.contents(oldName, newName);
    const diff = new LineDiff(oldLines, newLines);
    if (diff.blocks.length === 0) {
      this.emit(`Files ${oldName} and ${newName} are identical`);
      return;
    }
    const separator = byWord ? ' ' : '';
    const totals = new TokenTotals();
    for (const block of diff.blocks) {
      for (let row = 0; row < Math.max(block.x, block.y); row++) {
        const oldNumber = block.p + row + 1;
        const newNumber = block.q + row + 1;
        if (row < block.x && row < block.y) {
          const oldTokens = splitTokens(oldLines[oldNumber - 1], byWord);
          const newTokens = splitTokens(newLines[newNumber - 1], byWord);
          const text = compareTokens(oldTokens, newTokens, separator, totals);
          this.emit(`a${oldNumber} b${newNumber}: ${text}`);
        } else if (row < block.x) {
          const oldTokens = splitTokens(oldLines[oldNumber - 1], byWord);
          totals.deleted += oldTokens.length;
          this.emit(`a${oldNumber}: ${deletion(oldTokens, separator)}`);
        } else {
          const newTokens = splitTokens(newLines[newNumber - 1], byWord);
          totals.inserted += newTokens.length;
          this.emit(`b${newNumber}: ${insertion(newTokens, separator)}`);
        }
      }
    }
    const label = byWord ? 'WORDS' : 'CHARS';
    this.emit(
      `${label} deleted=${totals.deleted} inserted=${totals.inserted} common=${totals.common}`,
    );
  }

  stat([oldName, newName, ...options]) {
    const [oldLines, newLines] = this.contents(oldName, newName);
    const diff = new LineDiff(oldLines, newLines, options);
    const deleted = diff.blocks.reduce((sum, block) => sum + block.x, 0);
    const inserted = diff.blocks.reduce((sum, block) => sum + block.y, 0);
    const total = deleted + inserted;
    const unchanged = oldLines.length - deleted;
    let summary = `${oldName} -> ${newName} | ${total}`;
    if (total > 0) {
      summary += ` ${statGraph(inserted, deleted)}`;
    }
    this.emit(summary);
    const lineTotal = oldLines.length + newLines.length;
    const similarity = lineTotal > 0 ? Math.floor((200 * unchanged) / lineTotal) : 100;
    this.emit(
      `changes=${diff.blocks.length} insertions=${inserted} deletions=${deleted}` +
        ` unchanged=${unchanged} similarity=${similarity}%`,
    );
  }

  patch([name, , ...options], data) {
    let [lines] = this.contents(name);
    const reverse = options.includes('REVERSE');
    const dryRun = options.includes('DRYRUN');
    const fuzzIndex = options.indexOf('FUZZ');
    const maxFuzz = fuzzIndex === -1 ? 0 : Number(options[fuzzIndex + 1]);
    const hunks = parsePatch(data);
    this.emit(`${dryRun ? 'checking' : 'patching'} file ${name}`);
    const [first] = hunks;
    if (
      searchHunk(first, lines, 0, reverse, maxFuzz) === null &&
      searchHunk(first, lines, 0, !reverse, maxFuzz) !== null
    ) {
      this.emit('Reversed (or previously applied) patch detected! Skipping patch.');
      this.emit(`RESULT applied=0 failed=0 ignored=${hunks.length} lines=${lines.length}`);
      return;
    }
    let adjustment = 0;
    let applied = 0;
    let failed = 0;
    for (const [index, hunk] of hunks.entries()) {
      const number = index + 1;
      const match = searchHunk(hunk, lines, adjustment, reverse, maxFuzz);
      if (match === null) {
        failed++;
        this.emit(`Hunk #${number} FAILED at ${hunk.start(reverse)}`);
        continue;
      }
      const [oldLines, newLines] = hunk.sequences(reverse);
      lines = match.lines;
      adjustment += match.delta + newLines.length - oldLines.length;
      applied++;
      this.emit(match.report(number));
    }
    this.emit(`RESULT applied=${applied} failed=${failed} ignored=0 lines=${lines.length}`);
    if (!dryRun && applied >= 1) {
      this.save(name, lines);
    }
  }

  edit([name], data) {
    const [original] = this.contents(name);
    const { lines, executed } = runEditScript(original, data);
    this.emit(`EDIT ${name} commands=${executed} lines=${lines.length}`);
    this.save(name, lines);
  }

  threeWay(baseName, oursName, theirsName) {
    const [base, ours, theirs] = this.contents(baseName, oursName, theirsName);
    return threeWayChunks(base, ours, theirs);
  }

  diff3([baseName, oursName, theirsName]) {
    const chunks = this.threeWay(baseName, oursName, theirsName);
    const changes = chunks.filter((chunk) => chunk.kind !== 'stable');
    for (const chunk of changes) {
      this.emit(`==== ${chunk.kind} ${chunk.location()}`);
      this.emit(...chunk.base.map((line) => `O ${line}`));
      if (chunk.kind !== 'b') {
        this.emit(...chunk.ours.map((line) => `A ${line}`));
      }
      if (chunk.kind === 'b' || chunk.kind === 'conflict') {
        this.emit(...chunk.theirs.map((line) => `B ${line}`));
      }
    }
    this.emit(`DIFF3 chunks=${changes.length} ${kindCounts(chunks)}`);
  }

  merge([baseName, oursName, theirsName, target, mode = 'MARKERS']) {
    const chunks = this.threeWay(baseName, oursName, theirsName);
    const result = [];
    const conflicts = [];
    for (const chunk of chunks) {
      if (chunk.kind === 'b') {
        result.push(...chunk.theirs);
      } else if (chunk.kind === 'conflict') {
        result.push(...conflictLines(chunk, mode, baseName, oursName, theirsName));
        conflicts.push(chunk);
      } else {
        result.push(...chunk.ours);
      }
    }
    this.emit(`MERGE ${target} lines=${result.length} ${kindCounts(chunks)}`);
    conflicts.forEach((chunk, index) => {
      this.emit(`CONFLICT ${index + 1} ${chunk.location()}`);
    });
    this.save(target, result);
  }

  conflicts([name]) {
    const [lines] = this.contents(name);
    const regions = conflictRegions(lines);
    this.emit(`CONFLICTS ${name} count=${regions.length}`);
    regions.forEach((region, index) => {
      const base = region.base === null ? 'none' : region.base.length;
      this.emit(
        `${index + 1}: lines ${region.start}-${region.end} ours=${region.ours.length}` +
          ` base=${base} theirs=${region.theirs.length}`,
      );
    });
  }

  resolve([name, numberText, side]) {
    const [lines] = this.contents(name);
    const number = Number(numberText);
    const regions = conflictRegions(lines);
    if (regions.length < number) {
      throw new CommandError(`ERROR no conflict ${number} in ${name}`);
    }
    const region = regions[number - 1];
    if (side === 'BASE' && region.base === null) {
      throw new CommandError(`ERROR no base section in conflict ${number}`);
    }
    const content = [
      ...lines.slice(0, region.start - 1),
      ...region.part(side),
      ...lines.slice(region.end),
    ];
    const remaining = conflictRegions(content).length;
    this.emit(`RESOLVE ${name} ${number} ${side} lines=${content.length} remaining=${remaining}`);
    this.save(name, content);
  }

  execute([command, ...args], data) {
    try {
      this.handlers[command](args, data);
    } catch (error) {
      if (!(error instanceof CommandError)) {
        throw error;
      }
      this.emit(error.message);
    }
  }
}

function main() {
  const lines = readFileSync(0, 'utf8').split(/\r?\n/);
  const workspace = new Workspace();
  const commandCount = Number(lines[0]);
  let position = 1;
  for (let command = 0; command < commandCount; command++) {
    const words = lines[position].split(' ');
    position++;
    let data = [];
    if (DATA_COMMANDS.has(words[0])) {
      const count = Number(words[2]);
      data = lines.slice(position, position + count);
      position += count;
    }
    workspace.execute(words, data);
  }
  process.stdout.write(`${workspace.output.join('\n')}\n`);
}

main();
