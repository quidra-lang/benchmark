import 'dart:io';
import 'dart:math' as math;

class Version {
  final String text;
  final List<int> core;
  final List<String> pre;
  Version(this.text, this.core, this.pre);
}
class Comparator {
  final String op;
  final Version bound;
  Comparator(this.op, this.bound);
}
class Alternative {
  final List<Comparator> comparators;
  final Set<String> prereleases;
  Alternative(this.comparators, this.prereleases);
}
class Constraint {
  final List<Alternative> alternatives;
  Constraint(this.alternatives);
  String get normal => alternatives.map((alternative) => alternative.comparators.isEmpty
      ? '*' : alternative.comparators.map((comparator) => '${comparator.op}${comparator.bound.text}').join(' ')).join(' || ');
}
class Declaration {
  final String name, raw;
  final Constraint range;
  Declaration(this.name, this.raw, this.range);
}
class Package {
  final String name;
  final Version version;
  final List<Declaration> deps, conflicts;
  bool yanked = false;
  Package(this.name, this.version, this.deps, this.conflicts);
}
class Requirement extends Declaration {
  final String? origin;
  final Requirement? parent;
  Requirement(Declaration declaration, this.origin, this.parent)
      : super(declaration.name, declaration.raw, declaration.range);
}
class Selection {
  final Package item;
  final Requirement requirement;
  Selection(this.item, this.requirement);
}
class Failure {
  final int size;
  final List<String> chain;
  final String reason;
  final List<String>? other;
  Failure(this.size, this.chain, this.reason, this.other);
}
class Resolution {
  final Map<String, Package>? installation;
  final Failure? failure;
  Resolution(this.installation, this.failure);
}
class Snapshot {
  final List<Declaration> requests;
  final Map<String, Package> installed;
  Snapshot(this.requests, this.installed);
}
class PackageError implements Exception {
  final String message;
  PackageError(this.message);
}
final numberPattern = RegExp(r'^(?:0|[1-9][0-9]{0,3})$');
final digitsPattern = RegExp(r'^[0-9]+$');
final registry = <String, Map<String, Package>>{};
final constraintCache = <String, Constraint>{};
var requests = <Declaration>[];
var installed = <String, Package>{};
final held = <String>{};
final advisories = <String, Declaration>{};
final history = <Snapshot>[];
final output = <String>[];
Never fail(String message) => throw PackageError('error: $message');
T? firstOrNull<T>(Iterable<T> values) {
  for (final value in values) { return value; }
  return null;
}
Version? version(String text) {
  final match = RegExp(r'^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([a-z0-9]+(?:\.[a-z0-9]+)*))?$').firstMatch(text);
  if (match == null || ![1, 2, 3].every((i) => numberPattern.hasMatch(match.group(i)!))) return null;
  final pre = match.group(4)?.split('.') ?? <String>[];
  if (pre.any((part) => digitsPattern.hasMatch(part) && !numberPattern.hasMatch(part))) return null;
  return Version(text, [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)], pre);
}
Version requireVersion(String text) {
  final result = version(text);
  if (result == null) fail("invalid version '$text'");
  return result;
}
int compareVersions(Version a, Version b) {
  for (var i = 0; i < 3; i++) {
    if (a.core[i] != b.core[i]) return a.core[i].compareTo(b.core[i]);
  }
  if (a.pre.isEmpty || b.pre.isEmpty) return (b.pre.isNotEmpty ? 1 : 0) - (a.pre.isNotEmpty ? 1 : 0);
  for (var i = 0; i < math.min(a.pre.length, b.pre.length); i++) {
    final x = a.pre[i], y = b.pre[i];
    final nx = digitsPattern.hasMatch(x), ny = digitsPattern.hasMatch(y);
    final order = nx && ny ? int.parse(x).compareTo(int.parse(y))
        : nx != ny ? nx ? -1 : 1 : x.compareTo(y);
    if (order != 0) return order;
  }
  return a.pre.length.compareTo(b.pre.length);
}
Version synthetic(List<int> core, [List<String> pre = const []]) =>
    Version('${core.join('.')}${pre.isEmpty ? '' : '-${pre.join('.')}'}', core, pre);
