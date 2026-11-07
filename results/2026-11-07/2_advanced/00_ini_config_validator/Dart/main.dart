import 'dart:io';
import 'lexer.dart';
import 'ini_parser.dart';
import 'interpolate.dart';
import 'schema.dart';
import 'emitter.dart';

class Definition {
  final String value;
  final Origin origin;
  final int number;
  final List<Origin> history;
  Definition(this.value, this.origin, this.number, this.history);
}

class CheckError implements Exception {
  final String code;
  final String message;
  CheckError(this.code, this.message);
}

Object? parseScalar(String kind, String text, List<String> values) {
  switch (kind) {
    case 'string': return text;
    case 'enum':
      for (final value in values) {
        if (value.toLowerCase() == text.toLowerCase()) return value;
      }
      return null;
    case 'bool':
      final lower = text.toLowerCase();
      if (['true', 'yes', 'on', '1'].contains(lower)) return true;
      if (['false', 'no', 'off', '0'].contains(lower)) return false;
      return null;
    case 'int': return parseInteger(text);
    case 'size': return parseSize(text);
    case 'duration': return parseDuration(text);
    case 'host': return parseHost(text);
    case 'path': return parsePath(text);
    case 'url': return parseUrl(text);
    case 'date': return parseDate(text);
    default: throw ArgumentError('Unknown scalar type $kind');
  }
}

int? parseInteger(String text) {
  final match = fullMatch(r'([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*))', text);
  if (match == null) return null;
  final int value;
  if (match[2] != null) {
    value = int.parse(match[2]!, radix: 16);
  } else {
    final digits = match[3]!.replaceAll('_', '');
    if (digits.length > 12) return null;
    value = int.parse(digits);
  }
  return match[1] == '-' ? -value : value;
}

int? parseSize(String text) {
  final match = fullMatch(r'([0-9]{1,6})(?:\.([0-9]{1,3}))?([A-Za-z]*)', text);
  if (match == null) return null;
  final factor = {'': 1, 'b': 1, 'kb': 1024, 'mb': 1048576, 'gb': 1073741824}[match[3]!.toLowerCase()];
  if (factor == null) return null;
  var result = int.parse(match[1]!) * factor;
  final fraction = match[2];
  if (fraction != null) {
    final numerator = int.parse(fraction) * factor;
    final divisor = [1, 10, 100, 1000][fraction.length];
    if (numerator % divisor != 0) return null;
    result += numerator ~/ divisor;
  }
  return result;
}

int? parseDuration(String text) {
  if (fullMatch(r'[0-9]{1,6}', text) != null) return int.parse(text);
  final match = fullMatch(r'(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?', text);
  if (text.isEmpty || match == null) return null;
  int part(int index) => match[index] == null ? 0 : int.parse(match[index]!);
  return part(1) * 3600 + part(2) * 60 + part(3);
}

