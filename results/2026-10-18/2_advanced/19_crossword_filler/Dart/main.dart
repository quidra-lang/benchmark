import 'dart:io';
import 'dart:math' as math;
import 'grid.dart';
import 'slots.dart';
import 'word_index.dart';
import 'filler.dart';
import 'render.dart';

const letterPoints = [1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10];
List<String> readLines(String name) {
  final lines = File('input/$name').readAsStringSync().split('\n');
  return lines.sublist(0, lines.length - 1);
}
bool ignored(String line) => line.isEmpty || line.startsWith('#');
String joined(List<String> values, String separator) => values.isEmpty ? '-' : values.join(separator);
void writeLines(String name, List<String> lines) {
  File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}
void writeParagraphs(String name, List<List<String>> paragraphs) {
  final lines = <String>[];
  for (final paragraph in paragraphs) {
    if (lines.isNotEmpty) {
      lines.add('');
    }
    lines.addAll(paragraph);
  }
  writeLines(name, lines);
}

class Settings {
  int budget;
  int minimum;
  String symmetry;
  final int relax;
  final int weak;
  Settings(this.budget, this.minimum, this.symmetry, this.relax, this.weak);
  Settings copy() => Settings(budget, minimum, symmetry, relax, weak);
}

Settings readSettings(List<String> lines) {
  final values = <String, String>{};
  for (final line in lines) {
    if (!ignored(line)) {
      final parts = line.split(' ');
      values[parts.first] = parts[1];
    }
  }
  return Settings(int.parse(values['node_budget']!), int.parse(values['min_score']!), values['symmetry']!, int.parse(values['relax_step']!), int.parse(values['weak_score']!));
}

class WordList {
  final int lineCount;
  late final WordIndex index;
  final invalid = <(int, String)>[];
  final duplicates = <(int, String, int)>[];
  WordList(List<String> lines) : lineCount = lines.length {
    final scores = <String, int>{};
    final firstLines = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final reason = wordLineError(lines[i]);
      if (reason.isNotEmpty) {
        invalid.add((i + 1, reason));
        continue;
      }
      final parts = lines[i].split(' ');
      if (firstLines.containsKey(parts.first)) {
        duplicates.add((i + 1, parts.first, firstLines[parts.first]!));
      } else {
        scores[parts.first] = int.parse(parts[1]);
        firstLines[parts.first] = i + 1;
      }
    }
    index = WordIndex(scores);
  }

  List<String> report() {
    final lines = ['WORDLIST lines=$lineCount valid=${index.words.length} invalid=${invalid.length} duplicates=${duplicates.length}'];
    for (final (line, reason) in invalid) {
      lines.add('invalid $line $reason');
    }
    for (final (line, word, first) in duplicates) {
      lines.add('duplicate $line $word first=$first');
    }
    final lengths = index.byLength.keys.toList()..sort();
    for (final length in lengths) {
      final words = index.byLength[length]!;
      final total = words.fold(0, (sum, id) => sum + index.words[id].score);
      final best = index.words[words.first];
      lines.add('length $length words=${words.length} average=${decimal(total, words.length, 2)} best=${best.text}:${best.score}');
    }
    final bands = <String>[];
    for (var band = 0; band < 5; band++) {
      final low = band * 20 + 1, high = (band + 1) * 20;
      bands.add('$low-$high=${index.words.where((word) => word.score >= low && word.score <= high).length}');
    }
    lines.add('bands ${bands.join(' ')}');
    lines.add('top ${index.words.take(5).map((word) => '${word.text}:${word.score}').join(' ')}');
    final rare = [for (var letter = 65; letter <= 90; letter++) (index.words.where((word) => word.letters.contains(letter)).length, letter)]
      ..sort((a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    lines.add('rare_letters ${rare.take(5).map((entry) => '${String.fromCharCode(entry.$2)}:${entry.$1}').join(' ')}');
    return lines;
  }
}

class Clue {
  final String text;
  var uses = 0;
  Clue(this.text);
}

class ClueBook {
  var entries = 0, added = 0;
  final invalid = <(int, String)>[];
  final unknown = <(int, String)>[];
  final List<List<Clue>> clues;
  ClueBook(List<String> lines, WordIndex index) : clues = List.generate(index.words.length, (_) => []) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (ignored(line)) {
        continue;
      }
      entries++;
      final reason = clueLineError(line);
      if (reason.isNotEmpty) {
        invalid.add((i + 1, reason));
        continue;
      }
      final parts = line.split('|');
      final id = index.lookup[parts.first];
      if (id == null) {
        unknown.add((i + 1, parts.first));
      } else {
        clues[id].add(Clue(parts[1]));
        added++;
      }
    }
  }

  String choose(int id) {
    if (clues[id].isEmpty) {
      return '';
    }
    var chosen = 0;
    for (var i = 1; i < clues[id].length; i++) {
      if (clues[id][i].uses < clues[id][chosen].uses) {
        chosen = i;
      }
    }
    clues[id][chosen].uses++;
    return clues[id][chosen].text;
  }

  List<String> report(WordIndex index) {
    final lines = ['CLUES entries=$entries valid=$added invalid=${invalid.length} unknown=${unknown.length} words=${clues.where((list) => list.isNotEmpty).length}'];
    for (final (line, reason) in invalid) {
      lines.add('clue_invalid $line $reason');
    }
    for (final (line, word) in unknown) {
      lines.add('clue_unknown $line $word');
    }
    final all = clues.expand((list) => list).toList();
    final used = all.where((clue) => clue.uses > 0).length;
    final repeated = all.where((clue) => clue.uses >= 2).length;
    lines.add('CLUE_USE used=$used unused=${added - used} repeated=$repeated');
    final names = index.lookup.keys.toList()..sort();
    for (final word in names) {
      final list = clues[index.lookup[word]!];
      for (var i = 0; i < list.length; i++) {
        if (list[i].uses >= 2) {
          lines.add('repeated $word clue=${i + 1} uses=${list[i].uses}');
        }
      }
    }
    return lines;
  }
}

