import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { FormatError, tokenize } from './lexer.ts';
import { Parser, children } from './parser.ts';
import { cat, line, softline, hardline, breakParent, suffix, ifBreak, group, nest, align, groups } from './doc_builder.ts';
import { layout } from './printer.ts';
import { documentLines, diff } from './report.ts';
import type {
  Token, Profile, Source, Lexed, Doc, DocPart, AstNode, ExprNode, ProgramNode,
  FunctionNode, ParameterNode, DeclarationNode, ListNode, BlockNode, StatementNode,
  SimpleNode, IfNode, WhileNode, ForNode, ClauseNode, SwitchNode, AssignmentNode,
  BinaryNode, ConditionalNode, PostfixNode, FormatResult,
} from './types.ts';

const inputLines = (name: string): string[] => readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);
const trimLines = (lines: string[]): string[] => lines.map(value => value.replace(/ +$/, ''));

function readProfiles(): Map<string,Profile> {
  const profiles = new Map<string,Profile>(), numeric = new Set(['width', 'indent', 'max_blank_lines', 'comment_column']);
  let current: Profile | null = null;
  for (const value of inputLines('style.txt')) {
    if (value === '') continue;
    if (value.startsWith('[')) { current = {} as Profile; profiles.set(value.slice(1, -1), current); }
    else {
      const [key, setting] = value.split('='); current![key] = numeric.has(key) ? Number(setting) : setting;
    }
  }
  return profiles;
}

function readSources(profiles: Map<string,Profile>): Source[] {
  const sources: Source[] = [];
  for (const value of inputLines('sources.txt')) {
    if (value.startsWith('=== ')) {
      const [, name, profile] = value.split(' ');
      sources.push({ header: value, name, profile: profiles.get(profile)!, lines: [] });
    } else sources[sources.length - 1].lines.push(value);
  }
  return sources;
}

function attachComments(lexed: Lexed): void {
  const { tokens, records } = lexed;
  const following: (Token | null)[] = Array(records.length), end = tokens[tokens.length - 1];
  let next: Token | null = null;
  for (let i = records.length - 1; i >= 0; i--) {
    following[i] = next;
    if (!records[i].comment) next = records[i];
  }
  let previous: Token | null = null;
  for (let i = 0; i < records.length; i++) {
    const record = records[i];
    if (!record.comment) { previous = record; continue; }
    next = following[i];
    if (previous !== null && previous.line === record.line && (next === null || next.line > record.line)) {
      previous.trailing.push(record);
    } else {
      record.own = record.kind === 'line_comment' || i + 1 === records.length || records[i + 1].line > record.line;
      (next === null ? end : next).leading.push(record);
    }
  }
  for (const token of tokens) token.sourceTrailing = token.trailing.length > 0;
}

function checkComments(program: ProgramNode, tokens: Token[]): void {
  const allowed = new Set<Token>([program.end]), trailingCommas = new Set<Token>();
  const allowBody = (body: StatementNode): void => { if (body.kind !== 'block') allowed.add(body.first); };
  const work: AstNode[] = [program];
  while (work.length) {
    const node = work.pop()!;
    if (node.kind === 'program') node.items.forEach(item => allowed.add(item.first));
    if (node.kind === 'block') {
      allowed.add(node.close); node.statements.forEach(statement => allowed.add(statement.first));
    }
    if (node.kind === 'switch') {
      allowed.add(node.close);
      for (const clause of node.clauses) {
        allowed.add(clause.label); clause.statements.forEach(statement => allowed.add(statement.first));
      }
    }
    if (node.kind === 'if' || node.kind === 'while' || node.kind === 'for') allowBody(node.body);
    if (node.kind === 'if' && node.alternative !== null && node.alternative.kind !== 'if') allowBody(node.alternative);
    if (node.kind === 'list') {
      node.elements.forEach(element => allowed.add(element.first));
      if (node.trailing !== null) trailingCommas.add(node.trailing);
    }
    const nested = children(node);
    for (let i = nested.length - 1; i >= 0; i--) work.push(nested[i]);
  }
  for (const token of tokens) for (const comment of token.leading) {
    if (trailingCommas.has(token) || (comment.own && !allowed.has(token))) {
      throw new FormatError(comment.line, comment.column, 'comment not allowed here');
    }
  }
}

