import 'dart:io';

enum ValueKind { string, list, hash, set, zset }

sealed class Value {
  const Value();
  ValueKind get kind;
  bool get empty => false;
  Value copy();
}

final class TextValue extends Value {
  final String text;
  const TextValue(this.text);
  @override
  ValueKind get kind => ValueKind.string;
  @override
  TextValue copy() => this;
}

final class ListValue extends Value {
  final List<String> items;
  ListValue(this.items);
  @override
  ValueKind get kind => ValueKind.list;
  @override
  bool get empty => items.isEmpty;
  @override
  ListValue copy() => ListValue([...items]);
}

final class HashValue extends Value {
  final Map<String, String> fields;
  HashValue(this.fields);
  @override
  ValueKind get kind => ValueKind.hash;
  @override
  bool get empty => fields.isEmpty;
  @override
  HashValue copy() => HashValue({...fields});
}

final class SetValue extends Value {
  final Set<String> members;
  SetValue(this.members);
  @override
  ValueKind get kind => ValueKind.set;
  @override
  bool get empty => members.isEmpty;
  @override
  SetValue copy() => SetValue({...members});
}

final class SortedSetValue extends Value {
  final Map<String, int> scores;
  SortedSetValue(this.scores);
  @override
  ValueKind get kind => ValueKind.zset;
  @override
  bool get empty => scores.isEmpty;
  @override
  SortedSetValue copy() => SortedSetValue({...scores});
}

final class Entry {
  final Value value;
  final int? expiry;
  const Entry(this.value, [this.expiry]);
  Entry copy() => Entry(value.copy(), expiry);
}

typedef Database = Map<String, Entry>;

final class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
}

const wrongType = 'WRONGTYPE Operation against a key holding the wrong kind of value';
const notInteger = 'ERR value is not an integer or out of range';
const overflow = 'ERR increment or decrement would overflow';
const syntaxError = 'ERR syntax error';
const positive = 'ERR value is out of range, must be positive';
const noKey = 'ERR no such key';

int number(String text, [String error = notInteger]) {
  if (text == '0') return 0;
  final start = text.startsWith('-') ? 1 : 0;
  final digits = text.length - start;
  if (digits < 1 || digits > 9 || text.codeUnitAt(start) < 49 || text.codeUnitAt(start) > 57) {
    throw CommandError(error);
  }
  var value = 0;
  for (var i = start; i < text.length; i++) {
    final digit = text.codeUnitAt(i) - 48;
    if (digit < 0 || digit > 9) throw CommandError(error);
    value = value * 10 + digit;
  }
  return start == 0 ? value : -value;
}

int increment(int value, int delta) {
  final result = value + delta;
  if (result < -999999999 || result > 999999999) throw const CommandError(overflow);
  return result;
}

(int, int) normalizeRange(int length, int start, int stop) {
  if (start < 0) start += length;
  if (stop < 0) stop += length;
  if (start < 0) start = 0;
  if (stop >= length) stop = length - 1;
  return start <= stop ? (start, stop + 1) : (0, 0);
}

