import type { Instance } from './instance.ts';
import type { Schedule } from './genetic.ts';

interface Interval { start: number; end: number; mark: string }

function scaleFor(makespan: number, width: number): { scale: number; columns: number } {
    for (let power = 1;; power *= 10) for (const multiplier of [1, 2, 5]) {
        const scale = power * multiplier, columns = Math.ceil(makespan / scale);
        if (columns <= width) return { scale, columns };
    }
}

function row(label: string, intervals: Interval[], scale: number, columns: number): string {
    let cells = '';
    for (let column = 0; column < columns; column++) {
        let chosen: Interval | undefined;
        let greatest = 0;
        for (const interval of intervals) {
            const overlap = Math.min(interval.end, (column + 1) * scale) - Math.max(interval.start, column * scale);
            if (overlap > greatest || (overlap > 0 && overlap === greatest && chosen !== undefined && interval.start < chosen.start)) {
                greatest = overlap; chosen = interval;
            }
        }
        cells += chosen?.mark ?? '.';
    }
    return label.padEnd(4, ' ') + ' |' + cells + '|';
}

export function gantt(instance: Instance, schedule: Schedule, path: number[], width: number) {
    const { scale, columns } = scaleFor(schedule.makespan, width);
    let time = 'time';
    for (let column = 0; column < columns; column += 10) time += ' '.repeat(6 + column - time.length) + column * scale;
    const lines = [time, '      ' + Array.from({ length: columns }, (_, c) => c % 10 === 0 ? '+' : '-').join('')];
    const critical = new Set(path);
    for (let machine = 0; machine < instance.machineCount; machine++) {
        const intervals = schedule.order[machine].map(index => {
            const letter = instance.byNumber.get(instance.operations[index].job)!.letter;
            return { start: schedule.starts[index], end: schedule.ends[index], mark: critical.has(index) ? letter.toLowerCase() : letter };
        });
        lines.push(row(`M${machine + 1}`, intervals, scale, columns));
    }
    let busy = '';
    for (let column = 0; column < columns; column++) {
        const time = column * scale;
        const count = schedule.order.filter(sequence => sequence.some(index => schedule.starts[index] <= time && time < schedule.ends[index])).length;
        busy += count === 10 ? 'X' : String(count);
    }
    lines.push('busy |' + busy + '|');
    for (const job of instance.jobs) {
        const intervals = job.operations.map(index => ({ start: schedule.starts[index], end: schedule.ends[index],
            mark: String((instance.operations[index].machine + 1) % 10) }));
        lines.push(row(`J${job.number}`, intervals, scale, columns));
    }
    return { scale, columns, lines };
}
