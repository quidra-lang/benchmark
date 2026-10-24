export type Cell = string | number | boolean | null;

export interface Column {
  name: string;
  type: string;
  nullable: boolean;
  number: number;
}
export interface Options {
  encodings: Map<string, string>;
  row_group_size: number;
  page_size: number;
  dictionary_limit: number;
}
export interface Input {
  schema: Column[];
  table: Cell[][];
  options: Options;
  queries: string[];
  damaged: Buffer;
}
export interface Bounds {
  minimum: any;
  maximum: any;
}
export interface Chunk {
  bytes: number[];
  methods: number[];
  hasDictionary: boolean;
  pageCount: number;
  nulls: number;
  statistics: Bounds | null;
  fallback: number;
}
export interface WriteChunk extends Chunk {
  offset: number;
  column: Column;
}
export interface WriteGroup {
  count: number;
  chunks: WriteChunk[];
}
export interface Page {
  offset: number;
  kind: number;
  method: number;
  count: number;
  nulls: number;
  bodySize: number;
  checksum: number;
  statistics: Bounds | null;
  headerSize: number;
  bodyOffset: number;
  number?: number;
  firstRow?: number;
}
export interface ParsedChunk {
  column: Column;
  offset: number;
  size: number;
  methods: number[];
  hasDictionary: boolean;
  pageCount: number;
  nulls: number;
  statistics: Bounds | null;
  pages?: Page[];
  dataPages?: Page[];
  dictionary?: Page | null;
}
export interface ParsedGroup {
  number: number;
  count: number;
  firstRow: number;
  chunks: ParsedChunk[];
}
export interface ParsedFile {
  bytes: Buffer;
  footerOffset: number;
  footerSize: number;
  version: number;
  schema: Column[];
  rowCount: number;
  groups: ParsedGroup[];
}
export interface Literal {
  type: string;
  value: string | number | boolean;
}
export type Condition =
  | {kind: 'comparison'; name: string; operator: string; literals: Literal[]; column?: number; values?: any[]}
  | {kind: 'NOT'; child: Condition}
  | {kind: 'AND' | 'OR'; left: Condition; right: Condition};

export type Comparison = Extract<Condition, {kind: 'comparison'}>;

export interface ValueGroup {
  key: Cell;
  rows: {number: number; values: Cell[]}[];
}

export type QueryItem =
  | {kind: 'column'; name: string; number?: number}
  | {kind: 'aggregate'; function: string; name: string | null; distinct: boolean; number?: number};
export interface Query {
  star: boolean;
  items: QueryItem[];
  condition: Condition | null;
  group: string | null;
  order: {name: string; descending: boolean; column?: number} | null;
  limit: number | null;
  aggregate?: boolean;
  groupColumn?: number | null;
  needed?: number[];
  remaining?: number[];
  conditionColumns?: number[];
  headers?: string[];
}
