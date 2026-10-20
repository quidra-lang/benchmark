'use strict';

const fs = require('node:fs');
const { InputError, wellFormedNumber, readDimacs, modelLines } = require('./cnf_io');
const encoders = require('./encoders');
const { preprocess } = require('./preprocess');
const { solveRound } = require('./dpll');
const { items, numberList, frequencyList, boardLines, writeParagraphs, writeCsv } = require('./report');

const ARGUMENTS = new Map([
    ['SOLVE', ['file']], ['ENUM', ['file', 'limit']], ['CORE', ['file']],
    ['QUEENS', ['size', 'limit']], ['PIGEON', ['pigeons', 'holes', 'limit']],
    ['COLOR', ['graph', 'colors', 'limit']], ['CHROMATIC', ['graph', 'maximum']],
]);
const NUMBER_LIMITS = { size: 8, pigeons: 8, holes: 8, colors: 6, maximum: 6, limit: 200 };
const STAT_COLUMNS = ['job', 'command', 'status', 'variables', 'clauses', 'removed_clauses',
    'decisions', 'propagations', 'conflicts', 'max_depth', 'models', 'rounds'];

function sum(values, select = value => value) {
    let total = 0;
    for (const value of values) total += select(value);
    return total;
}

function emptyStatistics() {
    return { decisions: 0, propagations: 0, conflicts: 0, maxDepth: 0 };
}

function addStatistics(total, part) {
    total.decisions += part.decisions;
    total.propagations += part.propagations;
    total.conflicts += part.conflicts;
    total.maxDepth = Math.max(total.maxDepth, part.maxDepth);
}

function analyzeGraph(graph) {
    const adjacent = Array.from({ length: graph.vertices + 1 }, () => []);
    for (const [first, second] of graph.edges) {
        adjacent[first].push(second);
        adjacent[second].push(first);
    }
    const order = Array.from({ length: graph.vertices }, (_, index) => index + 1)
        .sort((first, second) => adjacent[second].length - adjacent[first].length || first - second);
    const colors = Array(graph.vertices + 1).fill(0);
    let maximumDegree = 0;
    let used = 0;
    for (const vertex of order) {
        maximumDegree = Math.max(maximumDegree, adjacent[vertex].length);
        const unavailable = new Set(adjacent[vertex].map(neighbor => colors[neighbor]));
        let color = 1;
        while (unavailable.has(color)) color++;
        colors[vertex] = color;
        used = Math.max(used, color);
    }
    graph.maximumDegree = maximumDegree;
    graph.greedy = { used, colors: colors.slice(1) };
}

function readGraphs() {
    const graphs = new Map();
    const lines = fs.readFileSync('input/graphs.txt', 'ascii').split('\n');
    let graph = null;
    let seen = new Set();
    for (let index = 0; index < lines.length; index++) {
        const line = lines[index];
        if (graph === null) {
            if (line === '' || line.startsWith('#')) continue;
            const [, name, vertices] = line.split(' ');
            graph = { name, vertices: Number(vertices), edges: [], reason: null };
            graphs.set(name, graph);
            seen = new Set();
            continue;
        }
        if (line === 'END') {
            if (graph.reason === null) {
                graph.edges.sort((first, second) => first[0] - second[0] || first[1] - second[1]);
                analyzeGraph(graph);
            }
            graph = null;
            continue;
        }
        if (graph.reason !== null) continue;
        const tokens = line.split(' ');
        let reason = null;
        if (tokens.length !== 2 || !tokens.every(wellFormedNumber)) reason = 'bad edge line';
        else {
            const first = Number(tokens[0]);
            const second = Number(tokens[1]);
            const edge = [Math.min(first, second), Math.max(first, second)];
            const key = edge.join(',');
            if (first < 1 || first > graph.vertices || second < 1 || second > graph.vertices) reason = 'vertex out of range';
            else if (first === second) reason = 'self loop';
            else if (seen.has(key)) reason = 'duplicate edge';
            else {
                graph.edges.push(edge);
                seen.add(key);
            }
        }
        if (reason !== null) graph.reason = `${reason} at line ${index + 1}`;
    }
    return graphs;
}

