'use strict';

const fs = require('node:fs');
const mesh = require('./mesh');
const materials = require('./materials');
const transient = require('./transient');
const steady = require('./steady');
const report = require('./report');
const { fixed: f, time } = report;

function sum(values) {
    if (values.length === 0) return 0;
    let result = values[0];
    for (let i = 1; i < values.length; i++) result += values[i];
    return result;
}

function readParams(plate) {
    const result = { probes: [], runs: [] };
    const lines = fs.readFileSync('input/params.txt', 'ascii').trimEnd().split('\n');
    for (const line of lines) {
        const fields = line.split(' ');
        switch (fields[0]) {
            case 'initial': result.initial = Number(fields[1]); break;
            case 'end_time': result.endTime = Number(fields[1]); break;
            case 'snapshots': result.snapshotTimes = fields.slice(1).map(Number); break;
            case 'probe_every': result.probeEvery = Number(fields[1]); break;
            case 'probe':
                result.probes.push({ name: fields[1], p: Number(fields[2]) * plate.width + Number(fields[3]) });
                break;
            case 'run':
                result.runs.push({ name: fields[1], method: fields[2], D: Number(fields[3]) });
                break;
            case 'reference': result.reference = fields[1]; break;
            case 'tolerance': result.tolerance = Number(fields[1]); break;
            case 'max_iterations': result.maxIterations = Number(fields[1]); break;
            case 'omega': result.omega = Number(fields[1]); break;
            case 'bands': result.bands = fields.slice(1).map(Number); break;
            case 'alarm': result.alarm = Number(fields[1]); break;
            case 'limit': result.limit = Number(fields[1]); break;
        }
    }
    return result;
}

function readBoundary(plate, endTime) {
    const segments = [], sources = [];
    const directions = { left: 0, right: 1, top: 2, bottom: 3 };
    const lines = fs.readFileSync('input/boundary.txt', 'ascii').trimEnd().split('\n');
    for (const line of lines) {
        const fields = line.split(' ');
        if (fields[0] === 'segment') {
            const [name, edge] = fields.slice(1, 3);
            const start = Number(fields[3]), end = Number(fields[4]), kind = fields[5];
            segments.push({
                name, edge, kind, direction: directions[edge],
                cells: mesh.segmentCells(plate, edge, start, end),
                h: kind === 'convective' ? Number(fields[6]) : null,
                theta: kind === 'fixed' ? Number(fields[6])
                    : kind === 'convective' ? Number(fields[7]) : null,
            });
        } else {
            const [r1, c1, r2, c2, power] = fields.slice(2, 7).map(Number);
            const cells = mesh.sourceCells(plate, r1, c1, r2, c2);
            const intervals = [];
            for (let i = 7; i < fields.length; i += 2) intervals.push([Number(fields[i]), Number(fields[i + 1])]);
            const duty = sum(intervals.map(([on, off]) => Math.min(off, endTime) - Math.min(on, endTime))) / endTime;
            sources.push({ name: fields[1], power, cells, intervals, duty, weight: power / cells.length });
        }
    }
    return { segments, sources };
}

function buildModel(plate, materialList, segments) {
    const indices = new Map(materialList.map((material, i) => [material.code, i]));
    const materialIndex = plate.codes.map(code => indices.get(code));
    const cellOrder = Array.from({ length: plate.count }, (_, p) => p);
    for (const p of cellOrder) materialList[materialIndex[p]].cells.push(p);
    const cellMaterials = materialIndex.map(i => materialList[i]);
    const capacities = cellMaterials.map(material => materials.capacity(material, plate.dx, plate.depth));
    const faces = cellOrder.map(p => plate.neighbors[p].map(q => ({
        q, g: q >= 0 ? materials.interior(cellMaterials[p].k, cellMaterials[q].k, plate.depth) : 0,
        theta: null,
    })));
    for (const segment of segments) {
        for (const p of segment.cells) {
            const face = faces[p][segment.direction];
            if (segment.kind === 'fixed') face.g = materials.fixed(cellMaterials[p].k, plate.depth);
            else if (segment.kind === 'convective') {
                face.g = materials.convective(cellMaterials[p].k, segment.h, plate.dx, plate.depth);
            }
            face.theta = segment.theta;
        }
    }
    const diagonal = faces.map(cellFaces => sum(cellFaces.map(face => face.g)));
    return { ...plate, materialList, materialIndex, cellOrder, capacities, faces, diagonal };
}