Constraint? parseConstraint(String text) {
  final alternatives = <Alternative>[];
  for (final alternative in text.split(' || ')) {
    final comparators = <Comparator>[], prereleases = <String>{};
    for (final term in alternative.split(' ')) {
      if (term.isEmpty) return null;
      var op = '';
      for (final candidate in ['>=', '<=', '>', '<', '=', '^', '~']) {
        if (term.startsWith(candidate)) { op = candidate; break; }
      }
      final pattern = term.substring(op.length), prerelease = version(term.substring(op.length));
      var core = <int>[0, 0, 0], count = 0;
      late Version lower;
      if (prerelease != null && prerelease.pre.isNotEmpty) {
        core = prerelease.core;
        count = 3;
        lower = prerelease;
        prereleases.add(core.join('.'));
      } else {
        final parts = pattern.split('.');
        if (parts.isEmpty || parts.length > 3) return null;
        var wildcard = false;
        for (final part in parts) {
          if (part == 'x' || part == '*') { wildcard = true; }
          else if (!wildcard && numberPattern.hasMatch(part)) { core[count++] = int.parse(part); }
          else { return null; }
        }
        lower = synthetic(core);
      }
      void add(String operator, Version bound) { comparators.add(Comparator(operator, bound)); }
      Version upper(int index) => synthetic([for (var i = 0; i < 3; i++)
        i < index - 1 ? core[i] : i == index - 1 ? core[i] + 1 : 0]);
      if (count == 0) {
        if (op == '>' || op == '<') add('<', synthetic([0, 0, 0], ['0']));
      } else if (op.isEmpty || op == '=') {
        if (count == 3) { add('=', lower); }
        else { add('>=', lower); add('<', upper(count)); }
      } else if (op == '>') {
        add(count == 3 ? '>' : '>=', count == 3 ? lower : upper(count));
      } else if (op == '<=') {
        add(count == 3 ? '<=' : '<', count == 3 ? lower : upper(count));
      } else if (op == '>=' || op == '<') {
        add(op, lower);
      } else if (op == '~') {
        add('>=', lower);
        add('<', upper(count == 1 ? 1 : 2));
      } else if (op == '^') {
        add('>=', lower);
        add('<', upper(core[0] != 0 || count == 1 ? 1 : core[1] != 0 || count == 2 ? 2 : 3));
      } else {
        return null;
      }
    }
    alternatives.add(Alternative(comparators, prereleases));
  }
  return Constraint(alternatives);
}
Constraint constraint(String text) {
  final cached = constraintCache[text];
  if (cached != null) return cached;
  final result = parseConstraint(text);
  if (result == null) fail("invalid constraint '$text'");
  constraintCache[text] = result;
  return result;
}
bool satisfies(Version value, Constraint range) => range.alternatives.any((alternative) =>
    (value.pre.isEmpty || alternative.prereleases.contains(value.core.join('.'))) &&
    alternative.comparators.every((comparator) {
      final order = compareVersions(value, comparator.bound);
      return switch (comparator.op) {
        '=' => order == 0, '>' => order > 0, '>=' => order >= 0,
        '<' => order < 0, _ => order <= 0
      };
    }));
List<Package> versions(String name) => (registry[name]?.values.toList() ?? <Package>[])
    ..sort((a, b) => compareVersions(b.version, a.version));
