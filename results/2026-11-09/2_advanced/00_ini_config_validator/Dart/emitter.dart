import 'dart:io';
import 'lexer.dart';
import 'schema.dart';

const mask = '********';

String stringNotation(String text) {
  final result = StringBuffer('"');
  for (var index = 0; index < text.length; index++) {
    result.write(switch (text[index]) {
      '\\' => r'\\', '"' => r'\"', '\n' => r'\n', '\t' => r'\t',
      _ => text[index],
    });
  }
  return (result..write('"')).toString();
}

String valueNotation(String kind, String item, Object value) {
  if (kind == 'string') return stringNotation(value as String);
  if (kind == 'bool') return value == true ? 'true' : 'false';
  if (kind == 'list') {
    final values = (value as List<Object>).map((v) => valueNotation(item, 'string', v));
    return '[${values.join(', ')}]';
  }
  return value.toString();
}

class OutputKey {
  final Origin origin;
  final List<Origin> history;
  final Spec? spec;
  final Object value;
  late final String notation = valueNotation(spec?.kind ?? 'string', spec?.item ?? 'string', value);
  OutputKey(this.origin, this.history, this.spec, this.value);
}

String shown(OutputKey output) => output.spec?.secret == true ? mask : output.notation;

class ProfileResult {
  final String name;
  final outputs = <String, OutputKey>{};
  final tree = <(int, String)>[];
  final diagnostics = <Diagnostic>[];
  final overridden = <(String, List<Origin>)>[];
  int errors = 0;
  int warnings = 0;
  int documentKeys = 0;
  int manifestKeys = 0;
  int defaultKeys = 0;
  int dropped = 0;
  ProfileResult(this.name);
}

class DiffEntry {
  final String sign;
  final String key;
  final OutputKey? before;
  final OutputKey? after;
  DiffEntry(this.sign, this.key, this.before, this.after);
}

class ProfileDiff {
  final String first;
  final String second;
  int added = 0;
  int removed = 0;
  int changed = 0;
  final entries = <DiffEntry>[];
  ProfileDiff(this.first, this.second);
}

Iterable<String> normalizedBlock(ProfileResult profile) sync* {
  yield 'profile ${profile.name}';
  String? previous;
  for (final key in sortedKeys(profile.outputs.keys)) {
    final section = sectionOf(key);
    if (section != previous) {
      yield '[$section]';
      previous = section;
    }
    yield '${nameOf(key)} = ${shown(profile.outputs[key]!)}';
  }
}

Iterable<String> diagnosticsBlock(ProfileResult profile) sync* {
  yield 'profile ${profile.name} errors ${profile.errors} warnings ${profile.warnings}';
  for (final diagnostic in profile.diagnostics) {
    yield '${diagnostic.origin} ${diagnostic.code} ${diagnostic.message}';
  }
}

Iterable<String> diffBlock(ProfileDiff diff) sync* {
  yield 'diff ${diff.first} -> ${diff.second}: ${diff.added} added, ${diff.removed} removed, ${diff.changed} changed';
  for (final entry in diff.entries) {
    if (entry.sign == '+') {
      yield '+ ${entry.key} = ${shown(entry.after!)}';
    } else if (entry.sign == '-') {
      yield '- ${entry.key} = ${shown(entry.before!)}';
    } else {
      yield '~ ${entry.key}: ${shown(entry.before!)} -> ${shown(entry.after!)}';
    }
  }
}

Iterable<String> reportBlock(ProfileResult profile) sync* {
  yield 'profile ${profile.name}';
  yield 'includes';
  for (final line in profile.tree) {
    yield ''.padLeft(2 + 2 * line.$1) + line.$2;
  }
  yield 'overridden';
  for (final entry in profile.overridden) {
    yield '  ${entry.$1}: ${entry.$2.join(' -> ')}';
  }
  if (profile.overridden.isEmpty) yield '  (none)';
  yield 'keys ${profile.outputs.length} documents ${profile.documentKeys} manifest ${profile.manifestKeys} defaults ${profile.defaultKeys}';
  yield 'dropped ${profile.dropped}';
  yield 'errors ${profile.errors} warnings ${profile.warnings}';
}

void writeBlocks(String path, Iterable<Iterable<String>> blocks) =>
    File(path).writeAsStringSync('${blocks.map((block) => block.join('\n')).join('\n\n')}\n');

void writeOutputs(String directory, List<ProfileResult> profiles, List<ProfileDiff> diffs) {
  Directory(directory).createSync(recursive: true);
  writeBlocks('$directory/normalized.txt', profiles.map(normalizedBlock));
  writeBlocks('$directory/diagnostics.txt', profiles.map(diagnosticsBlock));
  writeBlocks('$directory/diff.txt', diffs.map(diffBlock));
  writeBlocks('$directory/report.txt', profiles.map(reportBlock));
}