const expressionLevel = (expression: ExprNode): number => expression.kind === 'conditional' ? 0 : expression.kind === 'binary' ? expression.precedence : expression.kind === 'unary' ? 7 : 8;
const postfix = (expression: ExprNode): expression is PostfixNode => ['call', 'index', 'member'].includes(expression.kind);

class DocumentBuilder {
  profile: Profile;
  tokens: Token[];
  indent: number;
  space: string;
  keywordSpace: string;
  operatorBreak: Doc;
  firstFunction: {name:string; document: Doc} | null;
  constructor(profile: Profile, tokens: Token[]) {
    this.profile = profile; this.tokens = tokens; this.indent = profile.indent;
    this.space = profile.space_around_operators === 'yes' ? ' ' : '';
    this.keywordSpace = profile.space_after_keyword === 'yes' ? ' ' : '';
    this.operatorBreak = profile.space_around_operators === 'yes' ? line : softline;
    this.firstFunction = null;
  }

  separation(blank: number): Doc { return cat(Array(1 + Math.min(blank, this.profile.max_blank_lines)).fill(hardline)); }
  preBlank(token: Token): number { return token.leading.length ? token.leading[0].blank : token.blank; }

  comments(comments: Token[], final: Token | null): Doc {
    const parts: DocPart[] = [];
    comments.forEach((comment, i) => {
      parts.push(comment.value);
      const next = i + 1 < comments.length ? comments[i + 1] : final;
      if (next !== null) parts.push(comment.own ? this.separation(next.blank) : ' ');
    });
    return cat(parts);
  }

  trailing(token: Token): DocPart { return token.trailing.length ? suffix(token.trailing.map(comment => comment.value).join(' ')) : ''; }
  token(token: Token, leading: Token[] = token.leading): Doc { return cat(this.comments(leading, token), token.value, this.trailing(token)); }

  closingComments(token: Token): {own:Token[]; inline:Token[]} {
    let lastOwn = -1;
    token.leading.forEach((comment, i) => { if (comment.own) lastOwn = i; });
    return { own: token.leading.slice(0, lastOwn + 1), inline: token.leading.slice(lastOwn + 1) };
  }

  sequence<T extends AstNode & {first: Token}>(nodes: T[], render: (node: T) => DocPart): Doc {
    const parts: DocPart[] = [];
    nodes.forEach((node, i) => {
      if (i > 0) parts.push(this.separation(this.preBlank(node.first)));
      parts.push(render(node));
    });
    return cat(parts);
  }

  beforeClosing(comments: Token[], hasItems: boolean): DocPart {
    if (comments.length === 0) return '';
    return cat(hasItems ? this.separation(comments[0].blank) : '', this.comments(comments, null));
  }

  program(program: ProgramNode): Doc {
    const document = this.sequence(program.items, item => {
      const result = item.kind === 'function' ? this.function(item) : this.declaration(item);
      if (item.kind === 'function' && this.firstFunction === null) this.firstFunction = { name: item.name.value, document: result };
      return result;
    });
    return cat(document, this.beforeClosing(program.end.leading, program.items.length > 0));
  }

  function(node: FunctionNode): Doc {
    return cat(this.token(node.type), ' ', this.token(node.name), this.list(node.parameters), hardline, this.block(node.body));
  }

  parameter(node: ParameterNode): Doc {
    return cat(this.token(node.type), ' ', this.token(node.name), node.dimensions.map(dimension => cat(this.token(dimension.open), this.token(dimension.close))));
  }

  declaration(node: DeclarationNode): Doc {
    const parts: DocPart[] = [this.token(node.type), ' ', this.token(node.name)];
    for (const dimension of node.dimensions) {
      parts.push(this.token(dimension.open), dimension.value === null ? '' : this.expression(dimension.value, 0), this.token(dimension.close));
    }
    if (node.equal !== null) parts.push(this.space, this.token(node.equal), this.space, this.initializer(node.initializer!));
    if (node.semi !== null) parts.push(this.token(node.semi!));
    return cat(parts);
  }

