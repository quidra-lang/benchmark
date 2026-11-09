import { readFileSync } from 'node:fs';

export type ScalarType =
  'string' | 'int' | 'bool' | 'enum' | 'size' | 'duration' | 'host' | 'path' | 'url' | 'date';
export type ValueType = ScalarType | 'list';
export interface Spec {
  pattern: string;
  type: ValueType;
  key: string;
  parts: string[];
  wildcard: boolean;
  attributes: Map<string, string>;
  line: number;
}
export const compareText = (left: string, right: string) =>
  left < right ? -1 : left > right ? 1 : 0;
export function splitKey(key: string): [string, string] {
  const position = key.lastIndexOf('.');
  return [key.slice(0, position), key.slice(position + 1)];
}
export function compareKeys(left: string, right: string): number {
  const [ls, ln] = splitKey(left);
  const [rs, rn] = splitKey(right);
  return compareText(ls, rs) || compareText(ln, rn);
}

export class Schema {
  readonly specs: Spec[] = [];
  private readonly exact = new Map<string, Spec>();
  constructor(path: string) {
    const lines = readFileSync(path, 'ascii').split('\n').slice(0, -1);
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index];
      if (line.trim() === '' || line.startsWith('#')) continue;
      const [pattern, type, ...words] = line.split(' ');
      const [section, key] = splitKey(pattern);
      const attributes = new Map<string, string>();
      for (const word of words) {
        const equals = word.indexOf('=');
        attributes.set(
          equals < 0 ? word : word.slice(0, equals),
          equals < 0 ? '' : word.slice(equals + 1),
        );
      }
      const spec: Spec = {
        pattern,
        type: type as ValueType,
        key,
        parts: section.split('.'),
        wildcard: section.includes('*'),
        attributes,
        line: index + 1,
      };
      this.specs.push(spec);
      if (!spec.wildcard) this.exact.set(pattern, spec);
    }
  }
  matches(spec: Spec, section: string): boolean {
    const parts = section.split('.');
    return (
      parts.length === spec.parts.length &&
      spec.parts.every((part, i) => part === '*' || part === parts[i])
    );
  }
  find(key: string): Spec | null {
    const exact = this.exact.get(key);
    if (exact) return exact;
    const [section, name] = splitKey(key);
    return (
      this.specs.find(
        (spec) => spec.wildcard && spec.key === name && this.matches(spec, section),
      ) ?? null
    );
  }
  targets(spec: Spec, sections: Set<string>): string[] {
    if (!spec.wildcard) return [spec.pattern];
    return [...sections]
      .sort(compareText)
      .filter((section) => this.matches(spec, section))
      .map((section) => `${section}.${spec.key}`)
      .filter((key) => this.find(key) === spec);
  }
}
