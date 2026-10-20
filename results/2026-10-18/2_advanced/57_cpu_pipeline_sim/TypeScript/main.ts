import { classes, isClass, parseHex, parseRegister, readInputs, validRegister, type Instruction, type InstructionClass, type Predictor, type Variant } from './trace_io.ts';
import { control, dependencies, forwardingPath, idResolved } from './hazards.ts';
import { Btb, DirectionPredictor, Ras, storage } from './predictors.ts';
import { causes, simulate, type Cause, type Run } from './pipeline.ts';
import { cycleDigits, decimal, diagramRow, fraction, hex, percentage, writeReport } from './report.ts';

type Misprediction = 'direction' | 'btb_miss' | 'wrong_target';
interface Prediction { next: number; kind?: Misprediction }
interface ControlCount { executions: number; taken: number; misses: number }
interface PredictionResult { config: Predictor; predictions: Prediction[]; flags: boolean[]; controls: Map<number, ControlCount>; hits: number; rasPredicted: number; rasCorrect: number; misses: number; branchMisses: number; jumpMisses: number; kinds: Record<Misprediction, number> }
interface Combination { variant: Variant; predictor: PredictionResult; run: Run; totals: Record<Cause, number> }
const zeroCauses = (): Record<Cause, number> => ({ control: 0, structural: 0, load_use: 0, raw: 0 });
const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);
const ascii = (a: string, b: string) => a < b ? -1 : a > b ? 1 : 0;
const nextPc = (instruction: Instruction) => instruction.outcome === 'T' ? instruction.target! : instruction.pc + 4;
const registerText = (register: number | undefined) => register === undefined ? '-' : `r${register}`;
const { lines, config } = readInputs();
const instructions: Instruction[] = [], first = new Map<number, Instruction>(), executions = new Map<number, number[]>();
const rejects: string[] = [], gaps: string[] = [];
const usage: Record<InstructionClass, readonly string[]> = {
  ALU: ['required', 'required', 'optional'], MUL: ['required', 'required', 'required'], LOAD: ['required', 'required', 'none'],
  STORE: ['none', 'required', 'required'], BRANCH: ['none', 'required', 'optional'], JUMP: ['optional', 'optional', 'none'], NOP: ['none', 'none', 'none'],
};
function check(line: string, lineNumber: number): Instruction | string {
  const fields = line.split(' ');
  if (fields.length !== 8 || fields.some(field => field === '')) return 'fields';
  const [pcText, kind, rdText, rs1Text, rs2Text, outcome, targetText, addressText] = fields;
  const pc = parseHex(pcText);
  if (pc === undefined || pc % 4) return 'pc';
  if (!isClass(kind)) return 'class';
  const registers = [rdText, rs1Text, rs2Text];
  if (!registers.every(validRegister)) return 'register';
  if (registers.some((field, i) => usage[kind][i] === 'required' ? field === '-' : usage[kind][i] === 'none' && field !== '-')) return 'operands';
  if (kind === 'BRANCH' ? outcome !== 'T' && outcome !== 'N' : kind === 'JUMP' ? outcome !== 'T' : outcome !== '-') return 'taken';
  const target = parseHex(targetText), address = parseHex(addressText);
  if (kind === 'BRANCH' || kind === 'JUMP') { if (target === undefined || target % 4 || target === pc + 4) return 'target'; }
  else if (targetText !== '-') return 'target';
  if (kind === 'LOAD' || kind === 'STORE') { if (address === undefined || address % 4) return 'address'; }
  else if (addressText !== '-') return 'address';
  const rd = parseRegister(rdText), rs1 = parseRegister(rs1Text), rs2 = parseRegister(rs2Text), old = first.get(pc);
  if (old && (old.kind !== kind || old.rd !== rd || old.rs1 !== rs1 || old.rs2 !== rs2 || ((kind === 'BRANCH' || (kind === 'JUMP' && rs1 === undefined)) && old.target !== target))) return 'conflict';
  return { number: instructions.length + 1, line: lineNumber, pc, kind, rd, rs1, rs2, outcome: outcome === 'T' ? 'T' : outcome === 'N' ? 'N' : '-', target, address };
}
lines.forEach((line, i) => {
  const result = check(line, i + 1);
  if (typeof result === 'string') { rejects.push(`reject line ${i + 1} ${result}`); return; }
  const previous = instructions.at(-1);
  if (previous && result.pc !== nextPc(previous)) gaps.push(`gap line ${i + 1} expected ${hex(nextPc(previous))} found ${hex(result.pc)}`);
  if (!first.has(result.pc)) { first.set(result.pc, result); executions.set(result.pc, []); }
  executions.get(result.pc)!.push(instructions.length); instructions.push(result);
});
const n = instructions.length, sources = dependencies(instructions), staticInstructions = [...first.values()].sort((a, b) => a.pc - b.pc);
const countClass = (kind: InstructionClass) => instructions.filter(instruction => instruction.kind === kind).length;
const branchCount = countClass('BRANCH'), jumpCount = countClass('JUMP'), controlCount = branchCount + jumpCount;
const calls = instructions.filter(instruction => instruction.kind === 'JUMP' && instruction.rd === 31).length;
const returns = instructions.filter(instruction => instruction.kind === 'JUMP' && instruction.rd === undefined && instruction.rs1 === 31).length;

