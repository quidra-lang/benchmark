export interface Prefix {
  text: string;
  address: string;
  value: number;
  length: number;
  unit: number;
}

export interface Attribute {
  path: number[];
  origin: string;
  med: number;
  communities: number[];
}

export interface Route extends Attribute {
  local: boolean;
  localPref?: number;
  link?: Link;
}

export interface AutonomousSystem {
  asn: number;
  routerId: number;
  sessions: Session[];
  origination: Map<string, Route>;
  rib: Map<string, Route>;
  changes: number;
}

export interface Link {
  name: string;
  a: number;
  b: number;
  relationship: string;
  delay: number;
  mrai: number;
  number: number;
  up: boolean;
  downs: number;
  sessions: Map<number, Session>;
}

export interface Session {
  owner: AutonomousSystem;
  neighbor: number;
  link: Link;
  input: Map<string, Attribute>;
  output: Map<string, Attribute>;
  pending: Set<string>;
  timer: number | null;
  sent: number;
  received: number;
}

export interface Topology {
  ases: Map<number, AutonomousSystem>;
  asOrder: AutonomousSystem[];
  links: Link[];
  linkByName: Map<string, Link>;
  initial: {asn: number; prefix: string; origin: string; communities: string[]}[];
  sessions: Session[];
}

export interface PrefixListEntry {
  action: string;
  prefix: Prefix;
  low: number;
  high: number;
}

export interface PolicyCondition {
  kind: string;
  value: any;
}

export interface PolicyAction {
  kind: string;
  value: any;
}

export interface PolicyRule {
  name: string;
  active: boolean;
  asn: number;
  direction: string;
  target: string;
  conditions: PolicyCondition[];
  actions: PolicyAction[];
  hits: number;
  DENY?: boolean;
  ALLOW?: boolean;
  MED?: number;
  LOCALPREF?: number;
  PREPEND?: number;
  [key: string]: any;
}

export interface Policies {
  lists: Map<string, PrefixListEntry[]>;
  rules: PolicyRule[];
  byName: Map<string, PolicyRule>;
}

export interface Message {
  serial: number;
  sender: number;
  receiver: number;
  link: Link;
  prefix: string;
  content: Attribute | null;
  arrival: number;
}

export interface Event {
  number: number;
  time: number;
  text: string;
  fields: string[];
  kind: string;
}

export interface Trace {
  index: number;
  asn: number;
  address: string;
  value: number;
}

export interface Params {
  preferences: Record<string, number>;
  cap: number;
  traces: Trace[];
}

export interface PathResult {
  result: string;
  visits: number[];
  hops: {asn: number; prefix: string; link: Link | null}[];
  count: number;
  arrival?: number;
}
