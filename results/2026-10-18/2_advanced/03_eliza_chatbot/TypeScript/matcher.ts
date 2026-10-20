import { isWildcard, type Group } from './script_loader.ts';

export type Bindings = string[][];
export function match(pattern: string[], words: string[], groups: Map<string, Group>): Bindings | undefined {
  const failed = new Set<string>();
  function search(p: number, w: number): Bindings | undefined {
    const key = `${p}/${w}`;
    if (failed.has(key)) return undefined;
    if (p === pattern.length) return w === words.length ? [] : undefined;
    const element = pattern[p];
    if (element === '*') {
      for (let end = w; end <= words.length; end++) {
        const tail = search(p + 1, end);
        if (tail !== undefined) return [words.slice(w, end), ...tail];
      }
    } else if (w < words.length && (element === '#' || element === words[w]
      || element.startsWith('@') && groups.get(element.slice(1))?.members.has(words[w]))) {
      const tail = search(p + 1, w + 1);
      if (tail !== undefined) return isWildcard(element) ? [[words[w]], ...tail] : tail;
    }
    failed.add(key); return undefined;
  }
  return search(0, 0);
}
export function covers(earlier: string[], later: string[], groups: Map<string, Group>): boolean {
  const memo = new Map<string, boolean>();
  function search(p: number, r: number): boolean {
    const key = `${p}/${r}`, cached = memo.get(key);
    if (cached !== undefined) return cached;
    if (p === earlier.length) return r === later.length;
    const element = earlier[p], other = later[r];
    let result = false;
    if (element === '*') {
      for (let end = r; end <= later.length && !result; end++) result = search(p + 1, end);
    } else if (r < later.length) {
      let accepts = element === '#' ? other !== '*' : element === other && !element.startsWith('@');
      if (element.startsWith('@')) {
        const members = groups.get(element.slice(1))!.members;
        accepts = other.startsWith('@') ? [...groups.get(other.slice(1))!.members].every(word => members.has(word)) : members.has(other);
      }
      result = accepts && search(p + 1, r + 1);
    }
    memo.set(key, result); return result;
  }
  return search(0, 0);
}
