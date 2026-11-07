import 'dart:convert';
import 'dart:io';

typedef Value = Object?;
typedef SourceLine = ({int number, String text});
typedef KeyPart = ({Object part, String prefix});
typedef FilterArgument = Object;
typedef TemplateNode = Object;

final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final keyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[(?:0|[1-9][0-9]*)\])*$');
final namePattern = RegExp(r'^(?:\.|@(?:index|number|first|last)|(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*)(?:\.(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*))*)$');
final integerPattern = RegExp(r'^(?:0|-?[1-9][0-9]*)$');
final numericPattern = RegExp(r'^-?[0-9]{1,9}$');
final noArguments = {'upper', 'lower', 'title', 'trim', 'length', 'first', 'last', 'reverse', 'items', 'comma', 'sum', 'min', 'max'};
final numericFilters = {'add', 'sub', 'mul', 'div', 'mod', 'gt', 'lt'};
final filterNames = {...noArguments, ...numericFilters, 'default', 'eq', 'pad', 'lpad', 'truncate', 'replace', 'join', 'sort', 'pluck'};
final standaloneKinds = {'section', 'inverted', 'close', 'comment', 'partial', 'delimiter'};
const sigils = {'#': 'section', '^': 'inverted', '/': 'close', '!': 'comment', '>': 'partial', '&': 'raw', '=': 'delimiter'};
String strip(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && text[start] == ' ') start++;
  while (end > start && text[end - 1] == ' ') end--;
  return text.substring(start, end);
}

class EngineFailure implements Exception {
  final String reason;
  EngineFailure(this.reason);
}

class TemplateFailure implements Exception {
  final int number;
  final String reason;
  TemplateFailure(this.number, this.reason);
}

class TemplateFilter {
  final String name;
  final List<FilterArgument> arguments;
  TemplateFilter(this.name, this.arguments);
}

class Expression {
  final String name;
  final List<TemplateFilter> filters;
  Expression(this.name, this.filters);
}

class Tag {
  final String kind;
  final int number;
  final String argument;
  Expression? expression;
  final List<TemplateNode> children = [];
  String indentation = '';
  Tag(this.kind, this.number, this.argument);
}

bool hasPart(Value value, Object part) {
  if (part is String) return value is Map<String, Value> && value.containsKey(part);
  return part is int && value is List<Value> && part < value.length;
}

Value getPart(Value value, Object part) => part is String
    ? (value as Map<String, Value>)[part]
    : (value as List<Value>)[part as int];

void putPart(Value container, Object part, Value value) {
  if (part is String) {
    (container as Map<String, Value>)[part] = value;
  } else {
    final list = container as List<Value>;
    final index = part as int;
    if (index == list.length) {
      list.add(value);
    } else {
      list[index] = value;
    }
  }
}

List<KeyPart> parseKey(String key) {
  if (!keyPattern.hasMatch(key)) throw EngineFailure("bad key '$key'");
  return RegExp(r'([A-Za-z_][A-Za-z0-9_]*)|\[(0|[1-9][0-9]*)\]').allMatches(key).map((match) => (
    part: match[1] ?? int.parse(match[2]!),
    prefix: key.substring(0, match.end),
  )).toList();
}

