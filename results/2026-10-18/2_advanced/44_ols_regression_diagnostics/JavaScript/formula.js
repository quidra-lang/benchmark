'use strict';

function parseFactor(name) {
    const categorical = /^C\(([^)]+)\)$/.exec(name);
    if (categorical) return { name, column: categorical[1], kind: 'categorical' };
    const power = /^I\(([^)^]+)\^([23])\)$/.exec(name);
    if (power) return { name, column: power[1], kind: 'power', power: Number(power[2]) };
    return { name, column: name, kind: 'numeric' };
}

function combinations(values, count, start = 0, prefix = []) {
    if (count === 0) return [prefix];
    const result = [];
    for (let i = start; i <= values.length - count; i++) result.push(...combinations(values, count - 1, i + 1, [...prefix, values[i]]));
    return result;
}

function parseFormula(line, number) {
    const [original, weight = null] = line.split(' weights=');
    const [response, expressions] = original.split(' ~ ');
    const terms = [];
    const seen = new Set();
    for (const expression of expressions.split(' + ')) {
        const factors = expression.split(expression.includes('*') ? '*' : ':').map(parseFactor);
        const expanded = expression.includes('*') ? Array.from({ length: factors.length }, (_, i) => combinations(factors, i + 1)).flat() : [factors];
        for (const group of expanded) {
            const key = group.map(factor => factor.name).sort().join('|');
            if (seen.has(key)) continue;
            seen.add(key);
            terms.push({ name: group.map(factor => factor.name).join(':'), factors: group });
        }
    }
    const factorColumns = [...new Set(terms.flatMap(term => term.factors.map(factor => factor.column)))];
    return { number, original, response, weight, terms, factorColumns,
        variables: [...factorColumns, response, ...(weight === null ? [] : [weight])] };
}

function contained(first, second) {
    return first.factors.length < second.factors.length && first.factors.every(factor => second.factors.some(other => other.name === factor.name));
}

const formatFormula = (model, terms) => model.response + ' ~ ' + (terms.length ? terms.map(term => term.name).join(' + ') : '1');

function modelRows(model, data) {
    const rows = data.rows.filter(row => model.variables.every(name => row.values[name] !== null));
    const levels = new Map();
    for (const term of model.terms) for (const factor of term.factors) {
        if (factor.kind === 'categorical' && !levels.has(factor.column))
            levels.set(factor.column, [...new Set(rows.map(row => row.values[factor.column]))].sort());
    }
    return { rows, levels };
}

function components(factor, levels) {
    return factor.kind === 'categorical' ? levels.get(factor.column).slice(1).map(level => ({ ...factor, name: factor.name + level, level })) : [factor];
}

function columnsFor(terms, levels) {
    const columns = [{ name: '(Intercept)', term: null, components: [] }];
    for (const term of terms) {
        let tuples = [[]];
        for (const factor of term.factors) {
            const previous = tuples;
            tuples = components(factor, levels).flatMap(component => previous.map(tuple => [...tuple, component]));
        }
        for (const tuple of tuples) columns.push({ name: tuple.map(component => component.name).join(':'), term, components: tuple });
    }
    return columns;
}

function columnValues(columns, row) {
    return columns.map(column => {
        let product = 1;
        for (const component of column.components) {
            const raw = row.values[component.column];
            const value = component.kind === 'categorical' ? Number(raw === component.level)
                : component.kind === 'power' ? component.power === 2 ? raw * raw : raw * raw * raw : raw;
            product *= value;
        }
        return product;
    });
}

function design(model, rows, levels, terms = model.terms) {
    const columns = columnsFor(terms, levels);
    return { columns, matrix: rows.map(row => columnValues(columns, row)),
        response: rows.map(row => row.values[model.response]), weights: rows.map(row => model.weight === null ? 1 : row.values[model.weight]) };
}

function predictable(model, levels, row) {
    return model.factorColumns.every(name => row.values[name] !== null && (!levels.has(name) || levels.get(name).includes(row.values[name])));
}

module.exports = { parseFormula, contained, formatFormula, modelRows, columnsFor, columnValues, design, predictable };
