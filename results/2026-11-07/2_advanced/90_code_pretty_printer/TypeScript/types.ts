export interface Token {
  kind: string;
  value: string;
  line: number;
  column: number;
  blank: number;
  comment?: boolean;
  index: number;
  leading: Token[];
  trailing: Token[];
  own?: boolean;
  sourceTrailing?: boolean;
}

export interface Lexed {tokens: Token[]; comments: Token[]; records: Token[]}
export interface Profile {
  width: number;
  indent: number;
  brace_style: string;
  space_around_operators: string;
  space_after_keyword: string;
  indent_case_labels: string;
  add_braces: string;
  max_blank_lines: number;
  remove_parens: string;
  comment_column: number;
  [name: string]: string | number;
}
export interface Source {
  header: string;
  name: string;
  profile: Profile;
  lines: string[];
}

export interface NodeBase {kind: string; first: Token; last: Token}
export interface ProgramNode {kind: 'program'; items: (FunctionNode | DeclarationNode)[]; end: Token}
export interface FunctionNode extends NodeBase {
  kind: 'function'; type: Token; name: Token; parameters: ListNode; body: BlockNode;
}
export interface ParameterNode extends NodeBase {
  kind: 'parameter'; type: Token; name: Token; dimensions: {open: Token; close: Token}[];
}
export interface Dimension {open: Token; value: ExprNode | null; close: Token}
export interface DeclarationNode extends NodeBase {
  kind: 'declaration'; type: Token; name: Token; dimensions: Dimension[];
  equal: Token | null; initializer: ExprNode | ListNode | null; semi: Token | null;
}
export interface ListNode extends NodeBase {
  kind: 'list'; open: Token; close: Token; role: string;
  elements: (ParameterNode | ExprNode | ListNode)[]; commas: Token[]; trailing: Token | null;
}
export interface BlockNode extends NodeBase {
  kind: 'block'; open: Token; close: Token; statements: StatementNode[];
}
export interface IfNode extends NodeBase {
  kind: 'if'; keyword: Token; open: Token; close: Token; condition: ExprNode;
  body: StatementNode; otherwise: Token | null; alternative: StatementNode | null;
}
export interface WhileNode extends NodeBase {
  kind: 'while'; keyword: Token; open: Token; close: Token;
  condition: ExprNode; body: StatementNode;
}
export interface ForNode extends NodeBase {
  kind: 'for'; keyword: Token; open: Token; close: Token;
  initial: DeclarationNode | SimpleNode | null; firstSemi: Token;
  condition: ExprNode | null; secondSemi: Token; update: SimpleNode | null;
  body: StatementNode;
}
export interface ClauseNode extends NodeBase {
  kind: 'clause'; label: Token; value: ExprNode | null; colon: Token;
  statements: StatementNode[];
}
export interface SwitchNode extends NodeBase {
  kind: 'switch'; keyword: Token; left: Token; right: Token; open: Token;
  close: Token; condition: ExprNode; clauses: ClauseNode[];
}
export interface ReturnNode extends NodeBase {
  kind: 'return'; keyword: Token; value: ExprNode | null; semi: Token;
}
export interface JumpNode extends NodeBase {kind: 'jump'; keyword: Token; semi: Token}
export interface AssignmentNode extends NodeBase {
  kind: 'assignment'; left: ExprNode; operator: Token; right: ExprNode; semi: Token | null;
}
export interface ExpressionStatementNode extends NodeBase {
  kind: 'expression_statement'; value: ExprNode; semi: Token | null;
}
export type SimpleNode = AssignmentNode | ExpressionStatementNode;
export type StatementNode = DeclarationNode | BlockNode | IfNode | WhileNode | ForNode |
  SwitchNode | ReturnNode | JumpNode | SimpleNode;

export interface PrimaryNode extends NodeBase {kind: 'primary'; token: Token}
export interface ParenthesizedNode extends NodeBase {
  kind: 'parenthesized'; open: Token; inner: ExprNode; close: Token;
}
export interface UnaryNode extends NodeBase {kind: 'unary'; operator: Token; operand: ExprNode}
export interface BinaryNode extends NodeBase {
  kind: 'binary'; left: ExprNode; operator: Token; right: ExprNode; precedence: number;
}
export interface ConditionalNode extends NodeBase {
  kind: 'conditional'; condition: ExprNode; question: Token; yes: ExprNode; colon: Token; no: ExprNode;
}
export interface CallNode extends NodeBase {kind: 'call'; target: ExprNode; argumentsList: ListNode}
export interface IndexNode extends NodeBase {
  kind: 'index'; target: ExprNode; open: Token; value: ExprNode; close: Token;
}
export interface MemberNode extends NodeBase {kind: 'member'; target: ExprNode; dot: Token; name: Token}
export type ExprNode = PrimaryNode | ParenthesizedNode | UnaryNode | BinaryNode |
  ConditionalNode | CallNode | IndexNode | MemberNode;
export type PostfixNode = CallNode | IndexNode | MemberNode;
export type AstNode = ProgramNode | ParameterNode | ListNode | FunctionNode |
  ClauseNode | StatementNode | ExprNode;

export type Mode = 'flat' | 'break';
export interface TextDoc {kind: 'text'; value: string}
export interface ConcatDoc {kind: 'concat'; parts: Doc[]}
export interface GroupDoc {kind: 'group'; child: Doc; forced: boolean; mode: Mode | 'forced' | null}
export interface NestDoc {kind: 'nest'; indent: number; child: Doc}
export interface AlignDoc {kind: 'align'; child: Doc}
export interface SuffixDoc {kind: 'suffix'; value: string}
export interface IfBreakDoc {kind: 'if_break'; broken: string; flat: string}
export interface BreakDoc {kind: 'line'|'softline'|'hardline'|'break_parent'}
export type Doc = TextDoc | ConcatDoc | GroupDoc | NestDoc | AlignDoc |
  SuffixDoc | IfBreakDoc | BreakDoc;
export type DocPart = Doc | string | null | undefined | DocPart[];
export interface Frame {indent: number; mode: Mode; document: Doc}

export interface Metrics {
  lines: number; longest: number; comments: number;
  groups: number; broken: number; forced: number;
}
export interface FormatResult {
  formatted: string[];
  error?: {line: number; column: number; message: string};
  metrics?: Metrics;
  firstFunction?: {name: string; document: Doc} | null;
}