(Value, int) readScalar(String text, int start) {
  if (start < text.length && text[start] == '"') {
    final result = StringBuffer();
    for (var position = start + 1; position < text.length; position++) {
      final char = text[position];
      if (char == '"') return (result.toString(), position + 1);
      if (char == r'\') {
        position++;
        if (position == text.length) throw const FormatException();
        final next = text[position];
        if (next != '"' && next != r'\' && next != 'n') throw const FormatException();
        result.write(next == 'n' ? '\n' : next);
      } else {
        result.write(char);
      }
    }
    throw const FormatException();
  }
  var end = start;
  while (end < text.length && text[end] != ',' && text[end] != ']') end++;
  final word = text.substring(start, end);
  if (word == 'true' || word == 'false') return (word == 'true', end);
  if (integerPattern.hasMatch(word)) return (int.parse(word), end);
  throw const FormatException();
}

Value parseValue(String text) {
  try {
    if (text == '[]') return <Value>[];
    if (text == '{}') return <String, Value>{};
    if (text.startsWith('[')) {
      final values = <Value>[];
      var position = 1;
      while (true) {
        final (value, end) = readScalar(text, position);
        values.add(value);
        if (text.substring(end) == ']') return values;
        if (!text.startsWith(', ', end)) throw const FormatException();
        position = end + 2;
      }
    }
    final (value, end) = readScalar(text, 0);
    if (end != text.length) throw const FormatException();
    return value;
  } on FormatException {
    throw EngineFailure("bad value '$text'");
  }
}

List<String> splitUnquoted(String text, String separator) {
  final parts = <String>[];
  var quoted = false;
  var start = 0;
  for (var index = 0; index < text.length; index++) {
    if (text[index] == "'") {
      quoted = !quoted;
    } else if (text[index] == separator && !quoted) {
      parts.add(text.substring(start, index));
      start = index + 1;
    }
  }
  parts.add(text.substring(start));
  return parts;
}

bool validArguments(String name, List<FilterArgument> args) {
  final number = args.isNotEmpty && args[0] is int;
  final string = args.isNotEmpty && args[0] is String;
  if (noArguments.contains(name)) return args.isEmpty;
  if (name == 'default' || name == 'eq') return args.length == 1;
  if (name == 'sort') return args.isEmpty || args.length == 1 && string;
  if (name == 'join' || name == 'pluck') return args.length == 1 && string;
  if (name == 'replace') return args.length == 2 && string && args[0] != '' && args[1] is String;
  if (name == 'pad' || name == 'lpad') {
    return number && (args[0] as int) >= 0 && (args.length == 1 || args.length == 2 && args[1] is String && (args[1] as String).length == 1);
  }
  if (name == 'truncate') return args.length == 1 && number && (args[0] as int) >= 0;
  return args.length == 1 && number && (!(name == 'div' || name == 'mod') || args[0] != 0);
}

Expression parseExpression(String text, int number) {
  final parts = splitUnquoted(text, '|');
  final name = strip(parts[0]);
  if (!namePattern.hasMatch(name)) throw TemplateFailure(number, "invalid name '$name'");
  final chain = <TemplateFilter>[];
  for (final part in parts.skip(1)) {
    final pieces = splitUnquoted(strip(part), ':');
    final filter = pieces[0];
    if (!filterNames.contains(filter)) throw TemplateFailure(number, "unknown filter '$filter'");
    final args = <FilterArgument>[];
    var valid = true;
    for (final notation in pieces.skip(1)) {
      if (RegExp(r"^'[^']*'$").hasMatch(notation)) {
        args.add(notation.substring(1, notation.length - 1));
      } else if (numericPattern.hasMatch(notation)) {
        args.add(int.parse(notation));
      } else {
        valid = false;
      }
    }
    if (!valid || !validArguments(filter, args)) throw TemplateFailure(number, "bad arguments for '$filter'");
    chain.add(TemplateFilter(filter, args));
  }
  return Expression(name, chain);
}

List<TemplateNode> parseSource(List<SourceLine> source) {
  var opening = '{{';
  var closing = '}}';
  final nodes = <TemplateNode>[];
  final targets = <List<TemplateNode>>[nodes];
  final sections = <Tag>[];
  for (final line in source) {
    final text = line.text;
    final number = line.number;
    var position = 0;
    final tokens = <TemplateNode>[];
    final tags = <Tag>[];
    while (true) {
      final start = text.indexOf(opening, position);
      if (start < 0) {
        tokens.add(text.substring(position));
        break;
      }
      tokens.add(text.substring(position, start));
      final after = start + opening.length;
      final triple = after < text.length && text[after] == '{';
      final terminator = triple ? '}$closing' : closing;
      final end = text.indexOf(terminator, after + (triple ? 1 : 0));
      if (end < 0) throw TemplateFailure(number, 'unclosed tag');
      final content = strip(text.substring(after + (triple ? 1 : 0), end));
      final kind = triple ? 'raw' : sigils[content.isEmpty ? '' : content[0]] ?? 'variable';
      final argument = triple || kind == 'variable' || kind == 'delimiter' ? content : strip(content.substring(1));
      final tag = Tag(kind, number, argument);
      position = end + terminator.length;
      if (kind == 'delimiter') {
        if (content.length < 2 || !content.endsWith('=')) throw TemplateFailure(number, 'invalid delimiters');
        final words = strip(content.substring(1, content.length - 1)).split(RegExp(r' +'));
        if (words.length != 2 || words.any((word) => word.contains('='))) throw TemplateFailure(number, 'invalid delimiters');
        opening = words[0];
        closing = words[1];
      } else if (kind == 'variable' || kind == 'raw' || kind == 'section' || kind == 'inverted') {
        tag.expression = parseExpression(argument, number);
        if (kind == 'section' || kind == 'inverted') sections.add(tag);
      } else if (kind == 'close') {
        if (!namePattern.hasMatch(argument)) throw TemplateFailure(number, "invalid name '$argument'");
        if (sections.isEmpty) throw TemplateFailure(number, "unexpected closing '$argument'");
        final expected = sections.last.expression!.name;
        if (argument != expected) throw TemplateFailure(number, "mismatched closing '$argument', expected '$expected'");
        sections.removeLast();
      } else if (kind == 'partial' && !identifier.hasMatch(argument)) {
        throw TemplateFailure(number, "invalid name '$argument'");
      }
      tags.add(tag);
      tokens.add(tag);
    }
    final standalone = tags.length == 1 && standaloneKinds.contains(tags[0].kind) && tokens.every((token) => token is! String || RegExp(r'^ *$').hasMatch(token));
    final List<TemplateNode> placed;
    if (standalone) {
      if (tags[0].kind == 'partial') tags[0].indentation = tokens[0] as String;
      placed = tags;
    } else {
      tokens.add('\n');
      placed = tokens;
    }
    for (final token in placed) {
      if (token is String) {
        if (token.isNotEmpty) targets.last.add(token);
      } else {
        final tag = token as Tag;
        if (tag.kind == 'section' || tag.kind == 'inverted') {
          targets.last.add(tag);
          targets.add(tag.children);
        } else if (tag.kind == 'close') {
          targets.removeLast();
        } else if (tag.kind != 'comment' && tag.kind != 'delimiter') {
          targets.last.add(tag);
        }
      }
    }
  }
  if (sections.isNotEmpty) {
    final tag = sections.last;
    throw TemplateFailure(tag.number, "unclosed section '${tag.expression!.name}'");
  }
  return nodes;
}

String toText(Value value) {
  if (value == null) return '';
  if (value is Map<String, Value>) throw EngineFailure('cannot render map');
  if (value is List<Value>) return value.map(toText).join(', ');
  return value.toString();
}

bool truthy(Value value) {
  if (value is Map<String, Value>) return value.isNotEmpty;
  if (value is List<Value>) return value.isNotEmpty;
  return value != null && value != false && value != 0 && value != '';
}

int toNumber(Value value, String filter) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is String && !value.contains('\n') && numericPattern.hasMatch(value)) return int.parse(value);
  throw EngineFailure("not a number for '$filter'");
}

