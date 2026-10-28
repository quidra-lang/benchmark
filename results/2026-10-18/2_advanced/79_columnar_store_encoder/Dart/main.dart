import 'dart:io';
import 'dart:math';
part 'schema_io.dart';
part 'bitstream.dart';
part 'encoding.dart';
part 'query.dart';

class Zone {
  Value lo = const Value(), hi = const Value();
  bool has = false;
  int nulls = 0, rows = 0;
}

class Page {
  int kind = 0,
      method = 0,
      count = 0,
      nulls = 0,
      offset = 0,
      header = 0,
      body = 0,
      checksum = 0;
  Zone zone = Zone();
}

class Chunk {
  int offset = 0, size = 0, nulls = 0;
  List<int> methods = [];
  bool dictionary = false;
  Zone zone = Zone();
  final List<Page> pages = [], dataPages = [];
}

class RowGroup {
  final int rows, first;
  final List<Chunk> chunks = [];
  RowGroup(this.rows, this.first);
}

class Candidate {
  final List<int> data = [];
  int fallback = 0, k = 0;
  List<Value> dictionary = [];
  final List<int> methods = [];
}

int compare(Value a, Value b, String kind) {
  if (a.isNull) return b.isNull ? 0 : -1;
  if (b.isNull) return 1;
  return kind == 'STRING'
      ? a.text.compareTo(b.text)
      : a.number.compareTo(b.number);
}

bool equal(Value a, Value b, String kind) =>
    a.isNull == b.isNull && (a.isNull || compare(a, b, kind) == 0);
Zone statistics(List<Value> a, String kind) {
  final z = Zone()..rows = a.length;
  for (final v in a) {
    if (v.isNull) {
      z.nulls++;
      continue;
    }
    if (!z.has) {
      z.lo = v;
      z.hi = v;
      z.has = true;
    } else {
      if (compare(v, z.lo, kind) < 0) z.lo = v;
      if (compare(v, z.hi, kind) > 0) z.hi = v;
    }
  }
  return z;
}

void writeZone(List<int> out, Zone z, String kind) {
  out.add(z.has ? 1 : 0);
  if (z.has) {
    writeStatValue(out, z.lo, kind);
    writeStatValue(out, z.hi, kind);
  }
}

Zone readZone(Reader r, String kind) {
  final z = Zone();
  if (r.byte() != 0) {
    z.has = true;
    z.lo = readStatValue(r, kind);
    z.hi = readStatValue(r, kind);
  }
  return z;
}

String zoneText(Zone z, String kind) => z.has
    ? 'min ${valueText(z.lo, kind)} max ${valueText(z.hi, kind)}'
    : 'stats none';
List<int> makePage(
  int kind,
  int method,
  int count,
  int nulls,
  List<int> body,
  Zone zone,
  Column column,
) {
  final out = [kind, method];
  appendULEB(out, count);
  appendULEB(out, nulls);
  appendULEB(out, body.length);
  appendU32(out, adler(body));
  writeZone(out, zone, column.kind);
  out.addAll(body);
  return out;
}

Candidate makeCandidate(
  List<Value> values,
  Column column,
  int method,
  Options options,
) {
  final pages = [
        for (var start = 0; start < values.length; start += options.page)
          values.sublist(start, min(start + options.page, values.length)),
      ],
      candidate = Candidate();
  if (method == 1) {
    final seen = <String>{};
    for (final page in pages) {
      final proposed = List<Value>.of(candidate.dictionary), added = <String>{};
      for (final v in page) {
        if (v.isNull) continue;
        final key = dictionaryKey(v, column.kind);
        if (!seen.contains(key) && added.add(key)) proposed.add(v);
      }
      if (encodeValues(proposed, column.kind, 0, []).length > options.limit)
        break;
      candidate.dictionary = proposed;
      seen.addAll(added);
      candidate.k++;
    }
    if (candidate.dictionary.isEmpty) candidate.k = 0;
    candidate.fallback = pages.length - candidate.k;
    if (candidate.k > 0) {
      final body = encodeValues(candidate.dictionary, column.kind, 0, []);
      candidate.data.addAll(
        makePage(1, 0, candidate.dictionary.length, 0, body, Zone(), column),
      );
    }
  }
  final methods = <int>{};
  for (var p = 0; p < pages.length; p++) {
    final page = pages[p],
        encoding = method == 1 && p >= candidate.k ? 0 : method,
        body = <int>[];
    methods.add(encoding);
    if (column.nullable) {
      final levels = [for (final v in page) v.isNull ? 0 : 1],
          encoded = encodeHybrid(levels, 1);
      appendU32(body, encoded.length);
      body.addAll(encoded);
    }
    body.addAll(
      encodeValues(
        [
          for (final v in page)
            if (!v.isNull) v,
        ],
        column.kind,
        encoding,
        candidate.dictionary,
      ),
    );
    final z = statistics(page, column.kind);
    candidate.data.addAll(
      makePage(0, encoding, page.length, z.nulls, body, z, column),
    );
  }
  candidate.methods.addAll(methods.toList()..sort());
  return candidate;
}