String? parseHost(String text) {
  final parts = text.split('.');
  if (fullMatch(r'[0-9.]*', text) != null) {
    if (parts.length != 4) return null;
    for (final part in parts) {
      if (fullMatch(r'[0-9]{1,3}', part) == null ||
          (part.length > 1 && part.startsWith('0')) || int.parse(part) > 255) return null;
    }
    return text;
  }
  if (text.length > 253) return null;
  for (final label in parts) {
    if (fullMatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', label) == null) return null;
  }
  return text.toLowerCase();
}

String? parsePath(String text) {
  if (text.isEmpty || text.contains(' ') || text.contains('\n') || text.contains('\t')) return null;
  final absolute = text.startsWith('/');
  final parts = <String>[];
  for (final part in text.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part != '..') {
      parts.add(part);
    } else if (parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else if (absolute) {
      return null;
    } else {
      parts.add(part);
    }
  }
  return absolute ? '/${parts.join('/')}' : parts.isEmpty ? '.' : parts.join('/');
}

String? parseUrl(String text) {
  final separator = text.indexOf('://');
  if (separator < 0 || fullMatch(r'[A-Za-z][A-Za-z0-9+.-]*', text.substring(0, separator)) == null) return null;
  final scheme = text.substring(0, separator).toLowerCase();
  final rest = text.substring(separator + 3);
  if (rest.contains('?') || rest.contains('#')) return null;
  final slash = rest.indexOf('/');
  final authority = slash < 0 ? rest : rest.substring(0, slash);
  final path = slash < 0 ? '' : rest.substring(slash + 1);
  final colon = authority.indexOf(':');
  final host = colon < 0 ? authority : authority.substring(0, colon);
  final hostValue = parseHost(host), pathValue = parsePath('/$path');
  if (hostValue == null || pathValue == null) return null;
  var result = '$scheme://$hostValue';
  if (colon >= 0) {
    final port = authority.substring(colon + 1);
    if (fullMatch(r'[1-9][0-9]{0,4}', port) == null || int.parse(port) > 65535) return null;
    final defaultPort = {'http': 80, 'https': 443}[scheme];
    if (int.parse(port) != defaultPort) result += ':$port';
  }
  return result + pathValue;
}

String? parseDate(String text) {
  if (fullMatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', text) == null) return null;
  final year = int.parse(text.substring(0, 4));
  final month = int.parse(text.substring(5, 7));
  final day = int.parse(text.substring(8));
  if (year < 1 || month < 1 || month > 12) return null;
  var days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
  if (month == 2 && (year % 4 == 0 && year % 100 != 0 || year % 400 == 0)) days = 29;
  return day >= 1 && day <= days ? text : null;
}

CheckError invalidValue(String key, String kind, Spec spec, String text, {bool item = false}) {
  final display = '${item ? 'item ' : ''}${spec.secret ? mask : stringNotation(text)}';
  return kind == 'enum'
      ? CheckError('E_ENUM', '$key: $display is not one of ${spec.values.join(',')}')
      : CheckError('E_TYPE', '$key: $display is not a valid $kind');
}

Object? boundValue(String kind, String text) => text.isEmpty ? null :
    kind == 'string' || kind == 'list' ? int.parse(text) : parseScalar(kind, text, []);

int compareValues(Object left, Object right) => left is String
    ? left.compareTo(right as String) : (left as int).compareTo(right as int);

void checkRange(String key, Spec spec, Object value) {
  final range = spec.range;
  if (range == null) return;
  final lower = boundValue(spec.kind, range.$1), upper = boundValue(spec.kind, range.$2);
  final Object measure;
  final String display;
  if (spec.kind == 'string') {
    measure = (value as String).length;
    display = 'length $measure';
  } else if (spec.kind == 'list') {
    measure = (value as List<Object>).length;
    display = 'count $measure';
  } else {
    measure = value;
    display = spec.secret ? mask : valueNotation(spec.kind, spec.item, value);
  }
  if ((lower != null && compareValues(measure, lower) < 0) ||
      (upper != null && compareValues(measure, upper) > 0)) {
    throw CheckError('E_RANGE', '$key: $display is out of range ${lower ?? ''}..${upper ?? ''}');
  }
}

class DocumentLibrary {
  final documents = <String, Document?>{};

  Document? find(String name) {
    if (!documents.containsKey(name)) {
      final file = File('input/conf/$name.ini');
      documents[name] = file.existsSync() ? parseDocument(name, file.readAsLinesSync()) : null;
    }
    return documents[name];
  }
}

class Profile extends ProfileResult {
  final int manifestLine;
  late final String root;
  late final List<String> overrides;
  final configuration = <String, Definition>{};
  final parents = <String, (String, Origin)>{};
  final reported = <Diagnostic>{};
  var definitionNumber = 0;

  Profile(this.manifestLine, String line) : super(line.split(' ')[0]) {
    final words = line.split(' ');
    root = words[1];
    overrides = words.skip(2).toList();
  }

  void report(Origin origin, String code, String message) =>
      reported.add(Diagnostic(origin, code, message));

  void define(String key, String value, Origin origin) {
    final history = List<Origin>.of(configuration[key]?.history ?? []);
    if (history.isEmpty || history.last != origin) history.add(origin);
    configuration[key] = Definition(value, origin, ++definitionNumber, history);
  }

  void process(Schema schema, DocumentLibrary library, List<Profile> earlier) {
    apply(library, root, [root]);
    for (final entry in overrides) {
      final equals = entry.indexOf('=');
      define(entry.substring(0, equals), entry.substring(equals + 1), Origin('manifest', manifestLine));
    }
    inheritSections();
    resolveAliases(schema);
    final sections = configuration.keys.map(sectionOf).toSet();
    for (final spec in schema.specs) {
      final value = spec.defaultValue;
      if (value == null) continue;
      for (final key in schema.targetKeys(spec, sections)) {
        if (!configuration.containsKey(key)) define(key, value, Origin('schema', spec.line));
      }
    }
    final configured = configuration.keys.toSet();
    final expander = Expander(
        configuration.map((key, definition) => MapEntry(key, definition.value)),
        configuration.map((key, definition) => MapEntry(key, definition.origin)));
    for (final key in sortedKeys(configured)) { expander.expand(key); }
    reported.addAll(expander.diagnostics);
    checkTypes(schema, expander.results);
    checkOrder();
    checkRequired(schema, sections, configured);
    checkFixed(earlier);
    summarize(configured.length);
  }

  void apply(DocumentLibrary library, String name, List<String> chain) {
    final document = library.find(name)!;
    tree.add((chain.length - 1, name));
    reported.addAll(document.diagnostics);
    for (final statement in document.statements) {
      final origin = Origin(name, statement.line);
      final key = statement.target;
      switch (statement.kind) {
        case 'assign': define(key, statement.value, origin);
        case 'append':
          final current = configuration[key];
          final value = current != null && current.value.isNotEmpty
              ? '${current.value},${statement.value}' : statement.value;
          define(key, value, origin);
        case 'unset':
          if (configuration.remove(key) == null) report(origin, 'W_UNSET', '$key is not set');
        case 'inherit': parents[key] = (statement.value, origin);
        case 'include':
          final start = chain.indexOf(key);
          if (start >= 0) {
            final path = [...chain.skip(start), key];
            report(origin, 'E_INCLUDE_CYCLE', 'include cycle ${path.join(' -> ')}');
            tree.add((chain.length, '$key (cycle)'));
          } else if (library.find(key) == null) {
            report(origin, 'E_INCLUDE_MISSING', 'missing document $key');
            tree.add((chain.length, '$key (missing)'));
          } else {
            apply(library, key, [...chain, key]);
          }
      }
    }
  }

  void inheritSections() {
    final own = <String, List<(String, Definition)>>{};
    for (final entry in configuration.entries) {
      own.putIfAbsent(sectionOf(entry.key), () => []).add((nameOf(entry.key), entry.value));
    }
    for (final declaration in parents.entries) {
      final section = declaration.key, parent = declaration.value.$1;
      final origin = declaration.value.$2;
      final chain = [section];
      while (parents.containsKey(chain.last) && !chain.contains(parents[chain.last]!.$1)) {
        chain.add(parents[chain.last]!.$1);
      }
      if (parents.containsKey(chain.last)) {
        final path = [...chain, parents[chain.last]!.$1];
        report(origin, 'E_INHERIT_CYCLE', 'inheritance cycle ${path.join(' -> ')}');
        continue;
      }
      if (!parents.containsKey(parent) && !own.containsKey(parent)) {
        report(origin, 'W_PARENT_EMPTY', 'section $section inherits from empty section $parent');
      }
      for (final ancestor in chain.skip(1)) {
        for (final item in own[ancestor] ?? <(String, Definition)>[]) {
          configuration.putIfAbsent('$section.${item.$1}', () => item.$2);
        }
      }
    }
  }

  void resolveAliases(Schema schema) {
    for (final spec in schema.specs) {
      final aliases = spec.aliases.where(configuration.containsKey).toList();
      if (aliases.isEmpty) continue;
      final candidates = [spec.pattern, ...aliases].where(configuration.containsKey).toList();
      var winner = candidates.first;
      for (final candidate in candidates.skip(1)) {
        if (configuration[candidate]!.number > configuration[winner]!.number) winner = candidate;
      }
      final chosen = configuration[winner]!;
      for (final candidate in candidates) {
        final origin = configuration[candidate]!.origin;
        if (candidate != spec.pattern) report(origin, 'W_DEPRECATED', '$candidate is deprecated, use ${spec.pattern}');
        if (candidate != winner) report(origin, 'W_SHADOWED', '$candidate is superseded by $winner at ${chosen.origin}');
      }
      configuration[spec.pattern] = chosen;
      for (final alias in aliases) { configuration.remove(alias); }
    }
  }

  Object normalize(String key, Spec spec, String text, Origin origin) {
    final Object value;
    if (spec.kind != 'list') {
      value = parseScalar(spec.kind, text, spec.values) ?? (throw invalidValue(key, spec.kind, spec, text));
    } else {
      var items = <Object>[];
      if (trimSpaces(text).isNotEmpty) {
        final raw = text.split(',').map(trimSpaces).toList();
        if (raw.contains('')) report(origin, 'W_EMPTY_ITEM', '$key: empty list item ignored');
        for (final item in raw.where((item) => item.isNotEmpty)) {
          items.add(parseScalar(spec.item, item, spec.values) ??
              (throw invalidValue(key, spec.item, spec, item, item: true)));
        }
        if (spec.unique) {
          final seen = <String>{};
          final unique = items.where((item) => seen.add(valueNotation(spec.item, 'string', item))).toList();
          if (unique.length < items.length) report(origin, 'W_DUPLICATE_ITEM', '$key: duplicate items removed');
          items = unique;
        }
      }
      value = items;
    }
    checkRange(key, spec, value);
    return value;
  }

  void checkTypes(Schema schema, Map<String, String?> results) {
    for (final key in sortedKeys(results.keys)) {
      final text = results[key];
      if (text == null) continue;
      final definition = configuration[key]!;
      final spec = schema.specFor(key);
      try {
        if (spec == null) report(definition.origin, 'W_UNKNOWN', '$key is not in the schema');
        final value = spec == null ? text : normalize(key, spec, text, definition.origin);
        outputs[key] = OutputKey(definition.origin, definition.history, spec, value);
      } on CheckError catch (error) {
        report(definition.origin, error.code, error.message);
      }
    }
  }

  void checkOrder() {
    final remove = <String>[];
    for (final key in sortedKeys(outputs.keys)) {
      final output = outputs[key]!;
      final le = output.spec?.le;
      if (le == null) continue;
      final limitKey = '${sectionOf(key)}.$le';
      final limit = outputs[limitKey];
      if (limit != null && output.value is int && limit.value is int &&
          (output.value as int) > (limit.value as int)) {
        report(output.origin, 'E_ORDER', '$key: ${shown(output)} is greater than $limitKey (${shown(limit)})');
        remove.add(key);
      }
    }
    for (final key in remove) { outputs.remove(key); }
  }

  void checkRequired(Schema schema, Set<String> sections, Set<String> configured) {
    for (final spec in schema.specs.where((spec) => spec.required)) {
      for (final key in schema.targetKeys(spec, sections)) {
        if (configured.contains(key)) continue;
        final origin = Origin(root, 0);
        if (spec.when == null) {
          report(origin, 'E_REQUIRED', '$key is required');
        } else {
          final condition = '${sectionOf(key)}.${spec.when}';
          if (outputs[condition]?.value == true) {
            report(origin, 'E_REQUIRED', '$key is required when $condition is true');
          }
        }
      }
    }
  }

  void checkFixed(List<Profile> earlier) {
    for (final key in sortedKeys(outputs.keys)) {
      final output = outputs[key]!;
      if (output.spec?.fixed != true) continue;
      Profile? reference;
      for (final profile in earlier) {
        if (profile.outputs.containsKey(key)) { reference = profile; break; }
      }
      if (reference != null && reference.outputs[key]!.notation != output.notation) {
        report(output.origin, 'E_FIXED', '$key: value differs from profile ${reference.name}');
        outputs.remove(key);
      }
    }
  }

  void summarize(int configuredCount) {
    diagnostics.addAll(reported);
    diagnostics.sort((left, right) {
      var result = left.origin.document.compareTo(right.origin.document);
      if (result != 0) return result;
      result = left.origin.line.compareTo(right.origin.line);
      if (result != 0) return result;
      result = left.code.compareTo(right.code);
      return result != 0 ? result : left.message.compareTo(right.message);
    });
    errors = diagnostics.where((diagnostic) => diagnostic.code.startsWith('E_')).length;
    warnings = diagnostics.length - errors;
    for (final key in sortedKeys(outputs.keys)) {
      final output = outputs[key]!;
      if (output.history.length >= 2) overridden.add((key, output.history));
      switch (output.origin.document) {
        case 'manifest': manifestKeys++;
        case 'schema': defaultKeys++;
        default: documentKeys++;
      }
    }
    dropped = configuredCount - outputs.length;
  }
}

ProfileDiff profileDiff(ProfileResult first, ProfileResult second) {
  final diff = ProfileDiff(first.name, second.name);
  final keys = {...first.outputs.keys, ...second.outputs.keys};
  for (final key in sortedKeys(keys)) {
    final before = first.outputs[key], after = second.outputs[key];
    if (before == null) {
      diff.added++;
      diff.entries.add(DiffEntry('+', key, before, after));
    } else if (after == null) {
      diff.removed++;
      diff.entries.add(DiffEntry('-', key, before, after));
    } else if (before.notation != after.notation) {
      diff.changed++;
      diff.entries.add(DiffEntry('~', key, before, after));
    }
  }
  return diff;
}

void main() {
  final schema = Schema('input/schema.txt');
  final library = DocumentLibrary();
  final profiles = <Profile>[];
  final lines = File('input/manifest.txt').readAsLinesSync();
  for (var index = 0; index < lines.length; index++) {
    final profile = Profile(index + 1, lines[index]);
    profile.process(schema, library, profiles);
    profiles.add(profile);
  }
  final diffs = <ProfileDiff>[];
  for (var index = 1; index < profiles.length; index++) {
    diffs.add(profileDiff(profiles[index - 1], profiles[index]));
  }
  writeOutputs('output', profiles, diffs);
}
