import {readFileSync} from 'node:fs';
import type {SExpr,TypedName,Atom,Literal,Domain,Problem,ActionSchema} from './types.ts';

export function readText(name:string):string {
  return readFileSync(`input/${name}`, 'ascii');
}

export function expressions(text:string):SExpr[] {
  const tokens = text.replace(/;[^\n]*/g, '').match(/[()]|[^ ()\n]+/g) || [];
  let position = 0;
  function expression():SExpr {
    const token = tokens[position++];
    if (token !== '(') return token;
    const result:SExpr[] = [];
    while (tokens[position] !== ')') result.push(expression());
    position++;
    return result;
  }
  const result:SExpr[] = [];
  while (position < tokens.length) result.push(expression());
  return result;
}

export function typedList(words:string[]):TypedName[] {
  const result:TypedName[] = [];
  let pending:string[] = [];
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

export function atom(expression:SExpr[]):Atom {
  return {predicate: expression[0] as string, terms: expression.slice(1) as string[]};
}

export function notation(value:Atom):string {
  return `(${[value.predicate, ...value.terms].join(' ')})`;
}

export function literal(expression:SExpr[]):Literal {
  return expression[0] === 'not' && Array.isArray(expression[1]) ? {negative: true, atom: atom(expression[1] as SExpr[])} :
    {negative: false, atom: atom(expression)};
}

export function conjuncts(expression:SExpr[], allowEmpty = true):SExpr[][] {
  const conjunction = expression[0] === 'and' && (allowEmpty || expression.length > 1) &&
    expression.slice(1).every(item => Array.isArray(item));
  return conjunction ? expression.slice(1) as SExpr[][] : [expression];
}

export function domain(text:string):Domain {
  const expression = expressions(text)[0] as SExpr[];
  const result:Domain = {name:(expression[1] as SExpr[])[1] as string, types:['object'],
    parents:new Map<string,string|null>([['object',null]]),predicates:[],actions:[],
    predicateTable:new Map(),fluent:new Set(),static:new Set(),diagnostics:[],
    actionTable:new Map()};
  for (const section of expression.slice(2) as SExpr[][]) {
    if (section[0] === ':types') {
      for (const word of section.slice(1)) {
        if (word !== '-' && !result.parents.has(word as string)) {
          result.types.push(word as string);
          result.parents.set(word as string, 'object');
        }
      }
      for (const item of typedList(section.slice(1) as string[])) result.parents.set(item.name, item.type);
    } else if (section[0] === ':predicates') {
      for (const declaration of section.slice(1) as SExpr[][]) {
        result.predicates.push({name: declaration[0] as string, types: typedList(declaration.slice(1) as string[]).map(item => item.type),
          number: result.predicates.length});
      }
    } else if (section[0] === ':action') {
      const fields = new Map<string,SExpr[]>();
      for (let index = 2; index < section.length; index += 2) fields.set(section[index] as string, section[index + 1] as SExpr[]);
      const action:ActionSchema = {name: section[1] as string,parameters:typedList(fields.get(':parameters') as string[]), conditions:[],effects:[],cost:1,adds:[],deletes:[]};
      if (fields.has(':precondition')) action.conditions = conjuncts(fields.get(':precondition')!).map(literal);
      for (const element of conjuncts(fields.get(':effect')!, false)) {
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

export function problems(text:string):Problem[] {
  return expressions(text).map(value => {
    const expression = value as SExpr[];
    const sections = new Map<string,SExpr[]>( (expression.slice(2) as SExpr[][]).map(section => [section[0] as string, section.slice(1)]));
    const objects = typedList(sections.get(':objects') as string[]).map((item, number) => ({...item, number}));
    return {name: (expression[1] as SExpr[])[1] as string, objects, objectTypes: new Map(objects.map(item => [item.name, item.type])),
      objectNumbers: new Map(objects.map(item => [item.name, item.number])),
      init: (sections.get(':init') as SExpr[][]).map(atom), goals: conjuncts(sections.get(':goal')![0] as SExpr[], false).map(atom)} as Problem;
  });
}