(List<int>, List<String>) buildStore(
  List<Column> schema,
  List<List<Value>> rows,
  Options options,
) {
  final data = 'MPTC'.codeUnits.toList(),
      groups = <RowGroup>[],
      report = ['row_group,column,encoding,bytes,fallback_pages,chosen'];
  for (var first = 0; first < rows.length; first += options.rows) {
    final g = groups.length,
        end = min(first + options.rows, rows.length),
        group = RowGroup(end - first, first);
    for (var c = 0; c < schema.length; c++) {
      final column = schema[c],
          values = [for (var i = first; i < end; i++) rows[i][c]],
          all = {
            for (final method in candidates(column.kind))
              method: makeCandidate(values, column, method, options),
          };
      var chosen = options.methods[c];
      if (chosen < 0) {
        chosen = candidates(column.kind)[0];
        for (final method in candidates(column.kind)) {
          if (all[method]!.data.length < all[chosen]!.data.length)
            chosen = method;
        }
      }
      if (chosen == 1 && all[1]!.k == 0) chosen = 0;
      for (final method in candidates(column.kind)) {
        final candidate = all[method]!;
        report.add(
          '$g,${column.name},${methodNames[method]},${candidate.data.length},${candidate.fallback},${method == chosen ? 'yes' : 'no'}',
        );
      }
      final candidate = all[chosen]!,
          z = statistics(values, column.kind),
          chunk = Chunk()
            ..offset = data.length
            ..size = candidate.data.length
            ..nulls = z.nulls
            ..methods = List.of(candidate.methods)
            ..dictionary = chosen == 1 && candidate.k > 0
            ..zone = z;
      group.chunks.add(chunk);
      data.addAll(candidate.data);
    }
    groups.add(group);
  }
  final footer = <int>[];
  appendULEB(footer, 1);
  appendULEB(footer, schema.length);
  for (final column in schema) {
    appendULEB(footer, column.name.length);
    footer.addAll(column.name.codeUnits);
    footer.add(typeNames.indexOf(column.kind));
    footer.add(column.nullable ? 1 : 0);
  }
  appendULEB(footer, rows.length);
  appendULEB(footer, groups.length);
  for (final group in groups) {
    appendULEB(footer, group.rows);
    for (var c = 0; c < group.chunks.length; c++) {
      final chunk = group.chunks[c];
      appendULEB(footer, chunk.offset);
      appendULEB(footer, chunk.size);
      appendULEB(footer, chunk.methods.length);
      footer.addAll(chunk.methods);
      footer.add(chunk.dictionary ? 1 : 0);
      appendULEB(footer, (group.rows + options.page - 1) ~/ options.page);
      appendULEB(footer, chunk.nulls);
      writeZone(footer, chunk.zone, schema[c].kind);
    }
  }
  data.addAll(footer);
  appendU32(data, footer.length);
  data.addAll('MPTC'.codeUnits);
  return (data, report);
}

String methodsText(List<int> methods) =>
    methods.map((m) => methodNames[m]).join(',');
List<String> columnLines(List<Column> schema) => [
  for (var c = 0; c < schema.length; c++)
    'column $c ${schema[c].name} ${schema[c].kind} ${schema[c].nullable ? 'NULLABLE' : 'REQUIRED'}',
];

