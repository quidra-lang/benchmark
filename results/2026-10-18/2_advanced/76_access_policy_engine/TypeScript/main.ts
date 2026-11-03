import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { readRbac, permissionKey } from './rbac.ts';
import { readPolicies } from './policy_parser.ts';
import { combine, indeterminate } from './combining.ts';
import * as analysis from './analysis.ts';
import type {
  AttributeValue, RuntimeValue, EvalError, AttributeSet, Expression, TargetClause,
  TargetResult, PolicyElement, EvalResult, AttachmentRule, Attachment, Request,
  InputData, Domain, Resource, Context, Activated, EvalRecord, PolicyElement as Rule,
  DomainAnalysis, ConflictPair, RuleStatistic, Activation,
} from './types.ts';

const compare = (first: string, second: string): number => first < second ? -1 : first > second ? 1 : 0;
const definite = (decision: string): boolean => decision === 'PERMIT' || decision === 'DENY';
const error = (reason: string): EvalError => ({error: reason});
const isError = (value: unknown): value is EvalError => value !== null && typeof value === 'object' && Object.hasOwn(value, 'error');
const effectError = (effect: string): string => `INDETERMINATE{${effect === 'DENY' ? 'D' : 'P'}}`;

function readLines(name: string): string[] {
  const text = readFileSync('input/' + name, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
}

function parseValue(text: string): AttributeValue {
  if (text === 'true' || text === 'false') return text === 'true';
  if (/^-?[0-9]+$/.test(text)) return Number(text);
  if (text.startsWith('[')) return text === '[]' ? [] : text.slice(1, -1).split(',');
  return text;
}

function valueNotation(value: AttributeValue): string {
  if (Array.isArray(value)) return '[' + value.map(item => '"' + item + '"').join(',') + ']';
  if (typeof value === 'string') return '"' + value + '"';
  return String(value);
}

function attributes(tokens: string[]): AttributeSet {
  return new Map<string,AttributeValue>(tokens.map((token): [string,AttributeValue] => {
    const separator = token.indexOf('=');
    return [token.slice(0, separator), parseValue(token.slice(separator + 1))];
  }));
}

function readAttributes(): InputData {
  const subjects = new Map<string,AttributeSet>();
  const resources = new Map<string,Resource>();
  const domains: Domain[] = [];
  let reference: AttributeSet = new Map();
  for (const line of readLines('attributes.txt')) {
    const fields = line.split(' ');
    if (fields[0] === 'SUBJECT') subjects.set(fields[1], attributes(fields.slice(2)));
    else if (fields[0] === 'RESOURCE') resources.set(fields[1], {id: fields[1], type: fields[2], attributes: attributes(fields.slice(3))});
    else if (fields[0] === 'DOMAIN') domains.push({reference: fields[1], values: fields.slice(2).map(parseValue)});
    else reference = attributes(fields.slice(1));
  }
  return {subjects, resources, domains, reference};
}

function readRequests(): Request[] {
  return readLines('requests.txt').map(line => {
    const fields = line.split(' ');
    const explained = fields.at(-1) === 'EXPLAIN';
    if (explained) fields.pop();
    return {id: fields[0], user: fields[1], roleSpec: fields[2], action: fields[3], resourceId: fields[4],
      environment: attributes(fields.slice(5)), explained};
  });
}

function typedBoolean(value: RuntimeValue, operation: string): RuntimeValue {
  return typeof value === 'boolean' || isError(value) ? value : error('type ' + operation);
}

function logical(operation: string, values: RuntimeValue[]): RuntimeValue {
  const operands = values.map(value => typedBoolean(value, operation));
  if (operation === 'and' || operation === 'all_of') {
    if (operands.includes(false)) return false;
    return operands.find(isError) || true;
  }
  if (operands.includes(true)) return true;
  return operands.find(isError) || false;
}

function applyOperation(operation: string, values: RuntimeValue[]): RuntimeValue {
  const failure = values.find(isError);
  if (failure !== undefined) return failure;
  const [first, second] = values;
  const integers = values.every(value => typeof value === 'number');
  const strings = values.every(value => typeof value === 'string');
  switch (operation) {
    case '+': if (integers) return (first as number) + (second as number); break;
    case '-': if (integers) return values.length === 1 ? -(first as number) : (first as number) - (second as number); break;
    case '*': if (integers) return (first as number) * (second as number); break;
    case '==':
    case '!=':
      if (typeof first === typeof second && !Array.isArray(first) && !Array.isArray(second)) {
        return operation === '==' ? first === second : first !== second;
      }
      break;
    case '<': if (integers) return (first as number) < (second as number); break;
    case '<=': if (integers) return (first as number) <= (second as number); break;
    case '>': if (integers) return (first as number) > (second as number); break;
    case '>=': if (integers) return (first as number) >= (second as number); break;
    case 'in': if (typeof first === 'string' && Array.isArray(second)) return second.includes(first); break;
    case 'not': if (typeof first === 'boolean') return !first; break;
    case 'starts_with':
    case '^=': if (strings) return (first as string).startsWith(second as string); break;
    case 'size': if (Array.isArray(first)) return first.length; break;
  }
  return error('type ' + operation);
}

function evaluateExpression(expression: Expression, attributeSet: AttributeSet, currentItem: RuntimeValue = null): RuntimeValue {
  if (expression.kind === 'literal') return expression.value!;
  if (expression.kind === 'it') return currentItem;
  if (expression.kind === 'attribute') {
    return attributeSet.has(expression.name!) ? attributeSet.get(expression.name!)! : error('missing ' + expression.name);
  }
  const operation = expression.operation!;
  if (operation === 'present') return attributeSet.has(expression.arguments![0].name);
  if (operation === 'any_of' || operation === 'all_of') {
    const bag = evaluateExpression(expression.arguments![0], attributeSet, currentItem);
    if (isError(bag)) return bag;
    if (!Array.isArray(bag)) return error('type ' + operation);
    const values = bag.map(item => evaluateExpression(expression.arguments![1], attributeSet, item));
    return logical(operation, values);
  }
  const values = expression.arguments!.map(argument => evaluateExpression(argument, attributeSet, currentItem));
  if (operation === 'and' || operation === 'or') return logical(operation, values);
  return applyOperation(operation, values);
}

function matchClause(clause: TargetClause, attributeSet: AttributeSet): TargetResult {
  if (!attributeSet.has(clause.reference)) {
    return clause.mandatory ? {status: 'INDETERMINATE', reason: 'missing ' + clause.reference} : {status: 'NO_MATCH'};
  }
  const value = attributeSet.get(clause.reference)!;
  const items = Array.isArray(value) ? value : [value];
  const results = items.map(item => applyOperation(clause.operation, [item, clause.literal]));
  if (results.includes(true)) return {status: 'MATCH'};
  const failure = results.find(isError);
  return failure === undefined ? {status: 'NO_MATCH'} : {status: 'INDETERMINATE', reason: failure.error};
}

function targetAnd(results: TargetResult[]): TargetResult {
  if (results.some(result => result.status === 'NO_MATCH')) return {status: 'NO_MATCH'};
  return results.find(result => result.status === 'INDETERMINATE') || {status: 'MATCH'};
}

function targetOr(results: TargetResult[]): TargetResult {
  if (results.some(result => result.status === 'MATCH')) return {status: 'MATCH'};
  return results.find(result => result.status === 'INDETERMINATE') || {status: 'NO_MATCH'};
}

function evaluateTarget(element: PolicyElement, attributeSet: AttributeSet): TargetResult {
  const lines = element.targets.map(line => targetOr(line.map(alternative =>
    targetAnd(alternative.map(clause => matchClause(clause, attributeSet))))));
  return targetAnd(lines);
}

function emptyResult(element: PolicyElement, target: TargetResult): EvalResult {
  return {element, target, decision: 'NOT_APPLICABLE', reason: null, decisive: null,
    obligations: [], advice: [], children: []};
}

function ruleValue(element: PolicyElement, attributeSet: AttributeSet, target: TargetResult): EvalResult {
  const result = emptyResult(element, target);
  if (target.status === 'NO_MATCH') return result;
  if (target.status === 'INDETERMINATE') {
    result.decision = effectError(element.effect);
    result.reason = target.reason || null;
    return result;
  }
  result.condition = element.condition === null ? true : typedBoolean(evaluateExpression(element.condition, attributeSet), 'condition');
  if (result.condition === true) {
    result.decision = element.effect;
    result.decisive = element.id;
  } else if (isError(result.condition)) {
    result.decision = effectError(element.effect);
    result.reason = result.condition.error;
  }
  return result;
}

function attachment(item: AttachmentRule, attributeSet: AttributeSet): Attachment | EvalError {
  const values = item.arguments.map(argument => evaluateExpression(argument.expression, attributeSet));
  const failure = values.find(isError);
  if (failure !== undefined) return failure;
  let text = item.id;
  for (let index = 0; index < values.length; index++) text += ` ${item.arguments[index].name}=${valueNotation(values[index] as AttributeValue)}`;
  return {id: item.id, text};
}

function attachObligations(result: EvalResult, attributeSet: AttributeSet, supporters: EvalResult[]): void {
  const decision = result.decision;
  for (const supporter of supporters) {
    for (const item of supporter.obligations) result.obligations.push(item as Attachment);
    for (const item of supporter.advice) result.advice.push(item as Attachment);
  }
  for (const obligation of result.element.obligations) {
    if (obligation.effect !== decision) continue;
    const item = attachment(obligation, attributeSet);
    if (isError(item)) {
      result.decision = effectError(decision);
      result.reason = `obligation ${obligation.id}: ${item.error}`;
      result.decisive = null;
      result.obligations = [];
      result.advice = [];
      return;
    }
    result.obligations.push(item);
  }
  for (const advice of result.element.advice) {
    if (advice.effect !== decision) continue;
    const item = attachment(advice, attributeSet);
    if (!isError(item)) result.advice.push(item);
  }
}

function evaluateElement(element: PolicyElement, attributeSet: AttributeSet, coverage: Map<string,string> | null = null): EvalResult {
  const target = evaluateTarget(element, attributeSet);
  if (element.kind === 'rule') {
    const result = ruleValue(element, attributeSet, target);
    if (definite(result.decision)) attachObligations(result, attributeSet, []);
    if (coverage !== null) {
      coverage.set(element.id, result.decision === 'PERMIT' ? 'P' : result.decision === 'DENY' ? 'D'
        : result.decision === 'NOT_APPLICABLE' ? '-' : 'I');
    }
    return result;
  }
  const result = emptyResult(element, target);
  if (target.status === 'NO_MATCH') return result;
  const combined = combine(element, child => evaluateElement(child, attributeSet, coverage), child => evaluateTarget(child, attributeSet));
  result.children = combined.children;
  result.decision = combined.decision;
  result.reason = combined.reason;
  if (target.status === 'INDETERMINATE') {
    if (definite(result.decision)) result.decision = effectError(result.decision);
    if (indeterminate(result.decision)) result.reason = target.reason;
  }
  if (definite(result.decision)) {
    const supporters = result.children.filter(child => child.state === 'evaluated' && child.result?.decision === result.decision)
      .map(child => child.result!);
    result.decisive = supporters.length === 0 ? element.id : supporters[0].decisive;
    attachObligations(result, attributeSet, supporters);
  }
  return result;
}

function activate(request: Request, context: Context, day: number, resource: Resource): Activated {
  const rbac = context.rbac;
  const authorized = rbac.authorized(request.user, day);
  const candidates = request.roleSpec === '-' ? [] : request.roleSpec === '*' ? [...authorized].sort() : request.roleSpec.split(',');
  const seen = new Set<string>();
  const active: string[] = [];
  const activations: Activation[] = [];
  for (const role of candidates) {
    const duplicate = seen.has(role);
    seen.add(role);
    let reason: string | null = null;
    if (!rbac.roles.has(role)) reason = 'unknown';
    else if (duplicate) reason = 'duplicate';
    else if (!authorized.has(role)) reason = 'unauthorized';
    else {
      const expanded = rbac.closure(active.concat(role));
      for (const constraint of rbac.dsd) {
        if (constraint.roles.filter(item => expanded.has(item)).length >= constraint.cardinality) {
          reason = 'dsd ' + constraint.name;
          break;
        }
      }
    }
    if (reason === null) active.push(role);
    activations.push({role, reason});
  }
  const session = [...rbac.closure(active)].sort();
  const key = permissionKey(request.action, resource.type);
  const granting = session.find(role => rbac.roles.get(role)!.permissions.has(key)) || null;
  return {activations, session, granting};
}

function requestAttributes(request: Request, context: Context, resource: Resource, activation: Activated): AttributeSet {
  const result = new Map<string,AttributeValue>();
  for (const [name, value] of context.data.subjects.get(request.user)!) result.set('subject.' + name, value);
  result.set('subject.id', request.user);
  result.set('subject.role', activation.session);
  result.set('subject.rbac', activation.granting !== null);
  for (const [name, value] of resource.attributes) result.set('resource.' + name, value);
  result.set('resource.id', resource.id);
  result.set('resource.type', resource.type);
  result.set('action.id', request.action);
  for (const [name, value] of request.environment) result.set('environment.' + name, value);
  return result;
}

function evaluateRequest(request: Request, context: Context, recordCoverage = false): EvalRecord {
  const coverage = recordCoverage ? new Map<string,string>(context.policies.rules.map(rule => [rule.id, '.'])) : null;
  let message: string | null = null;
  const day = request.environment.get('day');
  if (!context.data.subjects.has(request.user)) message = 'unknown user ' + request.user;
  else if (!context.data.resources.has(request.resourceId)) message = 'unknown resource ' + request.resourceId;
  else if (typeof day !== 'number' || day < 1 || day > 365) message = 'bad day';
  if (message !== null) return {request, error: message, coverage};
  const resource = context.data.resources.get(request.resourceId)!;
  const activation = activate(request, context, day as number, resource);
  const attributeSet = requestAttributes(request, context, resource, activation);
  const evaluation = evaluateElement(context.policies.root, attributeSet, coverage);
  return {request, error: null, day: day as number, resource, ...activation, evaluation, coverage};
}

function decisionNotation(result: EvalResult): string {
  return result.decision + (indeterminate(result.decision) ? ` (${result.reason})` : '');
}

function requestDecision(record: EvalRecord): string {
  if (record.error !== null) return 'ERROR ' + record.error;
  const result = record.evaluation!;
  return decisionNotation(result) + (definite(result.decision) ? ' by ' + result.decisive : '');
}

function treeLines(result: EvalResult, depth = 0): string[] {
  const indent = ' '.repeat(2 + 2 * depth);
  const element = result.element;
  let line = `${indent}${element.kind} ${element.id} ${element.kind === 'rule' ? element.effect : element.algorithm}`
    + ` target ${result.target.status}`;
  if (element.kind === 'rule' && result.target.status === 'MATCH') {
    line += ' condition ' + (result.condition === true ? 'TRUE' : result.condition === false ? 'FALSE' : 'INDETERMINATE');
  }
  const lines = [line + ' -> ' + decisionNotation(result)];
  if (element.kind === 'rule' || result.target.status === 'NO_MATCH') return lines;
  for (const child of result.children) {
    if (child.state === 'evaluated') {
      for (const nested of treeLines(child.result!, depth + 1)) lines.push(nested);
    } else if (child.state === 'skipped') lines.push(`${indent}  ${child.element.kind} ${child.element.id} skipped`);
    else {
      let checked = `${indent}  ${child.element.kind} ${child.element.id} ${child.element.algorithm} target ${child.target!.status}`;
      if (child.target!.status === 'INDETERMINATE') checked += ` (${child.target!.reason})`;
      lines.push(checked);
    }
  }
  return lines;
}

function decisionsLines(records: EvalRecord[]): string[] {
  const lines: string[] = [];
  for (const record of records) {
    lines.push(record.request.id + ' ' + requestDecision(record));
    if (record.error !== null) continue;
    for (const activation of record.activations!) {
      if (activation.reason !== null) lines.push(`  refused ${activation.role} ${activation.reason}`);
    }
    for (const obligation of record.evaluation!.obligations) lines.push('  obligation ' + obligation.text);
    for (const advice of record.evaluation!.advice) lines.push('  advice ' + advice.text);
  }
  return lines;
}

function traceLines(records: EvalRecord[]): string[] {
  const lines: string[] = [];
  for (const record of records) {
    if (!record.request.explained) continue;
    if (lines.length > 0) lines.push('');
    lines.push('request ' + record.request.id);
    if (record.error !== null) {
      lines.push('  error ' + record.error);
      continue;
    }
    const request = record.request;
    lines.push(`  user ${request.user} resource ${request.resourceId} type ${record.resource!.type} action ${request.action} day ${record.day}`);
    for (const activation of record.activations!) {
      lines.push(`  activate ${activation.role} ${activation.reason === null ? 'ok' : 'refused ' + activation.reason}`);
    }
    lines.push('  roles ' + (record.session!.length === 0 ? '-' : record.session!.join(',')));
    lines.push(record.granting === null ? '  rbac no' : '  rbac yes ' + record.granting);
    for (const line of treeLines(record.evaluation!)) lines.push(line);
    lines.push('  decision ' + requestDecision(record));
  }
  return lines;
}

function mergeDays(mapping: Map<string,Set<number>>, key: string, days: Iterable<number>): void {
  if (!mapping.has(key)) mapping.set(key, new Set<number>());
  const target = mapping.get(key)!;
  for (const day of days) target.add(day);
}

function permissionLines(context: Context): string[] {
  const lines: string[] = [];
  for (const user of [...context.rbac.byUser.keys()].sort()) {
    if (lines.length > 0) lines.push('');
    lines.push('user ' + user);
    const assigned = new Map<string,Set<number>>();
    for (const assignment of context.rbac.byUser.get(user)!) {
      if (!assigned.has(assignment.role)) assigned.set(assignment.role, new Set<number>());
      const days = assigned.get(assignment.role)!;
      for (let day = assignment.first; day <= assignment.last; day++) days.add(day);
    }
    for (const role of [...assigned.keys()].sort()) lines.push(`  assigned ${role} ${analysis.dayNotation(assigned.get(role)!)}`);
    const authorized = new Map<string,Set<number>>();
    for (const [role, days] of assigned) {
      for (const inherited of context.rbac.closure([role])) mergeDays(authorized, inherited, days);
    }
    for (const role of [...authorized.keys()].sort()) lines.push(`  authorized ${role} ${analysis.dayNotation(authorized.get(role)!)}`);
    const permissions = new Map<string,{action:string;type:string;days:Set<number>;via:Set<string>}>();
    for (const permission of context.rbac.permissions) {
      if (!authorized.has(permission.role)) continue;
      const key = permissionKey(permission.action, permission.type);
      if (!permissions.has(key)) permissions.set(key, {action: permission.action, type: permission.type, days: new Set<number>(), via: new Set<string>()});
      const item = permissions.get(key)!;
      item.via.add(permission.role);
      for (const day of authorized.get(permission.role)!) item.days.add(day);
    }
    const ordered = [...permissions.values()].sort((a, b) => compare(a.action, b.action) || compare(a.type, b.type));
    for (const permission of ordered) {
      let effective = '-';
      if (context.data.subjects.has(user)) {
        let available = 0;
        let permitted = 0;
        for (const resource of context.data.resources.values()) {
          if (resource.type !== permission.type) continue;
          available++;
          const hypothetical = {user, roleSpec: '*', action: permission.action, resourceId: resource.id, environment: context.data.reference};
          if (evaluateRequest(hypothetical, context).evaluation!.decision === 'PERMIT') permitted++;
        }
        effective = `${permitted}/${available}`;
      }
      lines.push(`  permission ${permission.action} ${permission.type} ${analysis.dayNotation(permission.days)}`
        + ` via ${[...permission.via].sort().join(',')} effective ${effective}`);
    }
  }
  return lines;
}

function analyzeDomains(context: Context): DomainAnalysis {
  const {elements, rules} = context.policies;
  const statistics = new Map<string,RuleStatistic>(rules.map(rule =>
    [rule.id, {rule, count: 0, first: null, blocked: 0, blockers: new Set<string>()}]));
  const pairs: ConflictPair[] = [];
  for (const policy of elements) {
    if (policy.kind !== 'policy') continue;
    for (let first = 0; first < policy.children.length; first++) {
      for (let second = first + 1; second < policy.children.length; second++) {
        const a = policy.children[first];
        const b = policy.children[second];
        if (a.effect !== b.effect) pairs.push({policy, first: a, second: b, count: 0});
      }
    }
  }
  let count = 0;
  for (const point of analysis.points(context.data.domains)) {
    count++;
    const targets = new Map<string,TargetResult>(elements.map(element => [element.id, evaluateTarget(element, point)]));
    const ancestorsMatch = new Map<string,boolean>();
    for (const element of elements) {
      ancestorsMatch.set(element.id, targets.get(element.id)!.status === 'MATCH'
        && (element.parent === null || ancestorsMatch.get(element.parent.id)));
    }
    const values = new Map<string,string>(rules.map(rule => [rule.id, ruleValue(rule, point, targets.get(rule.id)!).decision]));
    const applies = new Set<string>();
    for (const rule of rules) {
      if (!ancestorsMatch.get(rule.parent!.id) || !definite(values.get(rule.id)!)) continue;
      applies.add(rule.id);
      const statistic = statistics.get(rule.id)!;
      statistic.count++;
      if (statistic.first === null) statistic.first = point;
      if (rule.parent!.algorithm === 'first-applicable') {
        const blocker = analysis.blocker(rule, values);
        if (blocker !== null) {
          statistic.blocked++;
          statistic.blockers.add(blocker.id);
        }
      }
    }
    for (const pair of pairs) if (applies.has(pair.first.id) && applies.has(pair.second.id)) pair.count++;
  }
  return {count, statistics, pairs: pairs.filter(pair => pair.count > 0)};
}

function exampleNotation(domains: Domain[], point: AttributeSet | null): string {
  if (point === null) return '-';
  return domains.filter(domain => domain.values.length >= 2)
    .map(domain => `${domain.reference}=${valueNotation(point.get(domain.reference)!)}`).join(' ');
}

function domainLines(context: Context, domains: DomainAnalysis): string[] {
  const rules = context.policies.rules;
  const lines: string[] = [`applicability ${domains.count}`];
  for (const rule of rules) {
    const statistic = domains.statistics.get(rule.id)!;
    lines.push(`  ${rule.id} ${statistic.count} ${exampleNotation(context.data.domains, statistic.first)}`);
  }
  const dead = rules.filter(rule => domains.statistics.get(rule.id)!.count === 0);
  lines.push(`dead ${dead.length}`);
  for (const rule of dead) lines.push('  ' + rule.id);
  const shadowed = rules.filter(rule => {
    const statistic = domains.statistics.get(rule.id);
    return rule.parent!.algorithm === 'first-applicable' && statistic.count > 0 && statistic.count === statistic.blocked;
  });
  lines.push(`shadowed ${shadowed.length}`);
  for (const rule of shadowed) {
    const blockers = domains.statistics.get(rule.id)!.blockers;
    lines.push(`  ${rule.id} by ${rules.filter(candidate => blockers.has(candidate.id)).map(candidate => candidate.id).join(',')}`);
  }
  lines.push(`conflicts ${domains.pairs.length}`);
  for (const pair of domains.pairs) {
    lines.push(`  ${pair.policy.id} ${pair.first.id} ${pair.second.id} ${pair.count} ${analysis.winner(pair.policy, pair.first, pair.second).id}`);
  }
  return lines;
}

function coverageLines(context: Context, records: EvalRecord[]): string[] {
  const lines = [`coverage ${records.length}`];
  const uncovered: PolicyElement[] = [];
  for (const rule of context.policies.rules) {
    const symbols = records.map(record => record.coverage!.get(rule.id));
    const count = symbols.filter(symbol => symbol === 'P' || symbol === 'D').length;
    lines.push(`  ${rule.id} ${symbols.join('')} ${count}`);
    if (count === 0) uncovered.push(rule);
  }
  lines.push(`uncovered ${uncovered.length}`);
  for (const rule of uncovered) lines.push('  ' + rule.id);
  return lines;
}

function increment(counts: Map<string,number>, key: string): void {
  counts.set(key, (counts.get(key) || 0) + 1);
}

function summaryLines(context: Context, records: EvalRecord[]): string[] {
  const decisions = new Map<string,number>(['PERMIT', 'DENY', 'NOT_APPLICABLE', 'INDETERMINATE', 'ERROR'].map(name => [name, 0]));
  const decisive = new Map<string,number>();
  const obligations = new Map<string,number>();
  const advice = new Map<string,number>();
  let refused = 0;
  for (const record of records) {
    if (record.error !== null) {
      increment(decisions, 'ERROR');
      continue;
    }
    const result = record.evaluation!;
    increment(decisions, indeterminate(result.decision) ? 'INDETERMINATE' : result.decision);
    refused += record.activations!.filter(activation => activation.reason !== null).length;
    if (definite(result.decision)) increment(decisive, result.decisive!);
    for (const obligation of result.obligations) increment(obligations, obligation.id);
    for (const item of result.advice) increment(advice, item.id);
  }
  const lines = ['summary'];
  for (const [name, count] of decisions) lines.push(`  decision ${name} ${count}`);
  lines.push(`  refused ${refused}`);
  for (const element of context.policies.elements) {
    if (decisive.has(element.id)) lines.push(`  decisive ${element.id} ${decisive.get(element.id)}`);
  }
  for (const id of [...obligations.keys()].sort()) lines.push(`  obligation ${id} ${obligations.get(id)}`);
  for (const id of [...advice.keys()].sort()) lines.push(`  advice ${id} ${advice.get(id)}`);
  return lines;
}

function analysisLines(context: Context, records: EvalRecord[], domains: DomainAnalysis): string[] {
  const rbac = context.rbac;
  const lines = [`rbac ${rbac.diagnostics.length}`];
  for (const diagnostic of rbac.diagnostics) lines.push(`  line ${diagnostic.line} ${diagnostic.keyword} ${diagnostic.reason}`);
  const grants = rbac.permissions.slice().sort((a, b) => compare(a.role, b.role) || compare(a.action, b.action) || compare(a.type, b.type));
  lines.push(`grants ${grants.length}`);
  for (const grant of grants) {
    const count = records.filter(record => record.error === null && record.granting === grant.role
      && record.request.action === grant.action && record.resource!.type === grant.type).length;
    lines.push(`  ${grant.role} ${grant.action} ${grant.type} ${count}`);
  }
  for (const line of domainLines(context, domains)) lines.push(line);
  for (const line of coverageLines(context, records)) lines.push(line);
  for (const line of summaryLines(context, records)) lines.push(line);
  return lines;
}

function main(): void {
  const context: Context = {rbac: readRbac(), policies: readPolicies(), data: readAttributes()};
  const records = readRequests().map(request => evaluateRequest(request, context, true));
  const domains = analyzeDomains(context);
  const files = {'decisions.txt': decisionsLines(records), 'traces.txt': traceLines(records),
    'permissions.txt': permissionLines(context), 'analysis.txt': analysisLines(context, records, domains)};
  mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) {
    writeFileSync('output/' + name, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
  }
}

main();
