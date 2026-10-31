import type {Engine} from './heuristics.ts';
export type SExpr = string | SExpr[];
export interface TypedName {name:string;type:string}
export interface Atom {predicate:string;terms:string[]}
export interface Literal {negative:boolean;atom:Atom}
export interface Predicate {name:string;types:string[];number:number}
export interface ActionSchema {
 name:string;parameters:TypedName[];conditions:Literal[];effects:Literal[];
 adds:Atom[];deletes:Atom[];cost:number;
}
export interface Domain {
 name:string;types:string[];parents:Map<string,string|null>;predicates:Predicate[];
 actions:ActionSchema[];predicateTable:Map<string,Predicate>;fluent:Set<string>;
 static:Set<string>;diagnostics:string[];actionTable:Map<string,ActionSchema>;
}
export interface ProblemObject extends TypedName {number:number}
export interface Step {name:string;arguments:string[]}
export interface CandidatePlan {
 number:number;problem:string;label:string;steps:Step[];
}
export interface SearchConfig {algorithm:string;heuristic:string;tag:string}
export interface Settings {
 runs:SearchConfig[];repair:SearchConfig;budget:number;weight:number;graphplan:number;
 [name:string]:number|SearchConfig|SearchConfig[];
}
export interface GroundedAction {
 number:number;name:string;source:ActionSchema;arguments:string[];cost:number;notation:string;
 pre:bigint;neg:bigint;add:bigint;del:bigint;
 preFacts:number[];negFacts:number[];addFacts:number[];delFacts:number[];
}
export interface GroundedFact extends Atom {notation:string}
export interface SchemaStats {
 source:ActionSchema;assignments:number;candidates:number;reachable:number;
}
export interface GroundedModel {
 facts:GroundedFact[];factNumbers:Map<string,number>;
 actions:GroundedAction[];schemas:SchemaStats[];candidateCount:number;
 objectsByType:Map<string,ProblemObject[]>;unreachable:Atom[];
 initial:bigint;goal:bigint;goalFacts:number[];staticCount:number;
 actionTable:Map<string,GroundedAction>;
}
export interface Problem {
 name:string;objects:ProblemObject[];
 objectTypes:Map<string,string>;objectNumbers:Map<string,number>;
 init:Atom[];goals:Atom[];diagnostics:string[];
 model:GroundedModel;unreachable:boolean;
 results:PlanResult[];engine:Engine;graph:GraphPlanResult;solved:number;
 best:number|null;proof:PlanResult|null;optimal:number|string;
}
export interface CandidateGrounded {
 source:ActionSchema;arguments:string[];cost:number;pre:Set<string>;neg:Set<string>;
 add:Set<string>;del:Set<string>;counts:SchemaStats;reachable:boolean;
}
export interface HeuristicRelaxation {value:number;plan:GroundedAction[];helpful:GroundedAction[]}
export interface Landmarks {value:number;facts:number[]}
export interface HeuristicRecord {
 cmax?:number[];cadd?:number[];relaxed?:HeuristicRelaxation;
 landmarks?:Landmarks;
 goalcount?:number;hmax?:number;hadd?:number;ff?:number;lmcount?:number;
}
export interface HeuristicLevels {facts:number[];actions:number[]}
export interface SearchResult {
 result:string;plan:GroundedAction[]|null;expanded:number;generated:number;
}
export interface PlanAnalysis {
 layers:GroundedAction[][];improved:GroundedAction[];landmarks:number[];
 missed:number[];parallel:string;validation:Validation;improvedValidation:Validation;
}
export interface PlanResult extends SearchConfig,SearchResult {
 cost?:number;analysis?:PlanAnalysis;
}
export interface Validation {result:string;messages:string[];correct:number;cost:number}
export interface GraphplanAction {
 number:number|null;fact?:number;pre:bigint;add:bigint;del:bigint;
 original:GroundedAction|null;index:number;
}
export interface TransformAction {
 number:number;original:GroundedAction;pre:bigint;add:bigint;del:bigint;
}
export interface TransformResult {actions:TransformAction[];initial:bigint;count:number;factCount:number}
export interface ActionLevel {
 elements:GraphplanAction[];actionCount:number;mutexes:import('./graphplan.ts').Mutexes;
 achievers:GraphplanAction[][];nextFacts:bigint;
 nextMutexes:import('./graphplan.ts').Mutexes;
}
export interface GraphPlanResult extends SearchResult {
 layers:GroundedAction[][]|null;logs:string[];memoHits:number;complements?:number;
}
export interface SearchNode {
 state:bigint;g:number;d:number;h:number;f:number;serial:number;
 parent:SearchNode|null;action:GroundedAction|null;
}
