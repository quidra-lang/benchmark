'use strict';

const traceIO = require('./trace_io');
const hazards = require('./hazards');
const pipeline = require('./pipeline');
const {BTB, RAS, DirectionPredictor, storage} = require('./predictors');
const {decimal, percentage, fraction, hex, cycleHeader, diagramRow, write} = require('./report');

const CLASSES = ['ALU', 'MUL', 'LOAD', 'STORE', 'BRANCH', 'JUMP', 'NOP'];
const CAUSES = ['control', 'structural', 'load_use', 'raw'];
const KINDS = ['direction', 'btb_miss', 'wrong_target'];
const STAGES = ['IF', 'ID', 'EX', 'MEM', 'WB'];
const OPERANDS = {
    ALU: ['required', 'required', 'optional'], MUL: ['required', 'required', 'required'],
    LOAD: ['required', 'required', 'none'], STORE: ['none', 'required', 'required'],
    BRANCH: ['none', 'required', 'optional'], JUMP: ['optional', 'optional', 'none'],
    NOP: ['none', 'none', 'none']
};
const zeros = names => Object.fromEntries(names.map(name => [name, 0]));
const namedCounts = (names, counts) => names.map(name => `${name} ${counts[name]}`).join(' ');
const asciiCompare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const registerText = register => register === null ? '-' : `r${register}`;

function validate(line, statics) {
    const fields = line.split(' ');
    if (fields.length !== 8 || fields.includes('')) return {reason: 'fields'};
    const [pcText, className, rdText, rs1Text, rs2Text, outcome, targetText, addressText] = fields;
    const pc = traceIO.parseHex(pcText);
    if (pc === null || pc % 4 !== 0) return {reason: 'pc'};
    if (!CLASSES.includes(className)) return {reason: 'class'};
    const registers = [rdText, rs1Text, rs2Text].map(traceIO.parseRegister);
    if (registers.some(register => register === undefined)) return {reason: 'register'};
    if (OPERANDS[className].some((mode, i) => mode === 'required' && registers[i] === null
        || mode === 'none' && registers[i] !== null)) return {reason: 'operands'};
    if (className === 'BRANCH' ? outcome !== 'T' && outcome !== 'N'
        : className === 'JUMP' ? outcome !== 'T' : outcome !== '-') return {reason: 'taken'};
    const control = className === 'BRANCH' || className === 'JUMP';
    let target = null;
    if (control) {
        target = traceIO.parseHex(targetText);
        if (target === null || target % 4 !== 0 || target === pc + 4) return {reason: 'target'};
    } else if (targetText !== '-') return {reason: 'target'};
    let address = null;
    if (className === 'LOAD' || className === 'STORE') {
        address = traceIO.parseHex(addressText);
        if (address === null || address % 4 !== 0) return {reason: 'address'};
    } else if (addressText !== '-') return {reason: 'address'};
    const [rd, rs1, rs2] = registers;
    const first = statics.get(pc);
    if (first && (first.className !== className || first.rd !== rd || first.rs1 !== rs1 || first.rs2 !== rs2
        || (className === 'BRANCH' || className === 'JUMP' && rs1 === null) && first.target !== target)) {
        return {reason: 'conflict'};
    }
    return {instruction: {pc, className, rd, rs1, rs2, outcome, target, address, control,
        nextPC: outcome === 'T' ? target : pc + 4}};
}

function checkTrace(lines) {
    const instructions = [];
    const statics = new Map();
    const rejected = [];
    const gaps = [];
    lines.forEach((line, index) => {
        const result = validate(line, statics);
        if (result.reason) {
            rejected.push({line: index + 1, reason: result.reason});
            return;
        }
        const instruction = {...result.instruction, line: index + 1, number: instructions.length + 1};
        const previous = instructions.at(-1);
        if (previous && instruction.pc !== previous.nextPC) {
            gaps.push({line: instruction.line, expected: previous.nextPC, found: instruction.pc});
        }
        if (!statics.has(instruction.pc)) statics.set(instruction.pc, {...instruction, executions: []});
        statics.get(instruction.pc).executions.push(instructions.length);
        instructions.push(instruction);
    });
    hazards.attachSources(instructions);
    return {lineCount: lines.length, instructions, statics, rejected, gaps};
}

