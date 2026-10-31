import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { KINDS, variable, copy, readProgram, definition, operandSlots, uses, expressionKey, expressionText,
  operation, instructionText, functionLines, programLines, cloneProgram } from './tac_parser.ts';
import { analyze, reaching, liveTransfer } from './dataflow.ts';
import { numeric } from './cfg.ts';
import { fold, rewrite, eliminateExpressions, hoist, removeUnreachable } from './optimizations.ts';
import { allocate, ascii } from './regalloc.ts';
import type { Operand, Instruction, TACFunction, TACProgram, Analysis,
  OptimizationRecord, CommonExpressionGroup, Settings, CallGraph,
  FunctionRuntime, Frame, ExecutionResult } from './types.ts';

const PASS_ORDER = ['constprop', 'copyprop', 'cse', 'dce', 'licm', 'unreachable'];
const list = (values: (string|number)[]): string => values.length ? values.join(',') : '-';
const blockList = (values: Iterable<number>): string => list(Array.from(values, number => 'B' + number));
const instructionList = (values: number[]): string => list(values.map(number => '#' + number));
const instructionCount = (fn: TACFunction): number => fn.code.filter(s => s.kind !== 'label').length;
const reachableInstructions = (analysis: Analysis): Instruction[] => analysis.blocks.filter(b => analysis.reachable.has(b.number)).flatMap(b => b.instructions);

function constantPropagation(fn: TACFunction, analysis: Analysis): OptimizationRecord {
  const replacements = new Map<number, Instruction[]>(), records: string[] = [];
  for (const source of reachableInstructions(analysis)) {
    const instruction = copy(source);
    for (const slot of operandSlots(source)) if (variable(source[slot])) {
      const name = source[slot] as string, definitions = reaching(analysis, source, source[slot] as string);
      if (definitions.length === 0 || definitions.some(value => value.number === 0)) continue;
      const assignments = definitions.map(value => analysis.instructions.get(value.number)!);
      if (assignments.some(s => s.kind !== 'copy' || variable(s.a))) continue;
      const value = assignments[0].a;
      if (!assignments.every(s => s.a === value)) continue;
      instruction[slot] = value;
      records.push('#' + source.number + ': ' + name + ' -> ' + value);
    }
    const result = fold(instruction);
    if (result.changed) {
      const description = result.instruction === null ? 'delete ' + instructionText(instruction) : 'fold ' + instructionText(result.instruction);
      records.push('#' + source.number + ': ' + description);
    }
    replacements.set(source.number!, result.instruction === null ? [] : [result.instruction]);
  }
  rewrite(fn, replacements);
  return { count: records.length, records };
}

function copyPropagation(fn: TACFunction, analysis: Analysis): OptimizationRecord {
  const replacements = new Map<number, Instruction[]>(), records: string[] = [];
  for (const source of reachableInstructions(analysis)) {
    const instruction = copy(source);
    const pairs = new Map<string,string>(Array.from(analysis.copies.before.get(source.number!)!, key => analysis.copyPairs.get(key)!));
    for (const slot of operandSlots(source)) if (variable(source[slot]) && pairs.has(source[slot] as string)) {
      const name = source[slot] as string, target = pairs.get(name)!; instruction[slot] = target;
      records.push('#' + source.number + ': ' + name + ' -> ' + target);
    }
    replacements.set(source.number, [instruction]);
  }
  rewrite(fn, replacements);
  return { count: records.length, records };
}

