'use strict';

const terms = require('./terms');

class Clause {
  constructor(head, body, file, line) { Object.assign(this, {head, body, file, line}); }
}

class Predicate {
  constructor(head) {
    this.name = head.name;
    this.arity = terms.arity(head);
    this.key = terms.predicateKey(head);
    this.clauses = [];
  }
}

class Database {
  constructor() { this.predicates = new Map(); }
  get(goal) { return this.predicates.get(terms.predicateKey(goal)); }
  ensure(head) {
    const key = terms.predicateKey(head);
    if (!this.predicates.has(key)) this.predicates.set(key, new Predicate(head));
    return this.predicates.get(key);
  }
}

function sameKind(first, second) {
  first = terms.dereference(first);
  second = terms.dereference(second);
  if (first.kind === 'variable' || second.kind === 'variable') return true;
  if (first.kind !== second.kind) return false;
  if (first.kind === 'integer') return first.value === second.value;
  if (first.kind === 'atom') return first.name === second.name;
  return first.name === second.name && first.args.length === second.args.length;
}

function candidates(predicate, goal) {
  if (predicate.arity === 0) return predicate.clauses;
  return predicate.clauses.filter(clause => sameKind(goal.args[0], clause.head.args[0]));
}

function copyClause(clause) {
  const variables = new Map();
  const compounds = new Map();
  return {head: terms.copy(clause.head, variables, compounds),
    body: clause.body === null ? null : terms.copy(clause.body, variables, compounds)};
}

module.exports = {Clause, Predicate, Database, candidates, copyClause};
