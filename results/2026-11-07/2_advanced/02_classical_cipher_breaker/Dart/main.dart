import 'dart:io';
import 'dart:math';

import 'scoring.dart';
import 'substitution.dart';
import 'transposition.dart';
import 'playfair.dart';
import 'analysis.dart';

class JobFault implements Exception {
  final String message;
  JobFault(this.message);
}

class Candidate {
  final String key;
  final String plaintext;
  final int score;
  final int order;
  Candidate(this.key, this.plaintext, this.score, this.order);
}

class BreakOutcome {
  final List<Candidate> ranked;
  final Candidate choice;
  final int length;
  final String method;
  final int passes;
  final int changes;
  final KasiskiData? kasiski;
  BreakOutcome(this.ranked, this.choice,
      {this.length = 0, this.method = '', this.passes = 0,
      this.changes = 0, this.kasiski});
}

class OptionRule {
  final int minimum;
  final int maximum;
  final int fallback;
  OptionRule(this.minimum, this.maximum, this.fallback);
}

class Benchmark {
  static const commands = ['ENCRYPT', 'DECRYPT', 'BREAK', 'ANALYZE', 'COMPARE', 'IDENTIFY'];
  static const ciphers = {
    'caesar', 'affine', 'vigenere', 'autokey', 'railfence', 'columnar', 'playfair'
  };
  static const multipliers = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25];

  final messages = <String, List<String>>{};
  final totals = <String, List<int>>{};
  final results = <String>[];
  final candidates = <String>[];
  final analysis = <String>[];
  late List<int> mono;
  late List<List<int>> bi;

  Benchmark() {
    final weights = readWeights('input/weights.txt');
    mono = weights.$1;
    bi = weights.$2;
    for (final command in commands) totals[command] = [0, 0];
    readMessages('input/messages.txt');
  }

  Never fail(String reason) => throw JobFault(reason);

  bool name(String text) => RegExp(r'^[a-z0-9_]{1,16}$').hasMatch(text);

  bool digits(String text, int maxLength) =>
      RegExp('^[0-9]{1,$maxLength}\$').hasMatch(text);

  String body(String name) => messages[name]!.join('\n');

  String letters(String name) => letterString(body(name));

  bool isSubstitution(String cipher) =>
      {'caesar', 'affine', 'vigenere', 'autokey'}.contains(cipher);

  void readMessages(String path) {
    String? current;
    var lines = <String>[];
    for (final line in File(path).readAsLinesSync()) {
      if (current == null) {
        if (line.isEmpty) continue;
        current = line.substring(8);
        lines = <String>[];
      } else if (line == 'END') {
        messages[current] = lines;
        current = null;
      } else {
        lines.add(line);
      }
    }
  }

  String normalizeKey(String cipher, String raw) {
    if (cipher == 'caesar') {
      if (!digits(raw, 2) || int.parse(raw) > 25) fail('bad key $raw');
      return int.parse(raw).toString();
    }
    if (cipher == 'affine') {
      final pair = raw.split(',');
      if (pair.length != 2 || !digits(pair[0], 2) || !digits(pair[1], 2) ||
          !multipliers.contains(int.parse(pair[0])) || int.parse(pair[1]) > 25) {
        fail('bad key $raw');
      }
      return '${int.parse(pair[0])},${int.parse(pair[1])}';
    }
    if (cipher == 'railfence') {
      if (!digits(raw, 2) || int.parse(raw) < 2 || int.parse(raw) > 20) {
        fail('bad key $raw');
      }
      return int.parse(raw).toString();
    }
    final pattern = switch (cipher) {
      'vigenere' || 'autokey' => r'^[A-Za-z]{1,20}$',
      'playfair' => r'^[A-Za-z]{1,25}$',
      'columnar' => r'^[A-Za-z0-9]{2,9}$',
      _ => '',
    };
    if (!RegExp(pattern).hasMatch(raw)) fail('bad key $raw');
    final key = raw.toUpperCase();
    return cipher == 'playfair' ? key.replaceAll('J', 'I') : key;
  }

  Map<String, OptionRule> rules(String command, String cipher) {
    final result = <String, OptionRule>{};
    if (command == 'ANALYZE') result['MAXLEN'] = OptionRule(2, 20, 10);
    if (command != 'BREAK') return result;

    result['TOP'] = OptionRule(1, 20, 5);
    if (cipher == 'vigenere') {
      result['MAXLEN'] = OptionRule(2, 20, 10);
      result['IOC'] = OptionRule(1, 100000, 6000);
      result['KASISKI'] = OptionRule(1, 100, 60);
      result['REFINE'] = OptionRule(0, 10, 5);
    } else if (cipher == 'autokey') {
      result['MAXLEN'] = OptionRule(1, 20, 8);
    } else if (cipher == 'railfence') {
      result['MAXRAILS'] = OptionRule(2, 20, 10);
    } else if (cipher == 'columnar') {
      result['MAXLEN'] = OptionRule(2, 6, 6);
    }
    return result;
  }

  Map<String, String> parseOptions(String command, String cipher, List<String> words) {
    final allowed = rules(command, cipher);
    final values = allowed.map((name, rule) =>
        MapEntry(name, rule.fallback.toString()));
    final seen = <String>{};
    for (final word in words) {
      final delimiter = word.indexOf('=');
      final label = delimiter < 0 ? '' : word.substring(0, delimiter);
      final value = delimiter < 0 ? '' : word.substring(delimiter + 1);
      if (delimiter < 0 || !seen.add(label)) fail('bad option $word');
      if (label == 'KEYS' && (command == 'IDENTIFY' ||
          (command == 'BREAK' && cipher == 'playfair'))) {
        if (!name(value)) fail('bad option $word');
        values[label] = value;
        continue;
      }
      final rule = allowed[label];
      if (rule == null || !digits(value, 6)) fail('bad option $word');
      final integer = int.parse(value);
      if (integer < rule.minimum || integer > rule.maximum) fail('bad option $word');
      values[label] = integer.toString();
    }
    if (command == 'BREAK' && cipher == 'playfair' && !values.containsKey('KEYS')) {
      fail('missing option KEYS');
    }
    return values;
  }

  int option(Map<String, String> values, String name) => int.parse(values[name]!);

  String decrypt(String text, String cipher, String key) {
    if (isSubstitution(cipher)) {
      return letterString(applySubstitution(text, cipher, key, false));
    }
    return switch (cipher) {
      'railfence' => railFence(text, int.parse(key), false),
      'columnar' => columnar(text, key, false),
      _ => playfair(text, key, false),
    };
  }

  String transform(String text, String cipher, String key, bool encrypt) {
    if (isSubstitution(cipher)) return applySubstitution(text, cipher, key, encrypt);
    final letters = letterString(text);
    return switch (cipher) {
      'railfence' => railFence(letters, int.parse(key), encrypt),
      'columnar' => columnar(letters, key, encrypt),
      _ => playfair(letters, key, encrypt),
    };
  }

  List<String> keyList(String name) {
    final seen = <String>{};
    final keys = <String>[];
    for (final match in RegExp(r'[A-Za-z]+').allMatches(body(name))) {
      final key = match.group(0)!.toUpperCase().replaceAll('J', 'I');
      if (seen.add(key)) keys.add(key);
    }
    return keys;
  }

  List<String> permutations(int length) {
    final digits = List.generate(length, (i) => String.fromCharCode(49 + i));
    final result = <String>[];
    void visit(int index) {
      if (index == digits.length) {
        result.add(digits.join());
        return;
      }
      for (var i = index; i < digits.length; i++) {
        final first = digits[index];
        digits[index] = digits[i];
        digits[i] = first;
        visit(index + 1);
        digits[i] = digits[index];
        digits[index] = first;
      }
    }
    visit(0);
    result.sort();
    return result;
  }

  String columnKey(String text, int length, bool autokey) {
    final key = StringBuffer();
    for (var columnIndex = 0; columnIndex < length; columnIndex++) {
      final textColumn = column(text, length, columnIndex);
      var bestScore = -(1 << 62);
      var best = 0;
      for (var guess = 0; guess < 26; guess++) {
        int score;
        if (!autokey) {
          final decoded = applySubstitution(textColumn, 'caesar', '$guess', false);
          score = monogram(decoded, mono);
        } else {
          var previous = guess;
          score = 0;
          for (var i = 0; i < textColumn.length; i++) {
            previous = modulo(letterValue(textColumn[i]) - previous);
            score += mono[previous];
          }
        }
        if (score > bestScore) {
          best = guess;
          bestScore = score;
        }
      }
      key.write(upperLetter(best));
    }
    return key.toString();
  }

  List<String> candidateKeys(String cipher, String text,
      Map<String, String> options, List<String>? keys) {
    final output = <String>[];
    if (cipher == 'caesar') {
      for (var i = 0; i < 26; i++) output.add('$i');
    } else if (cipher == 'affine') {
      for (final a in multipliers) {
        for (var b = 0; b < 26; b++) output.add('$a,$b');
      }
    } else if (cipher == 'railfence') {
      for (var r = 2; r <= option(options, 'MAXRAILS'); r++) output.add('$r');
    } else if (cipher == 'columnar') {
      for (var length = 2; length <= option(options, 'MAXLEN'); length++) {
        output.addAll(permutations(length));
      }
    } else if (cipher == 'playfair') {
      output.addAll(keys!);
    } else {
      for (var length = 1; length <= option(options, 'MAXLEN'); length++) {
        output.add(columnKey(text, length, cipher == 'autokey'));
      }
    }
    return output;
  }

  int score(String cipher, String plaintext) =>
      cipher == 'caesar' || cipher == 'affine'
          ? monogram(plaintext, mono) : bigram(plaintext, bi);

  BreakOutcome breakCipher(String cipher, String text,
      Map<String, String> options, [List<String>? keys]) {
    final raw = <Candidate>[];
    for (final key in candidateKeys(cipher, text, options, keys)) {
      final plaintext = decrypt(text, cipher, key);
      raw.add(Candidate(key, plaintext, score(cipher, plaintext), raw.length));
    }
    final ranked = [...raw]..sort((a, b) {
      final result = b.score.compareTo(a.score);
      return result != 0 ? result : a.order.compareTo(b.order);
    });
    if (cipher != 'vigenere') return BreakOutcome(ranked, ranked.first);

    final maxlen = option(options, 'MAXLEN');
    final threshold = option(options, 'IOC');
    final data = kasiski(text);
    final average = <int>[];
    for (var length = 1; length <= maxlen; length++) {
      average.add(averageIoc(text, length));
    }
    var kasiskiLength = 0;
    for (var length = 2; length <= maxlen; length++) {
      if (data.gaps.isNotEmpty &&
          100 * data.count(length) >= option(options, 'KASISKI') * data.gaps.length) {
        kasiskiLength = length;
      }
    }
    var chosen = 0;
    String method;
    if (kasiskiLength != 0 && average[kasiskiLength - 1] >= threshold) {
      chosen = kasiskiLength;
      method = 'kasiski';
    } else {
      for (var length = 1; length <= maxlen; length++) {
        if (average[length - 1] >= threshold) {
          chosen = length;
          break;
        }
      }
      if (chosen != 0) {
        method = 'ioc';
      } else {
        chosen = 1;
        for (var length = 2; length <= maxlen; length++) {
          if (average[length - 1] > average[chosen - 1]) chosen = length;
        }
        method = 'maxioc';
      }
    }
    var key = raw[chosen - 1].key;
    var reference = score(cipher, decrypt(text, cipher, key));
    var passes = 0;
    var changes = 0;
    for (var pass = 0; pass < option(options, 'REFINE'); pass++) {
      passes++;
      var count = 0;
      for (var index = 0; index < key.length; index++) {
        var winner = key[index];
        var high = reference;
        for (var value = 0; value < 26; value++) {
          final trial = key.substring(0, index) + upperLetter(value) +
              key.substring(index + 1);
          final currentScore = score(cipher, decrypt(text, cipher, trial));
          if (currentScore > high) {
            winner = upperLetter(value);
            high = currentScore;
          }
        }
        if (high > reference) {
          key = key.substring(0, index) + winner + key.substring(index + 1);
          reference = high;
          changes++;
          count++;
        }
      }
      if (count == 0) break;
    }
    final result = Candidate(key, decrypt(text, cipher, key), reference, -1);
    return BreakOutcome(ranked, result,
        length: chosen, method: method, passes: passes, changes: changes, kasiski: data);
  }

  void writeCandidateReport(int job, String cipher, String source,
      BreakOutcome broken, int top) {
    final rank = broken.ranked;
    final margin = rank.length > 1 ? rank[0].score - rank[1].score : 0;
    candidates.add('JOB $job BREAK $cipher source=$source tried=${rank.length} margin=$margin');
    for (var index = 0; index < min(top, rank.length); index++) {
      final item = rank[index];
      candidates.add('${index + 1} ${item.key} ${item.score} ${item.plaintext.substring(0, min(40, item.plaintext.length))}');
    }
  }

  void writeBreakAnalysis(int job, String cipher, String source,
      String text, Map<String, String> options, BreakOutcome broken) {
    if (cipher == 'vigenere') {
      analysis.add('JOB $job BREAK vigenere source=$source');
      analysis.add('letters=${text.length}');
      analysis.addAll(periodTable(text, option(options, 'MAXLEN'), broken.kasiski!));
      analysis.addAll(kasiskiTable(broken.kasiski!));
      analysis.add('decision length=${broken.length} method=${broken.method}');
      analysis.add('refine passes=${broken.passes} changes=${broken.changes} key=${broken.choice.key}');
    } else if (cipher == 'playfair') {
      final t = text.replaceAll('J', 'I');
      final squareText = square(broken.choice.key);
      final pairs = <String>[];
      for (var i = 0; i < t.length; i += 2) pairs.add(t.substring(i, i + 2));
      analysis.add('JOB $job BREAK playfair source=$source');
      analysis.add('letters=${t.length}');
      analysis.add('digraphs pairs=${pairs.length} distinct=${pairs.toSet().length}');
      analysis.add('top ${topPairs(t, true)}');
      analysis.add('square ${List.generate(5, (i) => squareText.substring(i * 5, i * 5 + 5)).join(" ")}');
    }
  }

  List<String> outputText(String source, String cipher, String key, bool encrypt) {
    final result = transform(source, cipher, key, encrypt);
    return isSubstitution(cipher) ? result.split('\n') : groups(result);
  }

  void save(String? target, List<String> lines) {
    if (target != null) messages[target] = lines;
  }

  void cipherJob(int job, String command, String cipher,
      String key, String source, String? target) {
    final text = letters(source);
    if (text.isEmpty) fail('no letters');
    if (command == 'DECRYPT' && cipher == 'playfair' && !validPlayfair(text)) {
      fail('bad playfair text');
    }
    final lines = outputText(body(source), cipher, key, command == 'ENCRYPT');
    final count = lines.fold<int>(0, (sum, line) => sum + letterString(line).length);
    final suffix = target == null ? '' : ' as=$target';
    results.add('JOB $job $command $cipher key=$key source=$source letters=$count lines=${lines.length}$suffix');
    results.addAll(lines);
    save(target, lines);
  }

  void breakJob(int job, String cipher, String source,
      String? target, Map<String, String> options) {
    final text = letters(source);
    if (text.length < 40) fail('text too short');
    if (cipher == 'playfair' && !validPlayfair(text)) fail('bad playfair text');
    final keys = cipher == 'playfair' ? keyList(options['KEYS']!) : null;
    if (cipher == 'playfair' && keys!.isEmpty) fail('empty key list');
    final broken = breakCipher(cipher, text, options, keys);
    final lines = outputText(body(source), cipher, broken.choice.key, false);
    final suffix = target == null ? '' : ' as=$target';
    results.add('JOB $job BREAK $cipher source=$source key=${broken.choice.key} score=${broken.choice.score} lines=${lines.length}$suffix');
    results.addAll(lines);
    writeCandidateReport(job, cipher, source, broken, option(options, 'TOP'));
    writeBreakAnalysis(job, cipher, source, text, options, broken);
    save(target, lines);
  }

  void analyzeJob(int job, String source, Map<String, String> options) {
    final text = letters(source);
    if (text.length < 40) fail('text too short');
    results.add('JOB $job ANALYZE source=$source letters=${text.length}');
    analysis.addAll(analyze(job, source, text, mono, bi, option(options, 'MAXLEN')));
  }

  void compareJob(int job, String leftName, String rightName) {
    final left = letters(leftName);
    final right = letters(rightName);
    final count = min(left.length, right.length);
    var first = count + 1;
    var mismatches = 0;
    for (var i = 0; i < count; i++) {
      if (left[i] != right[i]) {
        if (mismatches == 0) first = i + 1;
        mismatches++;
      }
    }
    if (left == right) {
      results.add('JOB $job COMPARE $leftName $rightName equal letters=${left.length}');
    } else {
      results.add('JOB $job COMPARE $leftName $rightName differ letters=${left.length},${right.length} first=$first mismatches=$mismatches');
    }
  }

  void identifyJob(int job, String source, Map<String, String> options) {
    final text = letters(source);
    if (text.length < 40) fail('text too short');
    final coincidence = ioc(text);
    final mean = monogram(text, mono) ~/ text.length;
    final distinct = frequencies(text).where((value) => value > 0).length;
    final shape = !text.contains('J') && validPlayfair(text);
    final family = shape ? 'playfair' : coincidence >= 5500
        ? mean >= 44 ? 'transposition' : 'monoalphabetic' : 'polyalphabetic';
    List<String>? keys;
    if (family == 'playfair' && options.containsKey('KEYS')) {
      keys = keyList(options['KEYS']!);
      if (keys.isEmpty) fail('empty key list');
    }
    final cipherNames = switch (family) {
      'transposition' => ['railfence', 'columnar'],
      'monoalphabetic' => ['affine'],
      'polyalphabetic' => ['vigenere', 'autokey'],
      _ => keys == null ? <String>[] : ['playfair'],
    };
    final tested = <(String, Candidate)>[];
    for (final cipher in cipherNames) {
      final entries = cipher == 'playfair' ? ['KEYS=${options["KEYS"]}'] : <String>[];
      final defaults = parseOptions('BREAK', cipher, entries);
      final chosen = breakCipher(cipher, text, defaults, keys).choice;
      tested.add((cipher, chosen));
    }
    (String, Candidate)? best;
    for (final entry in tested) {
      if (best == null || entry.$2.score > best.$2.score) best = entry;
    }
    var header = 'JOB $job IDENTIFY source=$source family=$family';
    String? reported;
    if (best != null) {
      reported = best.$1;
      var key = best.$2.key;
      if (reported == 'affine' && key.split(',')[0] == '1') {
        reported = 'caesar';
        key = key.split(',')[1];
      }
      final lines = outputText(body(source), reported, key, false);
      header += ' cipher=$reported key=$key score=${best.$2.score} lines=${lines.length}';
      results.add(header);
      results.addAll(lines);
    } else {
      results.add(header);
    }
    analysis.add('JOB $job IDENTIFY source=$source');
    analysis.add('letters=${text.length} ioc=$coincidence mono_avg=$mean distinct=$distinct shape=${shape ? "yes" : "no"}');
    analysis.add('family=$family');
    for (final entry in tested) {
      analysis.add('try ${entry.$1} key=${entry.$2.key} score=${entry.$2.score}');
    }
    if (reported != null) analysis.add('choice $reported');
  }

  void checkReferences(List<String> words, String command, Map<String, String> options) {
    final source = {'ENCRYPT', 'DECRYPT', 'BREAK'}.contains(command)
        ? words[command == 'BREAK' ? 2 : 3] : words[1];
    if (!messages.containsKey(source)) fail('unknown message $source');
    if (options.containsKey('KEYS') && !messages.containsKey(options['KEYS'])) {
      fail('unknown message ${options["KEYS"]}');
    }
    if (command == 'COMPARE' && !messages.containsKey(words[2])) {
      fail('unknown message ${words[2]}');
    }
  }

  void execute(int number, String line) {
    final words = line.split(' ');
    final command = words[0];
    if (!commands.contains(command)) fail('unknown command');
    String? target;
    if ({'ENCRYPT', 'DECRYPT', 'BREAK'}.contains(command) &&
        words.length >= 5 && words[words.length - 2] == 'AS') {
      target = words.removeLast();
      words.removeLast();
      if (!name(target)) fail('bad syntax');
    }
    final syntax = switch (command) {
      'ENCRYPT' || 'DECRYPT' => words.length == 4,
      'BREAK' => words.length >= 3,
      'ANALYZE' || 'IDENTIFY' => words.length == 2 || words.length == 3,
      _ => words.length == 3,
    };
    if (!syntax) fail('bad syntax');

    final cipher = {'ENCRYPT', 'DECRYPT', 'BREAK'}.contains(command) ? words[1] : '';
    if (cipher.isNotEmpty && !ciphers.contains(cipher)) fail('unknown cipher $cipher');
    final key = {'ENCRYPT', 'DECRYPT'}.contains(command)
        ? normalizeKey(cipher, words[2]) : '';
    final optionWords = command == 'BREAK' ? words.skip(3).toList()
        : {'ANALYZE', 'IDENTIFY'}.contains(command) ? words.skip(2).toList() : <String>[];
    final opts = parseOptions(command, cipher, optionWords);
    checkReferences(words, command, opts);
    if (target != null && messages.containsKey(target)) {
      fail('duplicate message $target');
    }
    switch (command) {
      case 'ENCRYPT':
      case 'DECRYPT':
        cipherJob(number, command, cipher, key, words[3], target);
        break;
      case 'BREAK':
        breakJob(number, cipher, words[2], target, opts);
        break;
      case 'ANALYZE':
        analyzeJob(number, words[1], opts);
        break;
      case 'COMPARE':
        compareJob(number, words[1], words[2]);
        break;
      case 'IDENTIFY':
        identifyJob(number, words[1], opts);
        break;
    }
  }

  void runJobs(String path) {
    var jobs = 0;
    var ok = 0;
    var errors = 0;
    for (final line in File(path).readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      jobs++;
      final command = line.split(' ').first;
      try {
        execute(jobs, line);
        ok++;
        if (totals.containsKey(command)) totals[command]![0]++;
      } on JobFault catch (fault) {
        errors++;
        if (totals.containsKey(command)) totals[command]![1]++;
        results.add('JOB $jobs ERROR ${fault.message}');
      }
    }
    for (final command in commands) {
      final counts = totals[command]!;
      results.add('TOTAL $command ok=${counts[0]} errors=${counts[1]}');
    }
    results.add('SUMMARY jobs=$jobs ok=$ok errors=$errors messages=${messages.length}');
  }

  void write(String filename, List<String> lines) {
    final content = lines.isEmpty ? '' : '${lines.join("\n")}\n';
    File('output/$filename').writeAsStringSync(content);
  }

  void run() {
    runJobs('input/jobs.txt');
    Directory('output').createSync(recursive: true);
    write('results.txt', results);
    write('candidates.txt', candidates);
    write('analysis.txt', analysis);
  }
}

void main() => Benchmark().run();
