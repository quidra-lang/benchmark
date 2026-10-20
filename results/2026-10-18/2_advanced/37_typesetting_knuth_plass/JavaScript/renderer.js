'use strict';

function displayLine(line, alignment) {
  const text = line.pieces.join(' ');
  if (line.slack <= 0) return text;
  if (alignment === 'justify' && !line.last && line.gaps > 0) {
    const quotient = Math.floor(line.slack / line.gaps);
    const remainder = line.slack % line.gaps;
    let result = line.pieces[0];
    for (let index = 1; index < line.pieces.length; index++) {
      result += ' '.repeat(quotient + 1 + (index - 1 < remainder ? 1 : 0)) + line.pieces[index];
    }
    return result;
  }
  if (alignment === 'right') return ' '.repeat(line.slack) + text;
  if (alignment === 'center') return ' '.repeat(Math.floor(line.slack / 2)) + text;
  return text;
}

function tableRows(rows, columns) {
  const widths = Array(columns.length).fill(0);
  for (const row of rows) for (let index = 0; index < row.length; index++) widths[index] = Math.max(widths[index], row[index].length);
  const lines = [];
  for (let row = 0; row < rows.length; row++) {
    const cells = rows[row].map((text, column) => {
      const missing = widths[column] - text.length;
      if (columns[column] === 'r') return ' '.repeat(missing) + text;
      if (columns[column] === 'c') return ' '.repeat(Math.floor(missing / 2)) + text + ' '.repeat(missing - Math.floor(missing / 2));
      return text + ' '.repeat(missing);
    });
    lines.push(cells.join(' | ').replace(/ +$/, ''));
    if (row === 0) lines.push(widths.map(width => '-'.repeat(width)).join('-+-'));
  }
  return lines;
}

function runningHead(fields, values, width, serial) {
  const expanded = fields.map(text => text.replace(/\{(page|pages|chapter|section)\}/g, (match, name) => values[name]));
  if (serial % 2 === 0) [expanded[0], expanded[2]] = [expanded[2], expanded[0]];
  const line = Array(width).fill(' ');
  const starts = [0, Math.floor((width - expanded[1].length) / 2), width - expanded[2].length];
  for (let field = 0; field < 3; field++) {
    for (let index = 0; index < expanded[field].length; index++) line[starts[field] + index] = expanded[field][index];
  }
  return line.join('').replace(/ +$/, '');
}

function pageLines(pages) {
  const lines = [];
  for (const page of pages) lines.push(`--- page ${page.serial} ---`, page.header, '', ...page.body, '', page.footer);
  return lines;
}

module.exports = { displayLine, tableRows, runningHead, pageLines };
