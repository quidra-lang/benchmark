import type {
  Cell, Column, Input, Bounds, Chunk, WriteGroup, ParsedFile,
  ParsedChunk, Page, Query, Condition
} from './types.ts';

import * as io from './schema_io.ts';
import * as bitstream from './bitstream.ts';
import * as encoding from './encoding.ts';
import * as queryParser from './query.ts';
const {Reader, append, uleb, uint32, adler32} = bitstream;
const TRUE = 1;
const FALSE = 0;
const UNKNOWN = 2;
const LOST = Symbol('lost');
const scanFields = ['row_groups_read', 'row_groups_skipped', 'pages_read', 'pages_skipped',
  'pages_unneeded', 'dictionary_pages_read', 'bytes_read', 'rows_scanned', 'rows_matched'];

function compare(first: any, second: any): number {
  if (first === second) return 0;
  if (first === null) return -1;
  if (second === null) return 1;
  return first < second ? -1 : 1;
}

function statistics(values: any[]): Bounds | null {
  let result = null;
  for (const value of values) {
    if (value === null) continue;
    if (result === null) result = {minimum: value, maximum: value};
    else {
      if (compare(value, result.minimum) < 0) result.minimum = value;
      if (compare(value, result.maximum) > 0) result.maximum = value;
    }
  }
  return result;
}

function pageBytes(column: Column, kind: number, method: number, count: number, nulls: number, stats: Bounds | null, body: number[]): number[] {
  const bytes = [kind, method];
  for (const value of [count, nulls, body.length]) append(bytes, uleb(value));
  append(bytes, uint32(adler32(body)));
  append(bytes, encoding.statisticsBytes(column.type, stats));
  return append(bytes, body);
}

function dataPage(column: Column, method: number, values: Cell[], dictionary: any[], ranks: Map<any, number>): number[] {
  const body = [];
  if (column.nullable) {
    const definitions = bitstream.hybridEncode(values.map(value => value === null ? 0 : 1), 1);
    append(body, uint32(definitions.length));
    append(body, definitions);
  }
  const present = values.filter(value => value !== null);
  append(body, encoding.encodeValues(column.type, method, present, dictionary, ranks));
  return pageBytes(column, 0, method, values.length, values.length - present.length, statistics(values), body);
}

function buildChunk(column: Column, values: Cell[], method: number, options: Input['options']): Chunk {
  const pages = [];
  for (let start = 0; start < values.length; start += options.page_size) {
    pages.push(values.slice(start, start + options.page_size));
  }
  const dictionary: any[] = [];
  let dictionaryPages = 0;
  if (method === 1) {
    const known = new Set();
    let bytes = 0;
    for (const page of pages) {
      const additions = new Set();
      let proposedBytes = bytes;
      for (const value of page) {
        if (value === null || known.has(value) || additions.has(value)) continue;
        additions.add(value);
        proposedBytes += encoding.encodeValues(column.type, 0, [value]).length;
      }
      if (proposedBytes > options.dictionary_limit) break;
      for (const value of additions) {
        dictionary.push(value);
        known.add(value);
      }
      bytes = proposedBytes;
      dictionaryPages++;
    }
    if (dictionary.length === 0) dictionaryPages = 0;
  }
  const ranks = new Map(dictionary.map((value, index) => [value, index]));
  const bytes = [];
  if (dictionaryPages > 0) {
    const body = encoding.encodeValues(column.type, 0, dictionary);
    append(bytes, pageBytes(column, 1, 0, dictionary.length, 0, null, body));
  }
  const methods = new Set();
  for (let index = 0; index < pages.length; index++) {
    const pageMethod = method === 1 ? (index < dictionaryPages ? 1 : 0) : method;
    methods.add(pageMethod);
    append(bytes, dataPage(column, pageMethod, pages[index], dictionary, ranks));
  }
  return {bytes, methods: [...methods].sort((a, b) => a - b), hasDictionary: dictionaryPages > 0,
    pageCount: pages.length, nulls: values.filter(value => value === null).length,
    statistics: statistics(values), fallback: method === 1 ? pages.length - dictionaryPages : 0};
}