function predict(instructions, specification, config) {
    const btb = new BTB(config.btb);
    const ras = new RAS(config.ras);
    const direction = new DirectionPredictor(specification);
    const results = [];
    const byPC = new Map();
    const counts = zeros(['control', 'mis', 'branches', 'branchMis', 'jumps', 'jumpMis',
        'hits', 'calls', 'returns', 'rasPredicted', 'rasCorrect']);
    const kinds = zeros(KINDS);
    for (const instruction of instructions) {
        if (!instruction.control) {
            results.push({mispredicted: false, predictedNext: instruction.nextPC, kind: null});
            continue;
        }
        const branch = instruction.className === 'BRANCH';
        const taken = instruction.outcome === 'T';
        counts.control++;
        counts[branch ? 'branches' : 'jumps']++;
        let candidate = btb.lookup(instruction.pc);
        if (candidate !== null) counts.hits++;
        if (instruction.className === 'JUMP' && instruction.rd === null && instruction.rs1 === 31) {
            counts.returns++;
            const returned = ras.pop();
            if (returned !== null) {
                candidate = returned;
                counts.rasPredicted++;
                if (returned === instruction.target) counts.rasCorrect++;
            }
        }
        if (instruction.className === 'JUMP' && instruction.rd === 31) {
            counts.calls++;
            ras.push(instruction.pc + 4);
        }
        const perfect = specification.scheme === 'PERFECT';
        const outcomePrediction = branch && !perfect ? direction.predict(instruction.pc, instruction.target) : null;
        let predictedNext = instruction.pc + 4;
        if (perfect) predictedNext = instruction.nextPC;
        else if (!branch || outcomePrediction.taken) predictedNext = candidate ?? predictedNext;
        const mispredicted = predictedNext !== instruction.nextPC;
        let kind = null;
        if (mispredicted) {
            kind = branch && outcomePrediction.taken !== taken ? 'direction'
                : candidate === null ? 'btb_miss' : 'wrong_target';
            counts.mis++;
            counts[branch ? 'branchMis' : 'jumpMis']++;
            kinds[kind]++;
        }
        results.push({mispredicted, predictedNext, kind});
        if (!byPC.has(instruction.pc)) byPC.set(instruction.pc, {executions: 0, taken: 0, mis: 0});
        const group = byPC.get(instruction.pc);
        group.executions++;
        if (taken) group.taken++;
        if (mispredicted) group.mis++;
        if (branch && !perfect) direction.update(outcomePrediction, taken);
        if (taken) btb.insert(instruction.pc, instruction.target);
    }
    return {specification, results, flags: results.map(result => result.mispredicted),
        byPC, counts, kinds, bits: storage(specification)};
}

function aggregateTiming(timing) {
    const stallCycles = zeros(CAUSES);
    const stallEvents = zeros(CAUSES);
    let totalStalls = 0;
    for (const record of timing.records) {
        stallCycles[record.cause] += record.cycles;
        stallEvents[record.cause]++;
        totalStalls += record.cycles;
    }
    return {stallCycles, stallEvents, totalStalls};
}

function allTimings(instructions, predictions, config) {
    const combinations = [];
    let primary;
    for (const variant of config.variants) {
        for (const prediction of predictions) {
            const timing = pipeline.simulate(instructions, variant, prediction.flags);
            const combination = {variant, prediction, cycles: timing.cycles, ...aggregateTiming(timing)};
            combinations.push(combination);
            if (variant.name === config.primaryVariant && prediction.specification.name === config.primaryPredictor) {
                primary = {...combination, timing};
            }
        }
    }
    return {combinations, primary};
}