function predict(predictor: Predictor): PredictionResult {
  const btb = new Btb(config.btb), ras = new Ras(config.ras), direction = new DirectionPredictor(predictor);
  const result: PredictionResult = { config: predictor, predictions: [], flags: [], controls: new Map(), hits: 0, rasPredicted: 0, rasCorrect: 0, misses: 0, branchMisses: 0, jumpMisses: 0, kinds: { direction: 0, btb_miss: 0, wrong_target: 0 } };
  for (const instruction of instructions) {
    if (!control(instruction)) { result.predictions.push({ next: nextPc(instruction) }); result.flags.push(false); continue; }
    const actual = nextPc(instruction), taken = instruction.outcome === 'T';
    let candidate = btb.lookup(instruction.pc);
    if (candidate !== undefined) result.hits++;
    if (instruction.kind === 'JUMP' && instruction.rd === undefined && instruction.rs1 === 31) {
      const popped = ras.pop();
      if (popped !== undefined) { candidate = popped; result.rasPredicted++; if (popped === instruction.target) result.rasCorrect++; }
    }
    if (instruction.kind === 'JUMP' && instruction.rd === 31) ras.push(instruction.pc + 4);
    const predictedTaken = instruction.kind === 'BRANCH' ? direction.predict(instruction.pc, instruction.target!, taken) : true;
    const predicted = predictor.scheme === 'PERFECT' ? actual : predictedTaken && candidate !== undefined ? candidate : instruction.pc + 4;
    const prediction: Prediction = { next: predicted }, mispredicted = predicted !== actual;
    const entry = result.controls.get(instruction.pc) ?? { executions: 0, taken: 0, misses: 0 };
    entry.executions++; if (taken) entry.taken++;
    if (mispredicted) {
      prediction.kind = instruction.kind === 'BRANCH' && predictedTaken !== taken ? 'direction' : candidate === undefined ? 'btb_miss' : 'wrong_target';
      result.kinds[prediction.kind]++; result.misses++; entry.misses++;
      if (instruction.kind === 'BRANCH') result.branchMisses++; else result.jumpMisses++;
    }
    result.controls.set(instruction.pc, entry); result.predictions.push(prediction); result.flags.push(mispredicted);
    if (instruction.kind === 'BRANCH') direction.update(instruction.pc, taken);
    if (taken) btb.insert(instruction.pc, instruction.target!);
  }
  return result;
}
const predictions = config.predictors.map(predict), combinations: Combination[] = [];
for (const variant of config.variants) for (const predictor of predictions) {
  const run = simulate(instructions, sources, variant, predictor.flags), totals = zeroCauses();
  for (const stall of run.stalls) totals[stall.cause] += stall.cycles;
  combinations.push({ variant, predictor, run, totals });
}
const primary = combinations.find(pair => pair.variant.name === config.primaryVariant && pair.predictor.config.name === config.primaryPredictor)!;
const { variant, predictor, run, totals } = primary, { timings, stalls, cycles } = run;
const events = zeroCauses(), byClass = new Map<InstructionClass, number>(), byPc = new Map<number, Record<Cause, number>>();
const annotations = Array.from({ length: n }, () => '');
interface DependencyPair { producer: number; waiting: number; cause: 'load_use' | 'raw'; cycles: number; events: number }
const dependencyGroups = new Map<string, DependencyPair>();
for (const stall of stalls) {
  events[stall.cause]++;
  const responsible = instructions[stall.responsible], pcTotals = byPc.get(responsible.pc) ?? zeroCauses();
  pcTotals[stall.cause] += stall.cycles; byPc.set(responsible.pc, pcTotals);
  byClass.set(responsible.kind, (byClass.get(responsible.kind) ?? 0) + stall.cycles);
  if (stall.waiting !== undefined) annotations[stall.waiting] += ` ${stall.cause} ${stall.cycles}`;
  if ((stall.cause === 'load_use' || stall.cause === 'raw') && stall.producer !== undefined && stall.waiting !== undefined) {
    const producerPc = instructions[stall.producer].pc, waitingPc = instructions[stall.waiting].pc, key = `${producerPc}:${waitingPc}:${stall.cause}`;
    const group = dependencyGroups.get(key) ?? { producer: producerPc, waiting: waitingPc, cause: stall.cause, cycles: 0, events: 0 };
    group.cycles += stall.cycles; group.events++; dependencyGroups.set(key, group);
  }
}
const stallTotal = sum(causes.map(cause => totals[cause])), lengths = [0, 0, 0, 0, 0], finishes: number[] = [];
let height = 0;
instructions.forEach((instruction, i) => {
  if (i) { const gap = timings[i].execute - timings[i - 1].execute - 1; if (gap > 0) lengths[Math.min(gap, 5) - 1]++; }
  let start = 0;
  for (const source of sources[i]) if (source.producer !== undefined) start = Math.max(start, finishes[source.producer]);
  const finish = start + (instruction.kind === 'LOAD' ? 2 : instruction.kind === 'MUL' ? variant.latency : 1);
  finishes.push(finish); height = Math.max(height, finish);
});
const paths = { regfile: 0, ex_mem: 0, mem_wb: 0 };
instructions.forEach((instruction, i) => { for (const source of sources[i]) paths[forwardingPath(source, instruction, timings[i], variant, timings)]++; });

