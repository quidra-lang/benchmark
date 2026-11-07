import {mkdirSync,writeFileSync} from 'node:fs';
import * as parser from './pddl_parser.ts';
import * as grounding from './grounding.ts';
import * as heuristics from './heuristics.ts';
import * as search from './search.ts';
import * as graphplan from './graphplan.ts';
import type {
  Domain,Problem,Settings,SearchConfig,CandidatePlan,Step,
  GroundedModel,GroundedAction,TransformResult,TransformAction,
  PlanResult,GraphPlanResult,Validation,PlanAnalysis,Atom
} from './types.ts';

function append(lines:string[],values:string[]):void {
  for (const value of values) lines.push(value);
}

function list(heading:string,values:(string|number)[]):string {
  return `${heading} ${values.length === 0 ? '-' : values.join(' ')}`;
}

function numberList(values:number[]):string {
  return values.length === 0 ? '-' : values.join(',');
}

function valueText(value:number):string {
  return value === Infinity ? 'inf' : String(value);
}

function planCost(plan:GroundedAction[]):number {
  let cost = 0;
  for (const action of plan) cost += action!.cost;
  return cost;
}

function stepOf(action:GroundedAction):Step {
  return {name: action.name, arguments: action.arguments};
}

function stepText(step:Step):string {
  return parser.notation({predicate: step.name, terms: step.arguments});
}

function meaningfulLines(text:string):string[] {
  return text.slice(0, -1).split('\n').filter(line => line !== '' && !line.startsWith('#'));
}

function readSettings(text:string):Settings {
  const settings:Settings = {runs:[],repair:{algorithm:'',heuristic:'',tag:''},budget:0,weight:1,graphplan:0};
  for (const line of meaningfulLines(text)) {
    const [kind, first, second] = line.split(' ');
    if (kind === 'run' || kind === 'repair') {
      const configuration:SearchConfig = {algorithm:first,heuristic:second,tag:`${first} ${second}`};
      if (kind === 'run') settings.runs.push(configuration);
      else settings.repair = configuration;
    } else settings[kind] = Number(first);
  }
  return settings;
}

function readCandidates(text:string):CandidatePlan[] {
  const candidates:CandidatePlan[] = [];
  let current:CandidatePlan|null = null;
  for (const line of meaningfulLines(text)) {
    if (line.startsWith('plan ')) {
      const [, problem, label] = line.split(' ');
      current = {number: candidates.length + 1, problem, label, steps: []};
    } else if (line === 'end') candidates.push(current!);
    else {
      const [name, ...args] = line.slice(1, -1).split(' ');
      current!.steps.push({name, arguments: args});
    }
  }
  return candidates;
}

function argumentError(domain:Domain,arguments_:string[],expected:string[],table:Map<string,string>,noun:string):string|null {
  if (arguments_.length !== expected.length) return `expected ${expected.length} arguments, got ${arguments_.length}`;
  for (let index = 0; index < arguments_.length; index++) {
    const name = arguments_[index];
    if (!table.has(name)) return `unknown ${noun} ${name}`;
    if (!grounding.subtype(table.get(name)!, expected[index], domain.parents)) {
      return `argument ${index + 1} (${name}) is not of type ${expected[index]}`;
    }
  }
  return null;
}

function validateDomain(domain:Domain):void {
  const kept:Domain['actions'] = [];
  const diagnostics:string[] = [];
  for (const action of domain.actions) {
    let error = null;
    for (const parameter of action.parameters) {
      if (!domain.parents.has(parameter.type)) {
        error = `unknown type ${parameter.type}`;
        break;
      }
    }
    const parameters = new Map<string,string>(action.parameters.map(parameter => [parameter.name, parameter.type]));
    if (error === null) {
      for (const literal of action.conditions.concat(action.effects)) {
        const atom = literal.atom;
        if (atom.predicate !== '=' && !domain.predicateTable.has(atom.predicate)) error = `unknown predicate ${atom.predicate}`;
        else {
          const expected = atom.predicate === '=' ? ['object', 'object'] : domain.predicateTable.get(atom.predicate)!.types;
          error = argumentError(domain, atom.terms, expected, parameters, 'variable');
        }
        if (error !== null) {
          error = `${parser.notation(atom)}: ${error}`;
          break;
        }
      }
    }
    if (error !== null) diagnostics.push(`error: action ${action.name}: ${error}`);
    else kept.push(action);
  }
  domain.actions = kept;
  const used = new Set<string>();
  for (const action of kept) for (const literal of action.conditions.concat(action.effects)) used.add(literal.atom.predicate);
  for (const predicate of domain.predicates) {
    if (!used.has(predicate.name)) diagnostics.push(`warning: predicate ${predicate.name} is not used by any action`);
  }
  domain.diagnostics = diagnostics;
  domain.actionTable = new Map(kept.map(action => [action.name, action]));
  grounding.classifyPredicates(domain);
}