function sourceState(model, sources, at = null) {
    const field = new Array(model.count).fill(0);
    const occupied = new Array(model.count).fill(false);
    const powers = [];
    for (const source of sources) {
        if (at !== null && !source.intervals.some(([on, off]) => on <= at && at < off)) continue;
        powers.push(source.power);
        for (const p of source.cells) {
            field[p] = occupied[p] ? field[p] + source.weight : source.weight;
            occupied[p] = true;
        }
    }
    return { field, power: sum(powers) };
}

function statistics(field, cells) {
    const first = cells[0];
    let hottest = first, minimum = field[first], total = field[first];
    for (let i = 1; i < cells.length; i++) {
        const p = cells[i];
        if (field[p] > field[hottest]) hottest = p;
        if (field[p] < minimum) minimum = field[p];
        total += field[p];
    }
    return { hottest, maximum: field[hottest], minimum, mean: total / cells.length };
}

function cell(model, p) {
    return Math.floor(p / model.width) + ' ' + p % model.width;
}

function describeField(model, field) {
    const stats = statistics(field, model.cellOrder);
    return 'max ' + f(stats.maximum, 2) + ' at ' + cell(model, stats.hottest)
        + ' min ' + f(stats.minimum, 2) + ' mean ' + f(stats.mean, 2);
}

function storedEnergy(model, field, initial, cells = model.cellOrder) {
    return sum(cells.map(p => model.capacities[p] * (field[p] - initial)));
}

function segmentSum(model, segment, term) {
    if (segment.kind === 'insulated') return 0;
    return sum(segment.cells.map(p => term(model.faces[p][segment.direction], p)));
}

function maxDifference(first, second) {
    let maximum = 0;
    for (let p = 0; p < first.length; p++) maximum = Math.max(maximum, Math.abs(first[p] - second[p]));
    return maximum;
}

function acceptRuns(model, params, sources) {
    let maxDt = model.capacities[0] / model.diagonal[0];
    for (let p = 1; p < model.count; p++) maxDt = Math.min(maxDt, model.capacities[p] / model.diagonal[p]);
    const times = [params.endTime, params.probeEvery, ...params.snapshotTimes];
    for (const source of sources) for (const interval of source.intervals) times.push(...interval);
    const runs = params.runs.map(run => {
        let status = 'accepted';
        if (times.some(value => value % run.D !== 0)) status = 'step';
        else if (run.method === 'ftcs' && run.D / 1000 > maxDt) status = 'unstable';
        return { ...run, status };
    });
    return { runs, maxDt };
}

function observe(model, params, run, n) {
    const at = n * run.D;
    const stats = statistics(run.field, model.cellOrder);
    if (run.peak === null || stats.maximum > run.peak.temperature) {
        run.peak = { temperature: stats.maximum, time: at, p: stats.hottest };
    }
    if (run.alarm === null && stats.maximum >= params.alarm) run.alarm = { time: at, p: stats.hottest };
    if (n > 0 && stats.maximum >= params.alarm) run.above += run.D;
    if (at % params.probeEvery === 0) {
        run.probeRecords.push({ time: at, values: params.probes.map(probe => run.field[probe.p]) });
    }
    if (params.snapshotTimes.includes(at)) {
        run.snapshots.set(at, {
            field: run.field.slice(),
            stored: storedEnergy(model, run.field, params.initial),
            boundary: sum(run.energyBySegment),
            source: run.sourceEnergy,
        });
    }
}

