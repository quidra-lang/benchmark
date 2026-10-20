import { angle, type Model } from './harmonic_fit.ts';

export interface GridExtremum { kind: 'high' | 'low'; refinedMinute: number; height: number }
export function level(model: Model, time: number): number { let value = model.mean; for (const c of model.constituents) { const theta = angle(c.speed, time); value += c.a * Math.cos(theta) + c.b * Math.sin(theta); } return value; }
export function gridExtrema(model: Model, start: number, hours: number, spacing: number): GridExtremum[] {
    const count = hours * 60 / spacing, values = Array.from({ length: count + 1 }, (_, j) => level(model, (60 * start + j * spacing) / 60)), extrema: GridExtremum[] = [];
    for (let j = 1; j < count; j++) {
        const previous = values[j - 1], current = values[j], next = values[j + 1]; let kind: GridExtremum['kind'];
        if (previous < current && current > next) kind = 'high'; else if (previous > current && current < next) kind = 'low'; else continue;
        const delta = (previous - next) / (2 * (previous - 2 * current + next)); extrema.push({ kind, refinedMinute: 60 * start + j * spacing + delta * spacing, height: current - (previous - next) * delta / 4 });
    }
    return extrema;
}