function validateProblem(domain:Domain,problem:Problem):void {
  problem.diagnostics = [];
  for (const [field, side] of [['init', 'init'], ['goals', 'goal']] as ['init'|'goals',string][]) {
    const kept:Atom[] = [];
    const seen = new Set<string>();
    for (const atom of problem[field]) {
      let error = null;
      if (!domain.predicateTable.has(atom.predicate)) error = `unknown predicate ${atom.predicate}`;
      else error = argumentError(domain, atom.terms, domain.predicateTable.get(atom.predicate).types, problem.objectTypes, 'object');
      const notation = parser.notation(atom);
      if (error === null && seen.has(notation)) error = 'duplicate';
      if (error !== null) problem.diagnostics.push(`warning: ${side} ${notation}: ${error}`);
      else {
        seen.add(notation);
        kept.push(atom);
      }
    }
    problem[field] = kept;
  }
}

function domainLines(domain:Domain):string[] {
  const lines = [`== domain ${domain.name} ==`];
  append(lines, domain.diagnostics);
  for (const type of domain.types) {
    const chain:string[] = [];
    for (let current:string|null = type; current !== null; current = domain.parents.get(current)!) chain.push(current);
    lines.push(`type ${chain.join(' < ')}`);
  }
  for (const predicate of domain.predicates) {
    lines.push(`predicate ${predicate.name}/${predicate.types.length} ${domain.fluent.has(predicate.name) ? 'fluent' : 'static'}`);
  }
  for (const action of domain.actions) {
    lines.push(`action ${action.name}/${action.parameters.length} cost=${action.cost} pre=${action.conditions.length} ` +
      `add=${action.adds.length} del=${action.deletes.length}`);
  }
  return lines;
}

function groundingLines(domain:Domain,problem:Problem):string[] {
  const model = problem.model;
  const lines = [`== problem ${problem.name} ==`];
  append(lines, problem.diagnostics);
  lines.push(`objects: ${problem.objects.length}`);
  for (const type of domain.types) lines.push(list(`  ${type}:`, model.objectsByType.get(type)!.map(object => object.name)));
  lines.push(`static facts: ${model.staticCount}`);
  for (const schema of model.schemas) {
    lines.push(`schema ${schema.source.name}: assignments=${schema.assignments} candidates=${schema.candidates} reachable=${schema.reachable}`);
  }
  lines.push(`candidates: ${model.candidateCount} reachable: ${model.actions.length}`);
  lines.push(`facts: ${model.facts.length} init: ${search.numbers(model.initial).length} goals: ${model.goalFacts.length}`);
  for (const atom of model.unreachable) lines.push(`unreachable goal: ${parser.notation(atom)}`);
  lines.push(list('facts by predicate:', domain.predicates.filter(predicate => domain.fluent.has(predicate.name))
    .map(predicate => `${predicate.name}=${model.facts.filter(fact => fact.predicate === predicate.name).length}`)));
  lines.push('facts:');
  for (let number = 0; number < model.facts.length; number++) lines.push(`  ${number} ${model.facts[number].notation}`);
  lines.push('actions:');
  for (const action of model.actions) {
    lines.push(`  ${action.number} ${action.notation} cost=${action.cost} pre=${numberList(action.preFacts)} ` +
      `neg=${numberList(action.negFacts)} add=${numberList(action.addFacts)} del=${numberList(action.delFacts)}`);
  }
  return lines;
}

function transform(model:GroundedModel):TransformResult {
  let negative = 0n;
  for (const action of model.actions) negative |= action.neg;
  const complements = new Map<number,number>(search.numbers(negative).map((fact, index) => [fact, model.facts.length + index]));
  const complement = (facts:bigint):bigint => {
    let result = 0n;
    for (const fact of search.numbers(facts)) if (complements.has(fact)) result |= search.bit(complements.get(fact)!);
    return result;
  };
  const actions:TransformAction[] = model.actions.map(action => ({number: action.number, original: action,
    pre: action.pre | complement(action.neg), add: action.add | complement(action.del),
    del: action.del | complement(action.add)}));
  return {actions, initial: model.initial | complement(negative & ~model.initial),
    count: complements.size, factCount: model.facts.length + complements.size};
}

