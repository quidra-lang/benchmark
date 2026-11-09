part of 'main.dart';

class FileData {
  final String path, guard;
  final List<LogicalLine> lines;
  final int physicalLines;
  int entered = 0, skipped = 0, outputLines = 0, skippedLines = 0;
  bool once = false;
  FileData(this.path, this.lines, this.physicalLines, this.guard);
}

String directiveName(List<Token> tokens) =>
    tokens.length >= 2 &&
        tokens[0].spelling == '#' &&
        tokens[1].kind == 'identifier'
    ? tokens[1].spelling
    : '';
String detectGuard(List<LogicalLine> logical) {
  final lines = [
    for (final line in logical)
      if (line.tokens.isNotEmpty) line.tokens,
  ];
  if (lines.isEmpty) return '';
  final first = lines.first, last = lines.last;
  if (first.length != 3 ||
      first[0].spelling != '#' ||
      first[1].spelling != 'ifndef' ||
      first[1].kind != 'identifier' ||
      first[2].kind != 'identifier' ||
      last.length != 2 ||
      last[0].spelling != '#' ||
      last[1].spelling != 'endif' ||
      last[1].kind != 'identifier')
    return '';
  var depth = 0;
  for (var i = 0; i < lines.length; i++) {
    final name = directiveName(lines[i]);
    if (wordIn('elif elifdef elifndef else', name) && depth == 1) return '';
    if (wordIn('if ifdef ifndef', name)) {
      depth++;
    } else if (name == 'endif') {
      depth--;
    }
    if (depth == 0 && i != lines.length - 1) return '';
  }
  return depth == 0 ? first[2].spelling : '';
}

class IncludeManager {
  final Map<String, FileData> files = {};
  final List<String> order = [];
  String? search(String name, bool quoted) {
    for (final path in [if (quoted) name, 'include/$name']) {
      if (File('input/$path').existsSync()) return path;
    }
    return null;
  }

  FileData load(String path) {
    final known = files[path];
    if (known != null) return known;
    final source = File('input/$path').readAsStringSync(),
        logical = lexSource(source),
        file = FileData(
          path,
          logical,
          '\n'.allMatches(source).length,
          detectGuard(logical),
        );
    files[path] = file;
    order.add(path);
    return file;
  }
}