Package registered(String name, String text) {
  final result = registry[name]?[text];
  if (result == null) fail('$name@$text is not registered');
  return result;
}
String packageText(Package item) => '${item.name}@${item.version.text}';
List<String> applicable(Package item) => (advisories.keys.toList()..sort()).where((id) {
  final advisory = advisories[id]!;
  return advisory.name == item.name && satisfies(item.version, advisory.range);
}).toList();
String display(Package item) {
  final current = installed[item.name]?.version.text == item.version.text;
  return packageText(item) + (item.yanked ? current ? ' (yanked, installed)' : ' (yanked)' : current ? ' (installed)' : '');
}
List<String> requirementChain(Requirement requirement) {
  final result = <String>[];
  for (Requirement? current = requirement; current != null; current = current.parent) {
    result.add(current.origin == null ? 'requested ${current.name} ${current.raw}'
        : '${current.origin} requires ${current.name} ${current.raw}');
  }
  return result.reversed.toList();
}
Resolution resolve(List<Declaration> wanted, Set<String> preferred, bool audit) {
  final selected = <String, Selection>{};
  Failure? failure;
  bool usable(Package item) => (!item.yanked || installed[item.name]?.version.text == item.version.text) &&
      (!audit || applicable(item).isEmpty);
  void record(Requirement requirement, String reason, [Requirement? other]) {
    if (failure == null || selected.length > failure!.size) {
      failure = Failure(selected.length, requirementChain(requirement), reason,
          other == null ? null : requirementChain(other));
    }
  }
  bool search(List<Requirement> requirements) {
    if (requirements.isEmpty) return true;
    final requirement = requirements.first, rest = requirements.skip(1).toList();
    final name = requirement.name, existing = selected[requirement.name];
    if (existing != null) {
      if (satisfies(existing.item.version, requirement.range)) return search(rest);
      record(requirement, '${packageText(existing.item)} was selected by:', existing.requirement);
      return false;
    }
    List<Package> candidates;
    if (held.contains(name)) {
      final item = installed[name]!;
      if (!satisfies(item.version, requirement.range) || !usable(item)) {
        record(requirement, '${packageText(item)} is held');
        return false;
      }
      candidates = [item];
    } else {
      candidates = versions(name).where((item) => satisfies(item.version, requirement.range) && usable(item)).toList();
      if (preferred.contains(name)) {
        final at = candidates.indexWhere((item) => item.version.text == installed[name]?.version.text);
        if (at >= 0) candidates.insert(0, candidates.removeAt(at));
      }
      if (candidates.isEmpty) {
        record(requirement, 'no version of $name matches ${requirement.raw}');
        return false;
      }
    }
    for (final item in candidates) {
      Selection? conflict;
      for (final otherName in selected.keys.toList()..sort()) {
        final other = selected[otherName]!;
        if (item.conflicts.any((dep) => dep.name == otherName && satisfies(other.item.version, dep.range)) ||
            other.item.conflicts.any((dep) => dep.name == name && satisfies(item.version, dep.range))) {
          conflict = other;
          break;
        }
      }
      if (conflict != null) {
        record(requirement, '${packageText(item)} conflicts with ${packageText(conflict.item)}, which was selected by:', conflict.requirement);
        continue;
      }
      selected[name] = Selection(item, requirement);
      final dependencies = item.deps.map((dep) => Requirement(dep, packageText(item), requirement));
      if (search([...dependencies, ...rest])) return true;
      selected.remove(name);
    }
    return false;
  }
  final requirements = wanted.map((request) => Requirement(request, null, null)).toList();
  if (search(requirements)) return Resolution({for (final entry in selected.entries) entry.key: entry.value.item}, null);
  return Resolution(null, failure);
}
void reportFailure(Failure failure) {
  output.add('UNSATISFIABLE');
  output.addAll(failure.chain.map((line) => '  $line'));
  output.add('  ${failure.reason}');
  if (failure.other != null) output.addAll(failure.other!.map((line) => '    $line'));
}
void plan(Map<String, Package> next) {
  final remaining = (next.keys.toList()..sort()).toSet(), arranged = <String>{};
  final counts = List<int>.filled(4, 0), lines = <String>[];
  while (remaining.isNotEmpty) {
    final name = remaining.firstWhere((name) => next[name]!.deps.every((dep) => arranged.contains(dep.name)));
    final item = next[name]!, old = installed[name];
    if (old == null) {
      lines.add('install ${packageText(item)}');
      counts[0]++;
    } else if (old.version.text != item.version.text) {
      final upgrading = compareVersions(item.version, old.version) > 0;
      lines.add('${upgrading ? 'upgrade' : 'downgrade'} $name ${old.version.text} -> ${item.version.text}');
      counts[upgrading ? 1 : 2]++;
    }
    remaining.remove(name);
    arranged.add(name);
  }
  final removals = (installed.keys.where((name) => !next.containsKey(name)).toList()..sort()).toSet();
  while (removals.isNotEmpty) {
    final name = removals.firstWhere((name) => !removals.any((other) => installed[other]!.deps.any((dep) => dep.name == name)));
    lines.add('remove ${packageText(installed[name]!)}');
    counts[3]++;
    removals.remove(name);
  }
  output.addAll(lines.isEmpty ? ['no changes'] : [...lines,
    '${counts[0]} installed, ${counts[1]} upgraded, ${counts[2]} downgraded, ${counts[3]} removed']);
}
void update(List<Declaration> wanted, Map<String, Package> next, [bool snapshot = true]) {
  if (snapshot) history.add(Snapshot(List.of(requests), Map.of(installed)));
  requests = List.of(wanted);
  installed = Map.of(next);
  held.removeWhere((name) => !installed.containsKey(name));
}
Set<String> reach(List<Declaration> wanted) {
  final seen = wanted.map((request) => request.name).toSet(), queue = <String>[];
  queue.addAll(seen);
  for (var i = 0; i < queue.length; i++) {
    for (final dep in installed[queue[i]]!.deps) {
      if (seen.add(dep.name)) queue.add(dep.name);
    }
  }
  return seen;
}
String requiredBy(String name) => (installed.keys.toList()..sort())
    .firstWhere((other) => installed[other]!.deps.any((dep) => dep.name == name));
