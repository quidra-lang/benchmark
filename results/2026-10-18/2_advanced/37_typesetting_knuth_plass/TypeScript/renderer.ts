import type { Alignment } from './document_parser.ts';
import type { BrokenLine, Page } from './main.ts';
export function displayLine(line: BrokenLine, alignment: Alignment): string {
  const text = line.pieces.join(' ');
  if (line.slack <= 0) return text;
  if (alignment === 'justify' && !line.last && line.gaps > 0) {
    const quotient = Math.floor(line.slack / line.gaps), remainder = line.slack % line.gaps;
    let result = line.pieces[0];
    for (let i = 1; i < line.pieces.length; i++) result += ' '.repeat(quotient + 1 + (i - 1 < remainder ? 1 : 0)) + line.pieces[i];
    return result;
  }
  if (alignment === 'right') return ' '.repeat(line.slack) + text;
  if (alignment === 'center') return ' '.repeat(Math.floor(line.slack / 2)) + text;
  return text;
}
export function tableRows(rows: string[][], columns: string): string[] {
  const widths = Array<number>(columns.length).fill(0), lines: string[] = [];
  for (const row of rows) row.forEach((text, i) => { widths[i] = Math.max(widths[i], text.length); });
  rows.forEach((row, r) => {
    const cells = row.map((text, c) => {
      const missing = widths[c] - text.length;
      if (columns[c] === 'r') return ' '.repeat(missing) + text;
      if (columns[c] === 'c') return ' '.repeat(Math.floor(missing / 2)) + text + ' '.repeat(missing - Math.floor(missing / 2));
      return text + ' '.repeat(missing);
    });
    lines.push(cells.join(' | ').trimEnd());
    if (r === 0) lines.push(widths.map(w => '-'.repeat(w)).join('-+-'));
  });
  return lines;
}
interface HeadValues { page: string; pages: string; chapter: string; section: string }
export function runningHead(fields: string[], values: HeadValues, width: number, serial: number): string {
  const expanded = fields.map(text => text.replace(/\{(page|pages|chapter|section)\}/g, (_, name: string) => {
    switch (name) { case 'page': return values.page; case 'pages': return values.pages;
      case 'chapter': return values.chapter; case 'section': return values.section; default: return ''; }
  }));
  if (serial % 2 === 0) [expanded[0], expanded[2]] = [expanded[2], expanded[0]];
  const line = Array<string>(width).fill(' '), starts = [0, Math.floor((width - expanded[1].length) / 2), width - expanded[2].length];
  expanded.forEach((field, f) => { for (let i = 0; i < field.length; i++) line[starts[f] + i] = field[i]; });
  return line.join('').trimEnd();
}
export function pageLines(pages: Page[]): string[] {
  return pages.flatMap(p => [`--- page ${p.serial} ---`, p.header, '', ...p.body, '', p.footer]);
}
