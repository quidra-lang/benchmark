'use strict';

const fs = require('node:fs');
const {readRbac, permissionKey} = require('./rbac');
const {readPolicies} = require('./policy_parser');
const {combine, indeterminate} = require('./combining');
const analysis = require('./analysis');

const compare = (first, second) => first < second ? -1 : first > second ? 1 : 0;
const definite = decision => decision === 'PERMIT' || decision === 'DENY';
const error = reason => ({error: reason});
const isError = value => value !== null && typeof value === 'object' && Object.hasOwn(value, 'error');
const effectError = effect => `INDETERMINATE{${effect === 'DENY' ? 'D' : 'P'}}`;

function readLines(name) {
  const text = fs.readFileSync('input/' + name, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
}

function parseValue(text) {
  if (text === 'true' || text === 'false') return text === 'true';
  if (/^-?[0-9]+$/.test(text)) return Number(text);
  if (text.startsWith('[')) return text === '[]' ? [] : text.slice(1, -1).split(',');
  return text;
}

function valueNotation(value) {
  if (Array.isArray(value)) return '[' + value.map(item => '"' + item + '"').join(',') + ']';
  if (typeof value === 'string') return '"' + value + '"';
  return String(value);
}

function attributes(tokens) {
  return new Map(tokens.map(token => {
    const separator = token.indexOf('=');
    return [token.slice(0, separator), parseValue(token.slice(separator + 1))];
  }));
}

function readAttributes() {
  const subjects = new Map();
  const resources = new Map();
  const domains = [];
  let reference = null;
  for (const line of readLines('attributes.txt')) {
    const fields = line.split(' ');
    if (fields[0] === 'SUBJECT') subjects.set(fields[1], attributes(fields.slice(2)));
    else if (fields[0] === 'RESOURCE') resources.set(fields[1], {id: fields[1], type: fields[2], attributes: attributes(fields.slice(3))});
    else if (fields[0] === 'DOMAIN') domains.push({reference: fields[1], values: fields.slice(2).map(parseValue)});
    else reference = attributes(fields.slice(1));
  }
  return {subjects, resources, domains, reference};
}

function readRequests() {
  return readLines('requests.txt').map(line => {
    const fields = line.split(' ');
    const explained = fields.at(-1) === 'EXPLAIN';
    if (explained) fields.pop();
    return {id: fields[0], user: fields[1], roleSpec: fields[2], action: fields[3], resourceId: fields[4],
      environment: attributes(fields.slice(5)), explained};
  });
}

function typedBoolean(value, operation) {
  return typeof value === 'boolean' || isError(value) ? value : error('type ' + operation);
}

function logical(operation, values) {
  const operands = values.map(value => typedBoolean(value, operation));
  if (operation === 'and' || operation === 'all_of') {
    if (operands.includes(false)) return false;
    return operands.find(isError) || true;
  }
  if (operands.includes(true)) return true;
  return operands.find(isError) || false;
}

function applyOperation(operation, values) {
  const failure = values.find(isError);
  if (failure !== undefined) return failure;
  const [first, second] = values;
  const integers = values.every(value => typeof value === 'number');
  const strings = values.every(value => typeof value === 'string');
  switch (operation) {
    case '+': if (integers) return first + second; break;
    case '-': if (integers) return values.length === 1 ? -first : first - second; break;
    case '*': if (integers) return first * second; break;
    case '==':
    case '!=':
      if (typeof first === typeof second && !Array.isArray(first) && !Array.isArray(second)) {
        return operation === '==' ? first === second : first !== second;
      }
      break;
    case '<': if (integers) return first < second; break;
    case '<=': if (integers) return first <= second; break;
    case '>': if (integers) return first > second; break;
    case '>=': if (integers) return first >= second; break;
    case 'in': if (typeof first === 'string' && Array.isArray(second)) return second.includes(first); break;
    case 'not': if (typeof first === 'boolean') return !first; break;
    case 'starts_with':
    case '^=': if (strings) return first.startsWith(second); break;
    case 'size': if (Array.isArray(first)) return first.length; break;
  }
  return error('type ' + operation);
}

function evaluateExpression(expression, attributeSet, currentItem = null) {
  if (expression.kind === 'literal') return expression.value;
  if (expression.kind === 'it') return currentItem;
  if (expression.kind === 'attribute') {
    return attributeSet.has(expression.name) ? attributeSet.get(expression.name) : error('missing ' + expression.name);
  }
  const operation = expression.operation;
  if (operation === 'present') return attributeSet.has(expression.arguments[0].name);
  if (operation === 'any_of' || operation === 'all_of') {
    const bag = evaluateExpression(expression.arguments[0], attributeSet, currentItem);
    if (isError(bag)) return bag;
    if (!Array.isArray(bag)) return error('type ' + operation);
    const values = bag.map(item => evaluateExpression(expression.arguments[1], attributeSet, item));
    return logical(operation, values);
  }
  const values = expression.arguments.map(argument => evaluateExpression(argument, attributeSet, currentItem));
  if (operation === 'and' || operation === 'or') return logical(operation, values);
  return applyOperation(operation, values);
}

function matchClause(clause, attributeSet) {
  if (!attributeSet.has(clause.reference)) {
    return clause.mandatory ? {status: 'INDETERMINATE', reason: 'missing ' + clause.reference} : {status: 'NO_MATCH'};
  }
  const value = attributeSet.get(clause.reference);
  const items = Array.isArray(value) ? value : [value];
  const results = items.map(item => applyOperation(clause.operation, [item, clause.literal]));
  if (results.includes(true)) return {status: 'MATCH'};
  const failure = results.find(isError);
  return failure === undefined ? {status: 'NO_MATCH'} : {status: 'INDETERMINATE', reason: failure.error};
}

function targetAnd(results) {
  if (results.some(result => result.status === 'NO_MATCH')) return {status: 'NO_MATCH'};
  return results.find(result => result.status === 'INDETERMINATE') || {status: 'MATCH'};
}

function targetOr(results) {
  if (results.some(result => result.status === 'MATCH')) return {status: 'MATCH'};
  return results.find(result => result.status === 'INDETERMINATE') || {status: 'NO_MATCH'};
}

function evaluateTarget(element, attributeSet) {
  const lines = element.targets.map(line => targetOr(line.map(alternative =>
    targetAnd(alternative.map(clause => matchClause(clause, attributeSet))))));
  return targetAnd(lines);
}

function emptyResult(element, target) {
  return {element, target, decision: 'NOT_APPLICABLE', reason: null, decisive: null,
    obligations: [], advice: [], children: []};
}

function ruleValue(element, attributeSet, target) {
  const result = emptyResult(element, target);
  if (target.status === 'NO_MATCH') return result;
  if (target.status === 'INDETERMINATE') {
    result.decision = effectError(element.effect);
    result.reason = target.reason;
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

function attachment(item, attributeSet) {
  const values = item.arguments.map(argument => evaluateExpression(argument.expression, attributeSet));
  const failure = values.find(isError);
  if (failure !== undefined) return failure;
  let text = item.id;
  for (let index = 0; index < values.length; index++) text += ` ${item.arguments[index].name}=${valueNotation(values[index])}`;
  return {id: item.id, text};
}

function attachObligations(result, attributeSet, supporters) {
  const decision = result.decision;
  for (const supporter of supporters) {
    for (const item of supporter.obligations) result.obligations.push(item);
    for (const item of supporter.advice) result.advice.push(item);
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

function evaluateElement(element, attributeSet, coverage = null) {
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
    const supporters = result.children.filter(child => child.state === 'evaluated' && child.result.decision === result.decision)
      .map(child => child.result);
    result.decisive = supporters.length === 0 ? element.id : supporters[0].decisive;
    attachObligations(result, attributeSet, supporters);
  }
  return result;
}

function activate(request, context, day, resource) {
  const rbac = context.rbac;
  const authorized = rbac.authorized(request.user, day);
  const candidates = request.roleSpec === '-' ? [] : request.roleSpec === '*' ? [...authorized].sort() : request.roleSpec.split(',');
  const seen = new Set();
  const active = [];
  const activations = [];
  for (const role of candidates) {
    const duplicate = seen.has(role);
    seen.add(role);
    let reason = null;
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
  const granting = session.find(role => rbac.roles.get(role).permissions.has(key)) || null;
  return {activations, session, granting};
}

function requestAttributes(request, context, resource, activation) {
  const result = new Map();
  for (const [name, value] of context.data.subjects.get(request.user)) result.set('subject.' + name, value);
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

function evaluateRequest(request, context, recordCoverage = false) {
  const coverage = recordCoverage ? new Map(context.policies.rules.map(rule => [rule.id, '.'])) : null;
  let message = null;
  const day = request.environment.get('day');
  if (!context.data.subjects.has(request.user)) message = 'unknown user ' + request.user;
  else if (!context.data.resources.has(request.resourceId)) message = 'unknown resource ' + request.resourceId;
  else if (typeof day !== 'number' || day < 1 || day > 365) message = 'bad day';
  if (message !== null) return {request, error: message, coverage};
  const resource = context.data.resources.get(request.resourceId);
  const activation = activate(request, context, day, resource);
  const attributeSet = requestAttributes(request, context, resource, activation);
  const evaluation = evaluateElement(context.policies.root, attributeSet, coverage);
  return {request, error: null, day, resource, ...activation, evaluation, coverage};
}

function decisionNotation(result) {
  return result.decision + (indeterminate(result.decision) ? ` (${result.reason})` : '');
}

function requestDecision(record) {
  if (record.error !== null) return 'ERROR ' + record.error;
  const result = record.evaluation;
  return decisionNotation(result) + (definite(result.decision) ? ' by ' + result.decisive : '');
}

function treeLines(result, depth = 0) {
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
      for (const nested of treeLines(child.result, depth + 1)) lines.push(nested);
    } else if (child.state === 'skipped') lines.push(`${indent}  ${child.element.kind} ${child.element.id} skipped`);
    else {
      let checked = `${indent}  ${child.element.kind} ${child.element.id} ${child.element.algorithm} target ${child.target.status}`;
      if (child.target.status === 'INDETERMINATE') checked += ` (${child.target.reason})`;
      lines.push(checked);
    }
  }
  return lines;
}

function decisionsLines(records) {
  const lines = [];
  for (const record of records) {
    lines.push(record.request.id + ' ' + requestDecision(record));
    if (record.error !== null) continue;
    for (const activation of record.activations) {
      if (activation.reason !== null) lines.push(`  refused ${activation.role} ${activation.reason}`);
    }
    for (const obligation of record.evaluation.obligations) lines.push('  obligation ' + obligation.text);
    for (const advice of record.evaluation.advice) lines.push('  advice ' + advice.text);
  }
  return lines;
}

function traceLines(records) {
  const lines = [];
  for (const record of records) {
    if (!record.request.explained) continue;
    if (lines.length > 0) lines.push('');
    lines.push('request ' + record.request.id);
    if (record.error !== null) {
      lines.push('  error ' + record.error);
      continue;
    }
    const request = record.request;
    lines.push(`  user ${request.user} resource ${request.resourceId} type ${record.resource.type} action ${request.action} day ${record.day}`);
    for (const activation of record.activations) {
      lines.push(`  activate ${activation.role} ${activation.reason === null ? 'ok' : 'refused ' + activation.reason}`);
    }
    lines.push('  roles ' + (record.session.length === 0 ? '-' : record.session.join(',')));
    lines.push(record.granting === null ? '  rbac no' : '  rbac yes ' + record.granting);
    for (const line of treeLines(record.evaluation)) lines.push(line);
    lines.push('  decision ' + requestDecision(record));
  }
  return lines;
}

function mergeDays(mapping, key, days) {
  if (!mapping.has(key)) mapping.set(key, new Set());
  const target = mapping.get(key);
  for (const day of days) target.add(day);
}

function permissionLines(context) {
  const lines = [];
  for (const user of [...context.rbac.byUser.keys()].sort()) {
    if (lines.length > 0) lines.push('');
    lines.push('user ' + user);
    const assigned = new Map();
    for (const assignment of context.rbac.byUser.get(user)) {
      if (!assigned.has(assignment.role)) assigned.set(assignment.role, new Set());
      const days = assigned.get(assignment.role);
      for (let day = assignment.first; day <= assignment.last; day++) days.add(day);
    }
    for (const role of [...assigned.keys()].sort()) lines.push(`  assigned ${role} ${analysis.dayNotation(assigned.get(role))}`);
    const authorized = new Map();
    for (const [role, days] of assigned) {
      for (const inherited of context.rbac.closure([role])) mergeDays(authorized, inherited, days);
    }
    for (const role of [...authorized.keys()].sort()) lines.push(`  authorized ${role} ${analysis.dayNotation(authorized.get(role))}`);
    const permissions = new Map();
    for (const permission of context.rbac.permissions) {
      if (!authorized.has(permission.role)) continue;
      const key = permissionKey(permission.action, permission.type);
      if (!permissions.has(key)) permissions.set(key, {action: permission.action, type: permission.type, days: new Set(), via: new Set()});
      const item = permissions.get(key);
      item.via.add(permission.role);
      for (const day of authorized.get(permission.role)) item.days.add(day);
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
          if (evaluateRequest(hypothetical, context).evaluation.decision === 'PERMIT') permitted++;
        }
        effective = `${permitted}/${available}`;
      }
      lines.push(`  permission ${permission.action} ${permission.type} ${analysis.dayNotation(permission.days)}`
        + ` via ${[...permission.via].sort().join(',')} effective ${effective}`);
    }
  }
  return lines;
}

function analyzeDomains(context) {
  const {elements, rules} = context.policies;
  const statistics = new Map(rules.map(rule => [rule.id, {rule, count: 0, first: null, blocked: 0, blockers: new Set()}]));
  const pairs = [];
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
    const targets = new Map(elements.map(element => [element.id, evaluateTarget(element, point)]));
    const ancestorsMatch = new Map();
    for (const element of elements) {
      ancestorsMatch.set(element.id, targets.get(element.id).status === 'MATCH'
        && (element.parent === null || ancestorsMatch.get(element.parent.id)));
    }
    const values = new Map(rules.map(rule => [rule.id, ruleValue(rule, point, targets.get(rule.id)).decision]));
    const applies = new Set();
    for (const rule of rules) {
      if (!ancestorsMatch.get(rule.parent.id) || !definite(values.get(rule.id))) continue;
      applies.add(rule.id);
      const statistic = statistics.get(rule.id);
      statistic.count++;
      if (statistic.first === null) statistic.first = point;
      if (rule.parent.algorithm === 'first-applicable') {
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

function exampleNotation(domains, point) {
  if (point === null) return '-';
  return domains.filter(domain => domain.values.length >= 2)
    .map(domain => `${domain.reference}=${valueNotation(point.get(domain.reference))}`).join(' ');
}

function domainLines(context, domains) {
  const rules = context.policies.rules;
  const lines = [`applicability ${domains.count}`];
  for (const rule of rules) {
    const statistic = domains.statistics.get(rule.id);
    lines.push(`  ${rule.id} ${statistic.count} ${exampleNotation(context.data.domains, statistic.first)}`);
  }
  const dead = rules.filter(rule => domains.statistics.get(rule.id).count === 0);
  lines.push(`dead ${dead.length}`);
  for (const rule of dead) lines.push('  ' + rule.id);
  const shadowed = rules.filter(rule => {
    const statistic = domains.statistics.get(rule.id);
    return rule.parent.algorithm === 'first-applicable' && statistic.count > 0 && statistic.count === statistic.blocked;
  });
  lines.push(`shadowed ${shadowed.length}`);
  for (const rule of shadowed) {
    const blockers = domains.statistics.get(rule.id).blockers;
    lines.push(`  ${rule.id} by ${rules.filter(candidate => blockers.has(candidate.id)).map(candidate => candidate.id).join(',')}`);
  }
  lines.push(`conflicts ${domains.pairs.length}`);
  for (const pair of domains.pairs) {
    lines.push(`  ${pair.policy.id} ${pair.first.id} ${pair.second.id} ${pair.count} ${analysis.winner(pair.policy, pair.first, pair.second).id}`);
  }
  return lines;
}

function coverageLines(context, records) {
  const lines = [`coverage ${records.length}`];
  const uncovered = [];
  for (const rule of context.policies.rules) {
    const symbols = records.map(record => record.coverage.get(rule.id));
    const count = symbols.filter(symbol => symbol === 'P' || symbol === 'D').length;
    lines.push(`  ${rule.id} ${symbols.join('')} ${count}`);
    if (count === 0) uncovered.push(rule);
  }
  lines.push(`uncovered ${uncovered.length}`);
  for (const rule of uncovered) lines.push('  ' + rule.id);
  return lines;
}

function increment(counts, key) {
  counts.set(key, (counts.get(key) || 0) + 1);
}

function summaryLines(context, records) {
  const decisions = new Map(['PERMIT', 'DENY', 'NOT_APPLICABLE', 'INDETERMINATE', 'ERROR'].map(name => [name, 0]));
  const decisive = new Map();
  const obligations = new Map();
  const advice = new Map();
  let refused = 0;
  for (const record of records) {
    if (record.error !== null) {
      increment(decisions, 'ERROR');
      continue;
    }
    const result = record.evaluation;
    increment(decisions, indeterminate(result.decision) ? 'INDETERMINATE' : result.decision);
    refused += record.activations.filter(activation => activation.reason !== null).length;
    if (definite(result.decision)) increment(decisive, result.decisive);
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

function analysisLines(context, records, domains) {
  const rbac = context.rbac;
  const lines = [`rbac ${rbac.diagnostics.length}`];
  for (const diagnostic of rbac.diagnostics) lines.push(`  line ${diagnostic.line} ${diagnostic.keyword} ${diagnostic.reason}`);
  const grants = rbac.permissions.slice().sort((a, b) => compare(a.role, b.role) || compare(a.action, b.action) || compare(a.type, b.type));
  lines.push(`grants ${grants.length}`);
  for (const grant of grants) {
    const count = records.filter(record => record.error === null && record.granting === grant.role
      && record.request.action === grant.action && record.resource.type === grant.type).length;
    lines.push(`  ${grant.role} ${grant.action} ${grant.type} ${count}`);
  }
  for (const line of domainLines(context, domains)) lines.push(line);
  for (const line of coverageLines(context, records)) lines.push(line);
  for (const line of summaryLines(context, records)) lines.push(line);
  return lines;
}

function main() {
  const context = {rbac: readRbac(), policies: readPolicies(), data: readAttributes()};
  const records = readRequests().map(request => evaluateRequest(request, context, true));
  const domains = analyzeDomains(context);
  const files = {'decisions.txt': decisionsLines(records), 'traces.txt': traceLines(records),
    'permissions.txt': permissionLines(context), 'analysis.txt': analysisLines(context, records, domains)};
  fs.mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) {
    fs.writeFileSync('output/' + name, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
  }
}

main();
