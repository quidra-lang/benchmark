'use strict';

function prepare(blocks, parameters) {
  const lines = [];
  const breaks = [];
  for (let index = 0; index < blocks.length; index++) {
    const block = blocks[index];
    if (index > 0) {
      const previous = blocks[index - 1];
      const end = lines.length;
      if (!previous.list || !block.list) lines.push({ text: '', footnotes: [], marks: [] });
      if (block.pageBreak || previous.type !== 'heading') breaks.push({ end, next: lines.length, forced: block.pageBreak });
    }
    const start = lines.length;
    lines.push(...block.lines);
    if (block.type === 'flow') {
      for (let count = 1; count < block.lines.length; count++) {
        if (count >= parameters.orphan_lines && block.lines.length - count >= parameters.widow_lines) {
          breaks.push({ end: start + count, next: start + count, forced: false });
        }
      }
    }
  }
  if (lines.length) breaks.push({ end: lines.length, next: lines.length, forced: true });
  return { lines, breaks };
}

function choosePages(blocks, height, parameters, footnotes) {
  const prepared = prepare(blocks, parameters);
  const pages = [];
  let start = 0;
  let firstBreak = 0;
  while (start < prepared.lines.length) {
    const notes = new Set();
    let noteHeight = 0;
    let examined = start;
    let best = null;
    for (let index = firstBreak; index < prepared.breaks.length; index++) {
      const candidate = prepared.breaks[index];
      while (examined < candidate.end) {
        for (const number of prepared.lines[examined].footnotes) {
          if (!notes.has(number)) {
            notes.add(number);
            noteHeight += footnotes.get(number).lines.length;
          }
        }
        examined++;
      }
      const used = candidate.end - start + (notes.size ? 1 + noteHeight : 0);
      if (used <= height) best = { candidate, index, height: used, notes: [...notes].sort((a, b) => a - b) };
      if (candidate.forced) break;
    }
    const { candidate, index } = best;
    pages.push({ content: prepared.lines.slice(start, candidate.end), footnotes: best.notes,
      height: best.height, endsByForce: candidate.forced, blank: false });
    start = candidate.next;
    firstBreak = index + 1;
  }
  return pages;
}

module.exports = { choosePages };