class Store {
  final List<int> data;
  int version = 0, rows = 0, footerOffset = 0, footerBytes = 0;
  final List<Column> schema = [];
  final List<RowGroup> groups = [];
  Store(this.data);
  List<int> body(Page page) => data.sublist(
    page.offset + page.header,
    page.offset + page.header + page.body,
  );
  List<Value> dictionary(Chunk chunk, Column column) {
    if (!chunk.dictionary) return [];
    final page = chunk.pages[0];
    return decodeValues(Reader(body(page)), page.count, column.kind, 0, []);
  }

  List<Value> decode(Page page, Column column, List<Value> dictionary) {
    final r = Reader(body(page));
    var levels = List.filled(page.count, 1);
    if (column.nullable) {
      final reader = Reader(r.take(r.u32()));
      levels = decodeHybrid(reader, page.count, 1);
    }
    final values = decodeValues(
          r,
          levels.where((v) => v == 1).length,
          column.kind,
          page.method,
          dictionary,
        ),
        out = <Value>[];
    var at = 0;
    for (final level in levels) {
      out.add(level == 0 ? const Value(isNull: true) : values[at++]);
    }
    return out;
  }

  List<String> metadata(List<List<Value>> original) {
    final out = [
          'file bytes ${data.length} footer_offset $footerOffset footer_bytes $footerBytes',
          'table version $version rows $rows columns ${schema.length} row_groups ${groups.length}',
          ...columnLines(schema),
        ],
        bytesByColumn = List.filled(schema.length, 0),
        pagesByColumn = List.filled(schema.length, 0),
        dictionaries = List.filled(schema.length, 0),
        methods = List.generate(schema.length, (_) => <int>{});
    var cells = 0, nulls = 0, mismatches = 0, checksums = 0;
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g],
          size = group.chunks.fold(0, (a, c) => a + c.size);
      out.add(
        'row_group $g rows ${group.rows} first_row ${group.first} bytes $size',
      );
      for (var c = 0; c < schema.length; c++) {
        final chunk = group.chunks[c], column = schema[c];
        if (chunk.dictionary) dictionaries[c]++;
        bytesByColumn[c] += chunk.size;
        pagesByColumn[c] += chunk.dataPages.length;
        methods[c].addAll(chunk.methods);
        out.add(
          'chunk $g ${column.name} offset ${chunk.offset} size ${chunk.size} encodings ${methodsText(chunk.methods)} dictionary ${chunk.dictionary ? 'yes' : 'no'} pages ${chunk.dataPages.length} nulls ${chunk.nulls} ${zoneText(chunk.zone, column.kind)}',
        );
        final dictionary = this.dictionary(chunk, column);
        var pageNumber = 0, row = group.first;
        for (final page in chunk.pages) {
          if (adler(body(page)) != page.checksum) checksums++;
          final prefix = 'page $g ${column.name} ';
          if (page.kind == 1) {
            out.add(
              '${prefix}dict offset ${page.offset} header ${page.header} body ${page.body} checksum ${formatChecksum(page.checksum)} entries ${page.count}',
            );
            continue;
          }
          out.add(
            '$prefix$pageNumber offset ${page.offset} header ${page.header} body ${page.body} checksum ${formatChecksum(page.checksum)} encoding ${methodNames[page.method]} values ${page.count} nulls ${page.nulls} ${zoneText(page.zone, column.kind)}',
          );
          pageNumber++;
          for (final value in decode(page, column, dictionary)) {
            cells++;
            if (value.isNull) nulls++;
            if (!equal(value, original[row][c], column.kind)) mismatches++;
            row++;
          }
        }
      }
    }
    for (var c = 0; c < schema.length; c++) {
      out.add(
        'summary ${schema[c].name} bytes ${bytesByColumn[c]} data_pages ${pagesByColumn[c]} dictionary_pages ${dictionaries[c]} encodings ${methodsText(methods[c].toList()..sort())}',
      );
    }
    out.add(
      'roundtrip ${mismatches == 0 && checksums == 0 ? 'ok' : 'failed'} cells $cells nulls $nulls mismatches $mismatches checksum_errors $checksums',
    );
    return out;
  }

  Scan scan(Query q) {
    final out = Scan(), dictionaries = <Chunk, List<Value>>{};
    List<Value> read(Chunk chunk, Page page, Column column) {
      if (page.method == 1 && !dictionaries.containsKey(chunk)) {
        dictionaries[chunk] = dictionary(chunk, column);
        final dictPage = chunk.pages[0];
        out.counts[5]++;
        out.counts[6] += dictPage.header + dictPage.body;
      }
      out.counts[2]++;
      out.counts[6] += page.header + page.body;
      return decode(page, column, dictionaries[chunk] ?? []);
    }

    for (final group in groups) {
      var zones = [for (final chunk in group.chunks) chunk.zone];
      if (q.condition != null &&
          (zoneValues(q.condition, zones, schema) & 2) == 0) {
        out.counts[1]++;
        out.records.add('skipped');
        continue;
      }
      out.counts[0]++;
      if (q.needed.isEmpty) {
        out.counts[7] += group.rows;
        for (var row = 0; row < group.rows; row++) {
          out.rows.add(Row(group.first + row, nullRow(schema.length)));
        }
        out.records.add('-');
        continue;
      }
      var record = '', first = group.first;
      for (var p = 0; p < group.chunks[0].dataPages.length; p++) {
        final count = group.chunks[0].dataPages[p].count;
        zones = [for (final chunk in group.chunks) chunk.dataPages[p].zone];
        if (q.condition != null &&
            (zoneValues(q.condition, zones, schema) & 2) == 0) {
          record += 's';
          out.counts[3] += q.needed.length;
          first += count;
          continue;
        }
        out.counts[7] += count;
        final rows = List.generate(count, (_) => nullRow(schema.length));
        for (final c in q.conditionColumns) {
          final values = read(
            group.chunks[c],
            group.chunks[c].dataPages[p],
            schema[c],
          );
          for (var i = 0; i < values.length; i++) {
            rows[i][c] = values[i];
          }
        }
        final selected = [
          for (var i = 0; i < rows.length; i++)
            if (conditionValue(q.condition, rows[i], schema) == 1) i,
        ];
        if (selected.isEmpty && q.remaining.isNotEmpty) {
          record += 'u';
          out.counts[4] += q.remaining.length;
        } else {
          record += 'r';
          for (final c in q.remaining) {
            final values = read(
              group.chunks[c],
              group.chunks[c].dataPages[p],
              schema[c],
            );
            for (var i = 0; i < values.length; i++) {
              rows[i][c] = values[i];
            }
          }
          for (final i in selected) {
            out.rows.add(Row(first + i, rows[i]));
          }
        }
        first += count;
      }
      out.records.add(record);
    }
    out.counts[8] = out.rows.length;
    return out;
  }

  (List<String>, List<String>) queries(List<List<Value>> original) {
    final results = <String>[],
        stats = <String>[],
        total = List.filled(9, 0),
        queries = readLines('input/queries.txt');
    var errors = 0, checks = 0;
    for (var i = 0; i < queries.length; i++) {
      final number = i + 1,
          q = parseQuery(queries[i]),
          errorCode = checkQuery(q, schema);
      if (errorCode.isNotEmpty) {
        errors++;
        final line = 'query $number error $errorCode';
        results.add(line);
        stats.add(line);
        continue;
      }
      final scan = this.scan(q),
          result = buildResult(q, scan.rows, schema),
          direct = [
            for (var row = 0; row < original.length; row++)
              if (conditionValue(q.condition, original[row], schema) == 1)
                Row(row, original[row]),
          ],
          check = sameResult(result, buildResult(q, direct, schema))
              ? 'ok'
              : 'mismatch';
      if (check == 'ok') checks++;
      results.addAll([
        'query $number ${result.kind} matched ${result.matched} output ${result.rows.length}',
        'columns ${queryHeaders(q)}',
        ...result.rows,
      ]);
      final names = [for (final c in q.needed) schema[c].name];
      stats.add(
        'query $number columns ${names.isEmpty ? '-' : names.join(',')} ${scanCounts(scan.counts)} check $check',
      );
      for (var g = 0; g < scan.records.length; g++) {
        final record = scan.records[g];
        stats.add(
          record == 'skipped'
              ? 'query $number row_group $g skipped'
              : 'query $number row_group $g pages $record',
        );
      }
      for (var j = 0; j < 9; j++) {
        total[j] += scan.counts[j];
      }
    }
    stats.add(
      'total queries ${queries.length} errors $errors ${scanCounts(total)} checks_ok $checks',
    );
    return (results, stats);
  }

  (List<String>, List<String>) recover() {
    final out = [
          'file bytes ${data.length} rows $rows columns ${schema.length} row_groups ${groups.length}',
          ...columnLines(schema),
        ],
        values = List.generate(
          rows,
          (_) => List.filled(schema.length, const Value(unknown: true)),
        );
    var pages = 0, damaged = 0, lost = 0, lostCells = 0;
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      for (var c = 0; c < schema.length; c++) {
        final chunk = group.chunks[c], column = schema[c];
        var dictionary = <Value>[],
            dictionaryDamaged = false,
            row = group.first,
            pageNumber = 0;
        for (final page in chunk.pages) {
          pages++;
          final computed = adler(body(page)),
              bad = computed != page.checksum,
              label = page.kind == 1 ? 'dict' : '$pageNumber';
          if (bad) {
            damaged++;
            out.add(
              'damaged $g ${column.name} $label offset ${page.offset} stored ${formatChecksum(page.checksum)} computed ${formatChecksum(computed)}',
            );
          }
          if (page.kind == 1) {
            dictionaryDamaged = bad;
            if (!bad)
              dictionary = decodeValues(
                Reader(body(page)),
                page.count,
                column.kind,
                0,
                [],
              );
            continue;
          }
          final reason = bad
              ? 'checksum'
              : page.method == 1 && dictionaryDamaged
              ? 'dictionary'
              : '';
          if (reason.isNotEmpty) {
            lost++;
            lostCells += page.count;
            out.add(
              'lost $g ${column.name} $pageNumber rows ${page.count} reason $reason',
            );
          } else {
            final decoded = decode(page, column, dictionary);
            for (var i = 0; i < decoded.length; i++) {
              values[row + i][c] = decoded[i];
            }
          }
          row += page.count;
          pageNumber++;
        }
      }
    }
    out.add(
      'summary pages $pages damaged $damaged lost_pages $lost lost_cells $lostCells recovered_cells ${rows * schema.length - lostCells}',
    );
    final csv = [
      schema.map((c) => c.name).join(','),
      for (final row in values)
        [
          for (var c = 0; c < schema.length; c++)
            valueText(row[c], schema[c].kind, true),
        ].join(','),
    ];
    return (out, csv);
  }
}