function readJobs() {
    const jobs = [];
    for (const line of fs.readFileSync('input/jobs.txt', 'ascii').split('\n')) {
        if (line === '' || line.startsWith('#')) continue;
        const [command, ...arguments_] = line.split(' ');
        jobs.push({ number: jobs.length + 1, line, command, arguments: arguments_, error: null });
    }
    return jobs;
}

function validateJob(job, graphs) {
    if (!ARGUMENTS.has(job.command)) throw new InputError(`unknown command ${job.command}`);
    const kinds = ARGUMENTS.get(job.command);
    if (job.arguments.length !== kinds.length) throw new InputError('wrong argument count');
    for (let index = 0; index < kinds.length; index++) {
        const kind = kinds[index];
        const token = job.arguments[index];
        if (kind === 'file') {
            if (!/^[a-z0-9_]{1,20}\.cnf$/.test(token)) throw new InputError(`bad file name ${token}`);
            job.file = token;
        } else if (kind === 'graph') {
            if (!graphs.has(token)) throw new InputError(`unknown graph ${token}`);
            job.graph = graphs.get(token);
            if (job.graph.reason !== null) throw new InputError(`invalid graph ${token}: ${job.graph.reason}`);
        } else {
            if (!wellFormedNumber(token)) throw new InputError(`bad number ${token}`);
            const value = Number(token);
            if (value < 1 || value > NUMBER_LIMITS[kind]) throw new InputError(`out of range ${token}`);
            job[kind] = value;
        }
    }
    if (job.limit === undefined) job.limit = 1;
}

function originalFormula(job) {
    if (job.file !== undefined) return readDimacs(`input/${job.file}`);
    if (job.command === 'QUEENS') return encoders.queens(job.size);
    if (job.command === 'PIGEON') return encoders.pigeon(job.pigeons, job.holes);
    return encoders.coloring(job.graph, job.colors);
}

function solveFormula(formula, limit) {
    const simplified = preprocess(formula, limit === 1);
    const result = { formula, preprocessing: simplified, models: [], rounds: 0,
        stop: 'limit', status: 'UNSAT', statistics: emptyStatistics(), trace: [], removed: simplified.removed };
    if (simplified.emptyClause !== null) {
        result.stop = 'preprocess';
        return result;
    }
    const blocking = [];
    while (result.models.length < limit) {
        const round = solveRound(formula.variables, simplified.clauses.concat(blocking));
        result.rounds++;
        if (result.rounds === 1) result.trace = round.events;
        addStatistics(result.statistics, round.statistics);
        if (!round.satisfiable) {
            result.stop = 'all';
            break;
        }
        const model = Array(formula.variables + 1).fill(false);
        for (let variable = 1; variable <= formula.variables; variable++) {
            model[variable] = simplified.fixed[variable] === null ? round.model[variable] : simplified.fixed[variable];
        }
        result.models.push(model);
        blocking.push(simplified.active.map(variable => model[variable] ? -variable : variable));
    }
    if (result.models.length > 0) result.status = 'SAT';
    return result;
}

function literalTrue(literal, model, flipped = 0) {
    const variable = Math.abs(literal);
    const value = variable === flipped ? !model[variable] : model[variable];
    return literal > 0 ? value : !value;
}

