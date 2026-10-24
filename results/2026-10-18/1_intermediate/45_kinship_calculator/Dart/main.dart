import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

enum Sex {
  male, female, other;

  String get code => switch (this) { male => 'M', female => 'F', other => 'X' };
  static Sex parse(String code) =>
      switch (code) { 'M' => male, 'F' => female, _ => other };
}

enum MarriageStatus { current, divorced, widowed }

final class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

final class Fraction {
  final int numerator;
  final int power;
  const Fraction._(this.numerator, this.power);
  static const zero = Fraction._(0, 0);
  static const one = Fraction._(1, 0);

  factory Fraction(int numerator, int power) {
    if (numerator == 0) return zero;
    while (power > 0 && numerator.isEven) {
      numerator ~/= 2;
      power--;
    }
    return Fraction._(numerator, power);
  }

  Fraction operator +(Fraction other) {
    final exponent = math.max(power, other.power);
    return Fraction((numerator << (exponent - power)) +
        (other.numerator << (exponent - other.power)), exponent);
  }

  Fraction half() => Fraction(numerator, power + 1);
  @override
  String toString() => '$numerator/${1 << power}';
}

final class Person {
  final String id;
  final Sex sex;
  final int birth;
  final String name;
  int? death;
  final Set<String> parents;

  Person(this.id, this.sex, this.birth, this.name)
      : parents = <String>{};
  Person.copy(Person source)
      : id = source.id, sex = source.sex, birth = source.birth,
        name = source.name, death = source.death,
        parents = {...source.parents};
  String get life => '$birth-${death ?? ''}';
}

final class Marriage {
  final String first;
  final String second;
  final int start;
  final int? end;
  final MarriageStatus status;
  final String? died;

  const Marriage(this.first, this.second, this.start,
      [this.end, this.status = MarriageStatus.current, this.died]);
  bool contains(String id) => first == id || second == id;
  String other(String id) => first == id ? second : first;
  Marriage finish(int year, MarriageStatus status, [String? died]) =>
      Marriage(first, second, start, year, status, died);
}

final class Family {
  final people = SplayTreeMap<String, Person>();
  final marriages = <Marriage>[];

  Family();
  Family.copy(Family source) {
    for (final person in source.people.values) {
      people[person.id] = Person.copy(person);
    }
    marriages.addAll(source.marriages);
  }
}

final class Apex {
  final String id;
  final int a;
  final int b;
  final int share;
  const Apex(this.id, this.a, this.b, [this.share = 0]);
  bool get collateral => a > 0 && b > 0;
}

String gender(Sex sex, String male, String female, String neutral) =>
    switch (sex) { Sex.male => male, Sex.female => female, Sex.other => neutral };

String grand(int generation) =>
    generation == 1 ? '' : List.filled(generation - 2, 'great-').join() + 'grand';