function footerBytes(schema: Column[], rowCount: number, groups: WriteGroup[]): number[] {
  const bytes = [];
  append(bytes, uleb(1));
  append(bytes, uleb(schema.length));
  for (const column of schema) {
    append(bytes, uleb(column.name.length));
    append(bytes, Buffer.from(column.name, 'ascii'));
    bytes.push(encoding.types.indexOf(column.type), column.nullable ? 1 : 0);
  }
  append(bytes, uleb(rowCount));
  append(bytes, uleb(groups.length));
  for (const group of groups) {
    append(bytes, uleb(group.count));
    for (const chunk of group.chunks) {
      append(bytes, uleb(chunk.offset));
      append(bytes, uleb(chunk.bytes.length));
      append(bytes, uleb(chunk.methods.length));
      append(bytes, chunk.methods);
      bytes.push(chunk.hasDictionary ? 1 : 0);
      append(bytes, uleb(chunk.pageCount));
      append(bytes, uleb(chunk.nulls));
      append(bytes, encoding.statisticsBytes(chunk.column.type, chunk.statistics));
    }
  }
  return bytes;
}

function writeTable(input: Input): {bytes: Buffer; report: string[]} {
  const bytes = [77, 80, 84, 67];
  const groups = [];
  const report = ['row_group,column,encoding,bytes,fallback_pages,chosen'];
  const {schema, table, options} = input;
  for (let start = 0; start < table.length; start += options.row_group_size) {
    const rows = table.slice(start, start + options.row_group_size);
    const group = {count: rows.length, chunks: []};
    for (const column of schema) {
      const values = rows.map(row => row[column.number]);
      const candidates = encoding.candidates[column.type].map(method =>
        ({method, chunk: buildChunk(column, values, method, options)}));
      let chosen;
      if (options.encodings.get(column.name) === 'AUTO') {
        chosen = candidates[0];
        for (const candidate of candidates) if (candidate.chunk.bytes.length < chosen.chunk.bytes.length) chosen = candidate;
      } else {
        const method = encoding.methods.indexOf(options.encodings.get(column.name));
        chosen = candidates.find(candidate => candidate.method === method);
        if (method === 1 && !chosen.chunk.hasDictionary) chosen = candidates[0];
      }
      for (const candidate of candidates) {
        report.push(`${groups.length},${column.name},${encoding.methods[candidate.method]},` +
          `${candidate.chunk.bytes.length},${candidate.chunk.fallback},${candidate === chosen ? 'yes' : 'no'}`);
      }
      const chunk = {...chosen.chunk, offset: bytes.length, column};
      group.chunks.push(chunk);
      append(bytes, chunk.bytes);
    }
    groups.push(group);
  }
  const footer = footerBytes(schema, table.length, groups);
  append(bytes, footer);
  append(bytes, uint32(footer.length));
  append(bytes, [77, 80, 84, 67]);
  return {bytes: Buffer.from(bytes), report};
}

function parsePages(bytes: Buffer, column: Column, chunk: ParsedChunk, firstRow: number): void {
  const reader = new Reader(bytes, chunk.offset);
  chunk.pages = [];
  chunk.dataPages = [];
  chunk.dictionary = null;
  let row = firstRow;
  while (reader.position < chunk.offset + chunk.size) {
    const offset = reader.position;
    const kind = reader.byte();
    const method = reader.byte();
    const count = reader.uleb();
    const nulls = reader.uleb();
    const bodySize = reader.uleb();
    const checksum = reader.uint32();
    const stats = encoding.readStatistics(reader, column.type);
    const bodyOffset = reader.position;
    const page: Page = {offset, kind, method, count, nulls, bodySize, checksum, statistics: stats,
      headerSize: bodyOffset - offset, bodyOffset};
    chunk.pages.push(page);
    if (kind === 1) chunk.dictionary = page;
    else {
      page.number = chunk.dataPages.length;
      page.firstRow = row;
      row += count;
      chunk.dataPages.push(page);
    }
    reader.position += bodySize;
  }
}

