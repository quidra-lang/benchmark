import 'dart:io';
import 'ini_parser.dart' show trimSpaces;

String sectionOf(String key) => key.substring(0, key.lastIndexOf('.'));
String nameOf(String key) => key.substring(key.lastIndexOf('.') + 1);

int keyOrder(String left, String right) {
  final result = sectionOf(left).compareTo(sectionOf(right));
  return result != 0 ? result : nameOf(left).compareTo(nameOf(right));
}

List<String> sortedKeys(Iterable<String> keys) => keys.toList()..sort(keyOrder);

class Spec {
  final int line;
  final String pattern;
  final String kind;
  late final String key = nameOf(pattern);
  late final List<String> sectionParts = sectionOf(pattern).split('.');
  late final bool wildcard = sectionParts.contains('*');
  bool required = false;
  bool secret = false;
  bool unique = false;
  bool fixed = false;
  String? defaultValue;
  (String, String)? range;
  List<String> values = [];
  String item = 'string';
  List<String> aliases = [];
  String? when;
  String? le;

  Spec(this.line, List<String> words) : pattern = words[0], kind = words[1] {
    for (final attribute in words.skip(2)) {
      final equals = attribute.indexOf('=');
      final name = equals < 0 ? attribute : attribute.substring(0, equals);
      final argument = equals < 0 ? '' : attribute.substring(equals + 1);
      switch (name) {
        case 'required': required = true;
        case 'secret': secret = true;
        case 'unique': unique = true;
        case 'fixed': fixed = true;
        case 'default': defaultValue = argument;
        case 'range':
          final separator = argument.indexOf('..');
          range = (argument.substring(0, separator), argument.substring(separator + 2));
        case 'values': values = argument.split(',');
        case 'item': item = argument;
        case 'alias': aliases = argument.split(',');
        case 'when': when = argument;
        case 'le': le = argument;
      }
    }
  }

  bool matches(String section) {
    final parts = section.split('.');
    if (parts.length != sectionParts.length) return false;
    for (var index = 0; index < parts.length; index++) {
      if (sectionParts[index] != '*' && sectionParts[index] != parts[index]) return false;
    }
    return true;
  }
}

class Schema {
  final specs = <Spec>[];
  final exact = <String, Spec>{};

  Schema(String path) {
    final lines = File(path).readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (trimSpaces(line).isEmpty || line.startsWith('#')) continue;
      final spec = Spec(index + 1, line.split(' '));
      specs.add(spec);
      if (!spec.wildcard) exact[spec.pattern] = spec;
    }
  }

  Spec? specFor(String key) {
    final spec = exact[key];
    if (spec != null) return spec;
    final section = sectionOf(key), name = nameOf(key);
    for (final spec in specs) {
      if (spec.wildcard && spec.key == name && spec.matches(section)) return spec;
    }
    return null;
  }

  Iterable<String> targetKeys(Spec spec, Set<String> sections) sync* {
    if (!spec.wildcard) {
      yield spec.pattern;
    } else {
      final ordered = sections.toList()..sort();
      for (final section in ordered) {
        final key = '$section.${spec.key}';
        if (spec.matches(section) && identical(specFor(key), spec)) yield key;
      }
    }
  }
}