  initializer(node: ExprNode | ListNode): DocPart { return node.kind === 'list' ? this.list(node) : this.expression(node, 0); }

  list(node: ListNode): Doc {
    if (node.elements.length === 0) return cat(this.token(node.open), this.token(node.close));
    const forced = this.tokens.slice(node.open.index, node.close.index).some(token => token.sourceTrailing);
    const parts: DocPart[] = [softline];
    node.elements.forEach((element, i) => {
      parts.push(node.role === 'parameters' ? this.parameter(element as ParameterNode) : node.role === 'initializers' ? this.initializer(element as ExprNode | ListNode) : this.expression(element as ExprNode, 0));
      if (i + 1 < node.elements.length) parts.push(this.token(node.commas[i]), line);
    });
    if (node.role === 'initializers') {
      parts.push(ifBreak(',', ''));
      if (node.trailing !== null) parts.push(this.trailing(node.trailing));
    }
    return group(forced ? breakParent : '', this.token(node.open), nest(this.indent, parts), softline, this.token(node.close));
  }

  block(node: BlockNode): Doc {
    const comments = this.closingComments(node.close);
    if (node.statements.length === 0 && comments.own.length === 0) return cat(this.token(node.open), this.token(node.close, comments.inline));
    return cat(this.token(node.open), nest(this.indent, hardline,
      this.sequence(node.statements, statement => this.statement(statement)), this.beforeClosing(comments.own, node.statements.length > 0)),
    hardline, this.token(node.close, comments.inline));
  }

  body(node: StatementNode): Doc {
    const beforeBrace = this.profile.brace_style === 'kr' ? ' ' : hardline;
    if (node.kind === 'block') return cat(beforeBrace, this.block(node));
    if (this.profile.add_braces === 'yes') return cat(beforeBrace, '{', nest(this.indent, hardline, this.statement(node)), hardline, '}');
    return nest(this.indent, hardline, this.statement(node));
  }

  simple(node: SimpleNode): Doc {
    return node.kind === 'assignment' ? cat(this.expression(node.left, 0), this.space, this.token(node.operator), this.space, this.expression(node.right, 0))
      : this.expression(node.value, 0);
  }

  ifStatement(node: IfNode): Doc {
    const parts = [this.token(node.keyword), this.keywordSpace, this.token(node.open), this.expression(node.condition, 0), this.token(node.close), this.body(node.body)];
    if (node.otherwise !== null) {
      const together = this.profile.brace_style === 'kr' && (node.body.kind === 'block' || this.profile.add_braces === 'yes');
      parts.push(together ? ' ' : hardline, this.token(node.otherwise!), node.alternative!.kind === 'if' ? cat(' ', this.ifStatement(node.alternative as IfNode)) : this.body(node.alternative!));
    }
    return cat(parts);
  }

  forStatement(node: ForNode): Doc {
    const initial = node.initial === null ? '' : node.initial.kind === 'declaration' ? this.declaration(node.initial) : this.simple(node.initial);
    const middle = group(align(initial, this.token(node.firstSemi), node.condition === null ? '' : cat(line, this.expression(node.condition, 0)),
      this.token(node.secondSemi), node.update === null ? '' : cat(line, this.simple(node.update))));
    return cat(this.token(node.keyword), this.keywordSpace, this.token(node.open), middle, this.token(node.close), this.body(node.body));
  }

  clause(node: ClauseNode): Doc {
    return cat(this.token(node.label), node.value === null ? '' : cat(' ', this.expression(node.value, 0)), this.token(node.colon),
      node.statements.length === 0 ? '' : nest(this.indent, hardline, this.sequence(node.statements, statement => this.statement(statement))));
  }