function parseFile(bytes: Buffer): ParsedFile {
  const footerSize = new Reader(bytes, bytes.length - 8).uint32();
  const footerOffset = bytes.length - 8 - footerSize;
  const reader = new Reader(bytes, footerOffset);
  const version = reader.uleb();
  const columns = reader.uleb();
  const schema = [];
  for (let number = 0; number < columns; number++) {
    const name = reader.text(reader.uleb());
    schema.push({name, type: encoding.types[reader.byte()], nullable: reader.byte() === 1, number});
  }
  const rowCount = reader.uleb();
  const groupCount = reader.uleb();
  const groups = [];
  let firstRow = 0;
  for (let number = 0; number < groupCount; number++) {
    const count = reader.uleb();
    const group = {number, count, firstRow, chunks: []};
    for (const column of schema) {
      const offset = reader.uleb();
      const size = reader.uleb();
      const methods = Array.from(reader.take(reader.uleb()));
      const hasDictionary = reader.byte() === 1;
      const pageCount = reader.uleb();
      const nulls = reader.uleb();
      const stats = encoding.readStatistics(reader, column.type);
      const chunk: ParsedChunk = {column, offset, size, methods, hasDictionary, pageCount, nulls, statistics: stats};
      parsePages(bytes, column, chunk, firstRow);
      group.chunks.push(chunk);
    }
    groups.push(group);
    firstRow += count;
  }
  return {bytes, footerOffset, footerSize, version, schema, rowCount, groups};
}

function bodyOf(file: ParsedFile, page: Page): Buffer {
  return file.bytes.subarray(page.bodyOffset, page.bodyOffset + page.bodySize);
}

function decodeDictionary(file: ParsedFile, chunk: ParsedChunk): any[] {
  return encoding.decodeValues(chunk.column.type, 0, new Reader(bodyOf(file, chunk.dictionary)), chunk.dictionary.count);
}

function decodePage(file: ParsedFile, chunk: ParsedChunk, page: Page, dictionary: any[] = []): Cell[] {
  const reader = new Reader(bodyOf(file, page));
  let definitions = Array(page.count).fill(1);
  if (chunk.column.nullable) {
    const levels = new Reader(reader.take(reader.uint32()));
    definitions = bitstream.hybridDecode(levels, page.count, 1);
  }
  let count = 0;
  for (const value of definitions) if (value === 1) count++;
  const values = encoding.decodeValues(chunk.column.type, page.method, reader, count, dictionary);
  let next = 0;
  return definitions.map(value => value === 1 ? values[next++] : null);
}

function checksumText(value: number): string {
  return value.toString(16).padStart(8, '0');
}

function statisticsText(column: Column, stats: Bounds | null): string {
  return stats === null ? 'stats none' :
    `min ${io.valueText(stats.minimum, column.type)} max ${io.valueText(stats.maximum, column.type)}`;
}

function columnLines(schema: Column[]): string[] {
  return schema.map(column => `column ${column.number} ${column.name} ${column.type} ${column.nullable ? 'NULLABLE' : 'REQUIRED'}`);
}

function methodList(methods: number[]): string {
  return methods.map(method => encoding.methods[method]).join(',');
}

