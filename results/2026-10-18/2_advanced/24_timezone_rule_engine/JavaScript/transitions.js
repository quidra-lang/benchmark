'use strict';

const { specifiedDay } = require('./day_rules');

function expandInstances(rules) {
    const instances = [];
    for (const rule of rules) {
        for (let year = rule.from; year <= rule.to; year++) {
            instances.push({ nominal: specifiedDay(year, rule.month, rule.day) * 86400 + rule.at.value,
                type: rule.at.type, save: rule.save, letter: rule.letter, rule });
        }
    }
    return instances.sort((a, b) => a.nominal - b.nominal || a.rule.number - b.rule.number);
}

const adj = (type, offset, save) => type === 'u' ? 0 : type === 's' ? offset : offset + save;

function processInstances(instances, offset, start, until) {
    let currentSave = 0;
    let preStart = null;
    const applied = [];
    for (const instance of instances) {
        const time = instance.nominal - adj(instance.type, offset, currentSave);
        if (until !== null && time >= until.nominal - adj(until.time.type, offset, currentSave)) break;
        if (time <= start) preStart = instance;
        else applied.push({ time, instance });
        currentSave = instance.save;
    }
    return { preStart, applied, end: until === null ? Infinity : until.nominal - adj(until.time.type, offset, currentSave) };
}

function abbreviation(format, save, letter) {
    if (format.includes('/')) return format.split('/')[save === 0 ? 0 : 1];
    return format.replace('%s', letter);
}

module.exports = { expandInstances, adj, processInstances, abbreviation };