function interfere(first:GroundedAction,second:GroundedAction):boolean {
  return (first.del & (second.pre | second.add)) !== 0n || (second.del & (first.pre | first.add)) !== 0n ||
    (first.add & second.neg) !== 0n || (second.add & first.neg) !== 0n;
}

function parallelize(plan:GroundedAction[]):GroundedAction[][] {
  const assigned:number[] = [];
  const layers:GroundedAction[][] = [];
  for (let index = 0; index < plan.length; index++) {
    let layer = 1;
    const action = plan[index];
    for (let before = 0; before < index; before++) {
      const earlier = plan[before];
      if ((earlier.add & action.pre) !== 0n || (earlier.del & action.neg) !== 0n || interfere(earlier, action)) {
        layer = Math.max(layer, assigned[before] + 1);
      }
    }
    assigned.push(layer);
    while (layers.length < layer) layers.push([]);
    layers[layer - 1].push(action);
  }
  return layers;
}

function validateParallel(model:GroundedModel,layers:GroundedAction[][]):string {
  let state = model.initial;
  for (let index = 0; index < layers.length; index++) {
    const layer = layers[index];
    if (layer.some(action => !search.applicable(state, action))) return `invalid at layer ${index + 1}`;
    for (let first = 0; first < layer.length; first++) {
      for (let second = first + 1; second < layer.length; second++) {
        if (interfere(layer[first], layer[second])) return `invalid at layer ${index + 1}`;
      }
    }
    let add = 0n;
    let del = 0n;
    for (const action of layer) {
      add |= action.add;
      del |= action.del;
    }
    state = (state & ~del) | add;
  }
  return search.contains(state, model.goal) ? 'valid' : 'goal not reached';
}

function improve(model:GroundedModel,original:GroundedAction[]):GroundedAction[] {
  let plan = original.slice();
  let index = 0;
  while (index < plan.length) {
    let state = model.initial;
    const retained = plan.slice(0, index);
    for (const action of retained) state = search.apply(state, action);
    for (const action of plan.slice(index + 1)) {
      if (search.applicable(state, action)) {
        state = search.apply(state, action);
        retained.push(action);
      }
    }
    if (search.contains(state, model.goal)) plan = retained;
    else index++;
  }
  return plan;
}

function validateSteps(domain:Domain,problem:Problem,steps:Step[]):Validation {
  const state = new Set<string>(problem.init.map(parser.notation));
  let cost = 0;
  for (let index = 0; index < steps.length; index++) {
    const step = steps[index];
    const prefix = `step ${index + 1} ${stepText(step)}:`;
    const action = domain.actionTable.get(step.name);
    let error:string|null = null;
    if (action === undefined) error = `unknown action ${step.name}`;
    else error = argumentError(domain, step.arguments, action.parameters.map(parameter => parameter.type), problem.objectTypes, 'object');
    let assignment:Map<string,string>;
    if (error === null) {
      assignment = new Map<string,string>(action!.parameters.map((parameter, number) => [parameter.name, step.arguments[number]]));
      for (const literal of action!.conditions) {
        const atom = grounding.substitute(literal.atom, assignment);
        const notation = parser.notation(atom);
        const truth = atom.predicate === '=' ? atom.terms[0] === atom.terms[1] : state.has(notation);
        if (truth === literal.negative) {
          error = `precondition ${literal.negative ? `(not ${notation})` : notation} is false`;
          break;
        }
      }
    }
    if (error !== null) return {result: 'invalid', messages: [`${prefix} ${error}`], correct: index, cost};
    for (const atom of action!.deletes) state.delete(parser.notation(grounding.substitute(atom, assignment)));
    for (const atom of action!.adds) state.add(parser.notation(grounding.substitute(atom, assignment)));
    cost += action.cost;
  }
  const missing = problem.goals.filter(atom => !state.has(parser.notation(atom)));
  return missing.length === 0 ? {result: 'valid', messages: [`length=${steps.length} cost=${cost}`], correct: steps.length, cost} :
    {result: 'goal not reached', messages: missing.map(atom => `unsatisfied goal ${parser.notation(atom)}`), correct: steps.length, cost};
}

function verdict(validation:Validation):string {
  return validation.result === 'valid' ? `valid ${validation.messages[0]}` : `${validation.result}: ${validation.messages[0]}`;
}