function runTransient(model, params, segments, sources, descriptor) {
    const run = {
        ...descriptor, steps: params.endTime / descriptor.D,
        field: new Array(model.count).fill(params.initial),
        snapshots: new Map(), probeRecords: [], peak: null, alarm: null, above: 0,
        energyBySegment: new Array(segments.length).fill(0), sourceEnergy: 0,
    };
    const dt = run.D / 1000;
    const advance = {
        ftcs: transient.ftcs,
        backward_euler: transient.backwardEuler,
        crank_nicolson: transient.crankNicolson,
    }[run.method];
    observe(model, params, run, 0);
    for (let n = 0; n < run.steps; n++) {
        const old = run.field;
        const active = sourceState(model, sources, n * run.D);
        const next = advance(model, old, active.field, dt);
        for (let j = 0; j < segments.length; j++) {
            const segment = segments[j];
            const horizontal = segment.direction < 2;
            const energy = dt * segmentSum(model, segment, (face, p) => {
                let temperature;
                if (run.method === 'ftcs') temperature = old[p];
                else if (horizontal) temperature = next.intermediate[p];
                else if (run.method === 'backward_euler') temperature = next.field[p];
                else temperature = (old[p] + next.field[p]) / 2;
                return face.g * (face.theta - temperature);
            });
            run.energyBySegment[j] = n === 0 ? energy : run.energyBySegment[j] + energy;
        }
        const supplied = dt * active.power;
        run.sourceEnergy = n === 0 ? supplied : run.sourceEnergy + supplied;
        run.field = next.field;
        observe(model, params, run, n + 1);
    }
    run.energy = {
        stored: storedEnergy(model, run.field, params.initial),
        boundary: sum(run.energyBySegment), source: run.sourceEnergy,
    };
    run.materialEnergy = model.materialList.map(material => storedEnergy(model, run.field, params.initial, material.cells));
    return run;
}

function solveSteady(model, params, sources) {
    const source = sourceState(model, sources).field;
    const beta = model.faces.map(faces => sum(faces.filter(face => face.theta !== null).map(face => face.g * face.theta)));
    const rhs = beta.map((value, p) => value + source[p]);
    const unitSources = sources.map(heatSource => {
        const vector = new Array(model.count).fill(0);
        for (const p of heatSource.cells) vector[p] = 1 / heatSource.cells.length;
        return vector;
    });
    const [field, base, ...responses] = steady.bandSolve(model, [rhs, beta, ...unitSources]);
    function solveIteration(name, omega = 1) {
        const result = steady.iterate(model, source, name, params.initial, params.tolerance, params.maxIterations, omega);
        const iterations = result.deltas.length;
        const rate = Math.sqrt(result.deltas[iterations - 1] / result.deltas[iterations - 3]);
        const milestones = [1000, 100, 10, 1].map(factor => {
            const index = result.deltas.findIndex(delta => delta < params.tolerance * factor);
            return index < 0 ? 'never' : index + 1;
        });
        return {
            ...result, name, omega, iterations, rate, milestones,
            error: maxDifference(result.field, field),
            residual: steady.maxResidual(model, rhs, result.field),
        };
    }
    const jacobi = solveIteration('jacobi');
    const rho = jacobi.rate;
    const omega = 2 / (1 + Math.sqrt(1 - rho * rho));
    const solvers = [
        jacobi, solveIteration('gauss_seidel'),
        solveIteration('sor', params.omega), solveIteration('sor_estimated', omega),
    ];
    return { field, base, responses, rhs, rho, omega, solvers };
}

