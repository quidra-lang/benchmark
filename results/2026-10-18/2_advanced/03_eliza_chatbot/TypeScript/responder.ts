import { isReference, type Substitution } from './script_loader.ts';
import type { Bindings } from './matcher.ts';

export function reflect(words: string[], substitutions: Map<string, Substitution>): string[] {
  return words.flatMap(word => substitutions.get(word)?.replacement ?? [word]);
}
export function reply(template: string, bindings: Bindings, substitutions: Map<string, Substitution>): string {
  let text = template.replace(/\((\d)\)/g, (_, digit: string) => reflect(bindings[Number(digit) - 1] ?? [], substitutions).join(' '));
  text = text.split(' ').filter(Boolean).join(' ');
  return text.replace(/^[a-z]/, char => char.toUpperCase());
}
export function restate(words: string[], bindings: Bindings): string[] {
  return words.flatMap(word => isReference(word) ? bindings[Number(word[1]) - 1] ?? [] : [word]);
}
export function wrap(text: string): string[] {
  const words = text.split(' ').filter(Boolean);
  if (!words.length) return ['ELIZA:'];
  const lines = ['ELIZA: ' + words[0]];
  for (const word of words.slice(1)) {
    if (lines.at(-1)!.length + 1 + word.length <= 72) lines[lines.length - 1] += ' ' + word;
    else lines.push('       ' + word);
  }
  return lines;
}