function commonSubexpressions(fn: TACFunction, analysis: Analysis): OptimizationRecord {
  const groups = new Map<string, {key: string; candidates: Instruction[]; sources: Set<number>}>();
  for (const instruction of reachableInstructions(analysis)) {
    const key = expressionKey(instruction);
    if (key !== null && analysis.available.before.get(instruction.number!)!.has(key)) {
      if (!groups.has(key)) groups.set(key, { key, candidates: [], sources: new Set<number>() });
      groups.get(key)!.candidates.push(instruction);
    }
  }
  for (const group of groups.values()) {
    for (const candidate of group.candidates) {
      const block = analysis.byNumber.get(analysis.owner.get(candidate.number!)!)!;
      const earlier = block.instructions.filter(s => s.number! < candidate.number! && expressionKey(s) === group.key);
      if (earlier.length) { group.sources.add(earlier[earlier.length - 1].number!); continue; }
      const work = analysis.reachablePredecessors(block.number).slice(), examined = new Set<number>();
      while (work.length) {
        const number = work.pop()!;
        if (examined.has(number)) continue;
        examined.add(number);
        const instructions = analysis.byNumber.get(number)!.instructions;
        let found = null;
        for (let i = instructions.length - 1; i >= 0; i--) if (expressionKey(instructions[i]) === group.key) { found = instructions[i]; break; }
        if (found !== null) group.sources.add(found.number!);
        else work.push(...analysis.reachablePredecessors(number));
      }
    }
    const candidates = new Set<number>(group.candidates.map(s => s.number!));
    group.sources = new Set<number>(numeric(group.sources).filter(n => !candidates.has(n)));
  }
  const prepared: CommonExpressionGroup[] = Array.from(groups.values()).map(group => ({
    key: group.key, candidates: group.candidates,
    sources: numeric(group.sources).map(n => analysis.instructions.get(n)!)
  }));
  const results = eliminateExpressions(fn, prepared);
  const records = results.map(group => expressionText(analysis.expressions.get(group.key)!) + ': ' + group.temporary +
    ' sources=' + instructionList(group.sources.map(s => s.number!)) + ' replaced=' + instructionList(group.candidates.map(s => s.number!)));
  return { count: results.reduce((sum, group) => sum + group.candidates.length, 0), records };
}

function deadCode(fn: TACFunction, analysis: Analysis): OptimizationRecord {
  const replacements = new Map<number, Instruction[]>(), records: {number:number;text:string}[] = [];
  for (const block of analysis.blocks) if (analysis.reachable.has(block.number)) {
    let live = new Set<string>(analysis.live.outgoing.get(block.number)!);
    for (let i = block.instructions.length - 1; i >= 0; i--) {
      let instruction = block.instructions[i];
      const number = instruction.number!, defined = definition(instruction), text = instructionText(instruction);
      if ((instruction.kind === 'copy' && instruction.dest === instruction.a)
          || (['copy', 'bin', 'load'].includes(instruction.kind) && !live.has(defined!))) {
        replacements.set(number, []); records.push({ number, text: '#' + number + ': delete ' + text }); continue;
      }
      if (instruction.kind === 'call' && defined !== undefined && !live.has(defined)) {
        instruction = copy(instruction); delete instruction.dest; replacements.set(number, [instruction]);
        records.push({ number, text: '#' + number + ': unused result ' + text });
      }
      live = liveTransfer(instruction, live);
    }
  }
  rewrite(fn, replacements); records.sort((a, b) => a.number - b.number);
  return { count: records.length, records: records.map(record => record.text) };
}

function invariantMotion(fn: TACFunction, analysis: Analysis): OptimizationRecord {
  const loops = analysis.loops.slice().sort((a, b) => a.blocks.size - b.blocks.size || a.header - b.header);
  for (const loop of loops) {
    const instructions = reachableInstructions(analysis).filter(s => loop.blocks.has(analysis.owner.get(s.number!)!));
    const marked = new Set<number>(), markOrder: Instruction[] = [], definitionCounts = new Map<string,number>();
    const stores = new Set<string>(instructions.filter(s => s.kind === 'store').map(s => s.array!));
    const hasCall = instructions.some(s => s.kind === 'call');
    for (const instruction of instructions) {
      const name = definition(instruction);
      if (name !== undefined) definitionCounts.set(name, (definitionCounts.get(name!) || 0) + 1);
    }
    const inside = (value: {number:number}): boolean => value.number !== 0 && loop.blocks.has(analysis.owner.get(value.number)!);
    let changed;
    do {
      changed = false;
      for (const instruction of instructions) {
        if (marked.has(instruction.number!) || !['copy', 'bin', 'load'].includes(instruction.kind)) continue;
        if (instruction.kind === 'load' && (hasCall || stores.has(instruction.array!))) continue;
        const invariant = uses(instruction).every(name => {
          const definitions = reaching(analysis, instruction, name);
          return definitions.every(value => !inside(value)) ||
            (definitions.length === 1 && inside(definitions[0]) && marked.has(definitions[0].number));
        });
        if (invariant) { marked.add(instruction.number!); markOrder.push(instruction); changed = true; }
      }
    } while (changed);
    const moving: Instruction[] = [], moved = new Set<number>();
    for (const instruction of markOrder) {
      const name = definition(instruction), block = analysis.owner.get(instruction.number!)!;
      if (definitionCounts.get(name) !== 1 || analysis.live.incoming.get(loop.header)!.has(name!)) continue;
      const dominatesExits = Array.from(loop.exits).every(exit => analysis.dominators.get(exit)!.has(block));
      const dangerous = instruction.kind === 'load' ||
        (instruction.kind === 'bin' && ['/', '%'].includes(instruction.op) && (variable(instruction.b) || instruction.b === 0));
      const deadOutside = Array.from(loop.outside).every(successor => !analysis.live.incoming.get(successor)!.has(name!));
      if (!dominatesExits && (dangerous || !deadOutside)) continue;
      if (!uses(instruction).every(operand => reaching(analysis, instruction, operand).filter(inside).every(value => moved.has(value.number)))) continue;
      moving.push(instruction); moved.add(instruction.number!);
    }
    if (moving.length) {
      const numbers = moving.map(s => s.number!), destination = hoist(fn, analysis, loop, moving);
      return { count: moving.length, records: ['B' + loop.header + ': hoist ' + instructionList(numbers) + ' to ' + destination] };
    }
  }
  return { count: 0, records: [] };
}