function analyzeModels(result) {
    const { formula, models } = result;
    if (models.length === 0) return null;
    let failure = null;
    for (let model = 0; model < models.length && failure === null; model++) {
        for (let clause = 0; clause < formula.clauses.length; clause++) {
            if (!formula.clauses[clause].some(literal => literalTrue(literal, models[model]))) {
                failure = { model: model + 1, clause: clause + 1 };
                break;
            }
        }
    }
    const distribution = formula.clauses.map(clause => clause.filter(literal => literalTrue(literal, models[0])).length);
    const safe = [];
    for (let variable = 1; variable <= formula.variables; variable++) {
        if (formula.clauses.every(clause => clause.some(literal => literalTrue(literal, models[0], variable)))) safe.push(variable);
    }
    let diversity = null;
    if (models.length >= 2) {
        diversity = { pairs: 0, minimum: formula.variables, maximum: 0 };
        for (let first = 0; first < models.length; first++) {
            for (let second = first + 1; second < models.length; second++) {
                let distance = 0;
                for (let variable = 1; variable <= formula.variables; variable++) {
                    if (models[first][variable] !== models[second][variable]) distance++;
                }
                diversity.pairs++;
                diversity.minimum = Math.min(diversity.minimum, distance);
                diversity.maximum = Math.max(diversity.maximum, distance);
            }
        }
    }
    let backbone = null;
    if (result.stop === 'all') {
        backbone = [];
        for (let variable = 1; variable <= formula.variables; variable++) {
            if (models.every(model => model[variable] === models[0][variable])) backbone.push(models[0][variable] ? variable : -variable);
        }
    }
    return { failure, distribution, safe, diversity, backbone };
}

function unsatisfiableCore(formula) {
    const retained = new Set(formula.clauses.map((_, index) => index + 1));
    let decisions = 0;
    let conflicts = 0;
    for (let number = 1; number <= formula.clauses.length; number++) {
        const clauses = formula.clauses.filter((_, index) => retained.has(index + 1) && index + 1 !== number);
        const result = solveFormula({ variables: formula.variables, clauses }, 1);
        decisions += result.statistics.decisions;
        conflicts += result.statistics.conflicts;
        if (result.status === 'UNSAT') retained.delete(number);
    }
    return { clauses: [...retained], decisions, conflicts };
}

function solveChromatic(job) {
    const attempts = [];
    const statistics = emptyStatistics();
    let rounds = 0;
    let removed = 0;
    for (let colors = 1; colors <= job.maximum; colors++) {
        const attempt = solveFormula(encoders.coloring(job.graph, colors), 1);
        attempts.push({ colors, result: attempt });
        addStatistics(statistics, attempt.statistics);
        rounds += attempt.rounds;
        removed += attempt.removed;
        job.colors = colors;
        if (attempt.status === 'SAT') break;
    }
    return { ...attempts.at(-1).result, attempts, statistics, rounds, removed };
}

function runJob(job, graphs) {
    try {
        validateJob(job, graphs);
        job.result = job.command === 'CHROMATIC' ? solveChromatic(job) : solveFormula(originalFormula(job), job.limit);
    } catch (error) {
        if (!(error instanceof InputError)) throw error;
        job.error = error.message;
        return;
    }
    job.analysis = analyzeModels(job.result);
    if (job.command === 'CORE' && job.result.status === 'UNSAT') job.core = unsatisfiableCore(job.result.formula);
}

function statisticsValues(job) {
    const result = job.result;
    return [job.number, job.command, result.status, result.formula.variables, result.formula.clauses.length,
        result.removed, result.statistics.decisions, result.statistics.propagations, result.statistics.conflicts,
        result.statistics.maxDepth, result.models.length, result.rounds];
}

function graphLine(graph) {
    return items('graph', { vertices: graph.vertices, edges: graph.edges.length, max_degree: graph.maximumDegree, greedy: graph.greedy.used });
}

function formulaLine(formula) {
    const lengths = formula.clauses.map(clause => clause.length);
    return items('formula', { variables: formula.variables, clauses: formula.clauses.length,
        literals: sum(lengths), lengths: frequencyList(lengths) });
}