function analyzePlan(domain:Domain,problem:Problem,plan:GroundedAction[]):PlanAnalysis {
  const model = problem.model;
  const layers = parallelize(plan);
  const improved = improve(model, plan);
  let state = model.initial;
  let visited = 0n;
  for (const action of plan) {
    state = search.apply(state, action);
    visited |= state;
  }
  const landmarks = problem.engine.landmarks(model.initial).facts;
  const missed = landmarks.filter(fact => (visited & search.bit(fact)) === 0n);
  return {layers, improved, landmarks, missed, parallel: validateParallel(model, layers),
    validation: validateSteps(domain, problem, plan.map(stepOf)),
    improvedValidation: validateSteps(domain, problem, improved.map(stepOf))};
}

function prepareProblem(domain:Domain,problem:Problem,settings:Settings):void {
  validateProblem(domain, problem);
  problem.model = grounding.ground(domain, problem);
  problem.unreachable = problem.model.unreachable.length > 0;
  problem.results = [];
  if (!problem.unreachable) problem.engine = new heuristics.Engine(problem.model);
  for (const configuration of settings.runs) {
    const result = problem.unreachable ? {result: 'unreachable goal', plan: null, expanded: 0, generated: 0} :
      search.run(problem.model, problem.model.initial, configuration.algorithm, configuration.heuristic, settings, problem.engine);
    problem.results.push({...configuration, ...result});
  }
  if (problem.unreachable) problem.graph = {result:'unreachable goal',plan:null,expanded:0,generated:0,logs:[],memoHits:0,layers:null};
  else {
    const transformed = transform(problem.model);
    problem.graph = graphplan.solve(transformed.actions, transformed.factCount, transformed.initial, problem.model.goal, settings.graphplan);
    problem.graph.complements = transformed.count;
  }
  problem.results.push({...problem.graph, algorithm: 'graphplan', heuristic: 'none', tag: 'graphplan'});
  for (const result of problem.results) {
    if (result.result === 'solved') {
      result.cost = planCost(result.plan!);
      result.analysis = analyzePlan(domain, problem, result.plan!);
    }
  }
  const solved = problem.results.filter(result => result.result === 'solved');
  problem.solved = solved.length;
  problem.best = null;
  for (const result of solved) if (problem.best === null || result.cost! < problem.best) problem.best = result.cost!;
  problem.proof = problem.results.find(result => result.result === 'solved' && ['ucs none', 'astar hmax'].includes(result.tag)) || null;
  problem.optimal = problem.proof !== null ? problem.proof.cost! :
    problem.results.some(result => ['unreachable goal', 'dead end', 'exhausted', 'unreachable'].includes(result.result)) ? 'none' : 'unknown';
}

function heuristicText(values:Record<string,number>):string {
  return heuristics.names.map(name => `${name}=${valueText(values[name])}`).join(' ');
}

function planBlock(domain:Domain,problem:Problem,result:PlanResult,earlier:Map<string,string>):string[] {
  const plan = result.plan!, analysis = result.analysis!;
  const key = plan.map(action => action.number).join(',');
  let heading = `plan: length=${plan.length} cost=${result.cost}`;
  if (earlier.has(key)) heading += ` (same as ${earlier.get(key)})`;
  else earlier.set(key, result.tag);
  const lines = [heading];
  for (let index = 0; index < plan.length; index++) lines.push(`  ${index + 1} ${plan[index].notation}`);
  const schemas = [];
  for (const source of domain.actions) {
    const count = plan.filter(action => action.source === source).length;
    if (count > 0) schemas.push(`${source.name}=${count}`);
  }
  lines.push(list('schemas:', schemas));
  lines.push(`parallel: layers=${analysis.layers.length}`);
  for (let index = 0; index < analysis.layers.length; index++) lines.push(list(`  ${index + 1}:`, analysis.layers[index].map(action => action.notation)));
  const removed = plan.length - analysis.improved.length;
  lines.push(`improved: length=${analysis.improved.length} cost=${planCost(analysis.improved)} removed=${removed}`);
  if (removed > 0) {
    for (let index = 0; index < analysis.improved.length; index++) lines.push(`  ${index + 1} ${analysis.improved[index].notation}`);
  }
  lines.push(`landmarks reached: ${analysis.landmarks.length - analysis.missed.length}/${analysis.landmarks.length}`);
  for (const fact of analysis.missed) lines.push(`  missed ${problem.model.facts[fact].notation}`);
  return lines;
}