Store parseStore(List<int> data) {
  final tail = Reader(data, data.length - 8),
      size = tail.u32(),
      position = data.length - 8 - size,
      r = Reader(data, position),
      store = Store(data)
        ..footerOffset = position
        ..footerBytes = size
        ..version = r.uleb();
  final columns = r.uleb();
  for (var c = 0; c < columns; c++) {
    final name = String.fromCharCodes(r.take(r.uleb())),
        kind = typeNames[r.byte()],
        nullable = r.byte() != 0;
    store.schema.add(Column(name, kind, nullable));
  }
  store.rows = r.uleb();
  final count = r.uleb();
  var first = 0;
  for (var g = 0; g < count; g++) {
    final group = RowGroup(r.uleb(), first);
    first += group.rows;
    for (var c = 0; c < columns; c++) {
      final chunk = Chunk()
        ..offset = r.uleb()
        ..size = r.uleb();
      final methods = r.uleb();
      chunk.methods = [for (var i = 0; i < methods; i++) r.byte()];
      chunk.dictionary = r.byte() != 0;
      r.uleb();
      chunk.nulls = r.uleb();
      chunk.zone = readZone(r, store.schema[c].kind)
        ..nulls = chunk.nulls
        ..rows = group.rows;
      group.chunks.add(chunk);
    }
    store.groups.add(group);
  }
  for (final group in store.groups) {
    for (var c = 0; c < columns; c++) {
      final chunk = group.chunks[c], p = Reader(data, chunk.offset);
      while (p.position < chunk.offset + chunk.size) {
        final offset = p.position,
            page = Page()
              ..offset = offset
              ..kind = p.byte()
              ..method = p.byte()
              ..count = p.uleb()
              ..nulls = p.uleb()
              ..body = p.uleb()
              ..checksum = p.u32();
        page.zone = readZone(p, store.schema[c].kind)
          ..nulls = page.nulls
          ..rows = page.count;
        page.header = p.position - page.offset;
        chunk.pages.add(page);
        if (page.kind == 0) chunk.dataPages.add(page);
        p.position += page.body;
      }
    }
  }
  return store;
}