function buildRows(instructions, primary) {
    const waiting = instructions.map(() => []);
    for (const record of primary.timing.records) {
        if (record.waiting !== null) waiting[record.waiting].push(record);
    }
    const segment = (stage, from, to, first, rest = first) => ({stage, from, to, first, rest});
    const rows = [];
    let refetch = 0;
    instructions.forEach((instruction, i) => {
        const time = primary.timing.times[i];
        const prediction = primary.prediction.results[i];
        let annotation = waiting[i].map(record => ` ${record.cause} ${record.cycles}`).join('');
        if (prediction.mispredicted) annotation += ` mispredict ${prediction.kind}`;
        rows.push({number: i + 1, pc: instruction.pc, className: instruction.className, wrong: false,
            segments: [segment(0, time.F, time.D - 1, 'F', '*'), segment(1, time.D, time.X - 1, 'D', '*'),
                segment(2, time.X, time.M - 1, 'X'), segment(3, time.M, time.M, 'M'), segment(4, time.W, time.W, 'W')],
            cancel: null, annotation});
        if (!prediction.mispredicted) return;
        const early = hazards.idResolved(instruction, primary.variant);
        const wrongSegments = [segment(0, time.D, time.X - 1, 'F', '*')];
        if (!early) wrongSegments.push(segment(1, time.X, time.X, 'D'));
        rows.push({number: null, pc: prediction.predictedNext, className: 'FLUSH', wrong: true,
            segments: wrongSegments, cancel: time.X + (early ? 0 : 1), annotation: ''});
        refetch++;
        if (!early) {
            rows.push({number: null, pc: prediction.predictedNext + 4, className: 'FLUSH', wrong: true,
                segments: [segment(0, time.X, time.X, 'F')], cancel: time.X + 1, annotation: ''});
            refetch++;
        }
    });
    const occupancy = STAGES.map(() => ({correct: 0, wrong: 0}));
    for (const row of rows) {
        for (const segment of row.segments) occupancy[segment.stage][row.wrong ? 'wrong' : 'correct'] += segment.to - segment.from + 1;
    }
    return {rows, occupancy, refetch};
}

function diagramReport(primary, diagram, config) {
    const lines = [`pipeline variant=${primary.variant.name} predictor=${primary.prediction.specification.name} cycles ${config.start}-${config.end}`,
        cycleHeader(config.start, config.end)];
    const contents = Array.from({length: config.end - config.start + 1}, () => STAGES.map(() => '.'));
    let count = 0;
    let stallCells = 0;
    let flushed = 0;
    for (const row of diagram.rows) {
        const rendered = diagramRow(row, config.start, config.end);
        if (rendered !== null) {
            lines.push(rendered.line);
            count++;
            stallCells += rendered.stallCells;
            flushed += rendered.flushed;
        }
        for (const segment of row.segments) {
            for (let cycle = Math.max(config.start, segment.from); cycle <= Math.min(config.end, segment.to); cycle++) {
                contents[cycle - config.start][segment.stage] = row.wrong ? 'w' : String(row.number);
            }
        }
    }
    const completed = primary.timing.times.filter(time => time.W >= config.start && time.W <= config.end).length;
    lines.push(`rows ${count} completed ${completed} stall_cells ${stallCells} flushed ${flushed}`, '', 'stages', 'cycle IF ID EX MEM WB');
    contents.forEach((stages, i) => lines.push(`${config.start + i} ${stages.join(' ')}`));
    return lines;
}

function traceSummary(trace) {
    const mix = zeros(CLASSES);
    const distances = Array(5).fill(0);
    const addresses = new Set();
    let taken = 0;
    let backward = 0;
    let indirect = 0;
    let link = 0;
    let operands = 0;
    let withProducer = 0;
    trace.instructions.forEach((instruction, i) => {
        mix[instruction.className]++;
        if (instruction.className === 'BRANCH') {
            if (instruction.outcome === 'T') taken++;
            if (instruction.target < instruction.pc) backward++;
        }
        if (instruction.className === 'JUMP') {
            if (instruction.rs1 !== null) indirect++;
            if (instruction.rd !== null) link++;
        }
        if (instruction.address !== null) addresses.add(instruction.address);
        for (const source of instruction.sources) {
            operands++;
            if (source.producer !== null) {
                withProducer++;
                distances[Math.min(5, i - source.producer) - 1]++;
            }
        }
    });
    const statics = [...trace.statics.values()];
    return {mix, distances, addresses: addresses.size, taken, backward, indirect, link, operands, withProducer,
        staticBranches: statics.filter(instruction => instruction.className === 'BRANCH').length,
        staticJumps: statics.filter(instruction => instruction.className === 'JUMP').length};
}

