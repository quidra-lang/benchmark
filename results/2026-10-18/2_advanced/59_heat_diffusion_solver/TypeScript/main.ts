import { readFileSync } from 'node:fs';
import { readPlate, segmentCells, sourceCells, type Mesh, type Edge } from './mesh.ts';
import { readMaterials, capacity, interior, fixed, convective, type Material } from './materials.ts';
import { ftcs, backwardEuler, crankNicolson, type ThermalModel, type Face, type Method } from './transient.ts';
import { iterate, bandSolve, maxResidual, type Solver, type Iteration } from './steady.ts';
import { fixed as f, time, temperatureRows, isothermRows, writeFiles } from './report.ts';

interface Probe { name: string; p: number }
interface RunSpec { name: string; method: Method; D: number }
interface Parameters {
    initial: number; endTime: number; snapshotTimes: number[]; probeEvery: number; probes: Probe[]; runs: RunSpec[];
    reference: string; tolerance: number; maxIterations: number; omega: number; bands: number[]; alarm: number; limit: number;
}
interface Segment { name: string; edge: Edge; kind: 'fixed' | 'convective' | 'insulated'; direction: number; cells: number[]; h: number | null; theta: number | null }
interface Source { name: string; power: number; cells: number[]; intervals: [number, number][]; duty: number; weight: number }
interface Model extends ThermalModel { materialList: Material[]; materialIndex: number[]; cellOrder: number[] }
interface Energy { stored: number; boundary: number; source: number }
interface Snapshot extends Energy { field: number[] }
interface Peak { temperature: number; time: number; p: number }
interface ProbeRecord { time: number; values: number[] }
interface AcceptedRun extends RunSpec {
    status: 'accepted'; steps: number; field: number[]; snapshots: Map<number, Snapshot>; probeRecords: ProbeRecord[];
    peak: Peak; alarm: { time: number; p: number } | null; above: number; energyBySegment: number[]; sourceEnergy: number;
    energy: Energy; materialEnergy: number[];
}
interface RejectedRun extends RunSpec { status: 'step' | 'unstable' }
type Run = AcceptedRun | RejectedRun;
type RunDescriptor = RunSpec & { status: 'accepted' | 'step' | 'unstable' };
interface SolverResult extends Iteration { name: Solver; omega: number; iterations: number; rate: number; milestones: (number | 'never')[]; error: number; residual: number }
interface Solution { field: number[]; base: number[]; responses: number[][]; rhs: number[]; rho: number; omega: number; solvers: SolverResult[] }
interface InterfaceFlow { first: number; second: number; faces: number; forward: number[]; backward: number[] }
interface SteadyAnalysis {
    dutyField: number[]; headrooms: { power: number; p: number }[]; interfaces: Map<string, InterfaceFlow>;
    gradient: { value: number; p: number; q: number }; flows: number[]; power: number; balance: boolean; superposition: boolean;
}
function sum(values: number[]): number { if (!values.length) return 0; let value = values[0]; for (let i = 1; i < values.length; i++) value += values[i]; return value; }
function readMethod(word: string): Method { if (word === 'ftcs' || word === 'backward_euler' || word === 'crank_nicolson') return word; throw new Error('Unknown method'); }
function readEdge(word: string): Edge { if (word === 'left' || word === 'right' || word === 'top' || word === 'bottom') return word; throw new Error('Unknown edge'); }
function readParameters(mesh: Mesh): Parameters {
    const p: Parameters = { initial: 0, endTime: 0, snapshotTimes: [], probeEvery: 0, probes: [], runs: [], reference: '', tolerance: 0, maxIterations: 0, omega: 0, bands: [], alarm: 0, limit: 0 };
    for (const line of readFileSync('input/params.txt', 'ascii').trimEnd().split('\n')) {
        const [key, ...w] = line.split(' ');
        switch (key) {
            case 'initial': p.initial = Number(w[0]); break;
            case 'end_time': p.endTime = Number(w[0]); break;
            case 'snapshots': p.snapshotTimes = w.map(Number); break;
            case 'probe_every': p.probeEvery = Number(w[0]); break;
            case 'probe': p.probes.push({ name: w[0], p: Number(w[1]) * mesh.width + Number(w[2]) }); break;
            case 'run': p.runs.push({ name: w[0], method: readMethod(w[1]), D: Number(w[2]) }); break;
            case 'reference': p.reference = w[0]; break;
            case 'tolerance': p.tolerance = Number(w[0]); break;
            case 'max_iterations': p.maxIterations = Number(w[0]); break;
            case 'omega': p.omega = Number(w[0]); break;
            case 'bands': p.bands = w.map(Number); break;
            case 'alarm': p.alarm = Number(w[0]); break;
            case 'limit': p.limit = Number(w[0]); break;
        }
    }
    return p;
}
function readBoundary(mesh: Mesh, endTime: number): { segments: Segment[]; sources: Source[] } {
    const segments: Segment[] = [], sources: Source[] = [], directions: Record<Edge, number> = { left: 0, right: 1, top: 2, bottom: 3 };
    for (const line of readFileSync('input/boundary.txt', 'ascii').trimEnd().split('\n')) {
        const w = line.split(' ');
        if (w[0] === 'segment') {
            const edge = readEdge(w[2]), kind = w[5];
            if (kind !== 'fixed' && kind !== 'convective' && kind !== 'insulated') throw new Error('Unknown boundary');
            segments.push({ name: w[1], edge, kind, direction: directions[edge], cells: segmentCells(mesh, edge, Number(w[3]), Number(w[4])),
                h: kind === 'convective' ? Number(w[6]) : null, theta: kind === 'fixed' ? Number(w[6]) : kind === 'convective' ? Number(w[7]) : null });
        } else {
            const [r1, c1, r2, c2, power] = w.slice(2, 7).map(Number), cells = sourceCells(mesh, r1, c1, r2, c2), intervals: [number, number][] = [];
            for (let i = 7; i < w.length; i += 2) intervals.push([Number(w[i]), Number(w[i + 1])]);
            const duty = sum(intervals.map(([on, off]) => Math.min(off, endTime) - Math.min(on, endTime))) / endTime;
            sources.push({ name: w[1], power, cells, intervals, duty, weight: power / cells.length });
        }
    }
    return { segments, sources };
}
function buildModel(mesh: Mesh, materialList: Material[], segments: Segment[]): Model {
    const indices = new Map(materialList.map((m, i) => [m.code, i])), materialIndex = mesh.codes.map(code => indices.get(code)!), cellOrder = Array.from({ length: mesh.count }, (_, p) => p);
    for (const p of cellOrder) materialList[materialIndex[p]].cells.push(p);
    const cellMaterials = materialIndex.map(i => materialList[i]), capacities = cellMaterials.map(m => capacity(m, mesh.dx, mesh.depth));
    const faces: Face[][] = cellOrder.map(p => mesh.neighbors[p].map(q => ({ q, g: q >= 0 ? interior(cellMaterials[p].k, cellMaterials[q].k, mesh.depth) : 0, theta: null })));
    for (const segment of segments) for (const p of segment.cells) {
        const face = faces[p][segment.direction];
        if (segment.kind === 'fixed') face.g = fixed(cellMaterials[p].k, mesh.depth);
        else if (segment.kind === 'convective') face.g = convective(cellMaterials[p].k, segment.h!, mesh.dx, mesh.depth);
        face.theta = segment.theta;
    }
    return { ...mesh, materialList, materialIndex, cellOrder, capacities, faces, diagonal: faces.map(cell => sum(cell.map(face => face.g))) };
}
function sourceState(model: Model, sources: Source[], at: number | null = null): { field: number[]; power: number } {
    const field: number[] = Array(model.count).fill(0), occupied: boolean[] = Array(model.count).fill(false), powers: number[] = [];
    for (const source of sources) {
        if (at !== null && !source.intervals.some(([on, off]) => on <= at && at < off)) continue;
        powers.push(source.power); for (const p of source.cells) { field[p] = occupied[p] ? field[p] + source.weight : source.weight; occupied[p] = true; }
    }
    return { field, power: sum(powers) };
}
function statistics(field: number[], cells: number[]) {
    let hottest = cells[0], minimum = field[hottest], total = minimum;
    for (let i = 1; i < cells.length; i++) { const p = cells[i]; if (field[p] > field[hottest]) hottest = p; if (field[p] < minimum) minimum = field[p]; total += field[p]; }
    return { hottest, maximum: field[hottest], minimum, mean: total / cells.length };
}
const cell = (model: Model, p: number): string => `${Math.floor(p / model.width)} ${p % model.width}`;
function describeField(model: Model, field: number[]): string { const s = statistics(field, model.cellOrder); return `max ${f(s.maximum, 2)} at ${cell(model, s.hottest)} min ${f(s.minimum, 2)} mean ${f(s.mean, 2)}`; }
const storedEnergy = (model: Model, field: number[], initial: number, cells = model.cellOrder): number => sum(cells.map(p => model.capacities[p] * (field[p] - initial)));
const segmentSum = (model: Model, segment: Segment, term: (face: Face, p: number) => number): number => segment.kind === 'insulated' ? 0 : sum(segment.cells.map(p => term(model.faces[p][segment.direction], p)));
function maxDifference(first: number[], second: number[]): number { let maximum = 0; for (let p = 0; p < first.length; p++) maximum = Math.max(maximum, Math.abs(first[p] - second[p])); return maximum; }
function acceptRuns(model: Model, params: Parameters, sources: Source[]): { runs: RunDescriptor[]; maxDt: number } {
    let maxDt = model.capacities[0] / model.diagonal[0]; for (let p = 1; p < model.count; p++) maxDt = Math.min(maxDt, model.capacities[p] / model.diagonal[p]);
    const times = [params.endTime, params.probeEvery, ...params.snapshotTimes]; for (const source of sources) for (const interval of source.intervals) times.push(...interval);
    const runs = params.runs.map((run): RunDescriptor => ({ ...run, status: times.some(t => t % run.D !== 0) ? 'step' : run.method === 'ftcs' && run.D / 1000 > maxDt ? 'unstable' : 'accepted' }));
    return { runs, maxDt };
}
function observe(model: Model, params: Parameters, run: AcceptedRun, n: number): void {
    const at = n * run.D, stats = statistics(run.field, model.cellOrder);
    if (stats.maximum > run.peak.temperature) run.peak = { temperature: stats.maximum, time: at, p: stats.hottest };
    if (run.alarm === null && stats.maximum >= params.alarm) run.alarm = { time: at, p: stats.hottest };
    if (n > 0 && stats.maximum >= params.alarm) run.above += run.D;
    if (at % params.probeEvery === 0) run.probeRecords.push({ time: at, values: params.probes.map(probe => run.field[probe.p]) });
    if (params.snapshotTimes.includes(at)) run.snapshots.set(at, { field: run.field.slice(), stored: storedEnergy(model, run.field, params.initial), boundary: sum(run.energyBySegment), source: run.sourceEnergy });
}
function runTransient(model: Model, params: Parameters, segments: Segment[], sources: Source[], descriptor: RunSpec): AcceptedRun {
    const run: AcceptedRun = { ...descriptor, status: 'accepted', steps: params.endTime / descriptor.D, field: Array(model.count).fill(params.initial), snapshots: new Map(), probeRecords: [],
        peak: { temperature: params.initial, time: 0, p: 0 }, alarm: null, above: 0, energyBySegment: Array(segments.length).fill(0), sourceEnergy: 0, energy: { stored: 0, boundary: 0, source: 0 }, materialEnergy: [] };
    const dt = run.D / 1000, advance = { ftcs, backward_euler: backwardEuler, crank_nicolson: crankNicolson }[run.method]; observe(model, params, run, 0);
    for (let n = 0; n < run.steps; n++) {
        const old = run.field, active = sourceState(model, sources, n * run.D), next = advance(model, old, active.field, dt);
        for (let j = 0; j < segments.length; j++) {
            const segment = segments[j], energy = dt * segmentSum(model, segment, (face, p) => {
                const temperature = run.method === 'ftcs' ? old[p] : segment.direction < 2 ? next.intermediate![p] : run.method === 'backward_euler' ? next.field[p] : (old[p] + next.field[p]) / 2;
                return face.g * (face.theta! - temperature);
            });
            run.energyBySegment[j] = n === 0 ? energy : run.energyBySegment[j] + energy;
        }
        const supplied = dt * active.power; run.sourceEnergy = n === 0 ? supplied : run.sourceEnergy + supplied; run.field = next.field; observe(model, params, run, n + 1);
    }
    run.energy = { stored: storedEnergy(model, run.field, params.initial), boundary: sum(run.energyBySegment), source: run.sourceEnergy };
    run.materialEnergy = model.materialList.map(m => storedEnergy(model, run.field, params.initial, m.cells)); return run;
}
function solveSteady(model: Model, params: Parameters, sources: Source[]): Solution {
    const source = sourceState(model, sources).field, beta = model.faces.map(faces => sum(faces.filter(face => face.theta !== null).map(face => face.g * face.theta!))), rhs = beta.map((value, p) => value + source[p]);
    const unitSources = sources.map(s => { const vector: number[] = Array(model.count).fill(0); for (const p of s.cells) vector[p] = 1 / s.cells.length; return vector; });
    const [field, base, ...responses] = bandSolve(model, [rhs, beta, ...unitSources]);
    function solve(name: Solver, omega = 1): SolverResult {
        const result = iterate(model, source, name, params.initial, params.tolerance, params.maxIterations, omega), iterations = result.deltas.length;
        const rate = Math.sqrt(result.deltas[iterations - 1] / result.deltas[iterations - 3]);
        const milestones = [1000, 100, 10, 1].map((factor): number | 'never' => { const i = result.deltas.findIndex(delta => delta < params.tolerance * factor); return i < 0 ? 'never' : i + 1; });
        return { ...result, name, omega, iterations, rate, milestones, error: maxDifference(result.field, field), residual: maxResidual(model, rhs, result.field) };
    }
    const jacobi = solve('jacobi'), rho = jacobi.rate, omega = 2 / (1 + Math.sqrt(1 - rho * rho));
    return { field, base, responses, rhs, rho, omega, solvers: [jacobi, solve('gauss_seidel'), solve('sor', params.omega), solve('sor_estimated', omega)] };
}
function analyzeSteady(model: Model, params: Parameters, segments: Segment[], sources: Source[], solution: Solution): SteadyAnalysis {
    const { field, base, responses } = solution, reconstructed: number[] = [], dutyField: number[] = [];
    for (const p of model.cellOrder) { let combined = base[p], duty = base[p]; for (let s = 0; s < sources.length; s++) { combined += sources[s].power * responses[s][p]; duty += (sources[s].duty * sources[s].power) * responses[s][p]; } reconstructed.push(combined); dutyField.push(duty); }
    const headrooms = sources.map((source, s) => {
        let power = Infinity, limiting = 0;
        for (const p of model.cellOrder) { const candidate = (params.limit - (field[p] - source.power * responses[s][p])) / responses[s][p]; if (candidate < power) { power = candidate; limiting = p; } }
        return { power, p: limiting };
    });
    const interfaces = new Map<string, InterfaceFlow>(); let gradient = { value: -1, p: 0, q: 1 };
    for (const p of model.cellOrder) for (const direction of [1, 3]) {
        const face = model.faces[p][direction], q = face.q; if (q < 0) continue;
        const slope = Math.abs(field[p] - field[q]) / model.dx; if (slope > gradient.value) gradient = { value: slope, p, q };
        const first = Math.min(model.materialIndex[p], model.materialIndex[q]), second = Math.max(model.materialIndex[p], model.materialIndex[q]); if (first === second) continue;
        const key = `${first},${second}`; let record = interfaces.get(key);
        if (record === undefined) { record = { first, second, faces: 0, forward: [], backward: [] }; interfaces.set(key, record); }
        const phi = face.g * (field[p] - field[q]), signed = model.materialIndex[p] === first ? phi : -phi; record.faces++; if (signed > 0) record.forward.push(signed); if (signed < 0) record.backward.push(-signed);
    }
    const flows = segments.map(s => segmentSum(model, s, (face, p) => face.g * (face.theta! - field[p]))), power = sum(sources.map(s => s.power));
    return { dutyField, headrooms, interfaces, gradient, flows, power, balance: Math.abs(sum(flows) + power) <= 0.000001 * (sum(flows.map(Math.abs)) + power), superposition: maxDifference(reconstructed, field) <= 0.000001 };
}
function steadyLines(model: Model, segments: Segment[], sources: Source[], solution: Solution, analysis: SteadyAnalysis): string[] {
    const { field, responses } = solution, lines = ['steady ' + describeField(model, field), ...temperatureRows(model, field)];
    for (const m of model.materialList) { const s = statistics(field, m.cells); lines.push(`material ${m.code} ${m.name} cells ${m.cells.length} min ${f(s.minimum, 2)} max ${f(s.maximum, 2)} mean ${f(s.mean, 2)}`); }
    for (const source of sources) { const s = statistics(field, source.cells); lines.push(`source ${source.name} power ${f(source.power, 4)} duty ${f(source.duty, 4)} mean ${f(s.mean, 2)} max ${f(s.maximum, 2)}`); }
    for (const recipient of sources) for (let s = 0; s < sources.length; s++) lines.push(`influence ${recipient.name} ${sources[s].name} ${f(sum(recipient.cells.map(p => responses[s][p])) / recipient.cells.length, 4)}`);
    lines.push('superposition ' + (analysis.superposition ? 'ok' : 'failed'));
    for (let s = 0; s < sources.length; s++) for (const segment of segments) lines.push(`path ${sources[s].name} ${segment.name} ${f(segmentSum(model, segment, (face, p) => face.g * responses[s][p]), 4)}`);
    lines.push('duty_steady ' + describeField(model, analysis.dutyField));
    for (let s = 0; s < sources.length; s++) lines.push(`headroom ${sources[s].name} max_power ${f(analysis.headrooms[s].power, 4)} at ${cell(model, analysis.headrooms[s].p)}`);
    for (let first = 0; first < model.materialList.length; first++) for (let second = first + 1; second < model.materialList.length; second++) {
        const pair = analysis.interfaces.get(`${first},${second}`); if (pair) lines.push(`interface ${model.materialList[first].code} ${model.materialList[second].code} faces ${pair.faces} forward ${f(sum(pair.forward), 4)} backward ${f(sum(pair.backward), 4)}`);
    }
    segments.forEach((s, j) => lines.push(`segment ${s.name} ${s.edge} ${s.kind} flow ${f(analysis.flows[j], 4)}`));
    const g = analysis.gradient; lines.push(`sources ${f(analysis.power, 4)}`, 'balance ' + (analysis.balance ? 'ok' : 'failed'), `max_gradient ${f(g.value, 2)} between ${cell(model, g.p)} and ${cell(model, g.q)}`);
    for (const s of solution.solvers) lines.push(`solver ${s.name}${s.name.startsWith('sor') ? ' omega ' + f(s.omega, 4) : ''} iterations ${s.iterations} converged ${s.converged ? 'yes' : 'no'} rate ${f(s.rate, 6)} milestones ${s.milestones.join(' ')}`);
    return lines;
}
const heading = (run: RunSpec): string => `run ${run.name} ${run.method} dt ${time(run.D)}`;
function snapshotLines(model: Model, params: Parameters, runs: Run[], maxDt: number): string[] {
    const lines: string[] = [];
    for (const run of runs) {
        if (run.status !== 'accepted') { lines.push(heading(run) + ' rejected ' + run.status + (run.status === 'unstable' ? ' max_dt ' + f(maxDt, 4) : '')); continue; }
        for (const at of params.snapshotTimes) { const field = run.snapshots.get(at)!.field; lines.push(`${heading(run)} time ${time(at)} ${describeField(model, field)}`, ...temperatureRows(model, field)); }
    }
    return lines;
}
function probeLines(params: Parameters, runs: Run[]): string[] {
    const lines = ['run,time,probe,temperature'];
    for (const run of runs) if (run.status === 'accepted') for (const record of run.probeRecords) params.probes.forEach((p, i) => lines.push(`${run.name},${time(record.time)},${p.name},${f(record.values[i], 3)}`));
    return lines;
}
const energyText = (e: Energy): string => `stored ${f(e.stored, 2)} boundary ${f(e.boundary, 2)} source ${f(e.source, 2)}`;
function probeSummary(run: AcceptedRun, index: number): string {
    const initial = run.probeRecords[0]; let maximum = initial.values[index], minimum = maximum, maxTime = initial.time, minTime = initial.time;
    for (let r = 1; r < run.probeRecords.length; r++) { const record = run.probeRecords[r], value = record.values[index]; if (value > maximum) { maximum = value; maxTime = record.time; } if (value < minimum) { minimum = value; minTime = record.time; } }
    return `max ${f(maximum, 3)} time ${time(maxTime)} min ${f(minimum, 3)} time ${time(minTime)}`;
}
function comparisonLines(model: Model, params: Parameters, segments: Segment[], runs: Run[], reference: AcceptedRun, maxDt: number, solution: Solution): string[] {
    const lines = ['ftcs_max_dt ' + f(maxDt, 4)];
    for (const run of runs) {
        if (run.status !== 'accepted') { lines.push(heading(run) + ' rejected ' + run.status); continue; }
        const alarm = run.alarm === null ? 'never' : `${time(run.alarm.time)} at ${cell(model, run.alarm.p)}`, peak = run.peak;
        lines.push(`${heading(run)} steps ${run.steps} peak ${f(peak.temperature, 2)} time ${time(peak.time)} at ${cell(model, peak.p)} alarm ${alarm} above ${time(run.above)}`);
        const e = run.energy, balance = Math.abs(e.stored - e.boundary - e.source) <= 0.000001 * (Math.abs(e.stored) + Math.abs(e.boundary) + Math.abs(e.source));
        lines.push(`energy ${run.name} ${energyText(e)} balance ${balance ? 'ok' : 'failed'}`);
        for (const at of params.snapshotTimes) lines.push(`energy_at ${run.name} time ${time(at)} ${energyText(run.snapshots.get(at)!)}`);
        model.materialList.forEach((m, i) => lines.push(`energy_material ${run.name} ${m.code} ${f(run.materialEnergy[i], 2)}`));
        segments.forEach((s, i) => lines.push(`energy_segment ${run.name} ${s.name} ${f(run.energyBySegment[i], 2)}`));
        params.probes.forEach((p, i) => lines.push(`probe_summary ${run.name} ${p.name} ${probeSummary(run, i)}`));
        if (run.name !== reference.name) for (const at of params.snapshotTimes) {
            const field = run.snapshots.get(at)!.field, other = reference.snapshots.get(at)!.field, squared = field.map((value, p) => { const error = Math.abs(value - other[p]); return error * error; });
            lines.push(`compare ${run.name} ${reference.name} time ${time(at)} max_diff ${f(maxDifference(field, other), 6)} rms_diff ${f(Math.sqrt(sum(squared) / model.count), 6)}`);
        }
        lines.push(`final ${run.name} steady_max_diff ${f(maxDifference(run.field, solution.field), 6)}`);
    }
    lines.push('steady direct max_residual ' + f(maxResidual(model, solution.rhs, solution.field), 6));
    for (const s of solution.solvers) lines.push(`steady ${s.name} iterations ${s.iterations} max_diff ${f(s.error, 6)} max_residual ${f(s.residual, 6)}`);
    lines.push(`jacobi_spectral_radius ${f(solution.rho, 6)} squared ${f(solution.rho * solution.rho, 6)}`, 'omega_estimated ' + f(solution.omega, 4)); return lines;
}
function isothermLines(model: Model, params: Parameters, reference: AcceptedRun, field: number[]): string[] {
    const steady = isothermRows(model, field, params.bands), lines = ['isotherms steady counts ' + steady.counts.join(' '), ...steady.lines];
    for (const at of params.snapshotTimes) { const map = isothermRows(model, reference.snapshots.get(at)!.field, params.bands); lines.push(`isotherms ${reference.name} time ${time(at)} counts ${map.counts.join(' ')}`, ...map.lines); }
    return lines;
}
function main(): void {
    const mesh = readPlate(), params = readParameters(mesh), { segments, sources } = readBoundary(mesh, params.endTime), model = buildModel(mesh, readMaterials(), segments);
    const accepted = acceptRuns(model, params, sources), solution = solveSteady(model, params, sources), analysis = analyzeSteady(model, params, segments, sources, solution);
    const runs = accepted.runs.map((r): Run => r.status === 'accepted' ? runTransient(model, params, segments, sources, r) : { ...r, status: r.status });
    const reference = runs.find((r): r is AcceptedRun => r.status === 'accepted' && r.name === params.reference)!;
    writeFiles({ 'snapshots.txt': snapshotLines(model, params, runs, accepted.maxDt), 'probes.csv': probeLines(params, runs), 'steady_state.txt': steadyLines(model, segments, sources, solution, analysis),
        'solver_comparison.txt': comparisonLines(model, params, segments, runs, reference, accepted.maxDt, solution), 'isotherms.txt': isothermLines(model, params, reference, solution.field) });
}
main();
