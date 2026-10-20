'use strict';

const text = value => ({ kind: 'text', value });
const line = { kind: 'line' }, softline = { kind: 'softline' }, hardline = { kind: 'hardline' }, breakParent = { kind: 'break_parent' };
const suffix = value => ({ kind: 'suffix', value });
const ifBreak = (broken, flat) => ({ kind: 'if_break', broken, flat });

function cat(...values) {
  const parts = [];
  const append = value => {
    if (value === null || value === undefined) return;
    if (Array.isArray(value)) { value.forEach(append); return; }
    if (typeof value === 'string') { append(text(value)); return; }
    if (value.kind === 'concat') { value.parts.forEach(append); return; }
    if (value.kind === 'text') {
      if (value.value === '') return;
      if (parts.length && parts[parts.length - 1].kind === 'text') {
        parts[parts.length - 1] = text(parts[parts.length - 1].value + value.value); return;
      }
    }
    parts.push(value);
  };
  values.forEach(append);
  return parts.length === 0 ? text('') : parts.length === 1 ? parts[0] : { kind: 'concat', parts };
}

function forceBroken(document) {
  if (document.kind === 'hardline' || document.kind === 'break_parent') return true;
  if (document.kind === 'concat') return document.parts.some(forceBroken);
  if (document.child) return forceBroken(document.child);
  return false;
}

function group(...parts) { const child = cat(...parts); return { kind: 'group', child, forced: forceBroken(child), mode: null }; }
const nest = (indent, ...parts) => ({ kind: 'nest', indent, child: cat(...parts) });
const align = (...parts) => ({ kind: 'align', child: cat(...parts) });

function groups(document) {
  const result = [];
  const visit = node => {
    if (node.kind === 'group') result.push(node);
    if (node.kind === 'concat') node.parts.forEach(visit);
    else if (node.child) visit(node.child);
  };
  visit(document); return result;
}

module.exports = { text, cat, line, softline, hardline, breakParent, suffix, ifBreak, group, nest, align, forceBroken, groups };