function analyzePrimary(instructions, primary, config) {
    const finish = [];
    let height = 0;
    const forwarding = zeros(['regfile', 'ex_mem', 'mem_wb']);
    instructions.forEach((instruction, i) => {
        let start = 0;
        for (const source of instruction.sources) {
            if (source.producer !== null) start = Math.max(start, finish[source.producer]);
            forwarding[hazards.forwardingPath(source, i, primary.variant, instructions, primary.timing.times)]++;
        }
        const latency = instruction.className === 'LOAD' ? 2 : instruction.className === 'MUL' ? primary.variant.latency : 1;
        finish.push(start + latency);
        height = Math.max(height, finish[i]);
    });
    const lengths = Array(5).fill(0);
    for (let i = 1; i < instructions.length; i++) {
        const gap = primary.timing.times[i].X - primary.timing.times[i - 1].X - 1;
        if (gap > 0) lengths[Math.min(gap, 5) - 1]++;
    }
    const byPC = new Map();
    const classStalls = zeros(CLASSES);
    const dependencyMap = new Map();
    for (const record of primary.timing.records) {
        const responsible = instructions[record.responsible];
        classStalls[responsible.className] += record.cycles;
        if (!byPC.has(responsible.pc)) byPC.set(responsible.pc, {pc: responsible.pc, className: responsible.className, total: 0, ...zeros(CAUSES)});
        const hotspot = byPC.get(responsible.pc);
        hotspot.total += record.cycles;
        hotspot[record.cause] += record.cycles;
        if (record.cause !== 'load_use' && record.cause !== 'raw') continue;
        const producer = instructions[record.producer];
        const waiting = instructions[record.waiting];
        const key = `${producer.pc}/${waiting.pc}/${record.cause}`;
        if (!dependencyMap.has(key)) dependencyMap.set(key, {producer, waiting, cause: record.cause, cycles: 0, events: 0});
        const dependency = dependencyMap.get(key);
        dependency.cycles += record.cycles;
        dependency.events++;
    }
    const hotspots = [...byPC.values()].sort((a, b) => b.total - a.total || a.pc - b.pc);
    const dependencies = [...dependencyMap.values()].sort((a, b) => b.cycles - a.cycles
        || a.producer.pc - b.producer.pc || a.waiting.pc - b.waiting.pc || CAUSES.indexOf(a.cause) - CAUSES.indexOf(b.cause));
    const intervals = [];
    for (let start = 0; start < instructions.length; start += config.interval) {
        const end = Math.min(instructions.length, start + config.interval) - 1;
        const cycles = primary.timing.times[end].W - (start === 0 ? 0 : primary.timing.times[start - 1].W);
        intervals.push({start: start + 1, end: end + 1, cycles});
    }
    return {height, forwarding, lengths, byPC, classStalls, hotspots, dependencies, intervals};
}

function whatifRuns(instructions, primary) {
    const variant = primary.variant;
    const oppositeStage = variant.resolution === 'ID' ? 'EX' : 'ID';
    const experiments = [
        {name: 'perfect_prediction', variant, flags: instructions.map(() => false)},
        {name: 'single_cycle_mul', variant: {...variant, latency: 1}, flags: primary.prediction.flags},
        {name: variant.forwarding ? 'forwarding_off' : 'forwarding_on',
            variant: {...variant, forwarding: !variant.forwarding}, flags: primary.prediction.flags},
        {name: `branch_stage_${oppositeStage}`, variant: {...variant, resolution: oppositeStage}, flags: primary.prediction.flags}
    ];
    return experiments.map(experiment => ({name: experiment.name,
        cycles: pipeline.simulate(instructions, experiment.variant, experiment.flags).cycles}));
}