const stageNames = ['IF', 'ID', 'EX', 'MEM', 'WB'] as const;
type Stage = typeof stageNames[number];
const occupancy: Record<Stage, { correct: number; wrong: number }> = { IF: { correct: 0, wrong: 0 }, ID: { correct: 0, wrong: 0 }, EX: { correct: 0, wrong: 0 }, MEM: { correct: 0, wrong: 0 }, WB: { correct: 0, wrong: 0 } };
const stageContents = new Map<number, Map<Stage, string>>();
for (let cycle = config.start; cycle <= config.end; cycle++) stageContents.set(cycle, new Map());
const pipeline = [`pipeline variant=${variant.name} predictor=${predictor.config.name} cycles ${config.start}-${config.end}`, cycleDigits(config.start, config.end)];
let rows = 0, stallCells = 0, cancelled = 0, refetches = 0;
function mark(cells: Map<number, string>, start: number, end: number, character: string): void {
  for (let cycle = Math.max(start, config.start); cycle <= Math.min(end, config.end); cycle++) cells.set(cycle, character);
}
function occupy(stage: Stage, start: number, end: number, content: string, wrong = false): void {
  occupancy[stage][wrong ? 'wrong' : 'correct'] += Math.max(0, end - start + 1);
  for (let cycle = Math.max(start, config.start); cycle <= Math.min(end, config.end); cycle++) stageContents.get(cycle)!.set(stage, content);
}
function appendRow(number: number | undefined, pc: number, kind: string, cells: Map<number, string>, annotation = ''): void {
  if (!cells.size) return;
  rows++; for (const character of cells.values()) { if (character === '*') stallCells++; if (character === 'x') cancelled++; }
  pipeline.push(diagramRow(number, pc, kind, cells, config.start, config.end, annotation));
}
instructions.forEach((instruction, i) => {
  const timing = timings[i], cells = new Map<number, string>(), number = String(i + 1);
  mark(cells, timing.fetch, timing.fetch, 'F'); mark(cells, timing.fetch + 1, timing.decode - 1, '*');
  mark(cells, timing.decode, timing.decode, 'D'); mark(cells, timing.decode + 1, timing.execute - 1, '*');
  mark(cells, timing.execute, timing.memory - 1, 'X'); mark(cells, timing.memory, timing.memory, 'M'); mark(cells, timing.writeback, timing.writeback, 'W');
  occupy('IF', timing.fetch, timing.decode - 1, number); occupy('ID', timing.decode, timing.execute - 1, number);
  occupy('EX', timing.execute, timing.memory - 1, number); occupy('MEM', timing.memory, timing.memory, number); occupy('WB', timing.writeback, timing.writeback, number);
  const prediction = predictor.predictions[i];
  appendRow(i + 1, instruction.pc, instruction.kind, cells, annotations[i] + (prediction.kind ? ` mispredict ${prediction.kind}` : ''));
  if (!prediction.kind) return;
  const early = idResolved(instruction, variant), firstWrong = new Map<number, string>();
  mark(firstWrong, timing.decode, timing.decode, 'F'); mark(firstWrong, timing.decode + 1, timing.execute - 1, '*');
  occupy('IF', timing.decode, timing.execute - 1, 'w', true);
  if (early) mark(firstWrong, timing.execute, timing.execute, 'x');
  else { mark(firstWrong, timing.execute, timing.execute, 'D'); mark(firstWrong, timing.execute + 1, timing.execute + 1, 'x'); occupy('ID', timing.execute, timing.execute, 'w', true); }
  appendRow(undefined, prediction.next, 'FLUSH', firstWrong); refetches++;
  if (!early) {
    const secondWrong = new Map<number, string>(); mark(secondWrong, timing.execute, timing.execute, 'F'); mark(secondWrong, timing.execute + 1, timing.execute + 1, 'x');
    occupy('IF', timing.execute, timing.execute, 'w', true); appendRow(undefined, prediction.next + 4, 'FLUSH', secondWrong); refetches++;
  }
});
const completed = timings.filter(timing => timing.writeback >= config.start && timing.writeback <= config.end).length;
pipeline.push(`rows ${rows} completed ${completed} stall_cells ${stallCells} flushed ${cancelled}`, '', 'stages', 'cycle IF ID EX MEM WB');
for (let cycle = config.start; cycle <= config.end; cycle++) pipeline.push(`${cycle} ${stageNames.map(stage => stageContents.get(cycle)!.get(stage) ?? '.').join(' ')}`);

