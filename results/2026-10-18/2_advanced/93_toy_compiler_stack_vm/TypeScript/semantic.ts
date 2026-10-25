import { CompileError, positionCompare } from './lexer.ts';
import { expressionChildren, resolve } from './parser.ts';
const isArray = declaration => declaration.kind === 'global' && declaration.size !== null;
const completion = new WeakMap();

function canComplete(statement) {
  const pending = [[statement, false]];
  while (pending.length) {
    const [node, ready] = pending.pop();
    if (completion.has(node)) continue;
    const children = node.kind === 'block' ? node.statements : node.kind === 'if' && node.otherwise !== null ? [node.then, node.otherwise] : [];
    if (!ready && children.length) {
      pending.push([node, true]);
      for (let i = children.length - 1; i >= 0; i--) pending.push([children[i], false]);
    } else {
      let result = !['return', 'break', 'continue'].includes(node.kind);
      if (node.kind === 'block') result = children.every(child => completion.get(child));
      else if (node.kind === 'if' && node.otherwise !== null) result = completion.get(node.then) || completion.get(node.otherwise);
      completion.set(node, result);
    }
  }
  return completion.get(statement);
}

class Semantic {
  declare currentFunction: any;
  declare functions: any;
  declare globals: any;
  declare loopDepth: any;
  declare names: any;
  declare program: any;
  declare scopes: any;
  declare variables: any;
  constructor(program) {
    this.program = program; this.names = new Map(); this.globals = []; this.functions = []; this.variables = [];
    this.scopes = []; this.currentFunction = null; this.loopDepth = 0;
  }
  error(position, message) { throw new CompileError('semantic', position, message); }
  initialize(declaration) { declaration.references = []; declaration.reads = 0; return declaration; }
  registerVariable(declaration) { this.initialize(declaration); this.variables.push(declaration); }
  lookup(name, position, write = false) {
    let declaration;
    for (let i = this.scopes.length - 1; i >= 0; i--) if (this.scopes[i].has(name)) { declaration = this.scopes[i].get(name); break; }
    if (declaration === undefined) declaration = this.names.get(name);
    if (declaration !== undefined) { declaration.references.push(position); if (!write) declaration.reads++; }
    return declaration;
  }
  variable(node, array, write = false) {
    const declaration = this.lookup(node.name, node.position, write), name = node.name, position = node.position;
    if (declaration === undefined) this.error(position, `undeclared identifier '${name}'`);
    if (declaration.kind === 'function') this.error(position, `'${name}' is a function, not a variable`);
    if (array && !isArray(declaration)) this.error(position, `'${name}' is not an array`);
    if (!array && isArray(declaration)) this.error(position, `array '${name}' used without index`);
    node.referent = declaration; return declaration;
  }
  expression(node, statementCall = false) { return resolve(this.checkExpression(node, statementCall)); }
  *checkExpression(node, statementCall = false) {
    let type;
    if (node.kind === 'literal') return node.type;
    if (node.kind === 'read') type = 'int';
    else if (node.kind === 'variable') type = this.variable(node, false).type;
    else if (node.kind === 'index') {
      this.variable(node, true);
      if ((yield this.checkExpression(node.index)) !== 'int') this.error(node.position, `index of '${node.name}' must be int`);
      type = 'int';
    } else if (node.kind === 'call') {
      const declaration = this.lookup(node.name, node.position), name = node.name;
      if (declaration === undefined) this.error(node.position, `undeclared function '${name}'`);
      if (declaration.kind !== 'function') this.error(node.position, `'${name}' is not a function`);
      node.referent = declaration; this.currentFunction.calls.add(declaration);
      if (node.args.length !== declaration.params.length) this.error(node.position,
        `wrong number of arguments to '${name}' (expected ${declaration.params.length}, found ${node.args.length})`);
      for (let i = 0; i < node.args.length; i++) if ((yield this.checkExpression(node.args[i])) !== declaration.params[i].type) {
        this.error(node.position, `argument ${i + 1} of '${name}' must be ${declaration.params[i].type}`);
      }
      if (!statementCall && declaration.type === 'void') this.error(node.position, `void function '${name}' used as a value`);
      type = declaration.type;
    } else if (node.kind === 'unary') {
      type = yield this.checkExpression(node.operand);
      const required = node.operator === '-' ? 'int' : 'bool';
      if (type !== required) this.error(node.position, `operator '${node.operator}' requires ${required} operand`);
    } else {
      const left = yield this.checkExpression(node.left), right = yield this.checkExpression(node.right), operator = node.operator;
      if (['==', '!='].includes(operator)) {
        if (left !== right) this.error(node.position, `operator '${operator}' requires operands of the same type`);
        type = 'bool';
      } else {
        const required = operator === '&&' || operator === '||' ? 'bool' : 'int';
        if (left !== required || right !== required) this.error(node.position, `operator '${operator}' requires ${required} operands`);
        type = ['+', '-', '*', '/', '%'].includes(operator) ? 'int' : 'bool';
      }
    }
    node.type = type; return type;
  }
  statement(node) { return resolve(this.checkStatement(node)); }
  *checkStatement(node) {
    const position = node.position, name = node.name;
    switch (node.kind) {
      case 'declaration': {
        const scope = this.scopes[this.scopes.length - 1];
        if (node.type === 'void') this.error(node.namePosition, `variable '${name}' cannot have type void`);
        if (scope.has(name)) this.error(node.namePosition, `redeclaration of '${name}'`);
        if (node.initializer !== null && (yield this.checkExpression(node.initializer)) !== node.type) this.error(node.namePosition, `type mismatch in initialization of '${name}'`);
        this.registerVariable(node); scope.set(name, node); break;
      }
      case 'assignment': {
        const target = this.variable(node, node.index !== null, true);
        if (node.index !== null && (yield this.checkExpression(node.index)) !== 'int') this.error(position, `index of '${name}' must be int`);
        if ((yield this.checkExpression(node.value)) !== target.type) this.error(position, `type mismatch in assignment to '${name}'`);
        break;
      }
      case 'call-statement': yield this.checkExpression(node.expression, true); break;
      case 'if': case 'while':
        if ((yield this.checkExpression(node.condition)) !== 'bool') this.error(position, `condition of '${node.kind}' must be bool`);
        if (node.kind === 'if') { yield this.checkStatement(node.then); if (node.otherwise !== null) yield this.checkStatement(node.otherwise); }
        else { this.loopDepth++; yield this.checkStatement(node.body); this.loopDepth--; }
        break;
      case 'for':
        this.scopes.push(new Map());
        if (node.initialization !== null) yield this.checkStatement(node.initialization);
        if (node.condition !== null && (yield this.checkExpression(node.condition)) !== 'bool') this.error(position, "condition of 'for' must be bool");
        if (node.update !== null) yield this.checkStatement(node.update);
        this.loopDepth++; yield this.checkStatement(node.body); this.loopDepth--; this.scopes.pop(); break;
      case 'break': case 'continue':
        if (this.loopDepth === 0) this.error(position, `'${node.kind}' outside loop`);
        break;
      case 'return': {
        const declaration = this.currentFunction;
        if (declaration.type === 'void' && node.value !== null) this.error(position, `function '${declaration.name}' must not return a value`);
        if (declaration.type !== 'void' && node.value === null) this.error(position, `function '${declaration.name}' must return a value`);
        if (node.value !== null && (yield this.checkExpression(node.value)) !== declaration.type) this.error(position, `return value of '${declaration.name}' must be ${declaration.type}`);
        break;
      }
      case 'print':
        for (let i = 0; i < node.values.length; i++) if ((yield this.checkExpression(node.values[i])) !== 'int') this.error(position, `argument ${i + 1} of 'print' must be int`);
        break;
      case 'block':
        this.scopes.push(new Map());
        for (const statement of node.statements) yield this.checkStatement(statement);
        this.scopes.pop(); break;
    }
  }
  analyze() {
    for (const declaration of this.program.declarations) {
      const name = declaration.name, position = declaration.namePosition;
      if (declaration.kind === 'global') {
        if (isArray(declaration) && declaration.type !== 'int') this.error(position, `array '${name}' must have element type int`);
        if (isArray(declaration) && declaration.size === 0) this.error(declaration.sizePosition, `array '${name}' must have a positive size`);
        if (!isArray(declaration) && declaration.type === 'void') this.error(position, `variable '${name}' cannot have type void`);
        if (this.names.has(name)) this.error(position, `redeclaration of '${name}'`);
        if (declaration.initializer !== null) {
          const forbidden = [], pending = [declaration.initializer];
          while (pending.length) {
            const node = pending.pop();
            if (['variable', 'index', 'call', 'read'].includes(node.kind)) forbidden.push(node.position);
            for (const child of expressionChildren(node)) pending.push(child);
          }
          if (forbidden.length) this.error(forbidden.sort(positionCompare)[0], 'global initializer must be constant');
          if (this.expression(declaration.initializer) !== declaration.type) this.error(position, `type mismatch in initialization of '${name}'`);
        }
        this.registerVariable(declaration); this.globals.push(declaration);
      } else {
        if (this.names.has(name)) this.error(position, `redeclaration of '${name}'`);
        const seen = new Set();
        for (const parameter of declaration.params) {
          if (parameter.type === 'void') this.error(parameter.namePosition, `parameter '${parameter.name}' cannot have type void`);
          if (seen.has(parameter.name)) this.error(parameter.namePosition, `redeclaration of '${parameter.name}'`);
          seen.add(parameter.name); this.registerVariable(parameter);
        }
        this.initialize(declaration); declaration.calls = new Set(); this.functions.push(declaration);
      }
      this.names.set(name, declaration);
    }
    const main = this.names.get('main');
    if (main === undefined || main.kind !== 'function') this.error(this.program.end, 'no main function');
    if (main.type !== 'void' || main.params.length !== 0) this.error(main.namePosition, "main must be declared as 'void main()'");
    for (const declaration of this.functions) {
      this.currentFunction = declaration; this.scopes = [new Map(declaration.params.map(parameter => [parameter.name, parameter]))];
      declaration.body.statements.forEach(statement => this.statement(statement));
      if (declaration.type !== 'void' && canComplete(declaration.body)) this.error(declaration.namePosition, `missing return in function '${declaration.name}'`);
    }
    return this;
  }
}

export { Semantic, canComplete, isArray };
