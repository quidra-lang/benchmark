export interface Prefix {
  text: string;
  address: string;
  value: number;
  length: number;
  unit: number;
}

export type Relationship = 'P2C' | 'P2P';
export type NeighborRole = 'customer' | 'peer' | 'provider';
export type Origin = 'IGP' | 'EGP' | 'INCOMPLETE';

export interface Attribute {
  path: number[];
  origin: Origin;
  med: number;
  communities: number[];
}

export interface LocalRoute extends Attribute {
  local: true;
}

export interface LearnedRoute extends Attribute {
  local: false;
  localPref: number;
  link: Link;
}

export type Route = LocalRoute | LearnedRoute;

export interface AutonomousSystem {
  asn: number;
  routerId: number;
  sessions: Session[];
  origination: Map<string, LocalRoute>;
  rib: Map<string, Route>;
  changes: number;
}

export interface Link {
  name: string;
  a: number;
  b: number;
  relationship: Relationship;
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

export interface InitialRoute {
  asn: number;
  prefix: string;
  origin: Origin;
  communities: string[];
}

export interface Topology {
  ases: Map<number, AutonomousSystem>;
  asOrder: AutonomousSystem[];
  links: Link[];
  linkByName: Map<string, Link>;
  initial: InitialRoute[];
  sessions: Session[];
}

export interface PrefixListEntry {
  action: string;
  prefix: Prefix;
  low: number;
  high: number;
}

export type RuleValue = string | number | number[];
export interface RuleCondition { kind: string; value: RuleValue }
export interface RuleAction { kind: string; value: boolean | number }
export interface PolicyRule {
  name: string;
  active: boolean;
  asn: number;
  direction: string;
  target: string;
  conditions: RuleCondition[];
  actions: RuleAction[];
  hits: number;
  DENY?: boolean;
  ALLOW?: boolean;
  LOCALPREF?: number;
  MED?: number;
  PREPEND?: number;
}

export interface Policies {
  lists: Map<string, PrefixListEntry[]>;
  rules: PolicyRule[];
  byName: Map<string, PolicyRule>;
}

export interface Delivery {
  serial: number;
  sender: number;
  receiver: number;
  link: Link;
  prefix: string;
  content: Attribute | null;
  arrival: number;
}

export interface SimEvent {
  number: number;
  time: number;
  text: string;
  fields: string[];
  kind: string;
}

export interface ForwardingTrace {
  index: number;
  asn: number;
  address: string;
  value: number;
}

export interface Parameters {
  preferences: Record<NeighborRole, number>;
  cap: number;
  traces: ForwardingTrace[];
}

export interface PathHop { asn: number; prefix: string; link: Link | null }
export type PathResultType = 'DELIVERED' | 'LOOP' | 'BLACKHOLE' | 'UNREACHABLE';
export interface PathResult {
  result: PathResultType;
  visits: number[];
  hops: PathHop[];
  count: number;
  arrival?: number;
}

export interface BestChange {
  time: number;
  asn: number;
  prefix: string;
  route: Route | null;
}

export interface Period {
  event: SimEvent;
  convergence: number;
  updates: number;
  withdrawals: number;
  drops: number;
  bestChanges: number;
  routesChanged: number;
  exploration: Map<string, number>;
  bestLines: BestChange[];
  deliveries: number;
  states: Map<string, number>;
  first: number | null;
  repeat: number | null;
  cycle: BestChange[];
  status: string;
  maxExploration: number;
}

export interface RingRecord {
  prefix: string;
  loop: number[];
  start: number;
  end: number | null;
}
export interface ActiveTrace {
  trace: ForwardingTrace;
  status: string;
  result: PathResultType;
  visits: number[];
  start: number;
  end: number | null;
}
