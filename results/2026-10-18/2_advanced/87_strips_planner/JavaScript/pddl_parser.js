'use strict';

const fs = require('node:fs');

function readText(name) {
  return fs.readFileSync(`input/${name}`, 'ascii');
}

function expressions(text) {
  const tokens = text.replace(/;[^\n]*/g, '').match(/[()]|[^ ()\n]+/g) || [];
  let position = 0;
  function expression() {
    const token = tokens[position++];
    if (token !== '(') return token;
    const result = [];
    while (tokens[position] !== ')') result.push(expression());
    position++;
    return result;
  }
  const result = [];
  while (position < tokens.length) result.push(expression());
  return result;
}

function typedList(words) {
  const result = [];
  let pending = [];
  for (let index = 0; index < words.length; index++) {
    if (words[index] === '-') {
      const type = words[++index];
      for (const name of pending) result.push({name, type});
      pending = [];
    } else pending.push(words[index]);
  }
  for (const name of pending) result.push({name, type: 'object'});
  return result;
}

function atom(expression) {
  return {predicate: expression[0], terms: expression.slice(1)};
}

function notation(value) {
  return `(${[value.predicate, ...value.terms].join(' ')})`;
}

function literal(expression) {
  return expression[0] === 'not' && Array.isArray(expression[1]) ? {negative: true, atom: atom(expression[1])} :
    {negative: false, atom: atom(expression)};
}

function conjuncts(expression, allowEmpty = true) {
  const conjunction = expression[0] === 'and' && (allowEmpty || expression.length > 1) &&
    expression.slice(1).every(item => Array.isArray(item));
  return conjunction ? expression.slice(1) : [expression];
}

function domain(text) {
  const expression = expressions(text)[0];
  const result = {name: expression[1][1], types: ['object'], parents: new Map([['object', null]]), predicates: [], actions: []};
  for (const section of expression.slice(2)) {
    if (section[0] === ':types') {
      for (const word of section.slice(1)) {
        if (word !== '-' && !result.parents.has(word)) {
          result.types.push(word);
          result.parents.set(word, 'object');
        }
      }
      for (const item of typedList(section.slice(1))) result.parents.set(item.name, item.type);
    } else if (section[0] === ':predicates') {
      for (const declaration of section.slice(1)) {
        result.predicates.push({name: declaration[0], types: typedList(declaration.slice(1)).map(item => item.type),
          number: result.predicates.length});
      }
    } else if (section[0] === ':action') {
      const fields = new Map();
      for (let index = 2; index < section.length; index += 2) fields.set(section[index], section[index + 1]);
      const action = {name: section[1], parameters: typedList(fields.get(':parameters')), conditions: [], effects: [], cost: 1};
      if (fields.has(':precondition')) action.conditions = conjuncts(fields.get(':precondition')).map(literal);
      for (const element of conjuncts(fields.get(':effect'), false)) {
        if (element[0] === 'increase' && Array.isArray(element[1])) action.cost = Number(element[2]);
        else action.effects.push(literal(element));
      }
      action.adds = action.effects.filter(item => !item.negative).map(item => item.atom);
      action.deletes = action.effects.filter(item => item.negative).map(item => item.atom);
      result.actions.push(action);
    }
  }
  result.predicateTable = new Map(result.predicates.map(predicate => [predicate.name, predicate]));
  return result;
}

function problems(text) {
  return expressions(text).map(expression => {
    const sections = new Map(expression.slice(2).map(section => [section[0], section.slice(1)]));
    const objects = typedList(sections.get(':objects')).map((item, number) => ({...item, number}));
    return {name: expression[1][1], objects, objectTypes: new Map(objects.map(item => [item.name, item.type])),
      objectNumbers: new Map(objects.map(item => [item.name, item.number])),
      init: sections.get(':init').map(atom), goals: conjuncts(sections.get(':goal')[0], false).map(atom)};
  });
}

module.exports = {readText, expressions, typedList, atom, notation, literal, conjuncts, domain, problems};