function metadata(file: ParsedFile, table: Cell[][]): string[] {
  const lines = [`file bytes ${file.bytes.length} footer_offset ${file.footerOffset} footer_bytes ${file.footerSize}`,
    `table version ${file.version} rows ${file.rowCount} columns ${file.schema.length} row_groups ${file.groups.length}`];
  append(lines, columnLines(file.schema));
  const summaries = file.schema.map(() => ({bytes: 0, pages: 0, dictionaries: 0, methods: new Set()}));
  let cells = 0;
  let nulls = 0;
  let mismatches = 0;
  let checksumErrors = 0;
  for (const group of file.groups) {
    let groupBytes = 0;
    for (const chunk of group.chunks) groupBytes += chunk.size;
    lines.push(`row_group ${group.number} rows ${group.count} first_row ${group.firstRow} bytes ${groupBytes}`);
    for (const chunk of group.chunks) {
      const column = chunk.column;
      lines.push(`chunk ${group.number} ${column.name} offset ${chunk.offset} size ${chunk.size} ` +
        `encodings ${methodList(chunk.methods)} dictionary ${chunk.hasDictionary ? 'yes' : 'no'} ` +
        `pages ${chunk.pageCount} nulls ${chunk.nulls} ${statisticsText(column, chunk.statistics)}`);
      for (const page of chunk.pages) {
        if (adler32(bodyOf(file, page)) !== page.checksum) checksumErrors++;
        const label = page.kind === 1 ? 'dict' : page.number;
        let line = `page ${group.number} ${column.name} ${label} offset ${page.offset} ` +
          `header ${page.headerSize} body ${page.bodySize} checksum ${checksumText(page.checksum)}`;
        line += page.kind === 1 ? ` entries ${page.count}` :
          ` encoding ${encoding.methods[page.method]} values ${page.count} nulls ${page.nulls} ${statisticsText(column, page.statistics)}`;
        lines.push(line);
      }
      const dictionary = chunk.dictionary === null ? [] : decodeDictionary(file, chunk);
      for (const page of chunk.dataPages) {
        const values = decodePage(file, chunk, page, dictionary);
        for (let index = 0; index < values.length; index++) {
          cells++;
          if (values[index] === null) nulls++;
          if (values[index] !== table[page.firstRow + index][column.number]) mismatches++;
        }
      }
      const summary = summaries[column.number];
      summary.bytes += chunk.size;
      summary.pages += chunk.pageCount;
      if (chunk.hasDictionary) summary.dictionaries++;
      for (const method of chunk.methods) summary.methods.add(method);
    }
  }
  for (const column of file.schema) {
    const summary = summaries[column.number];
    lines.push(`summary ${column.name} bytes ${summary.bytes} data_pages ${summary.pages} ` +
      `dictionary_pages ${summary.dictionaries} encodings ${methodList([...summary.methods].sort((a, b) => a - b))}`);
  }
  const status = mismatches === 0 && checksumErrors === 0 ? 'ok' : 'failed';
  lines.push(`roundtrip ${status} cells ${cells} nulls ${nulls} mismatches ${mismatches} checksum_errors ${checksumErrors}`);
  return lines;
}

function comparisonNodes(condition: Condition): Condition[] {
  if (condition === null) return [];
  if (condition.kind === 'comparison') return [condition];
  if (condition.kind === 'NOT') return comparisonNodes(condition.child);
  return comparisonNodes(condition.left).concat(comparisonNodes(condition.right));
}

