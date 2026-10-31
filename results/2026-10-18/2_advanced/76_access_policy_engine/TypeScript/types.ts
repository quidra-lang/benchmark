export type AttributeValue = string | number | boolean | string[];
export interface EvalError {error: string}
export type RuntimeValue = AttributeValue | EvalError | null;
export type AttributeSet = Map<string,AttributeValue>;
export interface Expression {
  kind: 'operation'|'literal'|'attribute'|'it';
  operation?: string;
  arguments?: Expression[];
  name?: string;
  value?: AttributeValue;
}
export interface TargetClause {
  reference: string;
  mandatory: boolean;
  operation: string;
  literal: AttributeValue;
}
export type TargetLine = TargetClause[][];
export interface TargetResult {status: 'MATCH'|'NO_MATCH'|'INDETERMINATE'; reason?: string}
export interface Argument {name: string; expression: Expression}
export interface AttachmentRule {
  effect: string;
  id: string;
  arguments: Argument[];
}
export interface Attachment {id: string; text: string}
export type ElementKind = 'policyset'|'policy'|'rule';
export interface PolicyElement {
  kind: ElementKind;
  id: string;
  parent: PolicyElement | null;
  targets: TargetLine[];
  condition: Expression | null;
  obligations: AttachmentRule[];
  advice: AttachmentRule[];
  children: PolicyElement[];
  index: number;
  effect: string;
  algorithm: string;
}
export interface Policies {
  root: PolicyElement;
  elements: PolicyElement[];
  rules: PolicyElement[];
}
export interface ChildResult {
  state: 'skipped'|'checked'|'evaluated';
  element: PolicyElement;
  target?: TargetResult;
  result?: EvalResult;
}
export interface CombineResult {decision: string; reason: string | null; children: ChildResult[]}
export interface EvalResult extends CombineResult {
  element: PolicyElement;
  target: TargetResult;
  decisive: string | null;
  obligations: Attachment[];
  advice: Attachment[];
  condition?: RuntimeValue;
}
export interface RbacRole {
  juniors: Set<string>;
  permissions: Set<string>;
}
export interface RoleConstraint {
  name: string; cardinality: number; roles: string[];
}
export interface Assignment {user: string; role: string; first: number; last: number}
export interface Permission {role: string; action: string; type: string}
export interface Diagnostic {line: number; keyword: string; reason: string}
export interface RbacEngine {
  roles: Map<string,RbacRole>;
  permissions: Permission[];
  ssd: RoleConstraint[];
  dsd: RoleConstraint[];
  assignments: Assignment[];
  byUser: Map<string,Assignment[]>;
  diagnostics: Diagnostic[];
  cachedClosures: Map<string,Set<string>> | null;
  closure(seeds: Iterable<string>): Set<string>;
  assigned(user: string,day: number): Set<string>;
  authorized(user: string,day: number): Set<string>;
}
export interface Resource {
  id: string;
  type: string;
  attributes: AttributeSet;
}
export interface Domain {
  reference: string;
  values: AttributeValue[];
}
export interface InputData {
  subjects: Map<string,AttributeSet>;
  resources: Map<string,Resource>;
  domains: Domain[];
  reference: AttributeSet;
}
export interface Request {
  id?: string;
  user: string;
  roleSpec: string;
  action: string;
  resourceId: string;
  environment: AttributeSet;
  explained?: boolean;
}
export interface Activation {
  role: string;
  reason: string | null;
}
export interface Activated {
  activations: Activation[];
  session: string[];
  granting: string | null;
}
export interface Context {
  rbac: RbacEngine;
  policies: Policies;
  data: InputData;
}
export interface EvalRecord {
  request: Request;
  error: string | null;
  coverage: Map<string,string> | null;
  day?: number;
  resource?: Resource;
  activations?: Activation[];
  session?: string[];
  granting?: string | null;
  evaluation?: EvalResult;
}
export interface RuleStatistic {
  rule: PolicyElement;
  count: number;
  first: AttributeSet | null;
  blocked: number;
  blockers: Set<string>;
}
export interface ConflictPair {
  policy: PolicyElement;
  first: PolicyElement;
  second: PolicyElement;
  count: number;
}
export interface DomainAnalysis {
  count: number;
  statistics: Map<string,RuleStatistic>;
  pairs: ConflictPair[];
}