String checkQuery(Query q, List<Column> schema) {
  final byName = {for (var c = 0; c < schema.length; c++) schema[c].name: c};
  if (q.star) {
    q.items.addAll([for (final column in schema) Item(column.name)]);
  }
  final leaves = conditionLeaves(q.condition);
  var unknown = false;
  for (final item in q.items) {
    if (item.column == '*') continue;
    final index = byName[item.column];
    if (index == null) {
      unknown = true;
    } else {
      item.index = index;
    }
  }
  for (final condition in leaves) {
    final index = byName[condition.column];
    if (index == null) {
      unknown = true;
    } else {
      condition.index = index;
    }
  }
  if (q.group.isNotEmpty) {
    final index = byName[q.group];
    if (index == null) {
      unknown = true;
    } else {
      q.groupIndex = index;
    }
  }
  if (q.order.isNotEmpty) {
    final index = byName[q.order];
    if (index == null) {
      unknown = true;
    } else {
      q.orderIndex = index;
    }
  }
  if (unknown) return 'unknown_column';
  for (final condition in leaves) {
    final kind = schema[condition.index].kind,
        expected = kind == 'DATE' ? 'STRING' : kind;
    for (final literal in condition.literals) {
      if (literal.kind != expected) return 'type_mismatch';
    }
  }
  for (final item in q.items) {
    if ((item.op == 'SUM' || item.op == 'AVG') &&
        schema[item.index].kind != 'INT')
      return 'bad_aggregate';
  }
  if (q.aggregate) {
    for (final item in q.items) {
      if (item.op.isEmpty && (q.group.isEmpty || item.column != q.group))
        return 'not_grouped';
    }
    if (q.order.isNotEmpty) return 'bad_order';
  }
  for (final condition in leaves) {
    if (schema[condition.index].kind == 'DATE') {
      for (final literal in condition.literals) {
        literal.value = Value(number: dateNumber(literal.value.text));
      }
    }
  }
  final needed = <int>{}, conditions = <int>{};
  for (final item in q.items) {
    if (item.column != '*') needed.add(item.index);
  }
  for (final condition in leaves) {
    needed.add(condition.index);
    conditions.add(condition.index);
  }
  if (q.groupIndex >= 0) needed.add(q.groupIndex);
  if (q.orderIndex >= 0) needed.add(q.orderIndex);
  for (var c = 0; c < schema.length; c++) {
    if (needed.contains(c)) {
      q.needed.add(c);
      if (conditions.contains(c)) {
        q.conditionColumns.add(c);
      } else {
        q.remaining.add(c);
      }
    }
  }
  return '';
}