function checkQuery(query: Query, schema: Column[]): string | null {
  if (query.star) query.items = schema.map(column => ({kind: 'column', name: column.name}));
  const byName = new Map(schema.map(column => [column.name, column]));
  const comparisons = comparisonNodes(query.condition);
  const names = query.items.filter(item => item.name !== null).map(item => item.name);
  for (const comparison of comparisons) names.push(comparison.name);
  if (query.group !== null) names.push(query.group);
  if (query.order !== null) names.push(query.order.name);
  if (names.some(name => !byName.has(name))) return 'unknown_column';
  for (const comparison of comparisons) {
    const type = byName.get(comparison.name).type;
    const expected = type === 'INT' ? 'integer' : type === 'BOOL' ? 'boolean' : 'string';
    if (comparison.literals.some(literal => literal.type !== expected)) return 'type_mismatch';
  }
  if (query.items.some(item => item.kind === 'aggregate' && ['SUM', 'AVG'].includes(item.function) &&
      byName.get(item.name).type !== 'INT')) return 'bad_aggregate';
  query.aggregate = query.group !== null || query.items.some(item => item.kind === 'aggregate');
  if (query.aggregate && query.items.some(item => item.kind === 'column' && item.name !== query.group)) return 'not_grouped';
  if (query.aggregate && query.order !== null) return 'bad_order';
  for (const comparison of comparisons) {
    const column = byName.get(comparison.name);
    comparison.column = column.number;
    comparison.values = comparison.literals.map(literal => column.type === 'DATE' ? io.dayNumber(literal.value) : literal.value);
  }
  for (const item of query.items) if (item.name !== null) item.column = byName.get(item.name).number;
  query.groupColumn = query.group === null ? null : byName.get(query.group).number;
  if (query.order !== null) query.order.column = byName.get(query.order.name).number;
  query.needed = [...new Set(names.map(name => byName.get(name).number))].sort((a, b) => a - b);
  query.conditionColumns = [...new Set(comparisons.map(comparison => comparison.column))].sort((a, b) => a - b);
  query.remaining = query.needed.filter(column => !query.conditionColumns.includes(column));
  query.headers = query.items.map(item => item.kind === 'column' ? item.name :
    `${item.function}(${item.distinct ? 'DISTINCT ' : ''}${item.name === null ? '*' : item.name})`);
  return null;
}

function logical(operator: string, first: number, second: number): number {
  if (operator === 'NOT') return first === UNKNOWN ? UNKNOWN : 1 - first;
  if (operator === 'AND') return first === FALSE || second === FALSE ? FALSE :
    first === UNKNOWN || second === UNKNOWN ? UNKNOWN : TRUE;
  return first === TRUE || second === TRUE ? TRUE : first === UNKNOWN || second === UNKNOWN ? UNKNOWN : FALSE;
}

function comparisonTruth(condition: Condition, value: any): number {
  const {operator, values} = condition;
  if (operator === 'IS NULL') return value === null ? TRUE : FALSE;
  if (operator === 'IS NOT NULL') return value === null ? FALSE : TRUE;
  if (value === null) return UNKNOWN;
  const order = compare(value, values[0]);
  let result;
  switch (operator) {
    case '=': result = order === 0; break;
    case '<>': result = order !== 0; break;
    case '<': result = order < 0; break;
    case '<=': result = order <= 0; break;
    case '>': result = order > 0; break;
    case '>=': result = order >= 0; break;
    case 'BETWEEN': result = order >= 0 && compare(value, values[1]) <= 0; break;
    case 'IN': result = values.some(literal => compare(value, literal) === 0); break;
  }
  return result ? TRUE : FALSE;
}

function evaluate(condition: Condition | null, values: Cell[]): number {
  if (condition === null) return TRUE;
  if (condition.kind === 'comparison') return comparisonTruth(condition, values[condition.column]);
  if (condition.kind === 'NOT') return logical('NOT', evaluate(condition.child, values));
  return logical(condition.kind, evaluate(condition.left, values), evaluate(condition.right, values));
}