String ordinal(int value) {
  const words = ['first', 'second', 'third', 'fourth', 'fifth',
    'sixth', 'seventh', 'eighth', 'ninth', 'tenth'];
  if (value <= 10) return words[value - 1];
  final suffix = switch (value % 100) {
    11 || 12 || 13 => 'th',
    _ => switch (value % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' },
  };
  return '$value$suffix';
}

String term(int a, int b, Sex sex) {
  if (a == 0 && b == 0) return 'self';
  if (a == 0) return grand(b) + gender(sex, 'father', 'mother', 'parent');
  if (b == 0) return grand(a) + gender(sex, 'son', 'daughter', 'child');
  if (a == 1 && b == 1) return gender(sex, 'brother', 'sister', 'sibling');
  if (a == 1) return grand(b - 1) + gender(sex, 'uncle', 'aunt', 'pibling');
  if (b == 1) return grand(a - 1) + gender(sex, 'nephew', 'niece', 'nibling');
  final removal = (a - b).abs();
  final suffix = switch (removal) {
    0 => '', 1 => ' once removed', 2 => ' twice removed',
    _ => ' $removal times removed',
  };
  return '${ordinal(math.min(a, b) - 1)} cousin$suffix';
}

final class Analysis {
  final Family family;
  final children = <String, List<String>>{};
  final _up = <String, Map<String, int>>{};
  final _down = <String, Map<String, int>>{};
  final _coefficients = <(String, String), Fraction>{};
  final _last = <(String, String), Marriage>{};

  Analysis(this.family) {
    for (final id in ids) {
      children[id] = [];
    }
    for (final person in family.people.values) {
      for (final parent in person.parents) {
        children[parent]!.add(person.id);
      }
    }
    for (final marriage in family.marriages) {
      _last[pair(marriage.first, marriage.second)] = marriage;
    }
  }

  static (String, String) pair(String a, String b) =>
      a.compareTo(b) <= 0 ? (a, b) : (b, a);
  Iterable<String> get ids => family.people.keys;
  Person person(String id) => family.people[id]!;
  Set<String> parents(String id) => person(id).parents;
  int compareAge(String a, String b) {
    final difference = person(a).birth.compareTo(person(b).birth);
    return difference != 0 ? difference : a.compareTo(b);
  }
  List<String> byAge(Iterable<String> values) =>
      values.toList()..sort(compareAge);
  String personList(Iterable<String> values) {
    final result = byAge(values).join(' ');
    return result.isEmpty ? '-' : result;
  }
  Marriage? current(String id) {
    for (final marriage in family.marriages) {
      if (marriage.status == MarriageStatus.current && marriage.contains(id)) {
        return marriage;
      }
    }
    return null;
  }
  String? spouse(String id) => current(id)?.other(id);
  Marriage? last(String a, String b) => _last[pair(a, b)];
  bool partner(String a, String b) {
    final marriage = last(a, b);
    return marriage != null && marriage.status != MarriageStatus.divorced;
  }
  Iterable<String> partners(String id) => ids.where((other) => partner(id, other));
  int sharedParents(String a, String b) =>
      parents(a).where(parents(b).contains).length;
  bool siblings(String a, String b) => a != b && sharedParents(a, b) > 0;
  bool stepSiblings(String a, String b) => sharedParents(a, b) == 0 &&
      parents(a).any((p) => parents(b).any((q) => partner(p, q)));

  Map<String, int> distances(String start, bool upward) {
    final cache = upward ? _up : _down;
    final saved = cache[start];
    if (saved != null) return saved;
    final result = <String, int>{start: 0};
    final pending = Queue<String>()..add(start);
    while (pending.isNotEmpty) {
      final current = pending.removeFirst();
      for (final next in upward ? parents(current) : children[current]!) {
        if (!result.containsKey(next)) {
          result[next] = result[current]! + 1;
          pending.add(next);
        }
      }
    }
    return cache[start] = result;
  }
  Map<String, int> up(String id) => distances(id, true);
  Map<String, int> down(String id) => distances(id, false);
  bool ancestor(String a, String b) => a != b && up(b).containsKey(a);

  Apex? apex(String a, String b) {
    final first = up(a), second = up(b);
    if (second.containsKey(a)) return Apex(a, 0, second[a]!);
    if (first.containsKey(b)) return Apex(b, first[b]!, 0);
    final common = first.keys.where(second.containsKey).toList();
    if (common.isEmpty) return null;
    common.sort((x, y) {
      var order = (first[x]! + second[x]!).compareTo(first[y]! + second[y]!);
      if (order == 0) order = first[x]!.compareTo(first[y]!);
      return order != 0 ? order : x.compareTo(y);
    });
    final id = common.first, da = first[id]!, db = second[id]!;
    final share = common.where((c) => first[c] == da && second[c] == db).length;
    return Apex(id, da, db, share);
  }

  String blood(Apex apex, Sex sex) {
    final prefix = !apex.collateral ? '' :
        apex.share == 1 ? 'half-' : apex.share >= 4 ? 'double ' : '';
    return prefix + term(apex.a, apex.b, sex);
  }

  List<String> relations(String a, String b, [Sex? overrideSex]) {
    if (a == b) return ['self'];
    final sex = overrideSex ?? person(a).sex;
    String word(String m, String f, String x) => gender(sex, m, f, x);
    final result = <String>[];
    final common = apex(a, b);
    if (common != null) result.add(blood(common, sex));
    final marriage = last(a, b);
    if (marriage != null) {
      result.add(switch (marriage.status) {
        MarriageStatus.current => word('husband', 'wife', 'spouse'),
        MarriageStatus.divorced => word('ex-husband', 'ex-wife', 'ex-spouse'),
        MarriageStatus.widowed => marriage.died == a
            ? word('late husband', 'late wife', 'late spouse')
            : word('widower', 'widow', 'surviving spouse'),
      });
    } else if (children[a]!.any((c) => parents(c).contains(b))) {
      result.add('co-parent');
    }
    if (!parents(b).contains(a) && parents(b).any((p) => partner(a, p))) {
      result.add(word('stepfather', 'stepmother', 'stepparent'));
    }
    if (!parents(a).contains(b) && parents(a).any((p) => partner(b, p))) {
      result.add(word('stepson', 'stepdaughter', 'stepchild'));
    }
    if (stepSiblings(a, b)) result.add(word('stepbrother', 'stepsister', 'stepsibling'));
    if (!ancestor(a, b) && up(b).entries.any((p) => p.value == 2 && partner(a, p.key))) {
      result.add(word('stepgrandfather', 'stepgrandmother', 'stepgrandparent'));
    }
    if (!ancestor(b, a) && up(a).entries.any((p) => p.value == 2 && partner(b, p.key))) {
      result.add(word('stepgrandson', 'stepgranddaughter', 'stepgrandchild'));
    }
    if (partners(b).any((p) => parents(p).contains(a))) {
      result.add(word('father-in-law', 'mother-in-law', 'parent-in-law'));
    }
    if (partners(a).any((p) => parents(p).contains(b))) {
      result.add(word('son-in-law', 'daughter-in-law', 'child-in-law'));
    }
    if (partners(b).any((p) => siblings(a, p)) || partners(a).any((p) => siblings(p, b))) {
      result.add(word('brother-in-law', 'sister-in-law', 'sibling-in-law'));
    }
    return result;
  }

  String relation(String a, String b) {
    final result = relations(a, b);
    return result.isEmpty ? 'no relation' : result.join(', ');
  }

  Fraction phi(String a, String b) {
    final key = pair(a, b), saved = _coefficients[pair(a, b)];
    if (saved != null) return saved;
    Fraction result;
    if (a == b) {
      result = (Fraction.one + inbreeding(a)).half();
    } else {
      if (person(a).birth < person(b).birth) {
        final temporary = a;
        a = b;
        b = temporary;
      }
      var sum = Fraction.zero;
      for (final parent in parents(a)) {
        sum = sum + phi(parent, b);
      }
      result = sum.half();
    }
    return _coefficients[key] = result;
  }
  Fraction inbreeding(String id) {
    final values = parents(id).toList();
    return values.length == 2 ? phi(values[0], values[1]) : Fraction.zero;
  }
}

final class Calculator {
  var family = Family();
  final history = <(String, Family)>[];

  void check(String id) {
    if (!family.people.containsKey(id)) throw CommandError('UNKNOWN PERSON $id');
  }
  void remember(String line) => history.add((line, Family.copy(family)));
  void reject(bool condition, String message) {
    if (condition) throw CommandError(message);
  }

  List<String> modify(String line, List<String> args, Analysis graph) {
    final command = args[0], id = args[1];
    if (command == 'PERSON') {
      reject(family.people.containsKey(id), 'DUPLICATE PERSON $id');
      remember(line);
      final person = Person(id, Sex.parse(args[2]), int.parse(args[3]), args[4]);
      family.people[id] = person;
      return ['ADDED $id ${person.name} ${person.sex.code} ${person.birth}'];
    }
    check(id);
    final first = graph.person(id);
    if (command == 'REMOVE') {
      remember(line);
      family.people.remove(id);
      for (final person in family.people.values) {
        person.parents.remove(id);
      }
      family.marriages.removeWhere((m) => m.contains(id));
      return ['REMOVED $id'];
    }
    if (command == 'DEATH') {
      final year = int.parse(args[2]);
      reject(first.death != null, 'ALREADY DECEASED $id');
      reject(year < first.birth || family.marriages.any((m) => m.contains(id) &&
          (m.start > year || m.end != null && m.end! > year)), 'BAD YEAR $id');
      for (final child in graph.children[id]!) {
        if (graph.person(child).birth > year + 1) throw CommandError('AFTER DEATH $child $id');
      }
      final current = graph.current(id);
      remember(line);
      first.death = year;
      if (current != null) {
        family.marriages[family.marriages.indexOf(current)] =
            current.finish(year, MarriageStatus.widowed, id);
      }
      return ['DIED $id $year${current == null ? '' : ' spouse=${current.other(id)}'}'];
    }
    final other = args[2];
    check(other);
    final second = graph.person(other);
    if (command == 'PARENT') {
      reject(id == other, 'SAME PERSON $id');
      reject(first.parents.contains(other), 'ALREADY PARENT $id $other');
      reject(first.parents.length == 2, 'TOO MANY PARENTS $id');
      reject(graph.ancestor(id, other), 'CYCLE $id $other');
      reject(second.birth + 12 > first.birth, 'AGE GAP $id $other');
      reject(second.death != null && second.death! + 1 < first.birth, 'AFTER DEATH $id $other');
      remember(line);
      first.parents.add(other);
      return ['LINKED $id $other ${gender(second.sex, 'father', 'mother', 'parent')}'];
    }
    if (command == 'UNPARENT') {
      reject(!first.parents.contains(other), 'NOT PARENT $id $other');
      remember(line);
      first.parents.remove(other);
      return ['UNLINKED $id $other'];
    }
    final year = int.parse(args[3]);
    if (command == 'SPOUSE') {
      reject(id == other, 'SAME PERSON $id');
      for (final person in [first, second]) {
        reject(person.death != null, 'DECEASED ${person.id}');
      }
      for (final person in [first, second]) {
        reject(graph.spouse(person.id) != null, 'ALREADY MARRIED ${person.id}');
      }
      reject(graph.ancestor(id, other) || graph.ancestor(other, id) ||
          graph.siblings(id, other), 'CLOSE KIN $id $other');
      for (final person in [first, second]) {
        reject(year < person.birth + 16, 'TOO YOUNG ${person.id}');
      }
      for (final person in [first, second]) {
        reject(family.marriages.any((m) => m.contains(person.id) &&
            m.end != null && m.end! >= year), 'BAD YEAR ${person.id}');
      }
      remember(line);
      family.marriages.add(Marriage(id, other, year));
      return ['MARRIED $id $other $year'];
    }
    final marriage = graph.current(id);
    if (marriage == null || marriage.other(id) != other) {
      throw CommandError('NOT MARRIED $id $other');
    }
    reject(year <= marriage.start, 'BAD YEAR $id');
    remember(line);
    family.marriages[family.marriages.indexOf(marriage)] =
        marriage.finish(year, MarriageStatus.divorced);
    return ['DIVORCED $id $other $year'];
  }

  List<String> info(String id, Analysis graph) {
    final person = graph.person(id);
    return [
      'INFO $id ${person.name} ${person.sex.code} ${person.life}',
      '  parents: ${graph.personList(person.parents)}',
      for (final m in family.marriages.where((m) => m.contains(id)))
        '  marriage: ${m.other(id)} ${m.start}-${m.end ?? ''} ${m.status.name}',
      '  children: ${graph.personList(graph.children[id]!)}',
      '  siblings: ${graph.personList(graph.ids.where((other) => graph.siblings(id, other)))}',
      '  inbreeding: ${graph.inbreeding(id)}',
    ];
  }

  List<String> path(String a, String b, Analysis graph) {
    final apex = graph.apex(a, b);
    if (apex == null) return ['PATH $a $b none'];
    final distance = graph.down(apex.id);
    List<String> upward(String id) {
      final result = [id];
      while (id != apex.id) {
        final candidates = graph.parents(id)
            .where((p) => distance[p] == distance[id]! - 1).toList()..sort();
        id = candidates.first;
        result.add(id);
      }
      return result;
    }
    final first = upward(a), second = upward(b)..removeLast();
    first.addAll(second.reversed);
    return ['PATH $a $b ${apex.a + apex.b}: ${first.join(' ')}'];
  }

  List<String> common(String a, String b, Analysis graph) {
    final first = graph.up(a), second = graph.up(b);
    final common = first.keys.where(second.containsKey).toSet();
    final nearest = common.where((c) => !graph.children[c]!.any(common.contains)).toList();
    nearest.sort((x, y) {
      final difference = (first[x]! + second[x]!).compareTo(first[y]! + second[y]!);
      return difference != 0 ? difference : x.compareTo(y);
    });
    return ['COMMON $a $b ${nearest.length}',
      for (final id in nearest) '  $id ${first[id]} ${second[id]}'];
  }

  List<String> tree(String id, Analysis graph) {
    final lines = ['TREE $id ${graph.down(id).length - 1}'];
    final visited = <String>{};
    void visit(String current, int depth) {
      final prefix = ' ' * (2 * (depth + 1));
      if (!visited.add(current)) {
        lines.add('$prefix$current (see above)');
        return;
      }
      final person = graph.person(current), spouse = graph.spouse(current);
      lines.add('$prefix$current ${person.name} ${person.life}'
          '${spouse == null ? '' : ' = $spouse'}');
      for (final child in graph.byAge(graph.children[current]!)) {
        visit(child, depth + 1);
      }
    }
    visit(id, 0);
    return lines;
  }

  List<String> pedigree(String id, int depth, Analysis graph) {
    final lines = <String>[], distinct = <String>{};
    void enter(String current, int number, int generation) {
      final person = graph.person(current);
      distinct.add(current);
      lines.add('${' ' * (2 * (generation + 1))}$number $current ${person.name} ${person.life}');
      if (generation >= depth) return;
      final parents = person.parents.toList()..sort((a, b) {
        final difference = graph.person(a).sex.index.compareTo(graph.person(b).sex.index);
        return difference != 0 ? difference : a.compareTo(b);
      });
      for (var i = 0; i < parents.length; i++) {
        enter(parents[i], 2 * number + i, generation + 1);
      }
    }
    enter(id, 1, 0);
    return ['PEDIGREE $id $depth entries=${lines.length} distinct=${distinct.length}', ...lines];
  }

  List<String> timeline(String id, Analysis graph) {
    final person = graph.person(id);
    final events = <(int, int, String, String)>[(person.birth, 0, '', 'born')];
    for (final marriage in family.marriages.where((m) => m.contains(id))) {
      final other = marriage.other(id);
      events.add((marriage.start, 1, other, 'married $other'));
      if (marriage.status == MarriageStatus.divorced) {
        events.add((marriage.end!, 3, other, 'divorced $other'));
      } else if (marriage.status == MarriageStatus.widowed && marriage.died == other) {
        events.add((marriage.end!, 4, other, 'widowed $other'));
      }
    }
    for (final child in graph.children[id]!) {
      events.add((graph.person(child).birth, 2, child, 'child $child'));
    }
    void lost(Iterable<String> relatives, String kind) {
      for (final other in relatives) {
        final year = graph.person(other).death;
        if (year != null && year >= person.birth &&
            (person.death == null || year <= person.death!)) {
          events.add((year, 5, other, 'lost $kind $other'));
        }
      }
    }
    lost(person.parents, 'parent');
    lost(graph.children[id]!, 'child');
    if (person.death != null) events.add((person.death!, 6, '', 'died'));
    events.sort((a, b) {
      var order = a.$1.compareTo(b.$1);
      if (order == 0) order = a.$2.compareTo(b.$2);
      return order != 0 ? order : a.$3.compareTo(b.$3);
    });
    return ['TIMELINE $id ${events.length}',
      for (final event in events) '  ${event.$1} ${event.$4}'];
  }

  List<String> census(int year, Analysis graph) {
    final residents = graph.byAge(graph.ids.where((id) {
      final person = graph.person(id);
      return person.birth <= year && (person.death == null || person.death! > year);
    }));
    final lines = ['CENSUS $year ${residents.length}'];
    for (final id in residents) {
      Marriage? last;
      for (final marriage in family.marriages) {
        if (marriage.contains(id) && marriage.start <= year) last = marriage;
      }
      final status = last == null ? 'single' :
          last.end == null || last.end! > year ? 'married ${last.other(id)}' : last.status.name;
      lines.add('  $id ${year - graph.person(id).birth} $status');
    }
    return lines;
  }

  List<String> find(String id, String route, Analysis graph) {
    var found = <String>{id};
    for (final step in route.split('.')) {
      final next = <String>{};
      final sex = switch (step) {
        'father' || 'son' || 'brother' || 'husband' => Sex.male,
        'mother' || 'daughter' || 'sister' || 'wife' => Sex.female,
        _ => null,
      };
      for (final current in found) {
        Iterable<String> candidates;
        switch (step) {
          case 'parent' || 'father' || 'mother':
            candidates = graph.parents(current);
          case 'child' || 'son' || 'daughter':
            candidates = graph.children[current]!;
          case 'sibling' || 'brother' || 'sister':
            candidates = graph.ids.where((other) => graph.siblings(current, other));
          default:
            final spouse = graph.spouse(current);
            candidates = spouse == null ? const [] : [spouse];
        }
        next.addAll(candidates.where((other) => sex == null || graph.person(other).sex == sex));
      }
      found = next;
    }
    found.remove(id);
    final ordered = found.toList()..sort();
    return ['FIND $id $route ${ordered.length}',
      for (final other in ordered) '  $other: ${graph.relation(other, id)}'];
  }

  List<String> execute(String line) {
    final args = line.split(' '), command = args[0];
    if (command == 'UNDO') {
      reject(history.isEmpty, 'NOTHING TO UNDO');
      final (previous, state) = history.removeLast();
      family = state;
      return ['UNDONE $previous'];
    }
    final graph = Analysis(family);
    if (const {'PERSON', 'DEATH', 'REMOVE', 'PARENT', 'UNPARENT', 'SPOUSE', 'DIVORCE'}
        .contains(command)) return modify(line, args, graph);
    if (command == 'TERM') {
      return ['$line ${term(int.parse(args[1]), int.parse(args[2]), Sex.parse(args[3]))}'];
    }
    if (command == 'CENSUS') return census(int.parse(args[1]), graph);
    if (command == 'STATS') {
      final lengths = <String, int>{};
      var longest = 0, links = 0, living = 0, founders = 0;
      for (final id in graph.byAge(graph.ids)) {
        final person = graph.person(id);
        var length = 1;
        for (final parent in person.parents) {
          length = math.max(length, lengths[parent]! + 1);
        }
        lengths[id] = length;
        longest = math.max(longest, length);
        links += person.parents.length;
        if (person.parents.isEmpty) founders++;
        if (person.death == null) living++;
      }
      final couples = family.marriages.where((m) => m.status == MarriageStatus.current).length;
      return ['STATS persons=${family.people.length} living=$living links=$links '
          'couples=$couples founders=$founders generations=$longest'];
    }
    if (command == 'AUDIT') {
      final lines = <String>[];
      for (final marriage in family.marriages) {
        final apex = graph.apex(marriage.first, marriage.second);
        if (apex != null) {
          lines.add('  marriage ${marriage.first} ${marriage.second} '
              '${graph.blood(apex, graph.person(marriage.first).sex)}');
        }
      }
      for (final id in graph.ids) {
        final value = graph.inbreeding(id);
        if (value.numerator != 0) lines.add('  inbred $id $value');
      }
      return ['AUDIT ${lines.length}', ...lines];
    }
    final id = args[1];
    check(id);
    if (const {'RELATION', 'PATH', 'COMMON', 'KINSHIP'}.contains(command)) {
      final other = args[2];
      check(other);
      return switch (command) {
        'RELATION' => ['RELATION $id $other: ${graph.relation(id, other)}'],
        'PATH' => path(id, other, graph),
        'COMMON' => common(id, other, graph),
        _ => ['KINSHIP $id $other ${graph.phi(id, other)}'],
      };
    }
    switch (command) {
      case 'INFO': return info(id, graph);
      case 'TREE': return tree(id, graph);
      case 'PEDIGREE': return pedigree(id, int.parse(args[2]), graph);
      case 'TIMELINE': return timeline(id, graph);
      case 'FIND': return find(id, args[2], graph);
      case 'RELATIVES':
      case 'WHO':
        final query = args.skip(2).join(' '), lines = <String>[];
        for (final other in graph.ids.where((other) => other != id)) {
          final terms = graph.relations(other, id);
          if (command == 'RELATIVES') {
            if (terms.isNotEmpty) lines.add('  $other: ${terms.join(', ')}');
          } else {
            final neutral = graph.relations(other, id, Sex.other);
            for (var i = 0; i < terms.length; i++) {
              if (terms[i] == query || neutral[i] == query) {
                lines.add('  $other: ${terms[i]}');
                break;
              }
            }
          }
        }
        return ['${command == 'WHO' ? 'WHO $id $query' : 'RELATIVES $id'} ${lines.length}', ...lines];
      case 'ANCESTORS':
      case 'DESCENDANTS':
        final upward = command == 'ANCESTORS';
        final distances = upward ? graph.up(id) : graph.down(id);
        final others = distances.keys.where((other) => other != id).toList()
          ..sort((a, b) {
            final order = distances[a]!.compareTo(distances[b]!);
            return order != 0 ? order : a.compareTo(b);
          });
        return ['$command $id ${others.length}', for (final other in others)
          '  ${distances[other]} $other ${term(upward ? 0 : distances[other]!, upward ? distances[other]! : 0, graph.person(other).sex)}'];
      case 'COUSINS':
        final degree = int.parse(args[2]), matches = <(String, Apex)>[];
        for (final other in graph.ids.where((other) => other != id)) {
          final apex = graph.apex(other, id);
          if (apex != null && apex.a >= 2 && apex.b >= 2 &&
              math.min(apex.a, apex.b) - 1 == degree) matches.add((other, apex));
        }
        matches.sort((a, b) {
          final order = (a.$2.a - a.$2.b).abs().compareTo((b.$2.a - b.$2.b).abs());
          return order != 0 ? order : a.$1.compareTo(b.$1);
        });
        return ['COUSINS $id $degree ${matches.length}', for (final (other, apex) in matches)
          '  $other ${graph.blood(apex, graph.person(other).sex)}'];
      case 'GENERATIONS':
        final groups = SplayTreeMap<int, List<Person>>();
        for (final entry in graph.down(id).entries) {
          if (entry.value > 0) {
            groups.putIfAbsent(entry.value, () => []).add(graph.person(entry.key));
          }
        }
        return ['GENERATIONS $id ${groups.length}', for (final entry in groups.entries)
          '  ${entry.key} ${entry.value.length} ${entry.value.where((p) => p.death == null).length} '
          '${entry.value.map((p) => p.birth).reduce(math.min)}-${entry.value.map((p) => p.birth).reduce(math.max)}'];
      default:
        final rows = <String>[];
        var order = 1;
        for (final other in graph.byAge(graph.ids.where((other) => other != id))) {
          final shared = graph.sharedParents(id, other);
          final kind = shared == 2 ? 'full' : shared == 1 ? 'half' :
              graph.stepSiblings(id, other) ? 'step' : '';
          if (kind.isEmpty) continue;
          if (shared > 0 && graph.compareAge(other, id) < 0) order++;
          rows.add('  $other $kind ${graph.person(other).birth}');
        }
        return ['SIBLINGS $id ${rows.length} order=$order', ...rows];
    }
  }
}

void main() {
  final calculator = Calculator();
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      for (final output in calculator.execute(line)) {
        stdout.writeln(output);
      }
    } on CommandError catch (error) {
      stdout.writeln('ERROR ${error.message}');
    }
  }
}
