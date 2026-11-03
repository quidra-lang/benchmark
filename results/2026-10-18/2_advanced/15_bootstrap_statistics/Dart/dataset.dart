import 'dart:io';

class Group {
  final int number;
  final String name;
  final values = <int>[];
  Group(this.number, this.name);
}

class PairedSample {
  final List<int> before, after, differences;
  PairedSample(this.before, this.after)
      : differences = [for (var index = 0; index < before.length; index++) after[index] - before[index]];
}

class Settings {
  final int seed, bootstrap, permutations, confidence, pilot, powerSims, powerPerms, bins;
  Settings(Map<String, List<int>> entries)
      : seed = entries['seed']![0], bootstrap = entries['bootstrap']![0],
        permutations = entries['permutations']![0], confidence = entries['confidence']![0],
        pilot = entries['pilot']![0], powerSims = entries['power']![0],
        powerPerms = entries['power']![1], bins = entries['bins']![0];
}

class Dataset {
  final List<Group> groups;
  final PairedSample paired;
  final List<(Group, Group)> pairs;
  final Settings settings;
  Dataset(this.groups, this.paired, this.pairs, this.settings);
}

List<String> readLines(String path) => File(path).readAsLinesSync();

int hundredths(String text) {
  final parts = text.split('.');
  final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return int.parse(parts[0]) * 100 + int.parse(fraction);
}

Dataset loadDataset() {
  final groups = <Group>[], byName = <String, Group>{};
  for (final line in readLines('input/samples.csv').skip(1)) {
    final fields = line.split(',');
    final group = byName.putIfAbsent(fields[0], () {
      final group = Group(groups.length + 1, fields[0]);
      groups.add(group);
      return group;
    });
    group.values.add(hundredths(fields[1]));
  }
  final before = <int>[], after = <int>[];
  for (final line in readLines('input/paired.csv').skip(1)) {
    final fields = line.split(',');
    before.add(hundredths(fields[1]));
    after.add(hundredths(fields[2]));
  }
  final entries = <String, List<int>>{}, pairs = <(Group, Group)>[];
  for (final line in readLines('input/params.txt')) {
    final fields = line.split(' ');
    if (fields[0] == 'compare') {
      pairs.add((byName[fields[1]]!, byName[fields[2]]!));
    } else {
      entries[fields[0]] = fields.skip(1).map(int.parse).toList();
    }
  }
  return Dataset(groups, PairedSample(before, after), pairs, Settings(entries));
}