function analyzeSteady(model, params, segments, sources, solution) {
    const { field, base, responses } = solution;
    const reconstructed = [], dutyField = [];
    for (const p of model.cellOrder) {
        let combined = base[p], duty = base[p];
        for (let s = 0; s < sources.length; s++) {
            combined += sources[s].power * responses[s][p];
            duty += (sources[s].duty * sources[s].power) * responses[s][p];
        }
        reconstructed.push(combined);
        dutyField.push(duty);
    }
    const headrooms = sources.map((source, s) => {
        let power = null, limiting = 0;
        for (const p of model.cellOrder) {
            const candidate = (params.limit - (field[p] - source.power * responses[s][p])) / responses[s][p];
            if (power === null || candidate < power) {
                power = candidate;
                limiting = p;
            }
        }
        return { power, p: limiting };
    });
    const interfaces = new Map();
    let gradient = null;
    for (const p of model.cellOrder) {
        for (const direction of [1, 3]) {
            const face = model.faces[p][direction];
            if (face.q < 0) continue;
            const q = face.q;
            const slope = Math.abs(field[p] - field[q]) / model.dx;
            if (gradient === null || slope > gradient.value) gradient = { value: slope, p, q };
            const first = Math.min(model.materialIndex[p], model.materialIndex[q]);
            const second = Math.max(model.materialIndex[p], model.materialIndex[q]);
            if (first === second) continue;
            const key = first + ',' + second;
            if (!interfaces.has(key)) interfaces.set(key, { first, second, faces: 0, forward: [], backward: [] });
            const record = interfaces.get(key);
            const phi = face.g * (field[p] - field[q]);
            const signed = model.materialIndex[p] === first ? phi : -phi;
            record.faces++;
            if (signed > 0) record.forward.push(signed);
            if (signed < 0) record.backward.push(-signed);
        }
    }
    const flows = segments.map(segment => segmentSum(model, segment, (face, p) => face.g * (face.theta - field[p])));
    const power = sum(sources.map(source => source.power));
    const balance = Math.abs(sum(flows) + power) <= 0.000001 * (sum(flows.map(Math.abs)) + power);
    return {
        dutyField, headrooms, interfaces, gradient, flows, power, balance,
        superposition: maxDifference(reconstructed, field) <= 0.000001,
    };
}

function steadyLines(model, params, segments, sources, solution, analysis) {
    const { field, responses } = solution;
    const lines = ['steady ' + describeField(model, field), ...report.temperatureRows(model, field)];
    for (const material of model.materialList) {
        const stats = statistics(field, material.cells);
        lines.push('material ' + material.code + ' ' + material.name + ' cells ' + material.cells.length
            + ' min ' + f(stats.minimum, 2) + ' max ' + f(stats.maximum, 2) + ' mean ' + f(stats.mean, 2));
    }
    for (const source of sources) {
        const stats = statistics(field, source.cells);
        lines.push('source ' + source.name + ' power ' + f(source.power, 4) + ' duty ' + f(source.duty, 4)
            + ' mean ' + f(stats.mean, 2) + ' max ' + f(stats.maximum, 2));
    }
    for (const recipient of sources) {
        for (let s = 0; s < sources.length; s++) {
            const influence = sum(recipient.cells.map(p => responses[s][p])) / recipient.cells.length;
            lines.push('influence ' + recipient.name + ' ' + sources[s].name + ' ' + f(influence, 4));
        }
    }
    lines.push('superposition ' + (analysis.superposition ? 'ok' : 'failed'));
    for (let s = 0; s < sources.length; s++) {
        for (const segment of segments) {
            const escape = segmentSum(model, segment, (face, p) => face.g * responses[s][p]);
            lines.push('path ' + sources[s].name + ' ' + segment.name + ' ' + f(escape, 4));
        }
    }
    lines.push('duty_steady ' + describeField(model, analysis.dutyField));
    for (let s = 0; s < sources.length; s++) {
        const headroom = analysis.headrooms[s];
        lines.push('headroom ' + sources[s].name + ' max_power ' + f(headroom.power, 4) + ' at ' + cell(model, headroom.p));
    }
    for (let first = 0; first < model.materialList.length; first++) {
        for (let second = first + 1; second < model.materialList.length; second++) {
            const pair = analysis.interfaces.get(first + ',' + second);
            if (!pair) continue;
            lines.push('interface ' + model.materialList[first].code + ' ' + model.materialList[second].code
                + ' faces ' + pair.faces + ' forward ' + f(sum(pair.forward), 4) + ' backward ' + f(sum(pair.backward), 4));
        }
    }
    for (let j = 0; j < segments.length; j++) {
        const segment = segments[j];
        lines.push('segment ' + segment.name + ' ' + segment.edge + ' ' + segment.kind + ' flow ' + f(analysis.flows[j], 4));
    }
    lines.push('sources ' + f(analysis.power, 4), 'balance ' + (analysis.balance ? 'ok' : 'failed'));
    lines.push('max_gradient ' + f(analysis.gradient.value, 2) + ' between '
        + cell(model, analysis.gradient.p) + ' and ' + cell(model, analysis.gradient.q));
    for (const solver of solution.solvers) {
        const relaxation = solver.name.startsWith('sor') ? ' omega ' + f(solver.omega, 4) : '';
        lines.push('solver ' + solver.name + relaxation + ' iterations ' + solver.iterations
            + ' converged ' + (solver.converged ? 'yes' : 'no') + ' rate ' + f(solver.rate, 6)
            + ' milestones ' + solver.milestones.join(' '));
    }
    return lines;
}