function preprocessingLines(simplified) {
    const statistics = simplified.statistics;
    const records = simplified.records;
    const lines = [items('preprocess', {
        pure: simplified.pure ? 'on' : 'off', tautologies: statistics.tautologies, duplicate_literals: statistics.duplicateLiterals,
        unit_fixed: statistics.unitFixed, unit_removed: statistics.unitRemoved, subsumed: statistics.subsumed,
        pure_fixed: statistics.pureFixed, pure_removed: statistics.pureRemoved, removed: simplified.removed,
    }), items('removed_clauses', {
        tautology: numberList(records.tautology), unit: numberList(records.unit),
        subsumed: numberList(records.subsumed), pure: numberList(records.pure),
    })];
    if (simplified.emptyClause !== null) lines.push(items('simplified', { empty_clause: simplified.emptyClause }));
    else {
        const lengths = simplified.clauses.map(clause => clause.length);
        lines.push(items('simplified', { clauses: simplified.clauses.length, literals: sum(lengths),
            lengths: frequencyList(lengths), fixed: simplified.fixedLiterals.length, active: simplified.active.length }));
        lines.push(items('fixed', { literals: numberList(simplified.fixedLiterals) }));
    }
    return lines;
}

function searchLine(statistics) {
    return items('search', { decisions: statistics.decisions, propagations: statistics.propagations,
        conflicts: statistics.conflicts, max_depth: statistics.maxDepth });
}

function analysisLines(job, full = true) {
    const { result, analysis } = job;
    if (analysis === null) return [];
    const lines = [];
    if (analysis.failure === null) {
        lines.push(items('verify ok', { models: result.models.length, clauses: result.formula.clauses.length,
            true_literals: frequencyList(analysis.distribution) }));
    } else lines.push(items('verify failed', analysis.failure));
    lines.push(items('flips', { safe: analysis.safe.length, variables: numberList(analysis.safe) }));
    if (full && analysis.diversity !== null) {
        const diversity = analysis.diversity;
        lines.push(items('diversity', { pairs: diversity.pairs, min_distance: diversity.minimum, max_distance: diversity.maximum }));
    }
    if (full && analysis.backbone !== null) lines.push(items('backbone', { size: analysis.backbone.length, literals: numberList(analysis.backbone) }));
    return lines;
}

function jobHeading(job) {
    return `JOB ${job.number} ${job.line}`;
}

function jobParagraph(job) {
    const lines = [jobHeading(job)];
    if (job.error !== null) return [...lines, `error ${job.error}`];
    const result = job.result;
    if (job.command === 'CHROMATIC') {
        lines.push(graphLine(job.graph));
        for (const attempt of result.attempts) {
            const current = attempt.result;
            const statistics = current.statistics;
            lines.push(items('attempt', { k: attempt.colors, clauses: current.formula.clauses.length,
                removed: current.removed, result: current.status, stop: current.stop,
                decisions: statistics.decisions, propagations: statistics.propagations,
                conflicts: statistics.conflicts, max_depth: statistics.maxDepth }));
        }
        lines.push(items(`result ${result.status}`, { chromatic: result.status === 'SAT' ? job.colors : '-', attempts: result.attempts.length }));
        lines.push(searchLine(result.statistics), ...analysisLines(job, false));
        return lines;
    }
    if (job.command === 'COLOR') lines.push(graphLine(job.graph));
    lines.push(formulaLine(result.formula), ...preprocessingLines(result.preprocessing));
    lines.push(items(`result ${result.status}`, { models: result.models.length, rounds: result.rounds, stop: result.stop }));
    lines.push(searchLine(result.statistics));
    if (result.rounds > 0) {
        let trace = result.trace.length === 0 ? '-' : result.trace.slice(0, 12).join(' ');
        if (result.trace.length > 12) trace += ` +${result.trace.length - 12}`;
        lines.push(`trace ${trace}`);
    }
    lines.push(...analysisLines(job));
    if (job.core !== undefined) lines.push(items('core', { size: job.core.clauses.length,
        decisions: job.core.decisions, conflicts: job.core.conflicts, clauses: numberList(job.core.clauses) }));
    return lines;
}