function profileLines(problem:Problem):string[] {
  const proof = problem.proof!;
  const model = problem.model;
  const lines = [`-- profile (${proof.tag}) --`];
  const overestimates = Object.fromEntries(heuristics.names.map(name => [name, 0]));
  let state = model.initial;
  let remaining = proof.cost!;
  for (let index = 0; index <= proof.plan!.length; index++) {
    const values = problem.engine.all(state);
    lines.push(`  ${index}: h*=${remaining} ${heuristicText(values)}`);
    for (const name of heuristics.names) if (values[name] > remaining) overestimates[name]++;
    if (index < proof.plan!.length) {
      state = search.apply(state, proof.plan![index]);
      remaining -= proof.plan![index].cost;
    }
  }
  lines.push(`overestimates: ${heuristicText(overestimates)}`);
  lines.push(`-- causal links (${proof.tag}) --`);
  const suppliers = Array(model.facts.length).fill(0);
  for (let index = 0; index < proof.plan!.length; index++) {
    const action = proof.plan![index];
    lines.push(list(`  ${index + 1} ${action.notation}:`, action.preFacts.map(fact => `${model.facts[fact].notation}<-${suppliers[fact]}`)));
    for (const fact of action.addFacts) suppliers[fact] = index + 1;
  }
  lines.push(list('  goal:', model.goalFacts.map(fact => `${model.facts[fact].notation}<-${suppliers[fact]}`)));
  return lines;
}

function plansLines(domain:Domain,problem:Problem):string[] {
  const lines = [`== problem ${problem.name} ==`];
  if (problem.unreachable) lines.push('initial h: unreachable goal');
  else {
    const initial = problem.model.initial;
    const values = problem.engine.all(initial);
    const landmarks = problem.engine.landmarks(initial);
    const relaxed = problem.engine.relaxedPlan(initial);
    lines.push(`initial h: ${heuristicText(values)}`);
    lines.push(`landmarks: ${landmarks.facts.length}`);
    for (const fact of landmarks.facts) lines.push(`  ${problem.model.facts[fact].notation}`);
    lines.push(`relaxed plan: length=${relaxed.plan.length} cost=${valueText(relaxed.value)}`);
    for (const action of relaxed.plan) lines.push(`  ${action.notation}`);
    lines.push(list('helpful:', relaxed.helpful.map(action => action.notation)));
  }
  const earlier = new Map<string,string>();
  for (const result of problem.results) {
    lines.push(`-- ${result.tag} --`);
    if (problem.unreachable) lines.push('result: FAIL (unreachable goal)');
    else {
      const text = result.result === 'solved' ? 'solved' : `FAIL (${result.result})`;
      lines.push(`result: ${text} expanded=${result.expanded} generated=${result.generated}`);
    }
    if (result.result === 'solved') append(lines, planBlock(domain, problem, result, earlier));
  }
  if (problem.proof !== null) append(lines, profileLines(problem));
  lines.push('');
  return lines;
}

function graphLines(problem:Problem):string[] {
  const lines = [`== problem ${problem.name} ==`];
  const result = problem.graph;
  if (problem.unreachable) lines.push('result: FAIL (unreachable goal)');
  else {
    lines.push(`complementary facts: ${result.complements}`);
    append(lines, result.logs);
    const counts = `searched=${result.expanded} memo_hits=${result.memoHits} tried=${result.generated}`;
    if (result.result === 'solved') {
      lines.push(`result: solved levels=${result.layers!.length} length=${result.plan!.length} cost=${planCost(result.plan!)} ${counts}`);
      for (let index = 0; index < result.layers!.length; index++) lines.push(list(`layer ${index + 1}:`, result.layers![index].map(action => action.notation)));
    } else lines.push(`result: FAIL (${result.result}) ${counts}`);
  }
  lines.push('');
  return lines;
}

function summaryLines(problems:Problem[],settings:Settings):string[] {
  const lines = ['== summary =='];
  for (const problem of problems) {
    lines.push(`${problem.name}: solved=${problem.solved}/${settings.runs.length + 1} ` +
      `best=${problem.best === null ? '-' : problem.best} optimal=${problem.optimal}`);
  }
  const tags = settings.runs.map(configuration => configuration.tag).concat('graphplan');
  for (let index = 0; index < tags.length; index++) {
    let solved = 0;
    let best = 0;
    let expanded = 0;
    let generated = 0;
    for (const problem of problems) {
      const result = problem.results[index];
      if (result.result === 'solved') {
        solved++;
        if (result.cost === problem.best) best++;
      }
      expanded += result.expanded;
      generated += result.generated;
    }
    lines.push(`${tags[index]}: solved=${solved} best=${best} expanded=${expanded} generated=${generated}`);
  }
  return lines;
}

