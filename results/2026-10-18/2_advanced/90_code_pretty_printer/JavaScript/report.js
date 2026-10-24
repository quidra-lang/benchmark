'use strict';

function documentLines(document) {
  const lines = [];
  const visit = (node, depth) => {
    const indent = ' '.repeat(2 * depth);
    switch (node.kind) {
      case 'text': lines.push(indent + 'text "' + node.value + '"'); break;
      case 'suffix': lines.push(indent + 'suffix "' + node.value + '"'); break;
      case 'if_break': lines.push(indent + 'if_break "' + node.broken + '" "' + node.flat + '"'); break;
      case 'concat': node.parts.forEach(part => visit(part, depth)); break;
      case 'group': lines.push(indent + 'group ' + node.mode); visit(node.child, depth + 1); break;
      case 'nest': lines.push(indent + 'nest ' + node.indent); visit(node.child, depth + 1); break;
      case 'align': lines.push(indent + 'align'); visit(node.child, depth + 1); break;
      default: lines.push(indent + node.kind);
    }
  };
  visit(document, 0); return lines;
}

function diff(original, formatted) {
  const n = original.length, m = formatted.length, lcs = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) {
    lcs[i][j] = original[i] === formatted[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
  }
  const hunks = [];
  let i = 0, j = 0, current = null, deleted = 0, inserted = 0;
  while (i < n || j < m) {
    if (i < n && j < m && original[i] === formatted[j]) { current = null; i++; j++; continue; }
    if (current === null) { current = { i, j, deleted: 0, inserted: 0, lines: [] }; hunks.push(current); }
    if (j === m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1])) {
      current.lines.push('-' + original[i++]); current.deleted++; deleted++;
    } else { current.lines.push('+' + formatted[j++]); current.inserted++; inserted++; }
  }
  const lines = [`hunks=${hunks.length} deleted=${deleted} inserted=${inserted}`];
  for (const hunk of hunks) {
    const startA = hunk.i + (hunk.deleted > 0 ? 1 : 0), startB = hunk.j + (hunk.inserted > 0 ? 1 : 0);
    lines.push(`@@ -${startA},${hunk.deleted} +${startB},${hunk.inserted} @@`, ...hunk.lines);
  }
  return lines;
}

module.exports = { documentLines, diff };