function summaryParagraph(jobs) {
    const valid = jobs.filter(job => job.error === null);
    const sat = valid.filter(job => job.result.status === 'SAT').length;
    const lines = [items('SUMMARY', { jobs: jobs.length, sat, unsat: valid.length - sat, error: jobs.length - valid.length })];
    lines.push(items('totals', {
        models: sum(valid, job => job.result.models.length), rounds: sum(valid, job => job.result.rounds),
        decisions: sum(valid, job => job.result.statistics.decisions), propagations: sum(valid, job => job.result.statistics.propagations),
        conflicts: sum(valid, job => job.result.statistics.conflicts), removed_clauses: sum(valid, job => job.result.removed),
    }));
    for (const command of ARGUMENTS.keys()) {
        const group = valid.filter(job => job.command === command);
        if (group.length === 0) continue;
        const satisfiable = group.filter(job => job.result.status === 'SAT').length;
        lines.push(items(`command ${command}`, { jobs: group.length, sat: satisfiable, unsat: group.length - satisfiable,
            decisions: sum(group, job => job.result.statistics.decisions), propagations: sum(group, job => job.result.statistics.propagations),
            conflicts: sum(group, job => job.result.statistics.conflicts) }));
    }
    if (valid.length > 0) {
        for (const [label, field, output] of [['hardest', 'conflicts', 'conflicts'], ['deepest', 'maxDepth', 'max_depth'], ['busiest', 'propagations', 'propagations']]) {
            let best = valid[0];
            for (const job of valid) if (job.result.statistics[field] > best.result.statistics[field]) best = job;
            lines.push(items(label, { job: best.number, [output]: best.result.statistics[field] }));
        }
    }
    return lines;
}

function modelParagraph(job) {
    const lines = [jobHeading(job)];
    job.result.models.forEach((model, index) => {
        lines.push(`model ${index + 1}`);
        for (const line of modelLines(model)) lines.push(line);
    });
    return lines;
}

function compareSequences(first, second) {
    for (let index = 0; index < first.length; index++) if (first[index] !== second[index]) return first[index] - second[index];
    return 0;
}

function queenCanonical(columns) {
    const size = columns.length;
    const transforms = Array.from({ length: 8 }, () => Array(size).fill(0));
    for (let row = 1; row <= size; row++) {
        const column = columns[row - 1];
        const images = [[row, column], [column, size + 1 - row], [size + 1 - row, size + 1 - column],
            [size + 1 - column, row], [row, size + 1 - column], [size + 1 - row, column],
            [column, row], [size + 1 - column, size + 1 - row]];
        images.forEach(([nextRow, nextColumn], index) => { transforms[index][nextRow - 1] = nextColumn; });
    }
    let canonical = transforms[0];
    for (const transform of transforms) if (compareSequences(transform, canonical) < 0) canonical = transform;
    return { canonical, orbit: new Set(transforms.map(transform => transform.join(','))).size };
}

function newClasses() {
    return { sequence: [], lookup: new Map() };
}

function registerClass(classes, canonical, model, extra = {}) {
    const key = canonical.join(',');
    let entry = classes.lookup.get(key);
    if (entry === undefined) {
        entry = { number: classes.sequence.length + 1, canonical, first: model, found: 0, ...extra };
        classes.sequence.push(entry);
        classes.lookup.set(key, entry);
    }
    entry.found++;
    return entry;
}