  switchStatement(node: SwitchNode): Doc {
    const comments = this.closingComments(node.close);
    const start = cat(this.token(node.keyword), this.keywordSpace, this.token(node.left), this.expression(node.condition, 0), this.token(node.right),
      this.profile.brace_style === 'kr' ? ' ' : hardline, this.token(node.open));
    if (node.clauses.length === 0 && comments.own.length === 0) return cat(start, this.token(node.close, comments.inline));
    const indent = this.profile.indent_case_labels === 'yes' ? this.indent : 0;
    return cat(start, nest(indent, hardline, this.sequence(node.clauses, clause => this.clause(clause)),
      this.beforeClosing(comments.own, node.clauses.length > 0)), hardline, this.token(node.close, comments.inline));
  }

  statement(node: StatementNode): Doc {
    switch (node.kind) {
      case 'block': return this.block(node);
      case 'declaration': return this.declaration(node);
      case 'assignment': case 'expression_statement': return cat(this.simple(node), this.token(node.semi!));
      case 'return': return cat(this.token(node.keyword), node.value === null ? '' : cat(' ', this.expression(node.value, 0)), this.token(node.semi));
      case 'jump': return cat(this.token(node.keyword), this.token(node.semi));
      case 'if': return this.ifStatement(node);
      case 'while': return cat(this.token(node.keyword), this.keywordSpace, this.token(node.open), this.expression(node.condition, 0), this.token(node.close), this.body(node.body));
      case 'for': return this.forStatement(node);
      case 'switch': return this.switchStatement(node);
    }
  }

  openAt(node: ExprNode, required: number): ExprNode {
    if (this.profile.remove_parens !== 'yes') return node;
    while (node.kind === 'parenthesized' && expressionLevel(node.inner) >= required && node.open.leading.length === 0 && node.close.leading.length === 0) {
      const inner = node.inner;
      inner.first.trailing = [...node.open.trailing, ...inner.first.trailing];
      inner.last.trailing = [...inner.last.trailing, ...node.close.trailing];
      node.open.trailing = []; node.close.trailing = []; node = inner;
    }
    return node;
  }

  binary(node: BinaryNode): Doc {
    const precedence = node.precedence, operations: {operator: Token; right: ExprNode}[] = [];
    let first = node;
    while (first.kind === 'binary' && first.precedence === precedence) {
      operations.push({ operator: first.operator, right: first.right }); first = this.openAt(first.left, precedence);
    }
    operations.reverse();
    const head = this.expression(first, precedence), tail: DocPart[] = [];
    for (const operation of operations) tail.push(this.operatorBreak, this.token(operation.operator), this.space, this.expression(operation.right, precedence + 1));
    return group(head, nest(this.indent, tail));
  }

  conditional(node: ConditionalNode): Doc {
    const tail: DocPart[] = [];
    let current = node;
    while (true) {
      tail.push(this.operatorBreak, this.token(current.question), this.space, this.expression(current.yes, 0), this.operatorBreak, this.token(current.colon), this.space);
      const next = this.openAt(current.no, 0);
      if (next.kind !== 'conditional') { tail.push(this.expression(next, 0)); break; }
      tail.push(this.expression(next.condition, 1)); current = next;
    }
    return group(this.expression(node.condition, 1), nest(this.indent, tail));
  }

  postfixPart(node: PostfixNode): Doc {
    if (node.kind === 'call') return this.list(node.argumentsList);
    if (node.kind === 'index') return cat(this.token(node.open), this.expression(node.value, 0), this.token(node.close));
    return cat(this.token(node.dot), this.token(node.name));
  }

  postfix(node: PostfixNode): Doc {
    const operations: PostfixNode[] = [];
    let head = node;
    while (postfix(head)) { operations.push(head); head = this.openAt(head.target, 8); }
    operations.reverse();
    const segments: PostfixNode[][] = [[]];
    for (const operation of operations) {
      if (operation.kind === 'member') segments.push([]);
      segments[segments.length - 1].push(operation);
    }
    const callSegments = segments.map((segment, index) => ({ index, call: index > 0 && segment.some(operation => operation.kind === 'call') })).filter(segment => segment.call);
    const first = this.expression(head, 8);
    if (callSegments.length < 2) return cat(first, operations.map(operation => this.postfixPart(operation)));
    const start = callSegments[0].index;
    const prefix = segments.slice(0, start).flatMap(segment => segment.map(operation => this.postfixPart(operation)));
    const tail = segments.slice(start).map(segment => cat(softline, segment.map(operation => this.postfixPart(operation))));
    return group(first, prefix, nest(this.indent, tail));
  }

