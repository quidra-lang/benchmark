import type { Parameters, LayoutBlock, PageLine, RawPage, BrokenText } from './main.ts';
interface Break {
  end: number;
  next: number;
  forced: boolean;
}
function prepare(blocks: LayoutBlock[], parameters: Parameters) {
  const lines: PageLine[] = [];
  const breaks: Break[] = [];
  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i];
    if (i > 0) {
      const previous = blocks[i - 1];
      const end = lines.length;
      if (!previous.list || !block.list) lines.push({ text: '', footnotes: [], marks: [] });
      if (block.pageBreak || previous.type !== 'heading') {
        breaks.push({ end, next: lines.length, forced: block.pageBreak });
      }
    }
    const start = lines.length;
    lines.push(...block.lines);
    if (block.type === 'flow') {
      for (let count = 1; count < block.lines.length; count++) {
        if (
          count >= parameters.orphan_lines &&
          block.lines.length - count >= parameters.widow_lines
        ) {
          breaks.push({ end: start + count, next: start + count, forced: false });
        }
      }
    }
  }
  if (lines.length) breaks.push({ end: lines.length, next: lines.length, forced: true });
  return { lines, breaks };
}
export function choosePages(
  blocks: LayoutBlock[],
  height: number,
  parameters: Parameters,
  footnotes: Map<number, BrokenText>,
): RawPage[] {
  const prepared = prepare(blocks, parameters);
  const pages: RawPage[] = [];
  let start = 0;
  let firstBreak = 0;
  while (start < prepared.lines.length) {
    const notes = new Set<number>();
    let noteHeight = 0;
    let examined = start;
    let best: { candidate: Break; index: number; height: number; notes: number[] } | null = null;
    for (let i = firstBreak; i < prepared.breaks.length; i++) {
      const candidate = prepared.breaks[i];
      while (examined < candidate.end) {
        for (const number of prepared.lines[examined].footnotes) {
          if (!notes.has(number)) {
            notes.add(number);
            noteHeight += footnotes.get(number)!.lines.length;
          }
        }
        examined++;
      }
      const used = candidate.end - start + (notes.size ? 1 + noteHeight : 0);
      if (used <= height) {
        best = { candidate, index: i, height: used, notes: [...notes].sort((a, b) => a - b) };
      }
      if (candidate.forced) break;
    }
    if (best === null) throw new Error('No feasible page break');
    const { candidate, index } = best;
    pages.push({
      content: prepared.lines.slice(start, candidate.end),
      footnotes: best.notes,
      height: best.height,
      endsByForce: candidate.forced,
      blank: false,
    });
    start = candidate.next;
    firstBreak = index + 1;
  }
  return pages;
}
