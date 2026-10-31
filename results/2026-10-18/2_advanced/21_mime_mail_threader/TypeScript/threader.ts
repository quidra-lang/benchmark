export type SortKey = [number, number, string, number];
export interface ThreadMessage {
  number: number;
  id: string;
  references: string[];
  baseSubject: string;
  reply: boolean;
  key: SortKey;
}
export interface Container<T extends ThreadMessage> {
  id: string;
  message?: T;
  parent?: Container<T>;
  children: Container<T>[];
  subject?: string;
}
export function compareKeys(a: SortKey, b: SortKey): number {
  return a[0] - b[0] || a[1] - b[1] || (a[2] < b[2] ? -1 : a[2] > b[2] ? 1 : 0) || a[3] - b[3];
}
export function buildThreads<T extends ThreadMessage>(messages: T[]): Container<T>[] {
  const table = new Map<string, Container<T>>();
  const all: Container<T>[] = [];
  const create = (id: string): Container<T> => {
    const c: Container<T> = { id, children: [] };
    all.push(c);
    return c;
  };
  const get = (id: string): Container<T> => {
    let c = table.get(id);
    if (!c) {
      c = create(id);
      table.set(id, c);
    }
    return c;
  };
  const ancestor = (a: Container<T>, b: Container<T>): boolean => {
    for (let c: Container<T> | undefined = b; c; c = c.parent) if (c === a) return true;
    return false;
  };
  const link = (child: Container<T>, parent: Container<T>): void => {
    child.parent = parent;
    parent.children.push(child);
  };
  for (const message of messages) {
    const m = message.id ? get(message.id) : create('');
    m.message = message;
    const refs = message.references.map(get);
    for (let i = 0; i + 1 < refs.length; i++) {
      if (!refs[i + 1].parent && !ancestor(refs[i + 1], refs[i])) link(refs[i + 1], refs[i]);
    }
    if (m.parent) {
      m.parent.children.splice(m.parent.children.indexOf(m), 1);
      m.parent = undefined;
    }
    const last = refs.at(-1);
    if (last && !ancestor(m, last)) link(m, last);
  }
  const prune = (collection: Container<T>[], root: boolean): Container<T>[] => {
    const result: Container<T>[] = [];
    for (const c of collection) {
      c.children = prune(c.children, false);
      if (c.message || (root && c.children.length >= 2)) result.push(c);
      else {
        for (const child of c.children) {
          child.parent = c.parent;
          result.push(child);
        }
      }
    }
    return result;
  };
  let roots = prune(
    all.filter((c) => !c.parent),
    true,
  );
  const key = (c: Container<T>): SortKey =>
    c.message
      ? c.message.key
      : c.children.map(key).reduce((a, b) => (compareKeys(a, b) <= 0 ? a : b));
  const sort = (collection: Container<T>[]): void => {
    for (const c of collection) sort(c.children);
    collection.sort((a, b) => compareKeys(key(a), key(b)));
  };
  sort(roots);
  const groups = new Map<string, Container<T>[]>();
  for (const root of roots) {
    const subject = root.message ? root.message.baseSubject : root.children[0].message!.baseSubject;
    if (subject) {
      const group = groups.get(subject) ?? [];
      group.push(root);
      groups.set(subject, group);
    }
  }
  for (const [subject, group] of groups) {
    if (group.length < 2) continue;
    let target = group.find((c) => !c.message);
    if (!target) {
      const originals = group.filter((c) => c.message && !c.message.reply);
      if (originals.length === 1) target = originals[0];
    }
    if (!target) {
      target = create('');
      target.subject = subject;
      roots.push(target);
    }
    for (const c of group) {
      if (c === target) continue;
      roots = roots.filter((root) => root !== c);
      if (c.message) link(c, target);
      else for (const child of c.children) link(child, target);
    }
  }
  sort(roots);
  return roots;
}