function runHeading(run) {
    return 'run ' + run.name + ' ' + run.method + ' dt ' + time(run.D);
}

function snapshotLines(model, params, runs, maxDt) {
    const lines = [];
    for (const run of runs) {
        if (run.status !== 'accepted') {
            const extra = run.status === 'unstable' ? ' max_dt ' + f(maxDt, 4) : '';
            lines.push(runHeading(run) + ' rejected ' + run.status + extra);
            continue;
        }
        for (const at of params.snapshotTimes) {
            const field = run.snapshots.get(at).field;
            lines.push(runHeading(run) + ' time ' + time(at) + ' ' + describeField(model, field));
            lines.push(...report.temperatureRows(model, field));
        }
    }
    return lines;
}

function probeLines(params, runs) {
    const lines = ['run,time,probe,temperature'];
    for (const run of runs) {
        if (run.status !== 'accepted') continue;
        for (const record of run.probeRecords) {
            for (let p = 0; p < params.probes.length; p++) {
                lines.push([run.name, time(record.time), params.probes[p].name, f(record.values[p], 3)].join(','));
            }
        }
    }
    return lines;
}

function energyText(energy) {
    return 'stored ' + f(energy.stored, 2) + ' boundary ' + f(energy.boundary, 2) + ' source ' + f(energy.source, 2);
}

function probeSummary(run, index) {
    const initial = run.probeRecords[0];
    let maximum = initial.values[index], minimum = maximum, maxTime = initial.time, minTime = initial.time;
    for (let r = 1; r < run.probeRecords.length; r++) {
        const record = run.probeRecords[r], temperature = record.values[index];
        if (temperature > maximum) {
            maximum = temperature;
            maxTime = record.time;
        }
        if (temperature < minimum) {
            minimum = temperature;
            minTime = record.time;
        }
    }
    return 'max ' + f(maximum, 3) + ' time ' + time(maxTime) + ' min ' + f(minimum, 3) + ' time ' + time(minTime);
}