int logical(String op, int a, int b) {
  if (op == 'NOT') return a == 2 ? 2 : 1 - a;
  if (op == 'AND')
    return a == 0 || b == 0
        ? 0
        : a == 2 || b == 2
        ? 2
        : 1;
  return a == 1 || b == 1
      ? 1
      : a == 2 || b == 2
      ? 2
      : 0;
}

int conditionValue(Condition? c, List<Value> row, List<Column> schema) {
  if (c == null) return 1;
  if (c.children.isNotEmpty)
    return logical(
      c.op,
      conditionValue(c.children[0], row, schema),
      c.children.length > 1 ? conditionValue(c.children[1], row, schema) : 0,
    );
  final v = row[c.index];
  if (c.op == 'IS NULL') return v.isNull ? 1 : 0;
  if (c.op == 'IS NOT NULL') return v.isNull ? 0 : 1;
  if (v.isNull) return 2;
  final kind = schema[c.index].kind;
  int compareLiteral(int i) => compare(v, c.literals[i].value, kind);
  final test = switch (c.op) {
    '=' => compareLiteral(0) == 0,
    '<>' => compareLiteral(0) != 0,
    '<' => compareLiteral(0) < 0,
    '<=' => compareLiteral(0) <= 0,
    '>' => compareLiteral(0) > 0,
    '>=' => compareLiteral(0) >= 0,
    'BETWEEN' => compareLiteral(0) >= 0 && compareLiteral(1) <= 0,
    'IN' => List.generate(
      c.literals.length,
      (i) => compareLiteral(i),
    ).contains(0),
    _ => false,
  };
  return test ? 1 : 0;
}

