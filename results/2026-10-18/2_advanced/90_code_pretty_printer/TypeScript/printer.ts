import type { Doc, Frame, Profile, Mode } from './types.ts';

export function fits(remaining: number, first: Frame, stack: Frame[]): boolean {
  if (remaining < 0) return false;
  const work = stack.slice(); work.push(first);
  while (work.length) {
    const { indent, mode, document } = work.pop()!;
    switch (document.kind) {
      case 'text': remaining -= document.value.length; break;
      case 'if_break': remaining -= (mode === 'break' ? document.broken : document.flat).length; break;
      case 'line': if (mode === 'break') return true; remaining--; break;
      case 'softline': if (mode === 'break') return true; break;
      case 'hardline': return true;
      case 'concat':
        for (let i = document.parts.length - 1; i >= 0; i--) work.push({ indent, mode, document: document.parts[i] });
        break;
      case 'group': work.push({ indent, mode: document.forced ? 'break' : mode, document: document.child }); break;
      case 'nest': case 'align': work.push({ indent, mode, document: document.child }); break;
    }
    if (remaining < 0) return false;
  }
  return true;
}

export function layout(document: Doc, profile: Profile): string[] {
  const lines: string[] = [], pending: string[] = [];
  const stack: Frame[] = [{ indent: 0, mode: 'break', document }];
  let current = '', column = 0;
  const append = (value: string): void => { current += value; column += value.length; };
  const finalize = (): void => {
    let value = current.replace(/ +$/, '');
    if (pending.length) {
      const comments = pending.join(' '), target = profile.comment_column - 1;
      value += profile.comment_column > 0 && value.length < target && target + comments.length <= profile.width
        ? ' '.repeat(target - value.length) + comments : ' ' + comments;
      pending.length = 0;
    }
    lines.push(value);
  };
  while (stack.length) {
    const { indent, mode, document: node } = stack.pop()!;
    const newline = (): void => { finalize(); current = ' '.repeat(indent); column = indent; };
    switch (node.kind) {
      case 'text': append(node.value); break;
      case 'if_break': append(mode === 'break' ? node.broken : node.flat); break;
      case 'line': if (mode === 'flat') append(' '); else newline(); break;
      case 'softline': if (mode === 'break') newline(); break;
      case 'hardline': newline(); break;
      case 'concat':
        for (let i = node.parts.length - 1; i >= 0; i--) stack.push({ indent, mode, document: node.parts[i] });
        break;
      case 'nest': stack.push({ indent: indent + node.indent, mode, document: node.child }); break;
      case 'align': stack.push({ indent: column, mode, document: node.child }); break;
      case 'suffix': pending.push(node.value); break;
      case 'group': {
        let chosen: Mode | 'forced';
        if (mode === 'flat') chosen = 'flat';
        else if (node.forced) chosen = 'forced';
        else chosen = fits(profile.width - column, { indent, mode: 'flat', document: node.child }, stack) ? 'flat' : 'break';
        node.mode = chosen;
        stack.push({ indent, mode: chosen === 'flat' ? 'flat' : 'break', document: node.child }); break;
      }
    }
  }
  finalize(); return lines;
}

