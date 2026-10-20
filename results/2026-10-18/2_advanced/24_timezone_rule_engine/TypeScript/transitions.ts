import { specifiedDay, type DaySpec } from './day_rules.ts';
import type { Time, TimeType, Until } from './tz_parser.ts';
export interface Rule { number: number; name: string; from: number; to: number; month: number; day: DaySpec; at: Time; save: number; letter: string; raw: string[] }
export interface Instance { nominal: number; type: TimeType; save: number; letter: string; rule: Rule }
export interface RuleSet { name: string; rules: Rule[]; instances: Instance[] }
export function expandInstances(rules: Rule[]) {
    const instances: Instance[] = [];
    for (const rule of rules) for (let year = rule.from; year <= rule.to; year++)
        instances.push({ nominal: specifiedDay(year, rule.month, rule.day) * 86400 + rule.at.value,
            type: rule.at.type, save: rule.save, letter: rule.letter, rule });
    return instances.sort((a, b) => a.nominal - b.nominal || a.rule.number - b.rule.number);
}
export const adj = (type: TimeType, offset: number, save: number) => type === 'u' ? 0 : type === 's' ? offset : offset + save;
export function processInstances(instances: Instance[], offset: number, start: number, until: Until | null) {
    let currentSave = 0, preStart: Instance | null = null;
    const applied: { time: number; instance: Instance }[] = [];
    for (const instance of instances) {
        const time = instance.nominal - adj(instance.type, offset, currentSave);
        if (until && time >= until.nominal - adj(until.time.type, offset, currentSave)) break;
        if (time <= start) preStart = instance; else applied.push({ time, instance });
        currentSave = instance.save;
    }
    return { preStart, applied, end: until ? until.nominal - adj(until.time.type, offset, currentSave) : Infinity };
}
export function abbreviation(format: string, save: number, letter: string) {
    return format.includes('/') ? format.split('/')[save === 0 ? 0 : 1] : format.replace('%s', letter);
}
