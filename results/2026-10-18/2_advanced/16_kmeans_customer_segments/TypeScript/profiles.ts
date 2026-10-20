import { readFileSync } from 'node:fs';
import { FEATURES, SQUARE_ROOT, type Scaling } from './features.ts';
export interface Condition { feature: number; comparison: string; threshold: number }
export interface Rule { name: string; conditions: Condition[] }
export function readRules(): Rule[] {
  return readFileSync('input/segment_rules.txt', 'ascii').split('\n').slice(0, -1).map(line => {
    const [name, ...words] = line.split(' '), conditions: Condition[] = [];
    for (let index = 0; index < words.length; index += 3) {
      conditions.push({ feature: FEATURES.indexOf(words[index]), comparison: words[index + 1], threshold: Number(words[index + 2]) });
    }
    return { name, conditions };
  });
}
export function matchingRule(center: number[], rules: Rule[]): number {
  return rules.findIndex(rule => rule.conditions.every(condition => condition.comparison === '>'
    ? center[condition.feature] > condition.threshold : center[condition.feature] < condition.threshold));
}
export function originalCenter(center: number[], scaling: Scaling[]): number[] {
  return center.map((coordinate, feature) => {
    const value = scaling[feature].mean + scaling[feature].sd * coordinate;
    return SQUARE_ROOT.has(feature) ? value * value : value;
  });
}
