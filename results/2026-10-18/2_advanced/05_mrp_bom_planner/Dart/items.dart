import 'dart:io';

typedef Row = ({int line, List<String> fields});

List<Row> readRows(String name) => File('input/$name').readAsLinesSync().skip(1).indexed.map((entry) => (line: entry.$1 + 2, fields: entry.$2.split(','))).toList();

class Item {
  final String id, rule, description;
  final int lead, safety, onHand, material, labor;
  final List<int> lot;
  Item(List<String> fields, this.lot)
      : id = fields[0], lead = int.parse(fields[1]), rule = fields[2], safety = int.parse(fields[4]),
        onHand = int.parse(fields[5]), material = int.parse(fields[6]), labor = int.parse(fields[7]), description = fields[8];
  String get lotLabel => rule == 'LFL' ? rule : '$rule ${lot.join(rule == 'MIN' ? '/' : '')}';
}

List<int>? lotValues(String rule, String text) {
  final values = text.split('/').map(int.parse).toList();
  final valid = rule == 'MIN' ? values.length == 2 && values.every((v) => v >= 1) : values.length == 1 && (rule == 'LFL' ? values[0] == 0 : values[0] >= 1);
  return valid ? values : null;
}

Map<String, Item> readItems(List<String> errors) {
  final items = <String, Item>{};
  for (final row in readRows('items.csv')) {
    final f = row.fields, id = f[0], rule = f[2], lot = f[3];
    final values = lotValues(rule, lot);
    final reason = items.containsKey(id) ? 'duplicate item $id' : !['LFL', 'FOQ', 'POQ', 'MIN'].contains(rule) ? 'unknown lot rule $rule' : values == null ? 'bad lot parameter $lot for $rule' : null;
    if (reason != null) { errors.add('items.csv line ${row.line}: $reason'); } else { items[id] = Item(f, values!); }
  }
  return items;
}
