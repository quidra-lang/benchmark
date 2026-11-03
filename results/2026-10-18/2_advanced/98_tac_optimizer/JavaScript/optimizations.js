'use strict';

const { variable, operation } = require('./tac_parser');

function fold(instruction) {
  const s = instruction;
  if (s.kind === 'if' && !variable(s.a) && !variable(s.b)) {
    return { changed: true, instruction: operation(s.op, s.a, s.b) ? { kind: 'goto', target: s.target, number: s.number } : null };
  }
  if (s.kind !== 'bin') return { changed: false, instruction: s };
  let value;
  if (!variable(s.a) && !variable(s.b)) {
    if ((s.op === '/' || s.op === '%') && s.b === 0) return { changed: false, instruction: s };
    value = operation(s.op, s.a, s.b);
    if (value < -2147483648 || value > 2147483647) return { changed: false, instruction: s };
  } else if (variable(s.a) !== variable(s.b)) {
    const constant = variable(s.a) ? s.b : s.a, name = variable(s.a) ? s.a : s.b;
    if ((s.op === '+' && constant === 0) || (s.op === '-' && s.b === 0)
        || (s.op === '*' && constant === 1) || (s.op === '/' && s.b === 1)) value = name;
    else if (s.op === '*' && constant === 0) value = 0;
    else return { changed: false, instruction: s };
  } else return { changed: false, instruction: s };
  return { changed: true, instruction: { kind: 'copy', dest: s.dest, a: value, number: s.number } };
}

function rewrite(fn, replacements) {
  fn.code = fn.code.flatMap(instruction => instruction.kind === 'label' || !replacements.has(instruction.number) ?
    [instruction] : replacements.get(instruction.number));
}

function eliminateExpressions(fn, groups) {
  const replacements = new Map(), results = [];
  for (const group of groups) {
    const temporary = '_t' + (++fn.temporary);
    for (const source of group.sources) replacements.set(source.number, [
      { ...source, dest: temporary }, { kind: 'copy', dest: source.dest, a: temporary }
    ]);
    for (const candidate of group.candidates) replacements.set(candidate.number, [
      { kind: 'copy', dest: candidate.dest, a: temporary, number: candidate.number }
    ]);
    results.push({ ...group, temporary });
  }
  rewrite(fn, replacements);
  return results;
}

function hoist(fn, analysis, loop, moving) {
  const header = analysis.byNumber.get(loop.header);
  const outside = header.predecessors.filter(n => !loop.blocks.has(n));
  const moved = new Set(moving.map(s => s.number)), replacements = new Map();
  let index, inserted, destination;
  if (loop.header !== 1 && outside.length === 1 && analysis.byNumber.get(outside[0]).successors.length === 1) {
    const preheader = analysis.byNumber.get(outside[0]), last = preheader.instructions[preheader.instructions.length - 1];
    index = fn.code.indexOf(last) + Number(!['goto', 'if'].includes(last.kind));
    inserted = moving; destination = 'B' + preheader.number;
  } else {
    const label = '_p' + (++fn.preheader); index = header.start;
    inserted = [{ kind: 'label', name: label }, ...moving]; destination = 'new ' + label;
    for (const n of outside) {
      const block = analysis.byNumber.get(n), last = block.instructions[block.instructions.length - 1];
      if (['goto', 'if'].includes(last.kind) && header.labels.includes(last.target)) replacements.set(last.number, { ...last, target: label });
    }
  }
  const code = [];
  for (let i = 0; i <= fn.code.length; i++) {
    if (i === index) code.push(...inserted);
    if (i === fn.code.length) break;
    const instruction = fn.code[i];
    if (instruction.kind === 'label') code.push(instruction);
    else if (!moved.has(instruction.number)) code.push(replacements.get(instruction.number) || instruction);
  }
  fn.code = code;
  return destination;
}

function removeUnreachable(fn, analysis) {
  const removedBlocks = analysis.blocks.filter(b => !analysis.reachable.has(b.number));
  const removedInstructions = new Set(removedBlocks.flatMap(b => b.instructions.map(s => s.number)));
  const removedBlockLabels = new Set(removedBlocks.flatMap(b => b.labels));
  const first = fn.code.filter(s => s.kind === 'label' ? !removedBlockLabels.has(s.name) : !removedInstructions.has(s.number));
  const jumps = [];
  for (let i = 0; i < first.length; i++) if (['goto', 'if'].includes(first[i].kind)) {
    for (let j = i + 1; j < first.length && first[j].kind === 'label'; j++) if (first[j].name === first[i].target) {
      jumps.push(first[i].number); break;
    }
  }
  const removedJumps = new Set(jumps), second = first.filter(s => s.kind === 'label' || !removedJumps.has(s.number));
  const targets = new Set(second.filter(s => ['goto', 'if'].includes(s.kind)).map(s => s.target));
  const labels = second.filter(s => s.kind === 'label' && !targets.has(s.name)).map(s => s.name);
  fn.code = second.filter(s => s.kind !== 'label' || targets.has(s.name));
  return { blocks: removedBlocks.map(b => b.number), jumps, labels };
}

module.exports = { fold, rewrite, eliminateExpressions, hoist, removeUnreachable };
