'use strict';

const {punct, copy} = require('./lexer');
const builtins = new Set(['__LINE__', '__FILE__', '__COUNTER__']);
const variadicError = '"__VA_ARGS__" can only appear in the expansion of a variadic macro';

class Macro {
  constructor(name, parameters, variadic, replacement, position, mainFile) {
    Object.assign(this, {name, parameters, variadic, replacement, position, mainFile});
    this.expanded = 0;
    this.tested = 0;
  }

  signature() {
    if (this.parameters === null) return this.name;
    const names = this.parameters.map(name => name === '__VA_ARGS__' ? '...' : name);
    return `${this.name}(${names.join(', ')})`;
  }
}

function checkName(operands, directive) {
  if (!operands.length) throw new Error(`no macro name given in #${directive} directive`);
  if (operands[0].kind !== 'identifier') throw new Error('macro names must be identifiers');
  const name = operands[0].spelling;
  if (name === 'defined') throw new Error('"defined" cannot be used as a macro name');
  if (builtins.has(name)) {
    const verb = directive === 'define' ? 'redefine' : 'undefine';
    throw new Error(`cannot ${verb} builtin macro "${name}"`);
  }
  return name;
}

function parseDefinition(operands, position, mainFile) {
  const name = checkName(operands, 'define');
  if (name === '__VA_ARGS__') throw new Error(variadicError);
  let index = 1;
  let parameters = null;
  let variadic = false;
  if (punct(operands[index], '(') && !operands[index].space) {
    parameters = [];
    index++;
    const requireToken = () => {
      if (!operands[index]) throw new Error("missing ')' in macro parameter list");
      return operands[index];
    };
    if (punct(requireToken(), ')')) index++;
    else {
      for (;;) {
        const token = requireToken();
        if (punct(token, '...')) {
          parameters.push('__VA_ARGS__');
          variadic = true;
        } else if (token.kind === 'identifier') {
          if (token.spelling === '__VA_ARGS__') throw new Error(variadicError);
          if (parameters.includes(token.spelling)) {
            throw new Error(`duplicate macro parameter "${token.spelling}"`);
          }
          parameters.push(token.spelling);
        } else throw new Error(`expected parameter name, found "${token.spelling}"`);
        index++;
        const separator = requireToken();
        index++;
        if (punct(separator, ')')) break;
        if (variadic) throw new Error(`expected ')' after "...", found "${separator.spelling}"`);
        if (!punct(separator, ',')) throw new Error(`expected ',' or ')', found "${separator.spelling}"`);
      }
    }
  }
  const replacement = operands.slice(index).map(copy);
  if (replacement.length) replacement[0].space = false;
  if (punct(replacement[0], '##') || punct(replacement.at(-1), '##')) {
    throw new Error("'##' cannot appear at either end of a macro expansion");
  }
  for (let item = 0; item < replacement.length; item++) {
    const token = replacement[item];
    if (!variadic && token.kind === 'identifier' && token.spelling === '__VA_ARGS__') {
      throw new Error(variadicError);
    }
    if (parameters !== null && punct(token, '#')
        && (replacement[item + 1]?.kind !== 'identifier'
          || !parameters.includes(replacement[item + 1].spelling))) {
      throw new Error("'#' is not followed by a macro parameter");
    }
  }
  return new Macro(name, parameters, variadic, replacement, {...position}, mainFile);
}

function identical(left, right) {
  if ((left.parameters === null) !== (right.parameters === null) || left.variadic !== right.variadic) return false;
  if (left.parameters !== null && (left.parameters.length !== right.parameters.length
      || left.parameters.some((name, index) => name !== right.parameters[index]))) return false;
  return left.replacement.length === right.replacement.length
    && left.replacement.every((token, index) => token.spelling === right.replacement[index].spelling
      && token.space === right.replacement[index].space);
}

module.exports = {builtins, checkName, parseDefinition, identical};