function zoneComparison(condition: Condition, information: any): Set<number> {
  const result = new Set();
  const {operator, values} = condition;
  const {count, nulls, statistics: stats} = information;
  if (operator === 'IS NULL' || operator === 'IS NOT NULL') {
    if (nulls > 0) result.add(operator === 'IS NULL' ? TRUE : FALSE);
    if (nulls < count) result.add(operator === 'IS NULL' ? FALSE : TRUE);
    return result;
  }
  if (nulls > 0) result.add(UNKNOWN);
  if (stats === null) return result;
  const lo = stats.minimum;
  const hi = stats.maximum;
  const x = values[0];
  const low = compare(lo, x);
  const high = compare(hi, x);
  let canTrue = false;
  let canFalse = false;
  switch (operator) {
    case '=': canTrue = low <= 0 && high >= 0; canFalse = !(low === 0 && high === 0); break;
    case '<>': canTrue = !(low === 0 && high === 0); canFalse = low <= 0 && high >= 0; break;
    case '<': canTrue = low < 0; canFalse = high >= 0; break;
    case '<=': canTrue = low <= 0; canFalse = high > 0; break;
    case '>': canTrue = high > 0; canFalse = low <= 0; break;
    case '>=': canTrue = high >= 0; canFalse = low < 0; break;
    case 'BETWEEN':
      canTrue = compare(lo, values[1]) <= 0 && high >= 0 && compare(x, values[1]) <= 0;
      canFalse = low < 0 || compare(hi, values[1]) > 0;
      break;
    case 'IN':
      canTrue = values.some(value => compare(lo, value) <= 0 && compare(hi, value) >= 0);
      canFalse = !(compare(lo, hi) === 0 && values.some(value => compare(lo, value) === 0));
      break;
  }
  if (canTrue) result.add(TRUE);
  if (canFalse) result.add(FALSE);
  return result;
}

function zoneValues(condition: Condition, information: (column: number) => any): Set<number> {
  if (condition.kind === 'comparison') return zoneComparison(condition, information(condition.column));
  if (condition.kind === 'NOT') return new Set([...zoneValues(condition.child, information)].map(value => logical('NOT', value)));
  const first = zoneValues(condition.left, information);
  const second = zoneValues(condition.right, information);
  const result = new Set();
  for (const a of first) for (const b of second) result.add(logical(condition.kind, a, b));
  return result;
}

function emptyCounts(): Record<string, number> {
  return Object.fromEntries(scanFields.map(field => [field, 0]));
}

function scan(file: ParsedFile, query: Query) {
  const counts = emptyCounts();
  const records = [];
  const rows = [];
  const dictionaries = new Map();
  const decode = (chunk, page) => {
    let dictionary = [];
    if (page.method === 1) {
      if (!dictionaries.has(chunk)) {
        dictionaries.set(chunk, decodeDictionary(file, chunk));
        counts.dictionary_pages_read++;
        counts.bytes_read += chunk.dictionary.headerSize + chunk.dictionary.bodySize;
      }
      dictionary = dictionaries.get(chunk);
    }
    counts.pages_read++;
    counts.bytes_read += page.headerSize + page.bodySize;
    return decodePage(file, chunk, page, dictionary);
  };
  for (const group of file.groups) {
    if (query.condition !== null && !zoneValues(query.condition, column =>
        ({...group.chunks[column], count: group.count})).has(TRUE)) {
      counts.row_groups_skipped++;
      records.push({number: group.number, skipped: true});
      continue;
    }
    counts.row_groups_read++;
    if (query.needed.length === 0) {
      counts.rows_scanned += group.count;
      for (let index = 0; index < group.count; index++) rows.push({number: group.firstRow + index, values: []});
      records.push({number: group.number, pages: '-'});
      continue;
    }
    let record = '';
    for (let pageNumber = 0; pageNumber < group.chunks[0].pageCount; pageNumber++) {
      if (query.condition !== null && !zoneValues(query.condition,
          column => group.chunks[column].dataPages[pageNumber]).has(TRUE)) {
        counts.pages_skipped += query.needed.length;
        record += 's';
        continue;
      }
      const page = group.chunks[0].dataPages[pageNumber];
      counts.rows_scanned += page.count;
      const values = Array.from({length: page.count}, () => Array(file.schema.length));
      const readColumn = column => {
        const chunk = group.chunks[column];
        const decoded = decode(chunk, chunk.dataPages[pageNumber]);
        for (let index = 0; index < page.count; index++) values[index][column] = decoded[index];
      };
      for (const column of query.conditionColumns) readColumn(column);
      const selected = [];
      for (let index = 0; index < page.count; index++) if (evaluate(query.condition, values[index]) === TRUE) selected.push(index);
      if (selected.length === 0 && query.remaining.length > 0) {
        counts.pages_unneeded += query.remaining.length;
        record += 'u';
      } else {
        for (const column of query.remaining) readColumn(column);
        for (const index of selected) rows.push({number: page.firstRow + index, values: values[index]});
        record += 'r';
      }
    }
    records.push({number: group.number, pages: record});
  }
  counts.rows_matched = rows.length;
  return {counts, records, rows};
}