Value field(Value value, String key) => value is Map<String, Value> ? value[key] : null;
int sortRank(Value value) => value == null ? 0 : value is int ? 1 : value is String ? 2 : value is bool ? 3 : 4;

int compareValues(Value left, Value right) {
  final rank = sortRank(left) - sortRank(right);
  if (rank != 0) return rank;
  if (left is int && right is int) return left.compareTo(right);
  if (left is String && right is String) return left.compareTo(right);
  if (left is bool && right is bool) return left == right ? 0 : left ? 1 : -1;
  return 0;
}

Value applyFilter(TemplateFilter filter, Value value) {
  final name = filter.name;
  final args = filter.arguments;
  switch (name) {
    case 'upper': return toText(value).toUpperCase();
    case 'lower': return toText(value).toLowerCase();
    case 'title':
      final text = toText(value);
      return List.generate(text.length, (i) => i == 0 || text[i - 1] == ' ' ? text[i].toUpperCase() : text[i].toLowerCase()).join();
    case 'trim': return strip(toText(value));
    case 'length': return value is Map<String, Value> ? value.length : value is List<Value> ? value.length : toText(value).length;
    case 'first': return value is List<Value> ? value.isEmpty ? null : value.first : value;
    case 'last': return value is List<Value> ? value.isEmpty ? null : value.last : value;
    case 'reverse': return value is List<Value> ? value.reversed.toList() : value is String ? value.split('').reversed.join() : value;
    case 'items':
      if (value is! Map<String, Value>) return value;
      final keys = value.keys.toList()..sort();
      return keys.map<Value>((key) => <String, Value>{'key': key, 'value': value[key]}).toList();
    case 'comma':
      final number = toNumber(value, name);
      final digits = number.abs().toString();
      final groups = <String>[];
      for (var end = digits.length; end > 0; end -= 3) {
        groups.add(digits.substring(end > 3 ? end - 3 : 0, end));
      }
      return '${number < 0 ? '-' : ''}${groups.reversed.join(',')}';
    case 'sum': case 'min': case 'max':
      if (value is! List<Value>) return toNumber(value, name);
      final numbers = value.map((element) => toNumber(element, name)).toList();
      if (name == 'sum') return numbers.fold<int>(0, (total, number) => total + number);
      if (numbers.isEmpty) return null;
      return numbers.reduce((a, b) => name == 'min' ? a < b ? a : b : a > b ? a : b);
    case 'default': return truthy(value) ? value : args[0];
    case 'eq': return toText(value) == toText(args[0]);
    case 'pad': return toText(value).padRight(args[0] as int, args.length == 2 ? args[1] as String : ' ');
    case 'lpad': return toText(value).padLeft(args[0] as int, args.length == 2 ? args[1] as String : ' ');
    case 'truncate':
      final text = toText(value);
      final limit = args[0] as int;
      return text.length > limit ? '${text.substring(0, limit)}...' : text;
    case 'replace': return toText(value).replaceAll(args[0] as String, args[1] as String);
    case 'join': return value is List<Value> ? value.map(toText).join(args[0] as String) : toText(value);
    case 'pluck': return value is List<Value> ? value.map((element) => field(element, args[0] as String)).toList() : value;
    case 'sort':
      if (value is! List<Value>) return value;
      final decorated = List.generate(value.length, (i) => (value: value[i], index: i, key: args.isEmpty ? value[i] : field(value[i], args[0] as String)));
      decorated.sort((a, b) {
        final comparison = compareValues(a.key, b.key);
        return comparison == 0 ? a.index.compareTo(b.index) : comparison;
      });
      return decorated.map((item) => item.value).toList();
    default:
      final number = toNumber(value, name);
      final n = args[0] as int;
      switch (name) {
        case 'add': return number + n;
        case 'sub': return number - n;
        case 'mul': return number * n;
        case 'div': return (number / n).floor();
        case 'mod': return number - n * (number / n).floor();
        case 'gt': return number > n;
        default: return number < n;
      }
  }
}