function unreachableCode(fn: TACFunction, analysis: Analysis): OptimizationRecord {
  const removed = removeUnreachable(fn, analysis);
  const records = [...removed.blocks.map(n => 'remove block B' + n), ...removed.jumps.map(n => 'remove jump #' + n),
    ...removed.labels.map(name => 'remove label ' + name)];
  return { count: records.length, records };
}

function callGraph(program: TACProgram): CallGraph {
  const names = program.functions.map(fn => fn.name), edges = new Map<string,string[]>();
  for (const fn of program.functions) {
    const callees = new Set<string>(fn.code.filter(s => s.kind === 'call').map(s => s.name!));
    edges.set(fn.name, names.filter(name => callees.has(name)));
  }
  const follow = (starts: string[]): Set<string> => {
    const marked = new Set<string>(), work = starts.slice();
    while (work.length) {
      const name = work.pop();
      if (marked.has(name)) continue;
      marked.add(name); work.push(...edges.get(name)!);
    }
    return marked;
  };
  const reachable = follow(['main']);
  const recursive = new Set(names.filter(name => follow(edges.get(name)!).has(name)));
  const unreachable = names.filter(name => !reachable.has(name));
  return { edges, reachable, recursive, unreachable };
}

function graphLines(program: TACProgram, graph: CallGraph): string[] {
  return [...program.functions.map(fn => fn.name + ' -> ' + list(graph.edges.get(fn.name)!) + (graph.recursive.has(fn.name) ? ' (recursive)' : '')),
    'unreachable functions: ' + list(graph.unreachable)];
}

function optimize(program: TACProgram, settings: Settings): {records: string[]; callLines: string[]} {
  const passes = PASS_ORDER.filter(name => settings.passes.has(name));
  const handlers: Record<string,(fn:TACFunction,analysis:Analysis)=>OptimizationRecord> = { constprop: constantPropagation, copyprop: copyPropagation, cse: commonSubexpressions,
    dce: deadCode, licm: invariantMotion, unreachable: unreachableCode };
  const totals = new Map<string,number>(passes.map(name => [name, 0])), records: string[] = [];
  for (const fn of program.functions) {
    const before = instructionCount(fn); let rounds = 0;
    records.push('== ' + fn.name + ' ==');
    for (let round = 1; round <= settings.rounds; round++) {
      const counts: string[] = [], details: string[] = []; let changed = 0; rounds = round;
      for (const name of passes) {
        const result = handlers[name](fn, analyze(fn));
        counts.push(name + '=' + result.count); changed += result.count;
        totals.set(name, totals.get(name)! + result.count);
        details.push(...result.records.map(record => '  ' + name + ' ' + record));
      }
      records.push('round ' + round + ': ' + counts.join(' '), ...details);
      if (changed === 0) break;
    }
    records.push('result: rounds=' + rounds + ' instructions=' + before + '->' + instructionCount(fn));
  }
  const graph = callGraph(program), callLines = graphLines(program, graph);
  const removed = settings.passes.has('unreachable') ? graph.unreachable : [];
  const removedSet = new Set(removed); program.functions = program.functions.filter(fn => !removedSet.has(fn.name));
  records.push('== program ==', 'removed functions: ' + list(removed), '== total ==', passes.map(name => name + '=' + totals.get(name)).join(' '));
  return { records, callLines };
}