  expression(node: ExprNode, required: number): Doc {
    node = this.openAt(node, required);
    switch (node.kind) {
      case 'primary': return this.token(node.token);
      case 'parenthesized': return cat(this.token(node.open), this.expression(node.inner, 0), this.token(node.close));
      case 'unary': return cat(this.token(node.operator), this.expression(node.operand, 8));
      case 'binary': return this.binary(node);
      case 'conditional': return this.conditional(node);
      case 'call': case 'index': case 'member': return this.postfix(node);
    }
  }
}

function formatSource(source: string[], profile: Profile): FormatResult {
  try {
    const lexed = tokenize(source); attachComments(lexed);
    const program = new Parser(lexed.tokens).program(); checkComments(program, lexed.tokens);
    const builder = new DocumentBuilder(profile, lexed.tokens), document = builder.program(program);
    const formatted = program.items.length === 0 && program.end.leading.length === 0 ? [] : layout(document, profile);
    const allGroups = groups(document);
    const metrics = { lines: formatted.length, longest: formatted.reduce((longest, line) => Math.max(longest, line.length), 0), comments: lexed.comments.length,
      groups: allGroups.length, broken: allGroups.filter(node => node.mode === 'break' || node.mode === 'forced').length,
      forced: allGroups.filter(node => node.mode === 'forced').length };
    return { formatted, metrics, firstFunction: builder.firstFunction };
  } catch (error) {
    if (!(error instanceof FormatError)) throw error;
    return { error, formatted: trimLines(source) };
  }
}

function idempotency(name: string, first: FormatResult, profile: Profile): string {
  const second = formatSource(first.formatted, profile);
  if (second.error) return `${name}: unstable (second pass: ${second.error.line}:${second.error.column}: ${second.error.message})`;
  for (let i = 0; i < Math.max(first.formatted.length, second.formatted.length); i++) {
    if (first.formatted[i] !== second.formatted[i]) return `${name}: unstable at line ${i + 1}`;
  }
  return name + ': stable';
}

function main(): void {
  const sources = readSources(readProfiles()), formatted: string[] = [], checks: string[] = [];
  const diagnostics: string[] = [], documents: string[] = [], changes: string[] = [];
  for (const source of sources) {
    const result = formatSource(source.lines, source.profile), name = source.name;
    formatted.push(source.header, ...result.formatted); documents.push('=== ' + name); changes.push('=== ' + name);
    if (result.error) {
      checks.push(name + ': skipped (syntax error)'); documents.push('syntax error'); changes.push('skipped (syntax error)');
      diagnostics.push(`${name}:${result.error.line}:${result.error.column}: error: ${result.error.message}`);
      continue;
    }
    checks.push(idempotency(name, result, source.profile));
    result.formatted.forEach((line, i) => {
      if (line.length > source.profile.width) diagnostics.push(`${name}:${i + 1}: warning: line too long (${line.length} > ${source.profile.width})`);
    });
    const metrics = result.metrics!;
    documents.push(`metrics lines=${metrics.lines} longest=${metrics.longest} comments=${metrics.comments} groups=${metrics.groups} broken=${metrics.broken} forced=${metrics.forced}`);
    if (result.firstFunction === null) documents.push('no function');
    else documents.push('function ' + result.firstFunction!.name, ...documentLines(result.firstFunction!.document));
    changes.push(...diff(trimLines(source.lines), result.formatted));
  }
  if (diagnostics.length === 0) diagnostics.push('no diagnostics');
  mkdirSync('output', { recursive: true });
  const outputs: [string,string[]][] = [['formatted.txt', formatted], ['idempotency.txt', checks], ['diagnostics.txt', diagnostics], ['doc_tree.txt', documents], ['changes.txt', changes]];
  for (const [name, lines] of outputs) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