const countWhere = (predicate: (instruction: Instruction) => boolean) => instructions.filter(predicate).length;
const distances = [0, 0, 0, 0, 0]; let sourceCount = 0, withProducer = 0;
sources.forEach((list, i) => { sourceCount += list.length; for (const source of list) if (source.producer !== undefined) { withProducer++; distances[Math.min(i - source.producer, 5) - 1]++; } });
const inputPart = [`input lines ${lines.length} accepted ${n} rejected ${rejects.length} gaps ${gaps.length}`, ...rejects, ...gaps];
const tracePart = [
  'trace', `instructions ${n}`, `static_instructions ${first.size}`, `mix ${classes.map(kind => `${kind} ${countClass(kind)}`).join(' ')}`,
  `branches ${branchCount} taken ${countWhere(instruction => instruction.kind === 'BRANCH' && instruction.outcome === 'T')} backward ${countWhere(instruction => instruction.kind === 'BRANCH' && instruction.target! < instruction.pc)}`,
  `jumps ${jumpCount} indirect ${countWhere(instruction => instruction.kind === 'JUMP' && instruction.rs1 !== undefined)} link ${countWhere(instruction => instruction.kind === 'JUMP' && instruction.rd !== undefined)}`,
  `static_control branches ${staticInstructions.filter(instruction => instruction.kind === 'BRANCH').length} jumps ${staticInstructions.filter(instruction => instruction.kind === 'JUMP').length}`,
  `memory loads ${countClass('LOAD')} stores ${countClass('STORE')} distinct_addresses ${new Set(instructions.filter(instruction => instruction.address !== undefined).map(instruction => instruction.address)).size}`,
  `operands ${sourceCount} with_producer ${withProducer} distance 1 ${distances[0]} 2 ${distances[1]} 3 ${distances[2]} 4 ${distances[3]} 5+ ${distances[4]}`,
];
const predictionPart = ['prediction', ...predictions.map(result => `${result.config.name} ${result.config.scheme} bits ${storage(result.config)} control ${controlCount} mispredicted ${result.misses} accuracy ${percentage(controlCount - result.misses, controlCount)} branches ${percentage(branchCount - result.branchMisses, branchCount)} jumps ${percentage(jumpCount - result.jumpMisses, jumpCount)} direction ${result.kinds.direction} btb_miss ${result.kinds.btb_miss} wrong_target ${result.kinds.wrong_target}`),
  `btb entries ${config.btb} lookups ${controlCount} hits ${predictor.hits} misses ${controlCount - predictor.hits}`,
  `ras depth ${config.ras} calls ${calls} returns ${returns} predicted ${predictor.rasPredicted} correct ${predictor.rasCorrect}`];