function analysisLines(fn: TACFunction, type: string, analysis: Analysis): string[] {
  const lines: string[] = ['== ' + fn.name + ' (' + type + ') ==', 'code:'];
  for (const instruction of fn.code) {
    if (instruction.kind === 'label') { lines.push(instructionText(instruction)); continue; }
    let line = '  #' + instruction.number + ' ' + instructionText(instruction);
    if (analysis.reachable.has(analysis.owner.get(instruction.number!)!)) {
      const names = Array.from(new Set(uses(instruction)));
      if (names.length) line += ' | ' + names.map(name => name + ':' +
        list(reaching(analysis, instruction, name).map(value => value.number).sort((a, b) => a - b))).join(' ');
    }
    lines.push(line);
  }
  lines.push('blocks: ' + analysis.blocks.length);
  for (const block of analysis.blocks) {
    lines.push('B' + block.number + ' ' + block.instructions[0].number + '-' + block.instructions[block.instructions.length - 1].number +
      ' labels=' + list(block.labels) + ' preds=' + blockList(block.predecessors) + ' succs=' + blockList(block.successors));
  }
  lines.push('unreachable: ' + blockList(analysis.blocks.filter(b => !analysis.reachable.has(b.number)).map(b => b.number)),
    'order: ' + blockList(analysis.reversePostorder), 'dominators:');
  const reachable = analysis.blocks.filter(b => analysis.reachable.has(b.number));
  for (const block of reachable) {
    const parent = analysis.immediate.get(block.number);
    lines.push('B' + block.number + ' idom=' + (parent === null ? '-' : 'B' + parent) +
      ' dom=' + blockList(numeric(analysis.dominators.get(block.number)!)));
  }
  lines.push('dominator tree:');
  const stack = [{ number: 1, depth: 0 }];
  while (stack.length) {
    const current = stack.pop(); lines.push(' '.repeat(2 * current.depth) + 'B' + current.number);
    const children = reachable.filter(b => analysis.immediate.get(b.number) === current.number);
    for (let i = children.length - 1; i >= 0; i--) stack.push({ number: children[i].number, depth: current.depth + 1 });
  }
  lines.push('loops: ' + analysis.loops.length);
  for (const loop of analysis.loops) {
    lines.push('header=B' + loop.header + ' latches=' + blockList(loop.latches) + ' depth=' + loop.depth +
      ' blocks=' + blockList(numeric(loop.blocks)) + ' exits=' + blockList(numeric(loop.exits)));
  }
  for (const [kind, title] of [['rd', 'reaching definitions'], ['live', 'liveness'], ['available', 'available expressions']]) {
    const flow = analysis[kind as 'rd'|'live'|'available'];
    const render = (set: Set<string>): string => {
      if (kind === 'rd') {
        const definitions = Array.from(set, key => analysis.definitions.get(key)!);
        definitions.sort((a, b) => a.number - b.number || ascii(a.name, b.name));
        return list(definitions.map(value => value.name + ':' + value.number));
      }
      const values = kind === 'available' ? Array.from(set, key => expressionText(analysis.expressions.get(key)!)) : Array.from(set);
      return list(values.sort(ascii));
    };
    lines.push(title + ': iterations=' + flow.iterations);
    for (const block of reachable) lines.push('B' + block.number + ' in=' + render(flow.incoming.get(block.number)) +
      ' out=' + render(flow.outgoing.get(block.number)));
  }
  return lines;
}

function allocateFunction(fn: TACFunction, analysis: Analysis, registers: number): {fn:TACFunction; lines:string[]} {
  const allocation = allocate(fn, analysis, registers), { colors, nodes } = allocation;
  const rename = (name: string): string => colors.has(name) && colors.get(name) !== null ? 'R' + colors.get(name) : name;
  let moves = 0, pressure = 0, spillUses = 0, spillDefs = 0;
  const spilled = new Set<string>(nodes.filter(name => colors.get(name) === null));
  for (const parameter of fn.parameters) if (spilled.has(parameter)) spillDefs++;
  const code: Instruction[] = [];
  for (const source of fn.code) {
    if (source.kind === 'label') { code.push(copy(source)); continue; }
    const instruction = copy(source), defined = definition(source);
    if (defined !== undefined) {
      if (spilled.has(defined)) spillDefs++;
      instruction.dest = rename(defined);
    }
    for (const slot of operandSlots(source)) if (variable(source[slot])) {
      if (spilled.has(source[slot] as string)) spillUses++;
      instruction[slot] = rename(source[slot] as string);
    }
    if (instruction.kind === 'copy' && instruction.dest === instruction.a) moves++;
    else code.push(instruction);
    if (analysis.live.before.has(source.number)) pressure = Math.max(pressure,
      analysis.live.before.get(source.number!)!.size, analysis.live.after.get(source.number!)!.size);
  }
  const result = { ...fn, parameters: fn.parameters.map(rename), code };
  const lines = ['== ' + fn.name + ' ==', 'nodes=' + nodes.length + ' edges=' + allocation.edges + ' registers=' + registers];
  for (const name of nodes) lines.push(name + ' degree=' + allocation.neighbors.get(name)!!.size + ' cost=' + allocation.costs.get(name)! +
    ' neighbors=' + list(Array.from(allocation.neighbors.get(name)).sort(ascii)));
  lines.push('simplify: ' + list(allocation.order),
    'potential spills: ' + list(allocation.potential.map(value => value.name + '(' + value.cost + '/' + value.degree + ')')));
  for (const name of nodes) lines.push(name + ' -> ' + (colors.get(name) === null ? 'spill' : 'R' + colors.get(name)));
  const used = new Set<number>(Array.from(colors.values()).filter((color): color is number => color !== null)).size;
  lines.push('summary: pressure=' + pressure + ' used=' + used + ' spilled=' + spilled.size + ' moves=' + moves +
    ' spill_uses=' + spillUses + ' spill_defs=' + spillDefs, ...functionLines(result));
  return { fn: result, lines };
}