int zoneValues(Condition? c, List<Zone> zones, List<Column> schema) {
  if (c == null) return 2;
  if (c.children.isNotEmpty) {
    final a = zoneValues(c.children[0], zones, schema);
    var result = 0;
    if (c.op == 'NOT') {
      for (var v = 0; v < 3; v++) {
        if (((a >> v) & 1) != 0) result |= 1 << logical('NOT', v, 0);
      }
      return result;
    }
    final b = zoneValues(c.children[1], zones, schema);
    for (var x = 0; x < 3; x++) {
      for (var y = 0; y < 3; y++) {
        if (((a >> x) & 1) != 0 && ((b >> y) & 1) != 0)
          result |= 1 << logical(c.op, x, y);
      }
    }
    return result;
  }
  final z = zones[c.index];
  var result = 0;
  if (c.op == 'IS NULL' || c.op == 'IS NOT NULL') {
    var t = z.nulls > 0, f = z.nulls < z.rows;
    if (c.op == 'IS NOT NULL') {
      final old = t;
      t = f;
      f = old;
    }
    if (t) result |= 2;
    if (f) result |= 1;
    return result;
  }
  if (z.nulls > 0) result |= 4;
  if (!z.has) return result;
  final kind = schema[c.index].kind;
  int lo(int i) => compare(z.lo, c.literals[i].value, kind);
  int hi(int i) => compare(z.hi, c.literals[i].value, kind);
  var t = false, f = false;
  switch (c.op) {
    case '=':
      t = lo(0) <= 0 && hi(0) >= 0;
      f = !(lo(0) == 0 && hi(0) == 0);
      break;
    case '<>':
      t = !(lo(0) == 0 && hi(0) == 0);
      f = lo(0) <= 0 && hi(0) >= 0;
      break;
    case '<':
      t = lo(0) < 0;
      f = hi(0) >= 0;
      break;
    case '<=':
      t = lo(0) <= 0;
      f = hi(0) > 0;
      break;
    case '>':
      t = hi(0) > 0;
      f = lo(0) <= 0;
      break;
    case '>=':
      t = hi(0) >= 0;
      f = lo(0) < 0;
      break;
    case 'BETWEEN':
      t =
          lo(1) <= 0 &&
          hi(0) >= 0 &&
          compare(c.literals[0].value, c.literals[1].value, kind) <= 0;
      f = lo(0) < 0 || hi(1) > 0;
      break;
    case 'IN':
      var matchesSingleton = false;
      for (var i = 0; i < c.literals.length; i++) {
        if (lo(i) <= 0 && hi(i) >= 0) t = true;
        if (lo(i) == 0) matchesSingleton = true;
      }
      f = !(compare(z.lo, z.hi, kind) == 0 && matchesSingleton);
      break;
  }
  if (t) result |= 2;
  if (f) result |= 1;
  return result;
}

class Row {
  final int number;
  final List<Value> values;
  Row(this.number, this.values);
}

const scanNames = [
  'row_groups_read',
  'row_groups_skipped',
  'pages_read',
  'pages_skipped',
  'pages_unneeded',
  'dictionary_pages_read',
  'bytes_read',
  'rows_scanned',
  'rows_matched',
];

class Scan {
  final counts = List.filled(9, 0);
  final List<String> records = [];
  final List<Row> rows = [];
}

List<Value> nullRow(int n) => List.filled(n, const Value(isNull: true));
String valueKey(Value v, String kind) =>
    v.isNull ? 'N' : 'V${dictionaryKey(v, kind)}';