function fraction(numerator: number, denominator: number): string {
  let first = Math.abs(numerator);
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  numerator /= first;
  denominator /= first;
  return denominator === 1 ? String(numerator) : `${numerator}/${denominator}`;
}

function aggregateItem(item: Query['items'][number], group: {number: number; values: Cell[]}[], schema: Column[]) {
  if (item.kind === 'column') return io.valueText(group.key, schema[item.column].type);
  if (item.name === null) return String(group.rows.length);
  const values = group.rows.map(row => row.values[item.column]).filter(value => value !== null);
  if (item.function === 'COUNT') return String(item.distinct ? new Set(values).size : values.length);
  if (values.length === 0) return 'NULL';
  if (item.function === 'SUM' || item.function === 'AVG') {
    let total = 0;
    for (const value of values) total += value;
    return item.function === 'SUM' ? String(total) : fraction(total, values.length);
  }
  let chosen = values[0];
  for (const value of values) {
    const order = compare(value, chosen);
    if (item.function === 'MIN' ? order < 0 : order > 0) chosen = value;
  }
  return io.valueText(chosen, schema[item.column].type);
}

function buildResult(query: Query, rows: {number: number; values: Cell[]}[], schema: Column[]) {
  const kind = query.group !== null ? 'grouped' : query.aggregate ? 'aggregate' : 'rows';
  let output;
  if (kind === 'rows') {
    const arranged = rows.slice();
    if (query.order !== null) {
      const {column, descending} = query.order;
      arranged.sort((a, b) => (descending ? -1 : 1) * compare(a.values[column], b.values[column]) || a.number - b.number);
    }
    output = arranged.map(row => query.items.map(item => io.valueText(row.values[item.column], schema[item.column].type)).join(','));
  } else {
    let groups;
    if (kind === 'aggregate') groups = [{key: null, rows}];
    else {
      const grouped = new Map();
      for (const row of rows) {
        const key = row.values[query.groupColumn];
        if (!grouped.has(key)) grouped.set(key, []);
        grouped.get(key).push(row);
      }
      groups = [...grouped].map(([key, members]) => ({key, rows: members}));
      groups.sort((a, b) => compare(a.key, b.key));
    }
    output = groups.map(group => query.items.map(item => aggregateItem(item, group, schema)).join(','));
  }
  if (query.limit !== null) output = output.slice(0, query.limit);
  return {kind, matched: rows.length, output};
}

function countText(counts: Record<string, number>): string {
  return scanFields.map(field => `${field} ${counts[field]}`).join(' ');
}