String quote(String text) => '"' + text.replaceAll(r'\', r'\\').replaceAll('"', r'\"') + '"';
List<String> integerReply(int value) => ['(integer) $value'];
List<String> textReply(String? value) => [value == null ? '(nil)' : quote(value)];
List<String> arrayReply(Iterable<String?> source) {
  final values = source.toList();
  if (values.isEmpty) return ['(empty array)'];
  final width = values.length.toString().length;
  return [
    for (var i = 0; i < values.length; i++)
      (i + 1).toString().padLeft(width) + ') ' + (values[i] == null ? '(nil)' : quote(values[i]!)),
  ];
}

List<String>? splitArguments(String line) {
  final words = <String>[];
  var position = 0;
  while (position < line.length) {
    if (line[position] == ' ') { position++; continue; }
    if (line[position] != '"') {
      final start = position;
      while (position < line.length && line[position] != ' ') { position++; }
      words.add(line.substring(start, position));
      continue;
    }
    position++;
    final value = StringBuffer();
    var closed = false;
    while (position < line.length) {
      var character = line[position++];
      if (character == '"') { closed = true; break; }
      if (character == r'\') {
        if (position == line.length || (line[position] != '"' && line[position] != r'\')) return null;
        character = line[position++];
      }
      value.write(character);
    }
    if (!closed || (position < line.length && line[position] != ' ')) return null;
    words.add(value.toString());
  }
  return words;
}

enum PatternKind { literal, any, star, characterClass }
final class PatternPart {
  final PatternKind kind;
  final int literal;
  final Set<int> characters;
  final bool negated;
  const PatternPart(this.kind, {this.literal = 0, this.characters = const {}, this.negated = false});
}

List<PatternPart> parsePattern(String text) {
  final parts = <PatternPart>[];
  for (var i = 0; i < text.length; i++) {
    final character = text.codeUnitAt(i);
    if (character == 92) {
      if (++i == text.length) throw const CommandError('ERR invalid pattern');
      parts.add(PatternPart(PatternKind.literal, literal: text.codeUnitAt(i)));
    } else if (character == 91) {
      final end = text.indexOf(']', i + 1);
      if (end < 0) throw const CommandError('ERR invalid pattern');
      var start = i + 1;
      final negated = start < end && text[start] == '^';
      if (negated) start++;
      if (start == end) throw const CommandError('ERR invalid pattern');
      final characters = <int>{};
      for (var j = start; j < end;) {
        if (j + 2 < end && text[j + 1] == '-') {
          final a = text.codeUnitAt(j), b = text.codeUnitAt(j + 2);
          for (var code = a < b ? a : b; code <= (a > b ? a : b); code++) { characters.add(code); }
          j += 3;
        } else {
          characters.add(text.codeUnitAt(j++));
        }
      }
      parts.add(PatternPart(PatternKind.characterClass, characters: characters, negated: negated));
      i = end;
    } else {
      parts.add(switch (character) {
        42 => const PatternPart(PatternKind.star),
        63 => const PatternPart(PatternKind.any),
        _ => PatternPart(PatternKind.literal, literal: character),
      });
    }
  }
  return parts;
}

bool matches(List<PatternPart> parts, String value) {
  var previous = List.filled(value.length + 1, false);
  previous[0] = true;
  for (final part in parts) {
    final current = List.filled(previous.length, false);
    if (part.kind == PatternKind.star) {
      current[0] = previous[0];
      for (var i = 1; i < current.length; i++) { current[i] = previous[i] || current[i - 1]; }
    } else {
      for (var i = 0; i < value.length; i++) {
        final character = value.codeUnitAt(i);
        final accepts = part.kind == PatternKind.any || (part.kind == PatternKind.literal
            ? part.literal == character : part.characters.contains(character) != part.negated);
        current[i + 1] = previous[i] && accepts;
      }
    }
    previous = current;
  }
  return previous.last;
}

enum BoundKind { negativeInfinity, finite, positiveInfinity }
final class Bound {
  final BoundKind kind;
  final int value;
  final bool inclusive;
  const Bound(this.kind, [this.value = 0, this.inclusive = true]);
  bool accepts(int score, bool lower) => switch (kind) {
    BoundKind.negativeInfinity => lower,
    BoundKind.positiveInfinity => !lower,
    BoundKind.finite => lower ? (inclusive ? score >= value : score > value) : (inclusive ? score <= value : score < value),
  };
}

Bound scoreBound(String word) {
  if (word == '-inf') return const Bound(BoundKind.negativeInfinity);
  if (word == '+inf') return const Bound(BoundKind.positiveInfinity);
  final inclusive = !word.startsWith('(');
  return Bound(BoundKind.finite, number(inclusive ? word : word.substring(1), 'ERR min or max is not a float'), inclusive);
}

enum Group { text, list, hash, set, sortedSet, key, control }
typedef CommandSpec = ({Group group, int minimum, int maximum, int parity});
final commands = buildCommands();
Map<String, CommandSpec> buildCommands() {
  final result = <String, CommandSpec>{};
  void add(Group group, String names, int minimum, [int maximum = -1, int parity = -1]) {
    for (final name in names.split(' ')) {
      result[name] = (group: group, minimum: minimum, maximum: maximum, parity: parity);
    }
  }
  add(Group.text, 'SET', 2);
  add(Group.text, 'GET INCR DECR STRLEN', 1, 1);
  add(Group.text, 'MSET', 2, -1, 0);
  add(Group.text, 'MGET', 1);
  add(Group.text, 'INCRBY DECRBY APPEND', 2, 2);
  add(Group.text, 'GETRANGE', 3, 3);
  add(Group.list, 'LPUSH RPUSH', 2);
  add(Group.list, 'LPOP RPOP', 1, 2);
  add(Group.list, 'LRANGE LSET LREM LTRIM', 3, 3);
  add(Group.list, 'LLEN', 1, 1);
  add(Group.list, 'LINDEX', 2, 2);
  add(Group.list, 'LINSERT', 4, 4);
  add(Group.hash, 'HSET', 3, -1, 1);
  add(Group.hash, 'HGET HEXISTS', 2, 2);
  add(Group.hash, 'HDEL', 2);
  add(Group.hash, 'HGETALL HLEN HKEYS HVALS', 1, 1);
  add(Group.hash, 'HINCRBY', 3, 3);
  add(Group.set, 'SADD SREM', 2);
  add(Group.set, 'SISMEMBER', 2, 2);
  add(Group.set, 'SMEMBERS SCARD', 1, 1);
  add(Group.set, 'SINTER SUNION SDIFF', 1);
  add(Group.set, 'SINTERSTORE SUNIONSTORE SDIFFSTORE', 2);
  add(Group.sortedSet, 'ZADD', 3, -1, 1);
  add(Group.sortedSet, 'ZSCORE ZRANK', 2, 2);
  add(Group.sortedSet, 'ZINCRBY', 3, 3);
  add(Group.sortedSet, 'ZREM', 2);
  add(Group.sortedSet, 'ZCARD', 1, 1);
  add(Group.sortedSet, 'ZRANGE ZRANGEBYSCORE', 3, 4);
  add(Group.key, 'DEL EXISTS', 1);
  add(Group.key, 'TYPE KEYS TTL PERSIST TICK', 1, 1);
  add(Group.key, 'RENAME RENAMENX', 2, 2);
  add(Group.key, 'EXPIRE', 2, 3);
  add(Group.key, 'TIME DBSIZE FLUSH INFO', 0, 0);
  add(Group.control, 'BEGIN COMMIT ROLLBACK', 0, 0);
  add(Group.control, 'SNAPSHOT RESTORE', 1, 1);
  return result;
}

final class Store {
  Database database = {};
  final List<Database> transactions = [];
  final Map<String, Database> snapshots = {};
  int time = 0;

  static Database copy(Database source) => {for (final entry in source.entries) entry.key: entry.value.copy()};
  T read<T extends Value>(String key, T empty) {
    final entry = database[key];
    if (entry == null) return empty;
    final value = entry.value;
    if (value is! T) throw const CommandError(wrongType);
    return value.copy() as T;
  }
  void replace(String key, Value value, [int? expiry]) {
    if (value.empty) {
      database.remove(key);
    } else {
      database[key] = Entry(value, expiry);
    }
  }
  void update(String key, Value value) => replace(key, value, database[key]?.expiry);
  int purge() {
    final expired = database.keys.where((key) {
      final expiry = database[key]!.expiry;
      return expiry != null && expiry <= time;
    }).toList();
    for (final key in expired) { database.remove(key); }
    return expired.length;
  }
  List<String> ordered(Iterable<String> values) => values.toList()..sort();

  List<String> textCommand(String command, List<String> args) {
    final key = args[0];
    if (command == 'SET') {
      final options = <String>{};
      String? secondsWord;
      for (var i = 2; i < args.length; i++) {
        final option = args[i].toUpperCase();
        if (!['NX', 'XX', 'EX', 'KEEPTTL', 'GET'].contains(option) || !options.add(option)) {
          throw const CommandError(syntaxError);
        }
        if (option == 'EX') {
          if (++i == args.length) throw const CommandError(syntaxError);
          secondsWord = args[i];
        }
      }
      if (options.contains('NX') && options.contains('XX') || options.contains('EX') && options.contains('KEEPTTL')) {
        throw const CommandError(syntaxError);
      }
      int? expiry;
      if (secondsWord != null) {
        final seconds = number(secondsWord);
        if (seconds <= 0) throw const CommandError("ERR invalid expire time in 'set' command");
        expiry = time + seconds;
      }
      final entry = database[key], exists = entry != null;
      String? old;
      if (options.contains('GET')) {
        final value = read(key, const TextValue(''));
        if (exists) old = value.text;
      }
      if (options.contains('KEEPTTL') && exists) expiry = entry!.expiry;
      final changed = !(options.contains('NX') && exists) && !(options.contains('XX') && !exists);
      if (changed) replace(key, TextValue(args[1]), expiry);
      return options.contains('GET') ? textReply(old) : changed ? ['OK'] : textReply(null);
    }
    if (command == 'MSET') {
      for (var i = 0; i < args.length; i += 2) { replace(args[i], TextValue(args[i + 1])); }
      return ['OK'];
    }
    if (command == 'MGET') {
      return arrayReply(args.map((key) => switch (database[key]?.value) {
        TextValue(:final text) => text,
        _ => null,
      }));
    }
    if (['INCR', 'DECR', 'INCRBY', 'DECRBY'].contains(command)) {
      var delta = args.length == 2 ? number(args[1]) : 1;
      if (command == 'DECR' || command == 'DECRBY') delta = -delta;
      final text = read(key, const TextValue('')).text;
      final result = increment(database.containsKey(key) ? number(text) : 0, delta);
      update(key, TextValue('$result'));
      return integerReply(result);
    }
    if (command == 'GETRANGE') {
      final start = number(args[1]), stop = number(args[2]);
      final text = read(key, const TextValue('')).text;
      final (first, end) = normalizeRange(text.length, start, stop);
      return textReply(text.substring(first, end));
    }
    var text = read(key, const TextValue('')).text;
    if (command == 'GET') return textReply(database.containsKey(key) ? text : null);
    if (command == 'STRLEN') return integerReply(text.length);
    text += args[1];
    update(key, TextValue(text));
    return integerReply(text.length);
  }

  List<String> listCommand(String command, List<String> args) {
    final key = args[0];
    if (command == 'LPOP' || command == 'RPOP') {
      final counted = args.length == 2;
      var count = counted ? number(args[1], positive) : 1;
      if (count < 0) throw const CommandError(positive);
      final value = read(key, ListValue([]));
      if (!database.containsKey(key)) return textReply(null);
      if (count > value.items.length) count = value.items.length;
      final removed = <String>[];
      for (var i = 0; i < count; i++) {
        removed.add(value.items.removeAt(command == 'LPOP' ? 0 : value.items.length - 1));
      }
      update(key, value);
      return counted ? arrayReply(removed) : textReply(removed.first);
    }
    if (command == 'LRANGE' || command == 'LTRIM') {
      final start = number(args[1]), stop = number(args[2]);
      final value = read(key, ListValue([]));
      final (first, end) = normalizeRange(value.items.length, start, stop);
      final kept = value.items.sublist(first, end);
      if (command == 'LRANGE') return arrayReply(kept);
      update(key, ListValue(kept));
      return ['OK'];
    }
    if (command == 'LINDEX' || command == 'LSET') {
      var index = number(args[1]);
      final value = read(key, ListValue([]));
      if (index < 0) index += value.items.length;
      final inside = index >= 0 && index < value.items.length;
      if (command == 'LINDEX') return textReply(inside ? value.items[index] : null);
      if (!database.containsKey(key)) throw const CommandError(noKey);
      if (!inside) throw const CommandError('ERR index out of range');
      value.items[index] = args[2];
      update(key, value);
      return ['OK'];
    }
    if (command == 'LREM') {
      final count = number(args[1]);
      final value = read(key, ListValue([]));
      final source = count < 0 ? value.items.reversed : value.items;
      final limit = count == 0 ? value.items.length : count.abs();
      var removed = 0;
      final kept = <String>[];
      for (final item in source) {
        if (item == args[2] && removed < limit) { removed++; } else { kept.add(item); }
      }
      update(key, ListValue(count < 0 ? kept.reversed.toList() : kept));
      return integerReply(removed);
    }
    if (command == 'LINSERT') {
      final where = args[1].toUpperCase();
      if (where != 'BEFORE' && where != 'AFTER') throw const CommandError(syntaxError);
      final value = read(key, ListValue([]));
      if (!database.containsKey(key)) return integerReply(0);
      final pivot = value.items.indexOf(args[2]);
      if (pivot < 0) return integerReply(-1);
      value.items.insert(pivot + (where == 'AFTER' ? 1 : 0), args[3]);
      update(key, value);
      return integerReply(value.items.length);
    }
    final value = read(key, ListValue([]));
    if (command == 'LLEN') return integerReply(value.items.length);
    for (final element in args.skip(1)) {
      if (command == 'LPUSH') { value.items.insert(0, element); } else { value.items.add(element); }
    }
    update(key, value);
    return integerReply(value.items.length);
  }

  List<String> hashCommand(String command, List<String> args) {
    final key = args[0];
    if (command == 'HINCRBY') {
      final delta = number(args[2]);
      final value = read(key, HashValue({}));
      final text = value.fields[args[1]];
      final old = text == null ? 0 : number(text, 'ERR hash value is not an integer');
      final result = increment(old, delta);
      value.fields[args[1]] = '$result';
      update(key, value);
      return integerReply(result);
    }
    final value = read(key, HashValue({}));
    if (command == 'HSET') {
      var added = 0;
      for (var i = 1; i < args.length; i += 2) {
        if (!value.fields.containsKey(args[i])) added++;
        value.fields[args[i]] = args[i + 1];
      }
      update(key, value);
      return integerReply(added);
    }
    if (command == 'HGET') return textReply(value.fields[args[1]]);
    if (command == 'HDEL') {
      var removed = 0;
      for (final field in args.skip(1)) { if (value.fields.remove(field) != null) removed++; }
      update(key, value);
      return integerReply(removed);
    }
    if (command == 'HLEN') return integerReply(value.fields.length);
    if (command == 'HEXISTS') return integerReply(value.fields.containsKey(args[1]) ? 1 : 0);
    final output = <String>[];
    for (final field in ordered(value.fields.keys)) {
      if (command != 'HVALS') output.add(field);
      if (command != 'HKEYS') output.add(value.fields[field]!);
    }
    return arrayReply(output);
  }

  List<String> setCommand(String command, List<String> args) {
    final storing = command.endsWith('STORE');
    final operation = storing ? command.substring(0, command.length - 5) : command;
    if (['SINTER', 'SUNION', 'SDIFF'].contains(operation)) {
      final sources = [
        for (final key in args.skip(storing ? 1 : 0)) read(key, SetValue({})).members,
      ];
      final result = sources.first;
      for (final source in sources.skip(1)) {
        if (operation == 'SUNION') {
          result.addAll(source);
        } else {
          result.removeWhere((member) => operation == 'SINTER' ? !source.contains(member) : source.contains(member));
        }
      }
      if (storing) {
        replace(args[0], SetValue(result));
        return integerReply(result.length);
      }
      return arrayReply(ordered(result));
    }
    final value = read(args[0], SetValue({}));
    if (command == 'SCARD') return integerReply(value.members.length);
    if (command == 'SMEMBERS') return arrayReply(ordered(value.members));
    if (command == 'SISMEMBER') return integerReply(value.members.contains(args[1]) ? 1 : 0);
    var changed = 0;
    for (final member in args.skip(1)) {
      if (command == 'SADD' ? value.members.add(member) : value.members.remove(member)) changed++;
    }
    update(args[0], value);
    return integerReply(changed);
  }

  List<String> sortedSetCommand(String command, List<String> args) {
    final key = args[0];
    if (command == 'ZADD') {
      final scores = [for (var i = 1; i < args.length; i += 2) number(args[i])];
      final value = read(key, SortedSetValue({}));
      var added = 0;
      for (var i = 0; i < scores.length; i++) {
        final member = args[2 * i + 2];
        if (!value.scores.containsKey(member)) added++;
        value.scores[member] = scores[i];
      }
      update(key, value);
      return integerReply(added);
    }
    if (command == 'ZINCRBY') {
      final delta = number(args[1]);
      final value = read(key, SortedSetValue({}));
      final result = increment(value.scores[args[2]] ?? 0, delta);
      value.scores[args[2]] = result;
      update(key, value);
      return textReply('$result');
    }
    final byIndex = command == 'ZRANGE', byScore = command == 'ZRANGEBYSCORE', withScores = args.length == 4;
    var start = 0, stop = 0;
    var minimum = const Bound(BoundKind.negativeInfinity), maximum = const Bound(BoundKind.positiveInfinity);
    if (byIndex || byScore) {
      if (withScores && args[3].toUpperCase() != 'WITHSCORES') throw const CommandError(syntaxError);
      if (byIndex) { start = number(args[1]); stop = number(args[2]); }
      else { minimum = scoreBound(args[1]); maximum = scoreBound(args[2]); }
    }
    final value = read(key, SortedSetValue({}));
    if (command == 'ZSCORE') return textReply(value.scores[args[1]]?.toString());
    if (command == 'ZREM') {
      var removed = 0;
      for (final member in args.skip(1)) { if (value.scores.remove(member) != null) removed++; }
      update(key, value);
      return integerReply(removed);
    }
    if (command == 'ZCARD') return integerReply(value.scores.length);
    var sorted = value.scores.entries.toList()..sort((left, right) {
      final comparison = left.value.compareTo(right.value);
      return comparison != 0 ? comparison : left.key.compareTo(right.key);
    });
    if (command == 'ZRANK') {
      final rank = sorted.indexWhere((entry) => entry.key == args[1]);
      return rank < 0 ? textReply(null) : integerReply(rank);
    }
    if (byIndex) {
      final (first, end) = normalizeRange(sorted.length, start, stop);
      sorted = sorted.sublist(first, end);
    }
    final output = <String>[];
    for (final entry in sorted) {
      if (byScore && (!minimum.accepts(entry.value, true) || !maximum.accepts(entry.value, false))) continue;
      output.add(entry.key);
      if (withScores) output.add(entry.value.toString());
    }
    return arrayReply(output);
  }

  List<String> keyCommand(String command, List<String> args) {
    if (command == 'DEL' || command == 'EXISTS') {
      var count = 0;
      for (final key in args) {
        if (command == 'DEL' ? database.remove(key) != null : database.containsKey(key)) count++;
      }
      return integerReply(count);
    }
    if (command == 'KEYS') {
      final pattern = parsePattern(args[0]);
      return arrayReply(ordered(database.keys.where((key) => matches(pattern, key))));
    }
    if (command == 'EXPIRE') {
      final condition = args.length == 3 ? args[2].toUpperCase() : '';
      if (args.length == 3 && !['NX', 'XX', 'GT', 'LT'].contains(condition)) {
        throw CommandError('ERR Unsupported option ' + args[2]);
      }
      final seconds = number(args[1]);
      final entry = database[args[0]];
      if (entry == null) return integerReply(0);
      final old = entry.expiry, expiry = time + seconds;
      final rejected = switch (condition) {
        'NX' => old != null,
        'XX' => old == null,
        'GT' => old == null || expiry <= old,
        'LT' => old != null && expiry >= old,
        _ => false,
      };
      if (rejected) return integerReply(0);
      if (seconds <= 0) { database.remove(args[0]); }
      else { database[args[0]] = Entry(entry.value, expiry); }
      return integerReply(1);
    }
    if (command == 'TICK') {
      final ticks = number(args[0]);
      if (ticks <= 0) throw const CommandError(positive);
      time += ticks;
      return integerReply(purge());
    }
    if (command == 'TIME') return integerReply(time);
    if (command == 'DBSIZE') return integerReply(database.length);
    if (command == 'FLUSH') { database.clear(); return ['OK']; }
    if (command == 'INFO') {
      final keys = database.length, expires = database.values.where((entry) => entry.expiry != null).length;
      final parts = ['keys=$keys', 'expires=$expires'];
      for (final kind in ValueKind.values) {
        final name = kind.name, count = database.values.where((entry) => entry.value.kind == kind).length;
        parts.add('$name=$count');
      }
      final depth = transactions.length, snapshotCount = snapshots.length;
      parts.addAll(['time=$time', 'depth=$depth', 'snapshots=$snapshotCount']);
      return [parts.join(',')];
    }
    final key = args[0], entry = database[key];
    if (command == 'TYPE') return [entry?.value.kind.name ?? 'none'];
    if (command == 'TTL') return integerReply(entry == null ? -2 : entry.expiry == null ? -1 : entry.expiry! - time);
    if (command == 'PERSIST') {
      if (entry == null || entry.expiry == null) return integerReply(0);
      database[key] = Entry(entry.value);
      return integerReply(1);
    }
    if (entry == null) throw const CommandError(noKey);
    if (command == 'RENAMENX' && database.containsKey(args[1])) return integerReply(0);
    if (key != args[1]) { database[args[1]] = entry; database.remove(key); }
    return command == 'RENAME' ? ['OK'] : integerReply(1);
  }

  List<String> controlCommand(String command, List<String> args) {
    if (command == 'BEGIN') { transactions.add(copy(database)); return ['OK']; }
    if (command == 'COMMIT' || command == 'ROLLBACK') {
      if (transactions.isEmpty) throw const CommandError('ERR no transaction');
      final saved = transactions.removeLast();
      if (command == 'ROLLBACK') { database = saved; purge(); }
      return ['OK'];
    }
    if (command == 'SNAPSHOT') { snapshots[args[0]] = copy(database); return ['OK']; }
    final saved = snapshots[args[0]];
    if (saved == null) throw const CommandError('ERR no such snapshot');
    database = copy(saved);
    purge();
    return ['OK'];
  }

  List<String> execute(String line) {
    final words = splitArguments(line);
    if (words == null) return ['Invalid argument(s)'];
    final original = words.first, command = original.toUpperCase();
    final spec = commands[command];
    if (spec == null) throw CommandError("ERR unknown command '$original'");
    final args = words.sublist(1);
    if (args.length < spec.minimum || spec.maximum >= 0 && args.length > spec.maximum ||
        spec.parity >= 0 && args.length % 2 != spec.parity) {
      final name = command.toLowerCase();
      throw CommandError("ERR wrong number of arguments for '$name' command");
    }
    return switch (spec.group) {
      Group.text => textCommand(command, args),
      Group.list => listCommand(command, args),
      Group.hash => hashCommand(command, args),
      Group.set => setCommand(command, args),
      Group.sortedSet => sortedSetCommand(command, args),
      Group.key => keyCommand(command, args),
      Group.control => controlCommand(command, args),
    };
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final store = Store();
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      stdout.writeln(store.execute(line).join('\n'));
    } on CommandError catch (error) {
      stdout.writeln('(error) ' + error.message);
    }
  }
}