class Renderer {
  final Map<String, List<SourceLine>> partials;
  final bool strict;
  final List<Value> contexts;
  final List<({int index, int count})> loops = [];
  final StringBuffer output = StringBuffer();
  Renderer(Map<String, Value> root, this.partials, this.strict) : contexts = [root];

  (bool, Value) resolve(String name) {
    if (name == '.') return (true, contexts.last);
    if (name.startsWith('@')) {
      if (loops.isEmpty) return (false, null);
      final loop = loops.last;
      if (name == '@index') return (true, loop.index);
      if (name == '@number') return (true, loop.index + 1);
      return (true, name == '@first' ? loop.index == 0 : loop.index == loop.count - 1);
    }
    final parts = name.split('.').map<Object>((part) => RegExp(r'^[0-9]+$').hasMatch(part) ? int.tryParse(part) ?? BigInt.parse(part) : part).toList();
    for (final context in contexts.reversed) {
      if (!hasPart(context, parts[0])) continue;
      Value value = context;
      for (final part in parts) {
        if (!hasPart(value, part)) return (false, null);
        value = getPart(value, part);
      }
      return (true, value);
    }
    return (false, null);
  }

  Value evaluate(Expression expression, bool strict) {
    final (found, resolved) = resolve(expression.name);
    if (!found && strict) throw EngineFailure("missing '${expression.name}'");
    Value value = resolved;
    for (final filter in expression.filters) value = applyFilter(filter, value);
    return value;
  }

