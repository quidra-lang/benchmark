import { readFileSync } from 'node:fs';
import * as expressions from './expressions.ts';
import type { AttributeValue, TargetLine, Argument, PolicyElement, Policies, ElementKind } from './types.ts';

function literal(text: string): AttributeValue {
  if (text.startsWith('"')) return text.slice(1, -1);
  if (text === 'true' || text === 'false') return text === 'true';
  return Number(text);
}

function target(text: string): TargetLine {
  return text.split(' | ').map(alternative => alternative.split(' & ').map(clause => {
    const first = clause.indexOf(' ');
    const second = clause.indexOf(' ', first + 1);
    const reference = clause.slice(0, first);
    const mandatory = reference.endsWith('!');
    return {reference: mandatory ? reference.slice(0, -1) : reference, mandatory,
      operation: clause.slice(first + 1, second), literal: literal(clause.slice(second + 1))};
  }));
}

function argumentsList(text: string): Argument[] {
  if (text === '') return [];
  return text.split(';').map(part => {
    const trimmed = part.trim();
    const separator = trimmed.indexOf('=');
    return {name: trimmed.slice(0, separator), expression: expressions.parse(trimmed.slice(separator + 1))};
  });
}

export function readPolicies(): Policies {
  const elements: PolicyElement[] = [];
  const stack: PolicyElement[] = [];
  for (const raw of readFileSync('input/policies.txt', 'ascii').split('\n')) {
    const line = raw.trimStart();
    if (line === '' || line.startsWith('#')) continue;
    const fields = line.split(' ');
    const keyword = fields[0];
    if (['POLICYSET', 'POLICY', 'RULE'].includes(keyword)) {
      const element: PolicyElement = {kind: keyword.toLowerCase() as ElementKind, id: fields[1], parent: stack.at(-1) || null,
        targets: [], condition: null, obligations: [], advice: [], children: [], index: elements.length,
        effect: '', algorithm: ''};
      if (keyword === 'RULE') element.effect = fields[2];
      else element.algorithm = fields[2];
      if (element.parent !== null) element.parent.children.push(element);
      elements.push(element);
      stack.push(element);
    } else if (keyword === 'END') stack.pop();
    else {
      const element = stack.at(-1)!;
      if (keyword === 'TARGET') element.targets.push(target(line.slice(7)));
      else if (keyword === 'CONDITION') element.condition = expressions.parse(line.slice(10));
      else {
        const item = {effect: fields[1], id: fields[2], arguments: argumentsList(fields.slice(3).join(' '))};
        (keyword === 'OBLIGATION' ? element.obligations : element.advice).push(item);
      }
    }
  }
  return {root: elements[0], elements, rules: elements.filter(element => element.kind === 'rule')};
}