function statsReport(trace, config, predictions, combinations, primary, summary, analysis, diagram, whatifs) {
    const n = trace.instructions.length;
    const C = primary.cycles;
    const parts = [];
    const input = [`input lines ${trace.lineCount} accepted ${n} rejected ${trace.rejected.length} gaps ${trace.gaps.length}`];
    for (const rejection of trace.rejected) input.push(`reject line ${rejection.line} ${rejection.reason}`);
    for (const gap of trace.gaps) input.push(`gap line ${gap.line} expected ${hex(gap.expected)} found ${hex(gap.found)}`);
    parts.push(input);
    const distanceText = ['1', '2', '3', '4', '5+'].map((name, i) => `${name} ${summary.distances[i]}`).join(' ');
    parts.push(['trace', `instructions ${n}`, `static_instructions ${trace.statics.size}`, `mix ${namedCounts(CLASSES, summary.mix)}`,
        `branches ${summary.mix.BRANCH} taken ${summary.taken} backward ${summary.backward}`,
        `jumps ${summary.mix.JUMP} indirect ${summary.indirect} link ${summary.link}`,
        `static_control branches ${summary.staticBranches} jumps ${summary.staticJumps}`,
        `memory loads ${summary.mix.LOAD} stores ${summary.mix.STORE} distinct_addresses ${summary.addresses}`,
        `operands ${summary.operands} with_producer ${summary.withProducer} distance ${distanceText}`]);
    const predictionLines = ['prediction'];
    for (const prediction of predictions) {
        const count = prediction.counts;
        predictionLines.push(`${prediction.specification.name} ${prediction.specification.scheme} bits ${prediction.bits}`
            + ` control ${count.control} mispredicted ${count.mis} accuracy ${percentage(count.control - count.mis, count.control)}`
            + ` branches ${percentage(count.branches - count.branchMis, count.branches)}`
            + ` jumps ${percentage(count.jumps - count.jumpMis, count.jumps)} ${namedCounts(KINDS, prediction.kinds)}`);
    }
    const common = predictions[0].counts;
    predictionLines.push(`btb entries ${config.btb} lookups ${common.control} hits ${common.hits} misses ${common.control - common.hits}`);
    predictionLines.push(`ras depth ${config.ras} calls ${common.calls} returns ${common.returns} predicted ${common.rasPredicted} correct ${common.rasCorrect}`);
    parts.push(predictionLines);
    const stack = CAUSES.map(cause => `${cause} ${decimal(primary.stallCycles[cause], n)}`).join(' ');
    const lengthText = ['1', '2', '3', '4', '5+'].map((name, i) => `${name} ${analysis.lengths[i]}`).join(' ');
    parts.push([`timing variant=${primary.variant.name} predictor=${primary.prediction.specification.name}`,
        `forwarding ${primary.variant.forwarding ? 'on' : 'off'} branch_stage ${primary.variant.resolution} mul_latency ${primary.variant.latency}`,
        `cycles ${C}`, `cpi ${fraction(C, n)} ${decimal(C, n)}`, `ipc ${decimal(n, C)}`,
        `stall_cycles total ${primary.totalStalls} ${namedCounts(CAUSES, primary.stallCycles)}`,
        `stall_events ${namedCounts(CAUSES, primary.stallEvents)}`, `flushed ${diagram.refetch}`,
        `cycle_check ${n} + 4 + ${primary.totalStalls} = ${n + 4 + primary.totalStalls}`,
        `cpi_stack base 1.0000 fill ${decimal(4, n)} ${stack}`, `stall_lengths ${lengthText}`,
        `dataflow height ${analysis.height} ilp ${decimal(n, analysis.height)}`]);
    parts.push(['whatif', ...whatifs.map(run => `${run.name} cycles ${run.cycles} saved ${C - run.cycles} speedup ${decimal(C, run.cycles)}`)]);
    parts.push(['classes', ...CLASSES.map(name => `${name} count ${summary.mix[name]} stall_cycles ${analysis.classStalls[name]}`
        + ` per_instruction ${summary.mix[name] === 0 ? '-' : decimal(analysis.classStalls[name], summary.mix[name])}`)]);
    parts.push([`forwarding ${namedCounts(['regfile', 'ex_mem', 'mem_wb'], analysis.forwarding)}`]);
    parts.push([`occupancy cycles ${C}`, ...STAGES.map((name, i) => {
        const {correct, wrong} = diagram.occupancy[i];
        return `${name} correct ${correct} wrong ${wrong} idle ${C - correct - wrong} busy ${percentage(correct + wrong, C)}`;
    })]);
    parts.push(['hotspots', ...analysis.hotspots.slice(0, config.top).map((hotspot, i) =>
        `${i + 1} ${hex(hotspot.pc)} ${hotspot.className} stall_cycles ${hotspot.total} ${namedCounts(CAUSES, hotspot)}`)]);
    parts.push([`dependencies total ${analysis.dependencies.length}`, ...analysis.dependencies.slice(0, config.top).map((dependency, i) =>
        `${i + 1} ${hex(dependency.producer.pc)} ${dependency.producer.className} -> ${hex(dependency.waiting.pc)}`
        + ` ${dependency.waiting.className} ${dependency.cause} stall_cycles ${dependency.cycles} events ${dependency.events}`)]);
    parts.push([`intervals size ${config.interval}`, ...analysis.intervals.map(interval =>
        `${interval.start}-${interval.end} cycles ${interval.cycles} cpi ${decimal(interval.cycles, interval.end - interval.start + 1)}`)]);
    const tableLines = [`cycles_table ${predictions.map(prediction => prediction.specification.name).join(' ')}`];
    for (const variant of config.variants) {
        const row = combinations.filter(combination => combination.variant === variant);
        tableLines.push(`${variant.name} ${row.map(combination => combination.cycles).join(' ')}`);
    }
    parts.push(tableLines);
    return parts.flatMap((part, i) => i === 0 ? part : ['', ...part]);
}

