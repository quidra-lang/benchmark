'use strict';

const fs = require('node:fs');
const lines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);

function readInput() {
    const fields = new Map(lines('params.txt').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values.map(Number)];
    }));
    const first = name => fields.get(name)[0];
    const settings = { season: first('season'), holdout: first('holdout'), horizon: first('horizon'),
        cvStart: first('cv_start'), combo: first('combo'), alpha: fields.get('alpha'), beta: fields.get('beta'),
        gamma: fields.get('gamma'), phi: fields.get('phi'), maxAr: first('max_ar'), maxLag: first('max_lag'),
        ljungBox: fields.get('ljung_box'), outlier: first('outlier'), interval: fields.get('interval') };
    const series = [];
    for (const line of lines('series.csv').slice(1)) {
        const [name, period, value] = line.split(',');
        if (series.at(-1)?.name !== name) series.push({ name, periods: [], raw: [], events: new Map() });
        series.at(-1).periods.push(period);
        series.at(-1).raw.push(value === 'NA' ? null : Number(value));
    }
    const byName = new Map(series.map(item => [item.name, item]));
    for (const line of lines('events.csv').slice(1)) {
        const [name, period, kind] = line.split(',');
        byName.get(name).events.set(period, kind);
    }
    for (const line of lines('inventory.csv').slice(1)) {
        const [name, onHand, leadTime, review, service] = line.split(',');
        byName.get(name).inventory = { onHand: Number(onHand), leadTime: Number(leadTime), review: Number(review), service: Number(service) };
    }
    return { settings, series };
}

function nextMonth(period) {
    let [year, month] = period.split('-').map(Number);
    if (month === 12) { year++; month = 1; }
    else month++;
    return String(year).padStart(4, '0') + '-' + String(month).padStart(2, '0');
}

function real(value) {
    if (Math.abs(value) >= 1e21) return (value < 0 ? '-' : '') + BigInt(Math.abs(value)).toString() + '.0000';
    const text = value.toFixed(4);
    return text === '-0.0000' ? '0.0000' : text;
}

function writeLines(name, values) {
    fs.mkdirSync('output', { recursive: true });
    fs.writeFileSync('output/' + name, values.length ? values.join('\n') + '\n' : '', 'ascii');
}

module.exports = { readInput, nextMonth, real, writeLines };
