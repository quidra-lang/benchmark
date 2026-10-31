'use strict';

function real(value, digits = 4) {
    if (value === null) return '-';
    if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.' + '0'.repeat(digits);
    const text = value.toFixed(digits);
    return /^-0\.0+$/.test(text) ? text.slice(1) : text;
}

function curvePlot(observed, fitted) {
    const count = observed.length;
    let maximum = observed[0];
    for (let i = 1; i < count; i++) if (observed[i] > maximum) maximum = observed[i];
    const width = String(maximum).length;
    const canvas = Array.from({length: 20}, () => Array(70).fill('.'));
    const dayIndex = x => Math.floor(x * (count - 1) / 69);
    for (let x = 0; x < 70; x++) {
        const day = dayIndex(x);
        const observedRow = Math.min(19, Math.floor(20 * observed[day] / maximum));
        const fittedRow = Math.min(19, Math.floor(20 * fitted[day] / maximum));
        canvas[observedRow][x] = observedRow === fittedRow ? '#' : 'o';
        if (fittedRow !== observedRow) canvas[fittedRow][x] = '*';
    }
    const lines = [`plot observed o fitted * both # days 1 ${count} max ${maximum}`];
    for (let y = 19; y >= 0; y--) {
        const label = String(Math.floor(maximum * y / 20)).padStart(width);
        lines.push(`${label} |${canvas[y].join('')}`);
    }
    const ticks = Array.from({length: 70}, (_, x) => x % 10 === 0 ? '+' : '-');
    lines.push(' '.repeat(width + 1) + '+' + ticks.join(''));
    const labels = Array(70).fill(' ');
    for (let x = 0; x <= 60; x += 10) {
        const label = String(dayIndex(x) + 1);
        for (let i = 0; i < label.length; i++) labels[x + i] = label[i];
    }
    lines.push((' '.repeat(width + 2) + labels.join('')).trimEnd());
    return lines;
}

module.exports = {real, curvePlot};
