import type { Doc, DocPart, GroupDoc } from './types.ts';

export const text = (value: string): Doc => ({ kind: 'text', value });
export const line: Doc = { kind: 'line' }, softline: Doc = { kind: 'softline' }, hardline: Doc = { kind: 'hardline' }, breakParent: Doc = { kind: 'break_parent' };
export const suffix = (value: string): Doc => ({ kind: 'suffix', value });
export const ifBreak = (broken: string, flat: string): Doc => ({ kind: 'if_break', broken, flat });

export function cat(...values: DocPart[]): Doc {
  const parts: Doc[] = [];
  const append = (value: DocPart): void => {
    if (value === null || value === undefined) return;
    if (Array.isArray(value)) { value.forEach(append); return; }
    if (typeof value === 'string') { append(text(value)); return; }
    if (value.kind === 'concat') { value.parts.forEach(append); return; }
    if (value.kind === 'text') {
      if (value.value === '') return;
      const previous = parts.at(-1);
      if (previous !== undefined && previous.kind === 'text') {
        parts[parts.length - 1] = text(previous.value + value.value); return;
      }
    }
    parts.push(value);
  };
  values.forEach(append);
  return parts.length === 0 ? text('') : parts.length === 1 ? parts[0] : { kind: 'concat', parts };
}

export function forceBroken(document: Doc): boolean {
  if (document.kind === 'hardline' || document.kind === 'break_parent') return true;
  if (document.kind === 'concat') return document.parts.some(forceBroken);
  if ('child' in document) return forceBroken(document.child);
  return false;
}

export function group(...parts: DocPart[]): GroupDoc { const child = cat(...parts); return { kind: 'group', child, forced: forceBroken(child), mode: null }; }
export const nest = (indent: number, ...parts: DocPart[]): Doc => ({ kind: 'nest', indent, child: cat(...parts) });
export const align = (...parts: DocPart[]): Doc => ({ kind: 'align', child: cat(...parts) });

export function groups(document: Doc): GroupDoc[] {
  const result: GroupDoc[] = [];
  const visit = (node: Doc): void => {
    if (node.kind === 'group') result.push(node);
    if (node.kind === 'concat') node.parts.forEach(visit);
    else if ('child' in node) visit(node.child);
  };
  visit(document); return result;
}