function execute(program: TACProgram, input: number[]): ExecutionResult {
  const functions = new Map<string, FunctionRuntime>();
  const calls = new Map<string,number>(), steps = new Map<string,number>();
  const kinds: Record<string,number> = Object.fromEntries(KINDS.map(kind => [kind, 0]));
  for (const fn of program.functions) {
    const instructions: Instruction[] = [], labels = new Map<string,number>();
    for (const instruction of fn.code) {
      if (instruction.kind === 'label') labels.set(instruction.name!, instructions.length);
      else instructions.push(instruction);
    }
    functions.set(fn.name, { ...fn, instructions, labels }); calls.set(fn.name, 0); steps.set(fn.name, 0);
  }
  const arrays = new Map<string,number[]>(program.arrays.map(array => [array.name, Array<number>(array.size).fill(0)]));
  const stack: Frame[] = [], output: number[] = []; let inputIndex = 0;
  const push = (name: string, argumentsList: number[], destination: string | undefined): void => {
    const fn = functions.get(name)!, values = new Map<string,number>(fn.parameters.map((parameter, i) => [parameter, argumentsList[i]]));
    stack.push({ fn, values, pc: 0, arguments: [], destination });
    calls.set(name, calls.get(name)! + 1);
  };
  push('main', [], undefined);
  while (stack.length) {
    const frame = stack[stack.length - 1], instruction = frame.fn.instructions[frame.pc++];
    const value = (operand: Operand | undefined): number => variable(operand) ? frame.values.get(operand)! : operand as number;
    steps.set(frame.fn.name, steps.get(frame.fn.name)! + 1); kinds[instruction.kind]++;
    switch (instruction.kind) {
      case 'copy': frame.values.set(instruction.dest!, value(instruction.a)); break;
      case 'bin': frame.values.set(instruction.dest, operation(instruction.op!, value(instruction.a), value(instruction.b))); break;
      case 'load': frame.values.set(instruction.dest, arrays.get(instruction.array!)![value(instruction.a)]); break;
      case 'store': arrays.get(instruction.array)[value(instruction.a)] = value(instruction.b); break;
      case 'goto': frame.pc = frame.fn.labels.get(instruction.target!)!; break;
      case 'if': if (operation(instruction.op!, value(instruction.a), value(instruction.b))) frame.pc = frame.fn.labels.get(instruction.target); break;
      case 'param': frame.arguments.push(value(instruction.a)); break;
      case 'call': {
        const argumentsList = frame.arguments.splice(frame.arguments.length - instruction.count!, instruction.count!);
        push(instruction.name!, argumentsList, instruction.dest); break;
      }
      case 'return': {
        const result = instruction.a === undefined ? undefined : value(instruction.a);
        stack.pop();
        if (stack.length && frame.destination !== undefined) stack[stack.length - 1].values.set(frame.destination, result!);
        break;
      }
      case 'read': frame.values.set(instruction.dest, input[inputIndex++]); break;
      case 'print': output.push(value(instruction.a)); break;
    }
  }
  return { output, calls, steps, kinds, totalSteps: Array.from(steps.values()).reduce((a, b) => a + b, 0),
    totalCalls: Array.from(calls.values()).reduce((a, b) => a + b, 0) };
}