const causeText = (values: Record<Cause, number>) => causes.map(cause => `${cause} ${values[cause]}`).join(' ');
const timingPart = [
  `timing variant=${variant.name} predictor=${predictor.config.name}`, `forwarding ${variant.forwarding ? 'on' : 'off'} branch_stage ${variant.stage} mul_latency ${variant.latency}`,
  `cycles ${cycles}`, `cpi ${fraction(cycles, n)} ${decimal(cycles, n)}`, `ipc ${decimal(n, cycles)}`,
  `stall_cycles total ${stallTotal} ${causeText(totals)}`, `stall_events ${causeText(events)}`, `flushed ${refetches}`, `cycle_check ${n} + 4 + ${stallTotal} = ${n + 4 + stallTotal}`,
  `cpi_stack base 1.0000 fill ${decimal(4, n)} ${causes.map(cause => `${cause} ${decimal(totals[cause], n)}`).join(' ')}`,
  `stall_lengths 1 ${lengths[0]} 2 ${lengths[1]} 3 ${lengths[2]} 4 ${lengths[3]} 5+ ${lengths[4]}`, `dataflow height ${height} ilp ${decimal(n, height)}`,
];
const whatifs: { name: string; variant: Variant; flags: boolean[] }[] = [
  { name: 'perfect_prediction', variant, flags: instructions.map(() => false) },
  { name: 'single_cycle_mul', variant: { ...variant, latency: 1 }, flags: predictor.flags },
  { name: variant.forwarding ? 'forwarding_off' : 'forwarding_on', variant: { ...variant, forwarding: !variant.forwarding }, flags: predictor.flags },
  { name: variant.stage === 'EX' ? 'branch_stage_ID' : 'branch_stage_EX', variant: { ...variant, stage: variant.stage === 'EX' ? 'ID' : 'EX' }, flags: predictor.flags },
];
const whatifPart = ['whatif', ...whatifs.map(whatif => { const result = simulate(instructions, sources, whatif.variant, whatif.flags); return `${whatif.name} cycles ${result.cycles} saved ${cycles - result.cycles} speedup ${decimal(cycles, result.cycles)}`; })];
const classPart = ['classes', ...classes.map(kind => { const count = countClass(kind), stalled = byClass.get(kind) ?? 0; return `${kind} count ${count} stall_cycles ${stalled} per_instruction ${count ? decimal(stalled, count) : '-'}`; })];
const forwardingPart = [`forwarding regfile ${paths.regfile} ex_mem ${paths.ex_mem} mem_wb ${paths.mem_wb}`];
const occupancyPart = [`occupancy cycles ${cycles}`, ...stageNames.map(stage => { const { correct, wrong } = occupancy[stage]; return `${stage} correct ${correct} wrong ${wrong} idle ${cycles - correct - wrong} busy ${percentage(correct + wrong, cycles)}`; })];
const pcTotal = (pc: number) => { const values = byPc.get(pc); return values ? sum(causes.map(cause => values[cause])) : 0; };
const hotspots = [...byPc.keys()].sort((a, b) => pcTotal(b) - pcTotal(a) || a - b).slice(0, config.top);
const hotspotPart = ['hotspots', ...hotspots.map((pc, i) => `${i + 1} ${hex(pc)} ${first.get(pc)!.kind} stall_cycles ${pcTotal(pc)} ${causeText(byPc.get(pc)!)}`)];
const dependencyList = [...dependencyGroups.values()].sort((a, b) => b.cycles - a.cycles || a.producer - b.producer || a.waiting - b.waiting || (a.cause === b.cause ? 0 : a.cause === 'load_use' ? -1 : 1));
const dependencyPart = [`dependencies total ${dependencyList.length}`, ...dependencyList.slice(0, config.top).map((group, i) => `${i + 1} ${hex(group.producer)} ${first.get(group.producer)!.kind} -> ${hex(group.waiting)} ${first.get(group.waiting)!.kind} ${group.cause} stall_cycles ${group.cycles} events ${group.events}`)];
const intervalPart = [`intervals size ${config.interval}`];
for (let a = 0; a < n; a += config.interval) { const b = Math.min(n, a + config.interval) - 1, elapsed = timings[b].writeback - (a ? timings[a - 1].writeback : 0); intervalPart.push(`${a + 1}-${b + 1} cycles ${elapsed} cpi ${decimal(elapsed, b - a + 1)}`); }
const tablePart = [`cycles_table ${predictions.map(result => result.config.name).join(' ')}`, ...config.variants.map(item => `${item.name} ${combinations.filter(pair => pair.variant === item).map(pair => pair.run.cycles).join(' ')}`)];
const stats = [inputPart, tracePart, predictionPart, timingPart, whatifPart, classPart, forwardingPart, occupancyPart, hotspotPart, dependencyPart, intervalPart, tablePart].flatMap((part, i) => i ? ['', ...part] : part);