(String, String?) cut(String text) {
  final at = text.indexOf(' ');
  return at < 0 ? (text, null) : (text.substring(0, at), text.substring(at + 1));
}
void execute(String commandLine) {
  final (command, argument) = cut(commandLine);
  final words = argument?.split(' ') ?? <String>[], name = argument?.split(' ').first ?? '';
  if (command == 'PKG') {
    final parts = commandLine.split('; '), main = parts.first.split(' ');
    final packageName = main[1], text = main[2], parsed = requireVersion(main[2]);
    if (registry[packageName]?.containsKey(text) ?? false) fail('$packageName@$text is already registered');
    final deps = <Declaration>[], conflicts = <Declaration>[];
    for (final clause in parts.skip(1)) {
      final (kind, rest) = cut(clause);
      final (other, raw) = cut(rest!);
      final range = constraint(raw!);
      (kind == 'DEP' ? deps : conflicts).add(Declaration(other, raw, range));
    }
    registry.putIfAbsent(packageName, () => {})[text] = Package(packageName, parsed, deps, conflicts);
    output.add('registered $packageName@$text');
    return;
  }
  if (command == 'YANK' || command == 'INFO') {
    final item = registered(name, words[1]);
    if (command == 'YANK') {
      if (item.yanked) fail('${packageText(item)} is already yanked');
      item.yanked = true;
      output.add('yanked ${packageText(item)}');
    } else {
      output.add(display(item));
      output.addAll(item.deps.map((dep) => '  requires ${dep.name} ${dep.raw}'));
      output.addAll(item.conflicts.map((dep) => '  conflicts with ${dep.name} ${dep.raw}'));
      output.addAll(applicable(item).map((id) => '  advisory $id'));
    }
    return;
  }
  if (command == 'COMPARE') {
    final a = requireVersion(words[0]), b = requireVersion(words[1]), order = compareVersions(a, b);
    output.add('${words[0]} ${order < 0 ? '<' : order > 0 ? '>' : '='} ${words[1]}');
    return;
  }
  if (command == 'MATCH') {
    final (text, raw) = cut(argument!);
    final parsed = requireVersion(text), range = constraint(raw!);
    output.add(satisfies(parsed, range) ? 'yes' : 'no');
    return;
  }
  if (command == 'RANGE') { output.add(constraint(argument!).normal); return; }
  if (command == 'VERSIONS' || command == 'INSTALL' || command == 'SIMULATE') {
    final (packageName, rest) = cut(argument!);
    final raw = rest ?? '*', range = constraint(rest ?? '*');
    if (!registry.containsKey(packageName)) fail('unknown package $packageName');
    if (command == 'VERSIONS') {
      final selected = versions(packageName).where((item) => rest == null || satisfies(item.version, range)).toList();
      output.addAll(selected.isEmpty ? ['no matching versions'] : selected.map(display));
      return;
    }
    final wanted = List<Declaration>.of(requests), at = requests.indexWhere((request) => request.name == packageName);
    final request = Declaration(packageName, raw, range);
    if (at >= 0) { wanted[at] = request; } else { wanted.add(request); }
    final result = resolve(wanted, installed.keys.toSet(), false);
    if (result.installation == null) { reportFailure(result.failure!); }
    else {
      plan(result.installation!);
      if (command == 'INSTALL') update(wanted, result.installation!);
    }
    return;
  }
  if (command == 'DEPENDENTS') {
    final parsed = words.length > 1 ? requireVersion(words[1]) : null, lines = <String>[];
    for (final other in registry.keys.toList()..sort()) {
      for (final item in versions(other)) {
        for (final dep in item.deps) {
          if (dep.name == name && (parsed == null || satisfies(parsed, dep.range))) lines.add('${packageText(item)} requires $name ${dep.raw}');
        }
      }
    }
    output.addAll(lines.isEmpty ? ['no dependents'] : lines);
    return;
  }
  if (command == 'REMOVE') {
    final at = requests.indexWhere((request) => request.name == name);
    if (at < 0) fail(installed.containsKey(name) ? '$name is required by ${requiredBy(name)}' : '$name is not installed');
    final wanted = requests.where((request) => request.name != name).toList(), keep = reach(requests.where((request) => request.name != name).toList());
    if (keep.contains(name)) {
      output.add('${packageText(installed[name]!)} is still required by ${requiredBy(name)}');
      update(wanted, installed);
    } else {
      final next = <String, Package>{for (final entry in installed.entries) if (keep.contains(entry.key)) entry.key: entry.value};
      plan(next);
      update(wanted, next);
    }
    return;
  }
  if (command == 'UPGRADE' || command == 'AUDIT' && argument == 'FIX') {
    if (command == 'UPGRADE' && argument != null && !installed.containsKey(name)) fail('$name is not installed');
    final preferred = command == 'AUDIT' || argument != null
        ? installed.keys.where((packageName) => command == 'AUDIT' || packageName != name).toSet() : <String>{};
    final result = resolve(requests, preferred, command == 'AUDIT');
    if (result.installation == null) { reportFailure(result.failure!); }
    else { plan(result.installation!); update(requests, result.installation!); }
    return;
  }
  if (command == 'ROLLBACK') {
    if (history.isEmpty) fail('nothing to roll back');
    final snapshot = history.removeLast();
    plan(snapshot.installed);
    update(snapshot.requests, snapshot.installed, false);
    return;
  }
  if (command == 'HOLD') {
    if (!installed.containsKey(name)) fail('$name is not installed');
    if (held.contains(name)) fail('$name is already held');
    held.add(name);
    output.add('held ${packageText(installed[name]!)}');
    return;
  }
  if (command == 'UNHOLD') {
    if (!held.contains(name)) fail('$name is not held');
    held.remove(name);
    output.add('released $name');
    return;
  }
  if (command == 'WHY') {
    if (!installed.containsKey(name)) fail('$name is not installed');
    if (requests.any((request) => request.name == name)) {
      output.add('${packageText(installed[name]!)} is explicitly installed');
      return;
    }
    final queue = requests.map((request) => request.name).toList()..sort();
    final parents = <String, String?>{for (final packageName in queue) packageName: null};
    for (var i = 0; i < queue.length; i++) {
      final current = queue[i];
      final deps = installed[current]!.deps.toList()..sort((a, b) => a.name.compareTo(b.name));
      for (final dep in deps) {
        if (!parents.containsKey(dep.name)) { parents[dep.name] = current; queue.add(dep.name); }
      }
    }
    final path = <String>[];
    for (String? current = name; current != null; current = parents[current]) {
      path.add(packageText(installed[current]!));
    }
    output.add(path.reversed.join(' -> '));
    return;
  }
  if (command == 'TREE') {
    if (argument != null && !installed.containsKey(name)) fail('$name is not installed');
    final roots = argument != null ? [name] : (requests.map((request) => request.name).toList()..sort());
    final seen = <String>{};
    void tree(String packageName, String? raw, String prefix, String indent) {
      final item = installed[packageName]!;
      final body = '$prefix${packageText(item)}${raw == null ? '' : ' [$raw]'}';
      if (!seen.add(packageName)) { output.add('$body (*)'); return; }
      output.add(body);
      for (var i = 0; i < item.deps.length; i++) {
        final dep = item.deps[i], last = i == item.deps.length - 1;
        tree(dep.name, dep.raw, indent + (last ? '`-- ' : '|-- '), indent + (last ? '    ' : '|   '));
      }
    }
    if (roots.isEmpty) output.add('(empty)');
    for (final root in roots) {
      tree(root, firstOrNull(requests.where((request) => request.name == root))?.raw, '', '');
    }
    return;
  }
  if (command == 'OUTDATED') {
    final lines = <String>[];
    for (final packageName in installed.keys.toList()..sort()) {
      final current = installed[packageName]!;
      final ranges = requests.where((request) => request.name == packageName).map((request) => request.range).toList();
      for (final item in installed.values) {
        for (final dep in item.deps) { if (dep.name == packageName) ranges.add(dep.range); }
      }
      final available = versions(packageName);
      final wanted = available.firstWhere((item) => (!item.yanked || item.version.text == current.version.text) && ranges.every((range) => satisfies(item.version, range)));
      final latest = firstOrNull(available.where((item) => !item.yanked && item.version.pre.isEmpty));
      if (wanted.version.text != current.version.text || latest != null && compareVersions(latest.version, current.version) > 0) {
        lines.add('$packageName ${current.version.text} ${wanted.version.text} ${latest?.version.text ?? '-'}');
      }
    }
    output.addAll(lines.isEmpty ? ['all packages are up to date'] : lines);
    return;
  }
  if (command == 'LOCK') {
    output.addAll(installed.isEmpty ? ['(empty)'] : (installed.keys.toList()..sort()).map((name) => packageText(installed[name]!)));
    return;
  }
  if (command == 'STATUS') {
    output.addAll(requests.isEmpty ? ['no requests'] : requests.map((request) => '${request.name} ${request.raw} -> ${installed[request.name]!.version.text}'));
    output.add('${installed.length} installed, ${held.length} held, ${history.length} snapshots');
    return;
  }
  if (command == 'ADVISORY') {
    final (id, rest) = cut(argument!);
    final (packageName, raw) = cut(rest!);
    if (advisories.containsKey(id)) fail('advisory $id already exists');
    final range = constraint(raw!);
    advisories[id] = Declaration(packageName, raw, range);
    output.add('advisory $id recorded');
    return;
  }
  if (command == 'AUDIT') {
    final lines = <String>[];
    for (final packageName in installed.keys.toList()..sort()) {
      final item = installed[packageName]!, ids = applicable(installed[packageName]!);
      if (ids.isEmpty) continue;
      final fix = firstOrNull(versions(packageName).reversed.where((candidate) => compareVersions(candidate.version, item.version) > 0 &&
          candidate.version.pre.isEmpty && !candidate.yanked && applicable(candidate).isEmpty));
      lines.add('${packageText(item)}: ${ids.join(', ')} (${fix == null ? 'no fix' : 'fix: ${fix.version.text}'})');
    }
    output.addAll(lines.isEmpty ? ['no known vulnerabilities'] : lines);
  }
}
void main() {
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try { execute(stdin.readLineSync()!); }
    on PackageError catch (error) { output.add(error.message); }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