function branchesReport(statics, predictions) {
    const lines = ['predictor,pc,class,executions,taken,mispredictions,accuracy'];
    const controls = statics.filter(instruction => instruction.control);
    for (const prediction of predictions) {
        for (const instruction of controls) {
            const count = prediction.byPC.get(instruction.pc);
            lines.push(`${prediction.specification.name},${hex(instruction.pc)},${instruction.className},${count.executions},`
                + `${count.taken},${count.mis},${percentage(count.executions - count.mis, count.executions)}`);
        }
    }
    return lines;
}

function comparisonReport(combinations, primary, n) {
    const lines = ['rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw'];
    const ranked = combinations.toSorted((a, b) => a.cycles - b.cycles || asciiCompare(a.variant.name, b.variant.name)
        || asciiCompare(a.prediction.specification.name, b.prediction.specification.name));
    ranked.forEach((combination, i) => {
        const count = combination.prediction.counts;
        lines.push(`${i + 1},${combination.variant.name},${combination.prediction.specification.name},${combination.cycles},`
            + `${decimal(combination.cycles, n)},${decimal(primary.cycles, combination.cycles)},`
            + `${percentage(count.control - count.mis, count.control)},${count.mis},`
            + CAUSES.map(cause => combination.stallCycles[cause]).join(','));
    });
    return lines;
}

function branchProfile(instructions, statics, predictions) {
    const branches = ['branches'];
    const loops = ['loops'];
    const candidates = predictions.filter(prediction => prediction.specification.scheme !== 'PERFECT');
    for (const instruction of statics) {
        if (instruction.className !== 'BRANCH') continue;
        let previous = null;
        let run = 0;
        let taken = 0;
        let transitions = 0;
        let longestTaken = 0;
        let longestNotTaken = 0;
        let trips = 0;
        let tripLength = 0;
        let maxTrip = 0;
        for (const i of instruction.executions) {
            const outcome = instructions[i].outcome;
            if (outcome === previous) run++;
            else {
                if (previous !== null) transitions++;
                run = 1;
            }
            previous = outcome;
            if (outcome === 'T') {
                taken++;
                longestTaken = Math.max(longestTaken, run);
            } else longestNotTaken = Math.max(longestNotTaken, run);
            tripLength++;
            if (outcome === 'N') {
                trips++;
                maxTrip = Math.max(maxTrip, tripLength);
                tripLength = 0;
            }
        }
        if (tripLength > 0) {
            trips++;
            maxTrip = Math.max(maxTrip, tripLength);
        }
        let best = candidates[0];
        for (const candidate of candidates.slice(1)) {
            if (candidate.byPC.get(instruction.pc).mis < best.byPC.get(instruction.pc).mis) best = candidate;
        }
        const direction = instruction.target < instruction.pc ? 'backward' : 'forward';
        const executions = instruction.executions.length;
        branches.push(`${hex(instruction.pc)} ${direction} executions ${executions} taken ${taken} transitions ${transitions}`
            + ` longest_taken ${longestTaken} longest_not_taken ${longestNotTaken} best ${best.specification.name} ${best.byPC.get(instruction.pc).mis}`);
        if (direction === 'backward') {
            const body = ((instruction.pc - instruction.target) >>> 2) + 1;
            loops.push(`${hex(instruction.target)}-${hex(instruction.pc)} body ${body} entries ${trips} iterations ${executions}`
                + ` avg_trip ${decimal(executions, trips)} max_trip ${maxTrip}`);
        }
    }
    return [branches, loops];
}