  void render(List<TemplateNode> nodes, int depth) {
    for (final node in nodes) {
      if (node is String) {
        output.write(node);
        continue;
      }
      final tag = node as Tag;
      try {
        if (tag.kind == 'variable' || tag.kind == 'raw') {
          final text = toText(evaluate(tag.expression!, strict));
          const escapes = {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'};
          output.write(tag.kind == 'raw' ? text : text.replaceAllMapped(RegExp('[&<>"\']'), (match) => escapes[match[0]]!));
        } else if (tag.kind == 'section') {
          final value = evaluate(tag.expression!, false);
          if (value is List<Value>) {
            for (var index = 0; index < value.length; index++) {
              contexts.add(value[index]);
              loops.add((index: index, count: value.length));
              render(tag.children, depth);
              loops.removeLast();
              contexts.removeLast();
            }
          } else if (truthy(value)) {
            contexts.add(value);
            render(tag.children, depth);
            contexts.removeLast();
          }
        } else if (tag.kind == 'inverted') {
          if (!truthy(evaluate(tag.expression!, false))) render(tag.children, depth);
        } else if (tag.kind == 'partial') {
          final source = partials[tag.argument];
          if (source == null) throw EngineFailure("unknown partial '${tag.argument}'");
          if (depth == 8) throw EngineFailure("partial depth exceeded at '${tag.argument}'");
          render(parseSource(source.map((line) => (number: line.number, text: line.text.isEmpty ? '' : tag.indentation + line.text)).toList()), depth + 1);
        }
      } on EngineFailure catch (error) {
        throw TemplateFailure(tag.number, error.reason);
      }
    }
  }
}

class TemplateEngine {
  final Map<String, Value> root = {};
  final Map<String, List<SourceLine>> partials = {};
  final Map<String, List<SourceLine>> templates = {};
  bool strict = false;
  final List<String> output = [];

