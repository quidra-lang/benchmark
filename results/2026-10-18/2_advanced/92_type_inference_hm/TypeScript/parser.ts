const operators = new Map([
  ['||', [1, true]], ['&&', [2, true]], ['=', [3, false]], ['<>', [3, false]],
  ['<', [3, false]], ['>', [3, false]], ['<=', [3, false]], ['>=', [3, false]],
  ['::', [4, true]], ['^', [4, true]], ['+', [5, false]], ['-', [5, false]],
  ['*', [6, false]], ['/', [6, false]], ['mod', [6, false]],
]);

class ParseError extends Error {
  declare token: any;
  constructor(token) { super('syntax error'); this.token = token; }
}

class Parser {
  declare index: any;
  declare tokens: any;
  constructor(tokens) { this.tokens = tokens; this.index = 0; }
  current() { return this.tokens[this.index]; }
  fail() { throw new ParseError(this.current()); }
  take(text) {
    if (this.current().text !== text) return null;
    return this.tokens[this.index++];
  }
  expect(text) {
    const token = this.take(text);
    if (token === null) this.fail();
    return token;
  }
  name(allowWildcard = false) {
    const token = this.current();
    if (token.kind !== 'name' || (!allowWildcard && token.text === '_')) this.fail();
    this.index++;
    return {name: token.text, position: token.position};
  }
  functions(parameters, body, position) {
    for (let i = parameters.length - 1; i >= 0; i--) body = {kind: 'fun', parameter: parameters[i], body, position};
    return body;
  }
  binding() {
    const binding = this.name();
    const parameters = [];
    while (this.current().kind === 'name') parameters.push(this.name(true));
    this.expect('=');
    binding.expression = this.functions(parameters, this.expression(), binding.position);
    return binding;
  }
  group() {
    const position = this.expect('let').position;
    const recursive = this.take('rec');
    const bindings = [this.binding()];
    while (this.take('and')) bindings.push(this.binding());
    return {bindings, recursive: recursive !== null, recPosition: recursive?.position, position};
  }
  item() {
    if (this.take('val')) {
      const name = this.name();
      this.expect(':');
      const type = this.typeExpression();
      this.expect(';;');
      return {kind: 'signature', ...name, type};
    }
    let item;
    if (this.current().text === 'let') {
      const group = this.group();
      if (this.take('in')) item = {kind: 'expression', expression: {kind: 'let', group, body: this.expression(), position: group.position}};
      else item = {kind: 'declaration', group};
    } else item = {kind: 'expression', expression: this.expression()};
    this.expect(';;');
    return item;
  }
  expression() {
    const token = this.current();
    if (token.text === 'let') {
      const group = this.group();
      this.expect('in');
      return {kind: 'let', group, body: this.expression(), position: token.position};
    }
    if (this.take('fun')) {
      const parameters = [this.name(true)];
      while (this.current().kind === 'name') parameters.push(this.name(true));
      this.expect('->');
      return this.functions(parameters, this.expression(), token.position);
    }
    if (this.take('if')) {
      const condition = this.expression();
      this.expect('then');
      const yes = this.expression();
      this.expect('else');
      return {kind: 'if', condition, yes, no: this.expression(), position: token.position};
    }
    if (this.take('match')) {
      const matched = this.expression();
      this.expect('with');
      this.take('|');
      const arms = [];
      do {
        const pattern = this.pattern();
        this.expect('->');
        arms.push({pattern, expression: this.expression()});
      } while (this.take('|'));
      return {kind: 'match', matched, arms, position: token.position};
    }
    return this.binary(1);
  }
  binary(minimum) {
    let left = this.unary();
    while (operators.has(this.current().text) && operators.get(this.current().text)[0] >= minimum) {
      const token = this.tokens[this.index++];
      const [precedence, rightAssociative] = operators.get(token.text);
      const right = this.binary(rightAssociative ? precedence : precedence + 1);
      left = {kind: 'binary', operator: token.text, operatorPosition: token.position, left, right, position: left.position};
    }
    return left;
  }
  atomicStart() {
    const token = this.current();
    return ['int', 'string'].includes(token.kind) || (token.kind === 'name' && token.text !== '_')
      || ['true', 'false', '(', '['].includes(token.text);
  }
  unary() {
    const minus = this.take('-');
    if (minus !== null) return {kind: 'unary', expression: this.unary(), position: minus.position, operatorPosition: minus.position};
    let expression = this.atomic();
    while (this.atomicStart()) expression = {kind: 'application', fn: expression, argument: this.atomic(), position: expression.position};
    return expression;
  }
  atomic() {
    const token = this.current();
    if (token.kind === 'int' || token.kind === 'string') {
      this.index++;
      return {kind: token.kind, value: token.value, position: token.position};
    }
    if (token.text === 'true' || token.text === 'false') {
      this.index++;
      return {kind: 'bool', value: token.text === 'true', position: token.position};
    }
    if (token.kind === 'name' && token.text !== '_') { this.index++; return {kind: 'name', name: token.text, position: token.position}; }
    if (this.take('(')) {
      const first = this.expression();
      if (this.take(',')) {
        const second = this.expression();
        this.expect(')');
        return {kind: 'pair', first, second, position: token.position};
      }
      this.expect(')');
      return first;
    }
    if (this.take('[')) {
      const elements = [];
      if (!this.take(']')) {
        elements.push(this.expression());
        while (this.take(';')) elements.push(this.expression());
        this.expect(']');
      }
      return {kind: 'list', elements, position: token.position};
    }
    this.fail();
  }
  pattern() {
    const first = this.atomicPattern();
    if (!this.take('::')) return first;
    return {kind: 'cons', first, second: this.pattern(), position: first.position};
  }
  atomicPattern() {
    const token = this.current();
    if (token.kind === 'name') {
      this.index++;
      return {kind: token.text === '_' ? 'wildcard' : 'name', name: token.text, position: token.position};
    }
    if (token.kind === 'int' || token.kind === 'string') {
      this.index++;
      return {kind: token.kind, value: token.value, position: token.position};
    }
    if (token.text === 'true' || token.text === 'false') {
      this.index++;
      return {kind: 'bool', value: token.text === 'true', position: token.position};
    }
    if (this.take('-')) {
      const integer = this.current();
      if (integer.kind !== 'int') this.fail();
      this.index++;
      return {kind: 'int', value: -integer.value, position: token.position};
    }
    if (this.take('(')) {
      const first = this.pattern();
      if (this.take(',')) {
        const second = this.pattern();
        this.expect(')');
        return {kind: 'pair', first, second, position: token.position};
      }
      this.expect(')');
      return first;
    }
    if (this.take('[')) {
      const elements = [];
      if (!this.take(']')) {
        elements.push(this.pattern());
        while (this.take(';')) elements.push(this.pattern());
        this.expect(']');
      }
      return {kind: 'list', elements, position: token.position};
    }
    this.fail();
  }
  typeExpression() {
    const first = this.productType();
    return this.take('->') ? {kind: 'function', args: [first, this.typeExpression()]} : first;
  }
  productType() {
    const first = this.listType();
    return this.take('*') ? {kind: 'pair', args: [first, this.listType()]} : first;
  }
  listType() {
    let type = this.typeAtom();
    while (this.take('list')) type = {kind: 'list', args: [type]};
    return type;
  }
  typeAtom() {
    const token = this.current();
    if (['int', 'bool', 'string'].includes(token.text)) { this.index++; return {kind: token.text, args: []}; }
    if (token.kind === 'typevar') { this.index++; return {kind: 'variable', name: token.text}; }
    if (this.take('(')) {
      const type = this.typeExpression();
      this.expect(')');
      return type;
    }
    this.fail();
  }
}

export {Parser, ParseError, operators};