function segmentProfile(instructions, primary, top) {
    const groups = new Map();
    let start = 0;
    for (let end = 0; end < instructions.length; end++) {
        if (!instructions[end].control && end !== instructions.length - 1) continue;
        const pc = instructions[start].pc;
        if (!groups.has(pc)) groups.set(pc, {pc, instances: 0, instructions: 0, cycles: 0});
        const group = groups.get(pc);
        group.instances++;
        group.instructions += end - start + 1;
        group.cycles += primary.timing.times[end].W - (start === 0 ? 0 : primary.timing.times[start - 1].W);
        start = end + 1;
    }
    const ranked = [...groups.values()].sort((a, b) => b.cycles - a.cycles || a.pc - b.pc);
    return [`segments total ${groups.size}`, ...ranked.slice(0, top).map((group, i) =>
        `${i + 1} ${hex(group.pc)} instances ${group.instances} instructions ${group.instructions} cycles ${group.cycles}`
        + ` cpi ${decimal(group.cycles, group.instructions)}`)];
}

function profileReport(instructions, statics, predictions, primary, analysis, config) {
    const parts = branchProfile(instructions, statics, predictions);
    parts.push(segmentProfile(instructions, primary, config.top));
    const indirect = ['indirect'];
    const staticLines = ['instructions'];
    for (const instruction of statics) {
        if (instruction.className === 'JUMP' && instruction.rs1 !== null) {
            const counts = new Map();
            for (const i of instruction.executions) {
                const target = instructions[i].target;
                counts.set(target, (counts.get(target) ?? 0) + 1);
            }
            const targets = [...counts].sort((a, b) => b[1] - a[1] || a[0] - b[0]);
            indirect.push(`${hex(instruction.pc)} executions ${instruction.executions.length} distinct ${counts.size}`
                + ` targets ${targets.map(([target, count]) => `${hex(target)}:${count}`).join(' ')}`);
        }
        const stalls = analysis.byPC.get(instruction.pc)?.total ?? 0;
        staticLines.push(`${hex(instruction.pc)} ${instruction.className} ${registerText(instruction.rd)}`
            + ` ${registerText(instruction.rs1)} ${registerText(instruction.rs2)} executions ${instruction.executions.length} stall_cycles ${stalls}`);
    }
    parts.push(indirect, staticLines);
    return parts.flatMap((part, i) => i === 0 ? part : ['', ...part]);
}

function main() {
    const {lines, config} = traceIO.read();
    const trace = checkTrace(lines);
    const instructions = trace.instructions;
    const predictions = config.predictors.map(specification => predict(instructions, specification, config));
    const {combinations, primary} = allTimings(instructions, predictions, config);
    const summary = traceSummary(trace);
    const analysis = analyzePrimary(instructions, primary, config);
    const diagram = buildRows(instructions, primary);
    const whatifs = whatifRuns(instructions, primary);
    const statics = [...trace.statics.values()].sort((a, b) => a.pc - b.pc);
    write('pipeline.txt', diagramReport(primary, diagram, config));
    write('stats.txt', statsReport(trace, config, predictions, combinations, primary, summary, analysis, diagram, whatifs));
    write('branches.csv', branchesReport(statics, predictions));
    write('comparison.csv', comparisonReport(combinations, primary, instructions.length));
    write('profile.txt', profileReport(instructions, statics, predictions, primary, analysis, config));
}

main();