  void assign(String line) {
    final separator = line.indexOf(' = ');
    if (separator < 0) throw EngineFailure('bad line');
    final parts = parseKey(line.substring(0, separator));
    final value = parseValue(line.substring(separator + 3));
    Value container = root;
    ({Value container, Object part, Value child})? detached;
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index].part;
      final prefix = parts[index].prefix;
      if (part is int && part > (container as List<Value>).length) throw EngineFailure("index gap at '$prefix'");
      if (index == parts.length - 1) {
        putPart(container, part, value);
        break;
      }
      final mapRequired = parts[index + 1].part is String;
      Value child;
      if (hasPart(container, part)) {
        child = getPart(container, part);
        if (!(mapRequired ? child is Map<String, Value> : child is List<Value>)) throw EngineFailure("type conflict at '$prefix'");
      } else {
        child = mapRequired ? <String, Value>{} : <Value>[];
        if (detached == null) {
          detached = (container: container, part: part, child: child);
        } else {
          putPart(container, part, child);
        }
      }
      container = child;
    }
    if (detached != null) putPart(detached.container, detached.part, detached.child);
  }

  void unset(String key) {
    final parts = parseKey(key);
    Value container = root;
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index].part;
      if (!hasPart(container, part)) throw EngineFailure("no value at '$key'");
      if (index == parts.length - 1) {
        if (part is String) {
          (container as Map<String, Value>).remove(part);
        } else {
          (container as List<Value>).removeAt(part as int);
        }
      } else {
        container = getPart(container, part);
      }
    }
  }

  void loadData(List<SourceLine> body) {
    var assigned = 0;
    var unsetCount = 0;
    final errors = <String>[];
    for (final line in body) {
      if (line.text.isEmpty || line.text.startsWith('#')) continue;
      try {
        if (line.text.startsWith('UNSET ')) {
          unset(line.text.substring(6));
          unsetCount++;
        } else {
          assign(line.text);
          assigned++;
        }
      } on EngineFailure catch (error) {
        errors.add('ERROR line ${line.number}: ${error.reason}');
      }
    }
    output.add('DATA set=$assigned unset=$unsetCount errors=${errors.length}');
    output.addAll(errors);
  }

  void render(String name) {
    try {
      final renderer = Renderer(root, partials, strict);
      renderer.render(parseSource(templates[name]!), 0);
      final result = renderer.output.toString();
      final lines = result.isEmpty ? <String>[] : result.split('\n');
      if (result.endsWith('\n')) lines.removeLast();
      output.add('TEMPLATE $name OK lines=${lines.length} chars=${result.length}');
      output.addAll(lines);
    } on TemplateFailure catch (error) {
      output.add('TEMPLATE $name ERROR line ${error.number}: ${error.reason}');
    }
  }

  void dump() {
    final leaves = <String>[];
    void visit(Value value, String path) {
      if (value is Map<String, Value> && value.isNotEmpty) {
        final keys = value.keys.toList()..sort();
        for (final key in keys) visit(value[key], '$path.$key');
      } else if (value is List<Value> && value.isNotEmpty) {
        for (var index = 0; index < value.length; index++) visit(value[index], '$path[$index]');
      } else {
        final notation = value is String ? '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"' : value is Map<String, Value> ? '{}' : value is List<Value> ? '[]' : value.toString();
        leaves.add('$path = $notation');
      }
    }
    final keys = root.keys.toList()..sort();
    for (final key in keys) visit(root[key], key);
    output.add('DUMP leaves=${leaves.length}');
    output.addAll(leaves);
  }

  void run(List<String> lines) {
    var position = 0;
    while (lines[position] != 'END') {
      final line = lines[position++];
      final number = position;
      final parts = line.split(' ');
      final command = parts[0];
      final name = parts.length > 1 ? parts[1] : '';
      if (command == 'DATA' || command == 'PARTIAL' || command == 'TEMPLATE') {
        final body = <SourceLine>[];
        while (lines[position] != 'END$command') {
          body.add((number: position + 1, text: lines[position]));
          position++;
        }
        position++;
        if (command == 'DATA') {
          loadData(body);
        } else if (command == 'TEMPLATE') {
          templates[name] = body;
          render(name);
        } else {
          try {
            parseSource(body);
            final status = partials.containsKey(name) ? 'REPLACED' : 'DEFINED';
            partials[name] = body;
            output.add('PARTIAL $name $status lines=${body.length}');
          } on TemplateFailure catch (error) {
            output.add('PARTIAL $name ERROR line ${error.number}: ${error.reason}');
          }
        }
      } else if (command == 'RENDER') {
        if (templates.containsKey(name)) {
          render(name);
        } else {
          output.add("TEMPLATE $name ERROR line $number: unknown template '$name'");
        }
      } else if (command == 'DUMP') {
        dump();
      } else if (command == 'STRICT') {
        strict = name == 'ON';
        output.add(line);
      } else if (command == 'RESET') {
        root.clear();
        partials.clear();
        templates.clear();
        output.add('RESET');
      }
    }
  }
}

Future<void> main() async {
  final engine = TemplateEngine();
  engine.run((await stdin.transform(utf8.decoder).join()).split('\n'));
  if (engine.output.isNotEmpty) stdout.write('${engine.output.join('\n')}\n');
}