function queryReports(file: ParsedFile, input: Input): {results: string[]; stats: string[]} {
  const results = [];
  const stats = [];
  const totals = emptyCounts();
  let errors = 0;
  let checks = 0;
  for (let index = 0; index < input.queries.length; index++) {
    const number = index + 1;
    const query = queryParser.parse(input.queries[index]);
    const error = checkQuery(query, file.schema);
    if (error !== null) {
      results.push(`query ${number} error ${error}`);
      stats.push(`query ${number} error ${error}`);
      errors++;
      continue;
    }
    const scanned = scan(file, query);
    const result = buildResult(query, scanned.rows, file.schema);
    const original = [];
    for (let row = 0; row < input.table.length; row++) {
      if (evaluate(query.condition, input.table[row]) === TRUE) original.push({number: row, values: input.table[row]});
    }
    const reference = buildResult(query, original, input.schema);
    const agrees = result.kind === reference.kind && result.matched === reference.matched &&
      result.output.length === reference.output.length && result.output.every((row, position) => row === reference.output[position]);
    const check = agrees ? 'ok' : 'mismatch';
    if (agrees) checks++;
    results.push(`query ${number} ${result.kind} matched ${result.matched} output ${result.output.length}`);
    results.push(`columns ${query.headers.join(',')}`);
    append(results, result.output);
    const needed = query.needed.map(column => file.schema[column].name).join(',') || '-';
    stats.push(`query ${number} columns ${needed} ${countText(scanned.counts)} check ${check}`);
    for (const record of scanned.records) {
      stats.push(`query ${number} row_group ${record.number} ` + (record.skipped ? 'skipped' : `pages ${record.pages}`));
    }
    for (const field of scanFields) totals[field] += scanned.counts[field];
  }
  stats.push(`total queries ${input.queries.length} errors ${errors} ${countText(totals)} checks_ok ${checks}`);
  return {results, stats};
}

function recover(bytes: Buffer): {lines: string[]; recovered: string[]} {
  const file = parseFile(bytes);
  const table = Array.from({length: file.rowCount}, () => Array(file.schema.length).fill(LOST));
  const lines = [`file bytes ${bytes.length} rows ${file.rowCount} columns ${file.schema.length} row_groups ${file.groups.length}`];
  append(lines, columnLines(file.schema));
  let pages = 0;
  let damaged = 0;
  let lostPages = 0;
  let lostCells = 0;
  for (const group of file.groups) {
    for (const chunk of group.chunks) {
      let dictionary = [];
      let dictionaryDamaged = false;
      for (const page of chunk.pages) {
        pages++;
        const computed = adler32(bodyOf(file, page));
        const bad = computed !== page.checksum;
        if (bad) {
          damaged++;
          lines.push(`damaged ${group.number} ${chunk.column.name} ${page.kind === 1 ? 'dict' : page.number} ` +
            `offset ${page.offset} stored ${checksumText(page.checksum)} computed ${checksumText(computed)}`);
        }
        if (page.kind === 1) {
          dictionaryDamaged = bad;
          if (!bad) dictionary = decodeDictionary(file, chunk);
          continue;
        }
        const reason = bad ? 'checksum' : page.method === 1 && dictionaryDamaged ? 'dictionary' : null;
        if (reason !== null) {
          lostPages++;
          lostCells += page.count;
          lines.push(`lost ${group.number} ${chunk.column.name} ${page.number} rows ${page.count} reason ${reason}`);
        } else {
          const values = decodePage(file, chunk, page, dictionary);
          for (let index = 0; index < values.length; index++) table[page.firstRow + index][chunk.column.number] = values[index];
        }
      }
    }
  }
  lines.push(`summary pages ${pages} damaged ${damaged} lost_pages ${lostPages} lost_cells ${lostCells} ` +
    `recovered_cells ${file.rowCount * file.schema.length - lostCells}`);
  const recovered = [file.schema.map(column => column.name).join(',')];
  for (const row of table) {
    recovered.push(row.map((value, column) => value === LOST ? '?' : io.valueText(value, file.schema[column].type, true)).join(','));
  }
  return {lines, recovered};
}

function main(): void {
  const input = io.readInputs();
  const written = writeTable(input);
  const file = parseFile(written.bytes);
  const verification = metadata(file, input.table);
  const queries = queryReports(file, input);
  const recovery = recover(input.damaged);
  const hex = [];
  for (let start = 0; start < written.bytes.length; start += 32) hex.push(written.bytes.subarray(start, start + 32).toString('hex'));
  io.writeFiles({'file.hex': hex, 'metadata.txt': verification, 'encoding_report.csv': written.report,
    'query_results.txt': queries.results, 'query_stats.txt': queries.stats,
    'recovery.txt': recovery.lines, 'recovered.csv': recovery.recovered});
}

main();
