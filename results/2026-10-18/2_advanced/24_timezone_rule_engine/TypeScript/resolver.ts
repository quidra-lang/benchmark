export interface Period { start: number; offset: number; dst: boolean; abbreviation: string }
export interface Transition { time: number; before: Period; after: Period }
export interface Candidate { time: number; period: Period }
export function periodIndex(periods: Period[], time: number) {
    let low = 0, high = periods.length;
    while (low + 1 < high) {
        const middle = Math.floor((low + high) / 2);
        if (periods[middle].start <= time) low = middle; else high = middle;
    }
    return low;
}
export function periodRange(periods: Period[], index: number) {
    return { start: periods[index].start, end: periods[index + 1]?.start ?? Infinity };
}
export function resolveLocal(zone: { periods: Period[]; transitions: Transition[] }, local: number) {
    const candidates: Candidate[] = [];
    for (let index = 0; index < zone.periods.length; index++) {
        const period = zone.periods[index], time = local - period.offset, range = periodRange(zone.periods, index);
        if (time >= range.start && time < range.end) candidates.push({ time, period });
    }
    candidates.sort((a, b) => a.time - b.time);
    const gap = candidates.length ? undefined : zone.transitions.find(t => t.time + t.before.offset <= local && local < t.time + t.after.offset);
    return { candidates, gap };
}
