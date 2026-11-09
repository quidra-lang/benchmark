part of 'main.dart';

class Production {
  final int number;
  final String lhs;
  final List<String> rhs;
  final predict = <String, String>{};
  String get notation => productionNotation(lhs, rhs);
  Production(this.number, this.lhs, this.rhs);
}

class TableEntry {
  final int number;
  final String reason;
  TableEntry(this.number, this.reason);
}

class Conflict {
  final String lhs, token, kind;
  final List<TableEntry> entries;
  final int chosen;
  Conflict(this.lhs, this.token, this.kind, this.entries, this.chosen);
}

class ParseTable {
  final List<Production> productions;
  final cells = <(String, String), List<TableEntry>>{},
      choices = <(String, String), int>{};
  final conflicts = <Conflict>[];
  ParseTable(this.productions);
}

List<Production> numberProductions(Grammar g) {
  final result = <Production>[];
  for (final lhs in g.order) {
    for (final rhs in g.rules[lhs]!) {
      result.add(Production(result.length + 1, lhs, rhs));
    }
  }
  return result;
}

ParseTable buildTable(Grammar g, Sets sets) {
  final table = ParseTable(numberProductions(g));
  for (final p in table.productions) {
    final (direct, empty) = firstSequence(p.rhs, sets.nullable, sets.first);
    for (final t in direct) {
      p.predict[t] = 'FIRST';
    }
    if (empty) {
      for (final t in sets.follow[p.lhs]!) {
        p.predict.putIfAbsent(t, () => 'FOLLOW');
      }
    }
    for (final entry in p.predict.entries) {
      table.cells
          .putIfAbsent((p.lhs, entry.key), () => [])
          .add(TableEntry(p.number, entry.value));
    }
  }
  for (final lhs in g.order) {
    for (final token in [...sets.terminals, endToken]) {
      final key = (lhs, token), entries = table.cells[key] ?? <TableEntry>[];
      if (entries.isEmpty) {
        continue;
      }
      var chosen = entries.first.number, hasFirst = false, hasFollow = false;
      for (final entry in entries) {
        if (entry.reason == 'FIRST') {
          if (!hasFirst) {
            chosen = entry.number;
          }
          hasFirst = true;
        } else {
          hasFollow = true;
        }
      }
      table.choices[key] = chosen;
      if (entries.length > 1) {
        table.conflicts.add(
          Conflict(
            lhs,
            token,
            !hasFirst
                ? 'FOLLOW/FOLLOW'
                : !hasFollow
                ? 'FIRST/FIRST'
                : 'FIRST/FOLLOW',
            entries,
            chosen,
          ),
        );
      }
    }
  }
  return table;
}