function queensParagraph(job) {
    const lines = [items('QUEENS', { job: job.number, n: job.size })];
    const classes = newClasses();
    job.result.models.forEach((model, index) => {
        const columns = encoders.positions(model, job.size, job.size);
        const symmetry = queenCanonical(columns);
        const entry = registerClass(classes, symmetry.canonical, index + 1, { orbit: symmetry.orbit });
        lines.push(items(`solution ${index + 1}`, { columns: numberList(columns), class: entry.number }));
        if (entry.first === index + 1) for (const line of boardLines(columns)) lines.push(line);
    });
    for (const entry of classes.sequence) {
        lines.push(items(`class ${entry.number}`, { orbit: entry.orbit, found: entry.found, first: entry.first, canonical: numberList(entry.canonical) }));
    }
    lines.push(items('summary', { solutions: job.result.models.length, stop: job.result.stop, classes: classes.sequence.length }));
    return lines;
}

function pigeonParagraph(job) {
    const lines = [items('PIGEON', { job: job.number, pigeons: job.pigeons, holes: job.holes })];
    job.result.models.forEach((model, index) => {
        const holes = encoders.positions(model, job.pigeons, job.holes);
        const occupied = new Set(holes);
        const empty = [];
        for (let hole = 1; hole <= job.holes; hole++) if (!occupied.has(hole)) empty.push(hole);
        lines.push(items(`assignment ${index + 1}`, { holes: numberList(holes), empty: numberList(empty) }));
    });
    let expected = 0;
    if (job.pigeons <= job.holes) {
        expected = 1;
        for (let pigeon = 0; pigeon < job.pigeons; pigeon++) expected *= job.holes - pigeon;
    }
    lines.push(items('summary', { assignments: job.result.models.length, stop: job.result.stop, expected }));
    return lines;
}

function colorCanonical(colors) {
    const mapping = new Map();
    return colors.map(color => {
        if (!mapping.has(color)) mapping.set(color, mapping.size + 1);
        return mapping.get(color);
    });
}

function coloringParagraph(job) {
    const graph = job.graph;
    const lines = [items(job.command, { job: job.number, graph: graph.name, vertices: graph.vertices, edges: graph.edges.length, colors: job.colors })];
    lines.push(items('greedy', { used: graph.greedy.used, colors: numberList(graph.greedy.colors) }));
    const classes = newClasses();
    job.result.models.forEach((model, index) => {
        const colors = encoders.positions(model, graph.vertices, job.colors);
        const sizes = Array(job.colors).fill(0);
        for (const color of colors) sizes[color - 1]++;
        const entry = registerClass(classes, colorCanonical(colors), index + 1);
        lines.push(items(`coloring ${index + 1}`, { colors: numberList(colors), used: new Set(colors).size,
            sizes: numberList(sizes), class: entry.number }));
    });
    for (const entry of classes.sequence) {
        lines.push(items(`class ${entry.number}`, { found: entry.found, first: entry.first, canonical: numberList(entry.canonical) }));
    }
    lines.push(items('summary', { colorings: job.result.models.length, stop: job.result.stop, classes: classes.sequence.length }));
    return lines;
}

function boardParagraph(job) {
    if (job.command === 'QUEENS') return queensParagraph(job);
    if (job.command === 'PIGEON') return pigeonParagraph(job);
    return coloringParagraph(job);
}

function main() {
    const graphs = readGraphs();
    const jobs = readJobs();
    for (const job of jobs) runJob(job, graphs);
    const valid = jobs.filter(job => job.error === null);
    const results = jobs.map(jobParagraph);
    results.push(summaryParagraph(jobs));
    const models = valid.filter(job => job.result.models.length > 0).map(modelParagraph);
    const boards = valid.filter(job => ['QUEENS', 'PIGEON', 'COLOR', 'CHROMATIC'].includes(job.command)).map(boardParagraph);
    fs.mkdirSync('output', { recursive: true });
    writeParagraphs('results.txt', results);
    writeParagraphs('models.txt', models);
    writeParagraphs('boards.txt', boards);
    writeCsv('stats.csv', [STAT_COLUMNS, ...valid.map(statisticsValues)]);
}

if (require.main === module) main();
