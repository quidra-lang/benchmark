'use strict';

const fs = require('node:fs');

function readLines(filename) {
    return fs.readFileSync(`input/${filename}`, 'ascii').slice(0, -1).split('\n');
}

function readInputs() {
    const rows = readLines('cases.csv').slice(1).map(line => line.split(',').map(Number));
    const groups = [];
    const contacts = [];
    for (const line of readLines('population.txt')) {
        const fields = line.split(' ');
        if (fields[0] === 'group') {
            groups.push({name: fields[1], population: Number(fields[2]), fatality: Number(fields[3])});
        } else contacts.push(fields.slice(1).map(Number));
    }
    const interventions = readLines('interventions.txt').map(line => {
        const [day, multiplier] = line.split(' ').map(Number);
        return {day, multiplier};
    });
    const settings = new Map();
    const scenarios = [];
    const contactChanges = [];
    for (const line of readLines('params.txt')) {
        const [key, ...fields] = line.split(' ');
        if (key === 'scenario') scenarios.push({name: fields[0], multiplier: Number(fields[1])});
        else if (key === 'contact_change') {
            contactChanges.push({name: fields[0], group: fields[1], factor: Number(fields[2])});
        } else settings.set(key, fields.map(Number));
    }
    const [betaMin, betaMax, betaCount] = settings.get('beta_grid');
    const [rhoMin, rhoMax, rhoCount] = settings.get('rho_grid');
    const [goldenIterations, rounds] = settings.get('golden');
    const [deltaBeta, deltaGamma] = settings.get('simplex');
    const [alpha, chi, psi, omega, iterations] = settings.get('nelder_mead');
    const [exposed, infectious] = settings.get('initial');
    const params = {
        sigma: settings.get('sigma')[0], gamma: settings.get('gamma')[0], exposed, infectious,
        betaMin, betaMax, betaCount, rhoMin, rhoMax, rhoCount, goldenIterations, rounds,
        deltaBeta, deltaGamma, alpha, chi, psi, omega, iterations,
        holdout: settings.get('holdout')[0], effectWidth: settings.get('effect_width')[0],
        outlier: settings.get('outlier')[0], deathLag: settings.get('death_lag')[0],
        milestones: settings.get('milestones'), generation: settings.get('generation')[0],
        horizon: settings.get('horizon')[0], threshold: settings.get('threshold')[0]
    };
    return {cases: rows.map(row => row[1]), deaths: rows.map(row => row[2]), groups, contacts,
        interventions, params, scenarios, contactChanges};
}

function writeOutputs(files) {
    fs.mkdirSync('output', {recursive: true});
    for (const [filename, lines] of Object.entries(files)) {
        fs.writeFileSync(`output/${filename}`, lines.join('\n') + '\n', 'ascii');
    }
}

module.exports = {readInputs, writeOutputs};