String aggregateItem(
  Item item,
  List<Row> rows,
  Value key,
  List<Column> schema,
) {
  if (item.op.isEmpty) return valueText(key, schema[item.index].kind);
  if (item.column == '*') return '${rows.length}';
  final kind = schema[item.index].kind,
      values = [
        for (final row in rows)
          if (!row.values[item.index].isNull) row.values[item.index],
      ];
  if (item.op == 'COUNT')
    return '${item.distinct ? {for (final v in values) valueKey(v, kind)}.length : values.length}';
  if (values.isEmpty) return 'NULL';
  if (item.op == 'SUM' || item.op == 'AVG') {
    var sum = values.fold(0, (a, v) => a + v.number);
    if (item.op == 'SUM') return '$sum';
    var n = values.length;
    final g = sum.abs().gcd(n);
    sum ~/= g;
    n ~/= g;
    return n == 1 ? '$sum' : '$sum/$n';
  }
  var best = values[0];
  for (final v in values.skip(1)) {
    final comparison = compare(v, best, kind);
    if (item.op == 'MIN' && comparison < 0 ||
        item.op == 'MAX' && comparison > 0)
      best = v;
  }
  return valueText(best, kind);
}

class QueryResult {
  final String kind;
  final int matched;
  List<String> rows = [];
  QueryResult(this.kind, this.matched);
}

class ResultGroup {
  final Value key;
  final List<Row> rows;
  ResultGroup(this.key, [List<Row>? rows]) : rows = rows ?? [];
}

QueryResult buildResult(Query q, List<Row> matched, List<Column> schema) {
  final result = QueryResult(
    q.aggregate ? (q.group.isEmpty ? 'aggregate' : 'grouped') : 'rows',
    matched.length,
  );
  if (!q.aggregate) {
    final rows = List<Row>.of(matched);
    if (q.order.isNotEmpty)
      rows.sort((a, b) {
        final comparison = compare(
          a.values[q.orderIndex],
          b.values[q.orderIndex],
          schema[q.orderIndex].kind,
        );
        return comparison == 0
            ? a.number.compareTo(b.number)
            : q.descending
            ? -comparison
            : comparison;
      });
    for (final row in rows) {
      result.rows.add(
        [
          for (final item in q.items)
            valueText(row.values[item.index], schema[item.index].kind),
        ].join(','),
      );
    }
  } else {
    final groups = <ResultGroup>[];
    if (q.group.isEmpty) {
      groups.add(ResultGroup(const Value(), matched));
    } else {
      final byKey = <String, ResultGroup>{}, kind = schema[q.groupIndex].kind;
      for (final row in matched) {
        final value = row.values[q.groupIndex], key = valueKey(value, kind);
        var group = byKey[key];
        if (group == null) {
          group = ResultGroup(value);
          byKey[key] = group;
          groups.add(group);
        }
        group.rows.add(row);
      }
      groups.sort((a, b) => compare(a.key, b.key, kind));
    }
    for (final group in groups) {
      result.rows.add(
        [
          for (final item in q.items)
            aggregateItem(item, group.rows, group.key, schema),
        ].join(','),
      );
    }
  }
  if (q.limit > 0 && result.rows.length > q.limit)
    result.rows = result.rows.take(q.limit).toList();
  return result;
}

bool sameResult(QueryResult a, QueryResult b) =>
    a.kind == b.kind &&
    a.matched == b.matched &&
    a.rows.length == b.rows.length &&
    List.generate(a.rows.length, (i) => a.rows[i] == b.rows[i]).every((v) => v);
String scanCounts(List<int> counts) =>
    [for (var i = 0; i < 9; i++) '${scanNames[i]} ${counts[i]}'].join(' ');
void main() {
  final schema = readSchema(),
      rows = readTable(schema),
      options = readOptions();
  final (data, encodingReport) = buildStore(schema, rows, options);
  final store = parseStore(data);
  final (queryResults, queryStats) = store.queries(rows);
  final (recovery, recovered) = parseStore(damagedBytes()).recover();
  final hexLines = [
    for (var at = 0; at < data.length; at += 32)
      data
          .sublist(at, min(at + 32, data.length))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
  ];
  Directory('output').createSync(recursive: true);
  writeLines('file.hex', hexLines);
  writeLines('metadata.txt', store.metadata(rows));
  writeLines('encoding_report.csv', encodingReport);
  writeLines('query_results.txt', queryResults);
  writeLines('query_stats.txt', queryStats);
  writeLines('recovery.txt', recovery);
  writeLines('recovered.csv', recovered);
}