class Block {
  final String name;
  final options = <String>[];
  final rows = <String>[];
  Block(this.name);
}

List<Block> splitBlocks(List<String> lines) {
  final blocks = <Block>[];
  Block? current;
  for (final line in lines) {
    if (current == null) {
      if (line.startsWith('TEMPLATE ')) {
        current = Block(line.substring(9));
      }
    } else if (line == 'END') {
      blocks.add(current);
      current = null;
    } else if (line.contains(' ')) {
      current.options.add(line);
    } else {
      current.rows.add(line);
    }
  }
  return blocks;
}

bool validName(String name) => name.isNotEmpty && name.length <= 20 && name.codeUnits.every((c) => (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95);
bool validRow(String row, int width) => row.length >= 3 && row.length <= 15 && row.length == width && row.codeUnits.every((c) => c == 46 || c == 35 || (c >= 65 && c <= 90));

class Prepared {
  final Settings settings;
  final Layout layout;
  final GridState initial;
  final List<bool> themeSlots;
  Prepared(this.settings, this.layout, this.initial, this.themeSlots);
}

(Prepared?, String) prepare(Block block, Settings defaults, Set<String> names, WordIndex index) {
  if (!validName(block.name)) {
    return (null, 'bad name');
  }
  if (names.contains(block.name)) {
    return (null, 'duplicate name');
  }
  final settings = defaults.copy();
  final seen = <String>{}, themeNames = <String>{};
  final themes = <String>[];
  for (var i = 0; i < block.options.length; i++) {
    final line = block.options[i];
    final split = line.indexOf(' ');
    final key = line.substring(0, split), value = line.substring(split + 1);
    var valid = false;
    if (key == 'theme') {
      if (validWord(value) && !themeNames.contains(value)) {
        themes.add(value);
        themeNames.add(value);
        valid = true;
      }
    } else if (!seen.contains(key)) {
      if (key == 'node_budget' && validInteger(value, 1, 100000)) {
        settings.budget = int.parse(value);
        valid = true;
      } else if (key == 'min_score' && validInteger(value, 1, 100)) {
        settings.minimum = int.parse(value);
        valid = true;
      } else if (key == 'symmetry' && ['rot180', 'mirror', 'none'].contains(value)) {
        settings.symmetry = value;
        valid = true;
      }
    }
    if (!valid) {
      return (null, 'bad option ${i + 1}');
    }
    seen.add(key);
  }
  if (block.rows.length < 3 || block.rows.length > 15) {
    return (null, 'bad height');
  }
  final width = block.rows.first.length;
  for (var i = 0; i < block.rows.length; i++) {
    if (!validRow(block.rows[i], width)) {
      return (null, 'bad row ${i + 1}');
    }
  }
  final grid = Grid(block.rows);
  if (settings.symmetry != 'none') {
    final cell = grid.asymmetricCell(settings.symmetry);
    if (cell >= 0) {
      return (null, 'asymmetric at ${grid.location(cell)}');
    }
  }
  final components = grid.componentCount;
  if (components != 1) {
    return (null, 'disconnected components=$components');
  }
  final reason = shortRunError(grid);
  if (reason.isNotEmpty) {
    return (null, reason);
  }
  final layout = Layout(grid);
  final orphan = layout.orphanCell;
  if (orphan >= 0) {
    return (null, 'orphan cell ${grid.location(orphan)}');
  }
  final initial = GridState(grid.cells, layout.slots.length, index.words.length);
  final themeSlots = List.filled(layout.slots.length, false);
  for (var i = 0; i < themes.length; i++) {
    final theme = themes[i];
    final id = index.lookup[theme];
    if (id == null) {
      return (null, 'unknown theme ${i + 1}');
    }
    var chosen = -1;
    for (final slot in layout.slots) {
      if (initial.words[slot.index] < 0 && slot.length == theme.length && matches(index.words[id].letters, initial.pattern(slot))) {
        chosen = slot.index;
        break;
      }
    }
    if (chosen < 0) {
      return (null, 'theme ${i + 1} does not fit');
    }
    initial.assign(layout.slots[chosen], id, index);
    themeSlots[chosen] = true;
  }
  return (Prepared(settings, layout, initial, themeSlots), '');
}

class Completed {
  final Prepared prepared;
  final attempts = <Attempt>[];
  late final GridState state;
  late final List<String> chosen;
  Completed(this.prepared, WordIndex index, ClueBook clues) {
    var minimum = prepared.settings.minimum;
    while (true) {
      final attempt = Attempt(prepared.layout, index, prepared.initial, minimum, prepared.settings.budget);
      attempt.run();
      attempts.add(attempt);
      if (attempt.outcome == 'filled' || prepared.settings.relax < 1 || minimum <= 1) {
        break;
      }
      minimum = math.max(minimum - prepared.settings.relax, 1);
    }
    state = finalAttempt.finalState.copy();
    chosen = List.filled(prepared.layout.slots.length, '');
    for (final across in [true, false]) {
      for (final slot in prepared.layout.slots) {
        if (slot.across == across && state.words[slot.index] >= 0) {
          chosen[slot.index] = clues.choose(state.words[slot.index]);
        }
      }
    }
  }
  Attempt get finalAttempt => attempts.last;
  bool get filled => finalAttempt.outcome == 'filled';
  int totalScore(WordIndex index) => state.words.where((id) => id >= 0).fold(0, (sum, id) => sum + index.words[id].score);
  String entry(Slot slot, WordIndex index) {
    final word = index.words[state.words[slot.index]];
    return '${slot.label}:${word.text}:${word.score}';
  }

  List<String> clueParagraph(String name, WordIndex index) {
    final lines = ['TEMPLATE $name'];
    var clued = 0, missing = 0, unfilled = 0;
    for (final (heading, across) in [('ACROSS', true), ('DOWN', false)]) {
      final group = prepared.layout.slots.where((slot) => slot.across == across).toList();
      if (group.isNotEmpty) {
        lines.add(heading);
      }
      for (final slot in group) {
        final id = state.words[slot.index];
        if (id < 0) {
          unfilled++;
          lines.add(listLine(slot, '(unfilled)', String.fromCharCodes(state.pattern(slot)), '-', false));
          continue;
        }
        var clue = chosen[slot.index];
        if (clue.isEmpty) {
          missing++;
          clue = '(no clue)';
        } else {
          clued++;
        }
        lines.add(listLine(slot, clue, index.words[id].text, '${index.words[id].score}', prepared.themeSlots[slot.index]));
      }
    }
    lines.add('clued=$clued missing=$missing unfilled=$unfilled');
    return lines;
  }

  List<String> statsParagraph(String name, WordIndex index) {
    final p = prepared, layout = prepared.layout, grid = prepared.layout.grid, slots = prepared.layout.slots;
    final whites = grid.whiteCells;
    final blacks = grid.cells.length - whites.length;
    final givens = whites.where((cell) => grid.cells[cell] != 46).length;
    final holding = ['rot180', 'mirror'].where((symmetry) => grid.asymmetricCell(symmetry) < 0).toList();
    final symmetry = holding.isEmpty ? 'none' : holding.join(',');
    final lengths = slots.map((slot) => slot.length).toSet().toList()..sort();
    final across = slots.where((slot) => slot.across).length;
    final lengthSum = slots.fold(0, (sum, slot) => sum + slot.length);
    final unchecked = whites.where((cell) => layout.ownerCount(cell) == 1).length;
    final lengthText = [for (final length in lengths) '$length:${slots.where((slot) => slot.length == length).length}'].join(',');
    final lines = ['TEMPLATE $name',
      'grid size=${grid.width}x${grid.height} blocks=$blacks white=${whites.length} density=${decimal(100 * blacks, grid.cells.length, 1)} givens=$givens required=${p.settings.symmetry} symmetry=$symmetry',
      'slots across=$across down=${slots.length - across} total=${slots.length} lengths=$lengthText avg_length=${decimal(lengthSum, slots.length, 2)} longest=${lengths.last} unchecked=$unchecked'];
    final themes = [for (final slot in slots) if (p.themeSlots[slot.index]) entry(slot, index)];
    if (themes.isNotEmpty) {
      lines.add('themes ${themes.join(' ')}');
    }
    final supply = [for (final length in lengths) '$length:${(index.byLength[length] ?? <int>[]).where((id) => index.words[id].score >= p.settings.minimum).length}'];
    lines.add('coverage ${supply.join(' ')}');
    final tight = [for (final slot in slots) if (!p.themeSlots[slot.index]) (index.candidates(p.initial.pattern(slot), p.settings.minimum, p.initial.used).length, slot.index)]
      ..sort((a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    lines.add('tightest ${joined(tight.take(3).map((item) => '${slots[item.$2].label}:${item.$1}').toList(), ' ')}');
    for (var i = 0; i < attempts.length; i++) {
      final attempt = attempts[i];
      lines.add('attempt ${i + 1} min_score=${attempt.minimum} budget=${attempt.budget} outcome=${attempt.outcome} nodes=${attempt.nodes} backtracks=${attempt.backtracks} prunes=${attempt.prunes} dead_ends=${attempt.deadEnds} max_depth=${attempt.maxDepth}');
    }
    final last = finalAttempt;
    lines.add('trace ${joined(last.trace, ' ')}');
    final hot = [for (var i = 0; i < slots.length; i++) if (last.failures[i] > 0) i]
      ..sort((a, b) => last.failures[a] == last.failures[b] ? a.compareTo(b) : last.failures[b].compareTo(last.failures[a]));
    lines.add('hotspots ${joined(hot.take(3).map((i) => '${slots[i].label}:${last.failures[i]}').toList(), ' ')}');
    if (filled) {
      lines.add('order ${joined(last.sequence.map((i) => slots[i].label).toList(), ' ')}');
      var weakest = 0;
      final weak = <String>[];
      for (var i = 0; i < slots.length; i++) {
        final score = index.words[state.words[i]].score;
        if (score < index.words[state.words[weakest]].score) {
          weakest = i;
        }
        if (score < p.settings.weak) {
          weak.add(entry(slots[i], index));
        }
      }
      final total = totalScore(index);
      lines.add('quality total=$total average=${decimal(total, slots.length, 2)} weakest=${entry(slots[weakest], index)} weak=${joined(weak, ',')}');
      final present = whites.map((cell) => state.letters[cell]).toSet();
      final missing = String.fromCharCodes([for (var letter = 65; letter <= 90; letter++) if (!present.contains(letter)) letter]);
      final points = whites.fold(0, (sum, cell) => sum + letterPoints[state.letters[cell] - 65]);
      var worst = -1, worstSum = 0;
      for (final cell in whites) {
        final a = layout.acrossSlot[cell], d = layout.downSlot[cell];
        if (a < 0 || d < 0) {
          continue;
        }
        final sum = index.words[state.words[a]].score + index.words[state.words[d]].score;
        if (worst < 0 || sum < worstSum) {
          worst = cell;
          worstSum = sum;
        }
      }
      var crossing = '-';
      if (worst >= 0) {
        final a = layout.acrossSlot[worst], d = layout.downSlot[worst];
        crossing = '${grid.location(worst)} ${slots[a].label}:${index.words[state.words[a]].text}+${slots[d].label}:${index.words[state.words[d]].text}=$worstSum';
      }
      lines.add('letters distinct=${present.length} pangram=${missing.isEmpty ? 'yes' : 'no'} missing=${missing.isEmpty ? '-' : missing} scrabble=${decimal(points, whites.length, 2)} worst_crossing=$crossing');
    } else {
      final assigned = state.words.where((id) => id >= 0).length;
      final lettered = whites.where((cell) => state.letters[cell] != 46).length;
      final blocked = [for (final slot in slots) if (state.words[slot.index] < 0 && index.candidates(state.pattern(slot), last.minimum, state.used).isEmpty) slot.label];
      lines.add('partial assigned=$assigned/${slots.length} letters=$lettered/${whites.length} blocked=${joined(blocked, ',')}');
    }
    return lines;
  }
}

class Template {
  final String name;
  final String error;
  final Completed? completed;
  Template(this.name, this.error, this.completed);
  List<String> gridParagraph() {
    final lines = ['TEMPLATE $name'];
    if (error.isNotEmpty) {
      return [...lines, 'error $error'];
    }
    final result = completed!, last = completed!.finalAttempt;
    return [...lines, 'outcome=${last.outcome} attempts=${result.attempts.length} min_score=${last.minimum}', ...gridLines(result.prepared.layout.grid, result.state.letters), 'numbers', ...numberLines(result.prepared.layout)];
  }
}

List<List<String>> overallParagraphs(List<Template> templates, WordIndex index) {
  final valid = templates.where((template) => template.error.isEmpty).toList();
  final filled = valid.where((template) => template.completed!.filled).toList();
  final ranked = [...filled]..sort((a, b) {
    final first = a.completed!, second = b.completed!;
    final left = first.totalScore(index) * second.prepared.layout.slots.length;
    final right = second.totalScore(index) * first.prepared.layout.slots.length;
    return left == right ? a.name.compareTo(b.name) : right.compareTo(left);
  });
  final ranking = ['RANKING'];
  for (var i = 0; i < ranked.length; i++) {
    final template = ranked[i], result = ranked[i].completed!;
    final total = result.totalScore(index), entries = result.prepared.layout.slots.length;
    ranking.add('rank ${i + 1} ${template.name} average=${decimal(total, entries, 2)} total=$total entries=$entries');
  }
  final appearances = <int, List<String>>{};
  for (final template in filled) {
    for (final id in template.completed!.state.words) {
      appearances.putIfAbsent(id, () => []).add(template.name);
    }
  }
  final reused = appearances.keys.where((id) => appearances[id]!.length >= 2).toList()..sort((a, b) =>
      appearances[a]!.length == appearances[b]!.length ? index.words[a].text.compareTo(index.words[b].text) : appearances[b]!.length.compareTo(appearances[a]!.length));
  final reuse = ['REUSE', for (final id in reused) 'reused ${index.words[id].text} ${appearances[id]!.length} ${appearances[id]!.join(',')}'];
  final attempts = valid.fold(0, (sum, template) => sum + template.completed!.attempts.length);
  final nodes = valid.fold(0, (sum, template) => sum + template.completed!.attempts.fold(0, (subtotal, attempt) => subtotal + attempt.nodes));
  final unfillable = valid.where((template) => template.completed!.finalAttempt.outcome == 'unfillable').length;
  final budget = valid.where((template) => template.completed!.finalAttempt.outcome == 'budget').length;
  final summary = ['SUMMARY templates=${templates.length} invalid=${templates.length - valid.length} filled=${filled.length} unfillable=$unfillable budget=$budget attempts=$attempts nodes=$nodes'];
  return [ranking, reuse, summary];
}

void main() {
  final settings = readSettings(readLines('params.txt'));
  final wordList = WordList(readLines('words.txt'));
  final index = wordList.index;
  final clues = ClueBook(readLines('clues.txt'), index);
  final templates = <Template>[];
  final names = <String>{};
  for (final block in splitBlocks(readLines('templates.txt'))) {
    final (prepared, error) = prepare(block, settings, names, index);
    templates.add(Template(block.name, error, error.isEmpty ? Completed(prepared!, index, clues) : null));
    names.add(block.name);
  }
  final grids = [for (final template in templates) template.gridParagraph()];
  final clueLines = [for (final template in templates) if (template.error.isEmpty) template.completed!.clueParagraph(template.name, index)];
  final stats = [for (final template in templates) if (template.error.isEmpty) template.completed!.statsParagraph(template.name, index)];
  stats.addAll(overallParagraphs(templates, index));
  Directory('output').createSync(recursive: true);
  writeParagraphs('grid.txt', grids);
  writeParagraphs('clues.txt', clueLines);
  writeParagraphs('search_stats.txt', stats);
  writeLines('wordlist.txt', [...wordList.report(), ...clues.report(index)]);
}