function staticKinds(program: TACProgram): Record<string,number> {
  const counts = Object.fromEntries(KINDS.map(kind => [kind, 0]));
  for (const fn of program.functions) for (const instruction of fn.code) if (instruction.kind !== 'label') counts[instruction.kind]++;
  return counts;
}

function comparePrograms(programs: TACProgram[], runs: number[][]): string[] {
  const names = ['original', 'optimized', 'allocated'], original = programs[0];
  const totals = programs.map(() => ({ 
    steps: new Map(original.functions.map(fn => [fn.name, 0])),
    calls: new Map(original.functions.map(fn => [fn.name, 0])),
    kinds: Object.fromEntries(KINDS.map(kind => [kind, 0])), totalSteps: 0
  }));
  const lines: string[] = []; let same = 0;
  for (let i = 0; i < runs.length; i++) {
    lines.push('run ' + (i + 1) + ': inputs=' + runs[i].length);
    const results = programs.map(program => execute(program, runs[i]));
    for (let j = 0; j < results.length; j++) {
      const result = results[j], total = totals[j];
      lines.push('  ' + names[j] + ': steps=' + result.totalSteps + ' calls=' + result.totalCalls + ' output=' + list(result.output));
      total.totalSteps += result.totalSteps;
      for (const [name, count] of result.calls) total.calls.set(name, total.calls.get(name)! + count);
      for (const [name, count] of result.steps) total.steps.set(name, total.steps.get(name)! + count);
      for (const kind of KINDS) total.kinds[kind] += result.kinds[kind];
    }
    const equal = results.slice(1).every(result => result.output.length === results[0].output.length &&
      result.output.every((value, index) => value === results[0].output[index]));
    if (equal) same++;
    lines.push('  result: ' + (equal ? 'same' : 'different'));
  }
  lines.push('== profile ==');
  for (const fn of original.functions) lines.push(fn.name + ': calls=' + totals[0].calls.get(fn.name) +
    ' original=' + totals[0].steps.get(fn.name) + ' optimized=' + totals[1].steps.get(fn.name) + ' allocated=' + totals[2].steps.get(fn.name));
  const counts = programs.slice(0, 2).map(staticKinds), instructions = programs.slice(0, 2).map(program =>
    program.functions.reduce((sum, fn) => sum + instructionCount(fn), 0));
  lines.push('== summary ==', 'runs=' + runs.length + ' same=' + same + ' different=' + (runs.length - same),
    'instructions: original=' + instructions[0] + ' optimized=' + instructions[1],
    'kinds: ' + KINDS.map(kind => kind + '=' + counts[0][kind] + '->' + counts[1][kind]).join(' '),
    'steps: ' + names.map((name, index) => name + '=' + totals[index].totalSteps).join(' '));
  for (let i = 0; i < names.length; i++) lines.push('dynamic ' + names[i] + ': ' + KINDS.map(kind => kind + '=' + totals[i].kinds[kind]).join(' '));
  return lines;
}

function main(): void {
  const parameters = readFileSync('input/params.txt', 'ascii').split('\n').map(line => line.split(' '));
  const settings = { registers: Number(parameters[0][1]), passes: new Set(parameters[1].slice(1)), rounds: Number(parameters[2][1]) };
  const input = fs.readFileSync('input/input.txt', 'ascii').trim().split('\n').map(line => line.split(/ +/).map(Number));
  const runs = input.slice(1, 1 + input[0][0]).map(line => line.slice(1, 1 + line[0]));
  const original = readProgram(), program = cloneProgram(original);
  const analyses = ['== call graph (original) ==', ...graphLines(original, callGraph(original))];
  for (const fn of original.functions) analyses.push(...analysisLines(fn, 'original', analyze(fn)));
  const passes = optimize(program, settings);
  analyses.push('== call graph (optimized) ==', ...passes.callLines);
  const allocated: TACProgram = { arrays: program.arrays.map(array => ({ ...array })), functions: [] };
  const allocationLines: string[] = [];
  for (const fn of program.functions) {
    const analysis = analyze(fn);
    analyses.push(...analysisLines(fn, 'optimized', analysis));
    const result = allocateFunction(fn, analysis, settings.registers);
    allocated.functions.push(result.fn); allocationLines.push(...result.lines);
  }
  const outputs = { 'optimized.tac': programLines(program), 'analysis.txt': analyses, 'passes.txt': passes.records,
    'regalloc.txt': allocationLines, 'comparison.txt': comparePrograms([original, program, allocated], runs) };
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(outputs)) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