function candidateLines(domain:Domain,problems:Problem[],candidates:CandidatePlan[],settings:Settings):{lines:string[];valid:number} {
  const byName = new Map<string,Problem>(problems.map(problem => [problem.name, problem]));
  const lines:string[] = ['== candidates =='];
  let valid = 0;
  for (const candidate of candidates) {
    const problem = byName.get(candidate.problem)!;
    const model = problem.model;
    const validation = validateSteps(domain, problem, candidate.steps);
    const prefix = `candidate ${candidate.number} ${problem.name} ${candidate.label}:`;
    if (validation.result === 'valid') {
      valid++;
      lines.push(`${prefix} ${verdict(validation)}`);
      const mapped = candidate.steps.map(step => model.actionTable.get(stepText(step))!);
      const improved = improve(model, mapped);
      lines.push(`  improved: length=${improved.length} cost=${planCost(improved)} removed=${mapped.length - improved.length} ` +
        `best known=${problem.best === null ? '-' : problem.best}`);
      continue;
    }
    lines.push(`${prefix} ${validation.result}`);
    for (const message of validation.messages) lines.push(`  ${message}`);
    if (problem.unreachable) {
      lines.push('  repair: FAIL (unreachable goal)');
      continue;
    }
    const prefixPlan = candidate.steps.slice(0, validation.correct).map(step => model.actionTable.get(stepText(step))!);
    let state = model.initial;
    for (const action of prefixPlan) state = search.apply(state, action);
    const repair = search.run(model, state, settings.repair.algorithm, settings.repair.heuristic, settings, problem.engine);
    if (repair.result !== 'solved') lines.push(`  repair: FAIL (${repair.result})`);
    else {
      const repaired = prefixPlan.concat(repair.plan);
      lines.push(`  repair: kept=${prefixPlan.length} added=${repair.plan.length} ${verdict(validateSteps(domain, problem, repaired.map(stepOf)))}`);
      for (let index = 0; index < repaired.length; index++) lines.push(`    ${index + 1} ${repaired[index].notation}`);
    }
  }
  return {lines, valid};
}

function writeOutputs(domain:Domain,problems:Problem[],settings:Settings,candidates:CandidatePlan[]):void {
  const ground = domainLines(domain);
  const plans = [];
  const graph = [];
  const validation = [];
  const comparison = ['problem,algorithm,heuristic,length,cost,expanded,generated'];
  let validatedPlans = 0;
  let validPlans = 0;
  for (const problem of problems) {
    ground.push('');
    append(ground, groundingLines(domain, problem));
    append(plans, plansLines(domain, problem));
    append(graph, graphLines(problem));
    validation.push(`== problem ${problem.name} ==`);
    for (const result of problem.results) {
      if (result.result === 'solved') {
        validatedPlans++;
        if (result.analysis!.validation.result === 'valid') validPlans++;
        validation.push(`${result.tag}: ${verdict(result.analysis!.validation)}`,
          `  parallel: ${result.analysis!.parallel}`, `  improved: ${verdict(result.analysis!.improvedValidation)}`);
      }
      comparison.push([problem.name, result.algorithm, result.heuristic, result.plan === null ? '-' : result.plan!.length,
        result.plan === null ? '-' : result.cost, result.expanded, result.generated].join(','));
    }
    validation.push('');
  }
  append(plans, summaryLines(problems, settings));
  const checkedCandidates = candidateLines(domain, problems, candidates, settings);
  append(validation, checkedCandidates.lines);
  validation.push('', '== summary ==', `plans: ${validatedPlans} valid: ${validPlans}`,
    `candidates: ${candidates.length} valid: ${checkedCandidates.valid}`);
  mkdirSync('output', {recursive: true});
  const files = {'grounding.txt': ground, 'plans.txt': plans, 'graphplan.txt': graph, 'validation.txt': validation, 'comparison.csv': comparison};
  for (const [name, lines] of Object.entries(files)) writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}

function main():void {
  const domain = parser.domain(parser.readText('domain.txt'));
  const problems = parser.problems(parser.readText('problems.txt'));
  const settings = readSettings(parser.readText('params.txt'));
  const candidates = readCandidates(parser.readText('candidates.txt'));
  validateDomain(domain);
  for (const problem of problems) prepareProblem(domain, problem, settings);
  writeOutputs(domain, problems, settings, candidates);
}

main();