function comparisonLines(model, params, segments, runs, reference, maxDt, solution) {
    const lines = ['ftcs_max_dt ' + f(maxDt, 4)];
    for (const run of runs) {
        if (run.status !== 'accepted') {
            lines.push(runHeading(run) + ' rejected ' + run.status);
            continue;
        }
        const alarm = run.alarm === null ? 'never' : time(run.alarm.time) + ' at ' + cell(model, run.alarm.p);
        lines.push(runHeading(run) + ' steps ' + run.steps + ' peak ' + f(run.peak.temperature, 2)
            + ' time ' + time(run.peak.time) + ' at ' + cell(model, run.peak.p) + ' alarm ' + alarm + ' above ' + time(run.above));
        const energy = run.energy;
        const balance = Math.abs(energy.stored - energy.boundary - energy.source)
            <= 0.000001 * (Math.abs(energy.stored) + Math.abs(energy.boundary) + Math.abs(energy.source));
        lines.push('energy ' + run.name + ' ' + energyText(energy) + ' balance ' + (balance ? 'ok' : 'failed'));
        for (const at of params.snapshotTimes) {
            lines.push('energy_at ' + run.name + ' time ' + time(at) + ' ' + energyText(run.snapshots.get(at)));
        }
        for (let m = 0; m < model.materialList.length; m++) {
            lines.push('energy_material ' + run.name + ' ' + model.materialList[m].code + ' ' + f(run.materialEnergy[m], 2));
        }
        for (let j = 0; j < segments.length; j++) {
            lines.push('energy_segment ' + run.name + ' ' + segments[j].name + ' ' + f(run.energyBySegment[j], 2));
        }
        for (let p = 0; p < params.probes.length; p++) {
            lines.push('probe_summary ' + run.name + ' ' + params.probes[p].name + ' ' + probeSummary(run, p));
        }
        if (run.name !== reference.name) {
            for (const at of params.snapshotTimes) {
                const field = run.snapshots.get(at).field, other = reference.snapshots.get(at).field;
                const squared = field.map((value, p) => {
                    const error = Math.abs(value - other[p]);
                    return error * error;
                });
                lines.push('compare ' + run.name + ' ' + reference.name + ' time ' + time(at)
                    + ' max_diff ' + f(maxDifference(field, other), 6) + ' rms_diff ' + f(Math.sqrt(sum(squared) / model.count), 6));
            }
        }
        lines.push('final ' + run.name + ' steady_max_diff ' + f(maxDifference(run.field, solution.field), 6));
    }
    lines.push('steady direct max_residual ' + f(steady.maxResidual(model, solution.rhs, solution.field), 6));
    for (const solver of solution.solvers) {
        lines.push('steady ' + solver.name + ' iterations ' + solver.iterations + ' max_diff ' + f(solver.error, 6)
            + ' max_residual ' + f(solver.residual, 6));
    }
    lines.push('jacobi_spectral_radius ' + f(solution.rho, 6) + ' squared ' + f(solution.rho * solution.rho, 6));
    lines.push('omega_estimated ' + f(solution.omega, 4));
    return lines;
}

function isothermLines(model, params, reference, field) {
    const initial = report.isothermRows(model, field, params.bands);
    const lines = ['isotherms steady counts ' + initial.counts.join(' '), ...initial.lines];
    for (const at of params.snapshotTimes) {
        const map = report.isothermRows(model, reference.snapshots.get(at).field, params.bands);
        lines.push('isotherms ' + reference.name + ' time ' + time(at) + ' counts ' + map.counts.join(' '), ...map.lines);
    }
    return lines;
}

function main() {
    const plate = mesh.readPlate();
    const params = readParams(plate);
    const { segments, sources } = readBoundary(plate, params.endTime);
    const model = buildModel(plate, materials.readMaterials(), segments);
    const accepted = acceptRuns(model, params, sources);
    const solution = solveSteady(model, params, sources);
    const analysis = analyzeSteady(model, params, segments, sources, solution);
    const runs = accepted.runs.map(run => run.status === 'accepted'
        ? runTransient(model, params, segments, sources, run) : run);
    const reference = runs.find(run => run.name === params.reference);
    report.writeFiles({
        'snapshots.txt': snapshotLines(model, params, runs, accepted.maxDt),
        'probes.csv': probeLines(params, runs),
        'steady_state.txt': steadyLines(model, params, segments, sources, solution, analysis),
        'solver_comparison.txt': comparisonLines(model, params, segments, runs, reference, accepted.maxDt, solution),
        'isotherms.txt': isothermLines(model, params, reference, solution.field),
    });
}

main();