const branches = ['predictor,pc,class,executions,taken,mispredictions,accuracy'];
for (const result of predictions) for (const instruction of staticInstructions.filter(control)) {
  const entry = result.controls.get(instruction.pc)!;
  branches.push([result.config.name, hex(instruction.pc), instruction.kind, entry.executions, entry.taken, entry.misses, percentage(entry.executions - entry.misses, entry.executions)].join(','));
}
const comparison = ['rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw'];
const ranked = [...combinations].sort((a, b) => a.run.cycles - b.run.cycles || ascii(a.variant.name, b.variant.name) || ascii(a.predictor.config.name, b.predictor.config.name));
ranked.forEach((pair, i) => comparison.push([i + 1, pair.variant.name, pair.predictor.config.name, pair.run.cycles, decimal(pair.run.cycles, n), decimal(cycles, pair.run.cycles), percentage(controlCount - pair.predictor.misses, controlCount), pair.predictor.misses, ...causes.map(cause => pair.totals[cause])].join(',')));

const branchProfile = ['branches'], loopProfile = ['loops'], indirectProfile = ['indirect'], staticProfile = ['instructions'];
for (const instruction of staticInstructions) {
  const indices = executions.get(instruction.pc)!;
  if (instruction.kind === 'BRANCH') {
    let taken = 0, transitions = 0, longestTaken = 0, longestNotTaken = 0, current = 0, previous = '', trip = 0;
    const trips: number[] = [];
    for (const index of indices) {
      const outcome = instructions[index].outcome;
      if (outcome === previous) current++; else { if (previous) transitions++; current = 1; }
      if (outcome === 'T') { taken++; longestTaken = Math.max(longestTaken, current); } else longestNotTaken = Math.max(longestNotTaken, current);
      previous = outcome; trip++; if (outcome === 'N') { trips.push(trip); trip = 0; }
    }
    if (trip) trips.push(trip);
    const best = predictions.filter(result => result.config.scheme !== 'PERFECT').reduce((a, b) => b.controls.get(instruction.pc)!.misses < a.controls.get(instruction.pc)!.misses ? b : a);
    const backward = instruction.target! < instruction.pc;
    branchProfile.push(`${hex(instruction.pc)} ${backward ? 'backward' : 'forward'} executions ${indices.length} taken ${taken} transitions ${transitions} longest_taken ${longestTaken} longest_not_taken ${longestNotTaken} best ${best.config.name} ${best.controls.get(instruction.pc)!.misses}`);
    if (backward) loopProfile.push(`${hex(instruction.target!)}-${hex(instruction.pc)} body ${(instruction.pc - instruction.target!) / 4 + 1} entries ${trips.length} iterations ${indices.length} avg_trip ${decimal(indices.length, trips.length)} max_trip ${Math.max(...trips)}`);
  }
  if (instruction.kind === 'JUMP' && instruction.rs1 !== undefined) {
    const targets = new Map<number, number>();
    for (const index of indices) { const target = instructions[index].target!; targets.set(target, (targets.get(target) ?? 0) + 1); }
    indirectProfile.push(`${hex(instruction.pc)} executions ${indices.length} distinct ${targets.size} targets ${[...targets].sort((a, b) => b[1] - a[1] || a[0] - b[0]).map(([target, count]) => `${hex(target)}:${count}`).join(' ')}`);
  }
  staticProfile.push(`${hex(instruction.pc)} ${instruction.kind} ${registerText(instruction.rd)} ${registerText(instruction.rs1)} ${registerText(instruction.rs2)} executions ${indices.length} stall_cycles ${pcTotal(instruction.pc)}`);
}
interface Segment { pc: number; instances: number; instructions: number; cycles: number }
const segments = new Map<number, Segment>(); let segmentStart = 0;
instructions.forEach((instruction, i) => {
  if (!control(instruction) && i !== n - 1) return;
  const pc = instructions[segmentStart].pc, segment = segments.get(pc) ?? { pc, instances: 0, instructions: 0, cycles: 0 };
  segment.instances++; segment.instructions += i - segmentStart + 1; segment.cycles += timings[i].writeback - (segmentStart ? timings[segmentStart - 1].writeback : 0);
  segments.set(pc, segment); segmentStart = i + 1;
});
const segmentProfile = [`segments total ${segments.size}`, ...[...segments.values()].sort((a, b) => b.cycles - a.cycles || a.pc - b.pc).slice(0, config.top).map((segment, i) => `${i + 1} ${hex(segment.pc)} instances ${segment.instances} instructions ${segment.instructions} cycles ${segment.cycles} cpi ${decimal(segment.cycles, segment.instructions)}`)];
const profile = [branchProfile, loopProfile, segmentProfile, indirectProfile, staticProfile].flatMap((part, i) => i ? ['', ...part] : part);
writeReport('pipeline.txt', pipeline); writeReport('stats.txt', stats); writeReport('branches.csv', branches); writeReport('comparison.csv', comparison); writeReport('profile.txt', profile);
