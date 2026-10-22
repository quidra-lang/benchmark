import 'dart:convert';
import 'dart:io';
import 'dart:math';

const dataCommands = {'FILE', 'PATCH', 'EDIT'};
const formatsWithArgument = {'IFDEF', 'UNIFIED', 'CONTEXT', 'SIDE'};
const offsets = [0, 1, -1, 2, -2, 3, -3];
const graphWidth = 20;
final numberPair = RegExp(r'^([0-9]{1,4})(?:,([0-9]{1,4}))?$');
final spaceRun = RegExp(' {2,}');
const conflictSeparator = '=======';

class CommandError implements Exception {
  final String message;

  CommandError(this.message);
}

String rangeR(int start, int count) {
  if (count >= 2) return '${start + 1},${start + count}';
  if (count == 1) return '${start + 1}';
  return '$start';
}

String rangeU(int start, int count) {
  if (count >= 2) return '${start + 1},$count';
  if (count == 1) return '${start + 1}';
  return '$start,0';
}

String rangeM(int start, int count) => '${start + 1},$count';

String comparisonKey(String line, List<String> options) {
  var key = line;
  if (options.contains('ICASE')) key = key.toLowerCase();
  if (options.contains('IWHITE')) key = key.replaceAll(' ', '');
  if (options.contains('ISPACE')) key = key.replaceAll(spaceRun, ' ');
  return key;
}

bool sameLines(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

List<(int, int)> matchedPairs(List<String> first, List<String> second) {
  final rows = first.length;
  final columns = second.length;
  final table = List.generate(rows + 1, (_) => List.filled(columns + 1, 0));
  for (var i = 1; i <= rows; i++) {
    for (var j = 1; j <= columns; j++) {
      table[i][j] = first[i - 1] == second[j - 1]
          ? table[i - 1][j - 1] + 1
          : max(table[i - 1][j], table[i][j - 1]);
    }
  }
  final pairs = [(rows + 1, columns + 1)];
  var i = rows;
  var j = columns;
  while (i >= 1 && j >= 1) {
    if (first[i - 1] == second[j - 1]) {
      pairs.add((i, j));
      i--;
      j--;
    } else if (table[i - 1][j] >= table[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  pairs.add((0, 0));
  return pairs.reversed.toList();
}

class ChangeBlock {
  final int p;
  final int q;
  final int x;
  final int y;

  ChangeBlock(this.p, this.q, this.x, this.y);

  String get letter {
    if (x >= 1 && y >= 1) return 'c';
    return y == 0 ? 'd' : 'a';
  }
}

List<ChangeBlock> changeBlocks(List<String> first, List<String> second) {
  final pairs = matchedPairs(first, second);
  final blocks = <ChangeBlock>[];
  for (var k = 0; k + 1 < pairs.length; k++) {
    final (i, j) = pairs[k];
    final (nextI, nextJ) = pairs[k + 1];
    if (nextI - i > 1 || nextJ - j > 1) {
      blocks.add(ChangeBlock(i, j, nextI - i - 1, nextJ - j - 1));
    }
  }
  return blocks;
}

typedef Step = (int oldIndex, int newIndex, ChangeBlock? block);

List<Step> walk(
  List<ChangeBlock> blocks,
  int oldStart,
  int newStart,
  int oldEnd,
) {
  final steps = <Step>[];
  var oldIndex = oldStart;
  var newIndex = newStart;
  for (final block in blocks) {
    while (oldIndex < block.p) {
      steps.add((oldIndex++, newIndex++, null));
    }
    steps.add((oldIndex, newIndex, block));
    oldIndex = block.p + block.x;
    newIndex = block.q + block.y;
  }
  while (oldIndex < oldEnd) {
    steps.add((oldIndex++, newIndex++, null));
  }
  return steps;
}

String truncate(String text, int width) =>
    text.length > width ? text.substring(0, width) : text;

String sideRow(String left, String symbol, String right, int width) =>
    '${truncate(left, width).padRight(width)} $symbol ${truncate(right, width)}'
        .trimRight();

String statGraph(int inserted, int deleted) {
  final total = inserted + deleted;
  var plus = inserted;
  var minus = deleted;
  if (total > graphWidth) {
    plus = graphWidth * inserted ~/ total;
    minus = graphWidth * deleted ~/ total;
    if (inserted >= 1 && plus == 0) plus = 1;
    if (deleted >= 1 && minus == 0) minus = 1;
  }
  return '+' * plus + '-' * minus;
}

class Hunk {
  final List<ChangeBlock> blocks;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;

  Hunk._(
    this.blocks,
    this.oldStart,
    this.oldCount,
    this.newStart,
    this.newCount,
  );

  factory Hunk(List<ChangeBlock> blocks, int context, int oldTotal) {
    final first = blocks.first;
    final last = blocks.last;
    final before = min(context, first.p);
    final after = min(context, oldTotal - last.p - last.x);
    final oldStart = first.p - before;
    final newStart = first.q - before;
    return Hunk._(
      blocks,
      oldStart,
      last.p + last.x + after - oldStart,
      newStart,
      last.q + last.y + after - newStart,
    );
  }

  List<Step> steps() => walk(blocks, oldStart, newStart, oldStart + oldCount);
}

class LineDiff {
  final List<String> oldLines;
  final List<String> newLines;
  final List<ChangeBlock> blocks;

  LineDiff(this.oldLines, this.newLines, [List<String> options = const []])
    : blocks = changeBlocks(
        [for (final line in oldLines) comparisonKey(line, options)],
        [for (final line in newLines) comparisonKey(line, options)],
      );

  List<String> deleted(ChangeBlock block) =>
      oldLines.sublist(block.p, block.p + block.x);

  List<String> inserted(ChangeBlock block) =>
      newLines.sublist(block.q, block.q + block.y);

  List<Hunk> hunks(int context) {
    final groups = <List<ChangeBlock>>[];
    for (final block in blocks) {
      if (groups.isNotEmpty) {
        final previous = groups.last.last;
        if (block.p - (previous.p + previous.x) <= 2 * context) {
          groups.last.add(block);
          continue;
        }
      }
      groups.add([block]);
    }
    return [for (final group in groups) Hunk(group, context, oldLines.length)];
  }

  List<String> normal() => [
    for (final block in blocks) ...[
      rangeR(block.p, block.x) + block.letter + rangeR(block.q, block.y),
      for (final line in deleted(block)) '< $line',
      if (block.letter == 'c') '---',
      for (final line in inserted(block)) '> $line',
    ],
  ];

  List<String> ed() => [
    for (final block in blocks.reversed) ...[
      rangeR(block.p, block.x) + block.letter,
      if (block.letter != 'd') ...[...inserted(block), '.'],
    ],
  ];

  List<String> rcs() => [
    for (final block in blocks) ...[
      if (block.x >= 1) 'd${block.p + 1} ${block.x}',
      if (block.y >= 1) ...[
        'a${block.p + block.x} ${block.y}',
        ...inserted(block),
      ],
    ],
  ];

  List<String> ifdef(String macro) {
    final lines = <String>[];
    for (final (oldIndex, _, block) in walk(blocks, 0, 0, oldLines.length)) {
      if (block == null) {
        lines.add(oldLines[oldIndex]);
      } else if (block.x >= 1 && block.y >= 1) {
        lines.addAll([
          '#ifndef $macro',
          ...deleted(block),
          '#else /* $macro */',
          ...inserted(block),
          '#endif /* $macro */',
        ]);
      } else if (block.y == 0) {
        lines.addAll([
          '#ifndef $macro',
          ...deleted(block),
          '#endif /* ! $macro */',
        ]);
      } else {
        lines.addAll([
          '#ifdef $macro',
          ...inserted(block),
          '#endif /* $macro */',
        ]);
      }
    }
    return lines;
  }

  List<String> unified(int context, String oldName, String newName) {
    final lines = ['--- $oldName', '+++ $newName'];
    for (final hunk in hunks(context)) {
      final oldRange = rangeU(hunk.oldStart, hunk.oldCount);
      final newRange = rangeU(hunk.newStart, hunk.newCount);
      lines.add('@@ -$oldRange +$newRange @@');
      for (final (oldIndex, _, block) in hunk.steps()) {
        if (block == null) {
          lines.add(' ${oldLines[oldIndex]}');
        } else {
          lines.addAll([
            for (final line in deleted(block)) '-$line',
            for (final line in inserted(block)) '+$line',
          ]);
        }
      }
    }
    return lines;
  }

  List<String> context(int context, String oldName, String newName) {
    final lines = ['*** $oldName', '--- $newName'];
    for (final hunk in hunks(context)) {
      lines.add('*' * 15);
      lines.add('*** ${rangeR(hunk.oldStart, hunk.oldCount)} ****');
      if (hunk.blocks.any((block) => block.x >= 1)) {
        for (final (oldIndex, _, block) in hunk.steps()) {
          if (block == null) {
            lines.add('  ${oldLines[oldIndex]}');
          } else {
            final marker = block.y >= 1 ? '! ' : '- ';
            lines.addAll([for (final line in deleted(block)) '$marker$line']);
          }
        }
      }
      lines.add('--- ${rangeR(hunk.newStart, hunk.newCount)} ----');
      if (hunk.blocks.any((block) => block.y >= 1)) {
        for (final (_, newIndex, block) in hunk.steps()) {
          if (block == null) {
            lines.add('  ${newLines[newIndex]}');
          } else {
            final marker = block.x >= 1 ? '! ' : '+ ';
            lines.addAll([for (final line in inserted(block)) '$marker$line']);
          }
        }
      }
    }
    return lines;
  }

  List<String> sideBySide(int width) {
    final lines = <String>[];
    for (final (oldIndex, newIndex, block) in walk(
      blocks,
      0,
      0,
      oldLines.length,
    )) {
      if (block == null) {
        lines.add(sideRow(oldLines[oldIndex], ' ', newLines[newIndex], width));
        continue;
      }
      for (var row = 0; row < max(block.x, block.y); row++) {
        if (row < block.x && row < block.y) {
          lines.add(
            sideRow(
              oldLines[block.p + row],
              '|',
              newLines[block.q + row],
              width,
            ),
          );
        } else if (row < block.x) {
          lines.add(sideRow(oldLines[block.p + row], '<', '', width));
        } else {
          lines.add(sideRow('', '>', newLines[block.q + row], width));
        }
      }
    }
    return lines;
  }
}

class TokenTotals {
  int deleted = 0;
  int inserted = 0;
  int common = 0;
}

List<String> splitTokens(String line, bool byWord) => byWord
    ? line.split(' ').where((word) => word.isNotEmpty).toList()
    : line.split('');

String deletion(List<String> tokens, String separator) =>
    '[-${tokens.join(separator)}-]';

String insertion(List<String> tokens, String separator) =>
    '{+${tokens.join(separator)}+}';

String compareTokens(
  List<String> oldTokens,
  List<String> newTokens,
  String separator,
  TokenTotals totals,
) {
  final parts = <String>[];
  final blocks = changeBlocks(oldTokens, newTokens);
  for (final (oldIndex, _, block) in walk(blocks, 0, 0, oldTokens.length)) {
    if (block == null) {
      parts.add(oldTokens[oldIndex]);
      totals.common++;
      continue;
    }
    if (block.x >= 1) {
      parts.add(
        deletion(oldTokens.sublist(block.p, block.p + block.x), separator),
      );
    }
    if (block.y >= 1) {
      parts.add(
        insertion(newTokens.sublist(block.q, block.q + block.y), separator),
      );
    }
    totals.deleted += block.x;
    totals.inserted += block.y;
  }
  return parts.join(separator);
}

typedef LineRange = ({int start, int count});

typedef BodyLine = ({String kind, String text});

class PatchHunk {
  final int lineNumber;
  final LineRange oldRange;
  final LineRange newRange;
  final body = <BodyLine>[];

  PatchHunk(this.lineNumber, this.oldRange, this.newRange);

  (List<String>, List<String>) sequences(bool reverse) {
    final oldKind = reverse ? '+' : '-';
    final newKind = reverse ? '-' : '+';
    return (
      [
        for (final line in body)
          if (line.kind == ' ' || line.kind == oldKind) line.text,
      ],
      [
        for (final line in body)
          if (line.kind == ' ' || line.kind == newKind) line.text,
      ],
    );
  }

  int start(bool reverse) => reverse ? newRange.start : oldRange.start;

  int leadingContext() => body.takeWhile((line) => line.kind == ' ').length;

  int trailingContext() =>
      body.reversed.takeWhile((line) => line.kind == ' ').length;
}

class HunkMatch {
  final int fuzz;
  final int delta;
  final int position;
  final List<String> lines;

  HunkMatch(this.fuzz, this.delta, this.position, this.lines);

  String report(int number) {
    final text = StringBuffer('Hunk #$number succeeded at ${position + 1}');
    if (fuzz >= 1) text.write(' with fuzz $fuzz');
    if (delta == 1 || delta == -1) {
      text.write(' (offset $delta line)');
    } else if (delta != 0) {
      text.write(' (offset $delta lines)');
    }
    return text.toString();
  }
}

LineRange? parseRange(String text, String sign) {
  if (!text.startsWith(sign)) return null;
  final match = numberPair.firstMatch(text.substring(1));
  if (match == null) return null;
  final start = int.parse(match[1]!);
  final count = match[2] == null ? 1 : int.parse(match[2]!);
  if (start == 0 && count != 0) return null;
  return (start: start, count: count);
}

PatchHunk parseHunkHeader(String line, int lineNumber) {
  final parts = line.split(' ');
  if (parts.length == 4 && parts[0] == '@@' && parts[3] == '@@') {
    final oldRange = parseRange(parts[1], '-');
    final newRange = parseRange(parts[2], '+');
    if (oldRange != null && newRange != null) {
      return PatchHunk(lineNumber, oldRange, newRange);
    }
  }
  throw CommandError('PATCH ERROR line $lineNumber: bad hunk header');
}

List<PatchHunk> parsePatch(List<String> patchLines) {
  var index = patchLines.indexWhere((line) => line.startsWith('@@'));
  if (index < 0) throw CommandError('PATCH ERROR no hunks');
  final hunks = <PatchHunk>[];
  while (index < patchLines.length) {
    final hunk = parseHunkHeader(patchLines[index], index + 1);
    index++;
    final oldCount = hunk.oldRange.count;
    final newCount = hunk.newRange.count;
    var oldSeen = 0;
    var newSeen = 0;
    while (oldSeen < oldCount || newSeen < newCount) {
      if (index == patchLines.length) {
        throw CommandError(
          'PATCH ERROR line ${hunk.lineNumber}: truncated hunk',
        );
      }
      final line = patchLines[index];
      final kind = line[0];
      final inOld = kind == ' ' || kind == '-';
      final inNew = kind == ' ' || kind == '+';
      if (line.length < 2 ||
          !(inOld || inNew) ||
          (inOld && oldSeen == oldCount) ||
          (inNew && newSeen == newCount)) {
        throw CommandError('PATCH ERROR line ${index + 1}: bad hunk line');
      }
      hunk.body.add((kind: kind, text: line.substring(1)));
      if (inOld) oldSeen++;
      if (inNew) newSeen++;
      index++;
    }
    if (hunk.body.every((line) => line.kind == ' ')) {
      throw CommandError('PATCH ERROR line ${hunk.lineNumber}: no changes');
    }
    hunks.add(hunk);
  }
  return hunks;
}

HunkMatch? searchHunk(
  PatchHunk hunk,
  List<String> lines,
  int adjustment,
  bool reverse,
  int maxFuzz,
) {
  final (oldLines, newLines) = hunk.sequences(reverse);
  final start = hunk.start(reverse);
  final expected = oldLines.isEmpty
      ? start + adjustment
      : start - 1 + adjustment;
  final leading = hunk.leadingContext();
  final trailing = hunk.trailingContext();
  for (var fuzz = 0; fuzz <= maxFuzz; fuzz++) {
    final head = min(fuzz, leading);
    final tail = min(fuzz, trailing);
    final oldPart = oldLines.sublist(head, oldLines.length - tail);
    final newPart = newLines.sublist(head, newLines.length - tail);
    for (final delta in offsets) {
      final position = expected + head + delta;
      final end = position + oldPart.length;
      if (position < 0 || end > lines.length) continue;
      if (sameLines(lines.sublist(position, end), oldPart)) {
        final result = [
          ...lines.sublist(0, position),
          ...newPart,
          ...lines.sublist(end),
        ];
        return HunkMatch(fuzz, delta, position, result);
      }
    }
  }
  return null;
}

typedef EditCommand = ({String instruction, int first, int last});

EditCommand? parseEditCommand(String line) {
  final instruction = line[line.length - 1];
  final match = numberPair.firstMatch(line.substring(0, line.length - 1));
  if (!'acd'.contains(instruction) || match == null) return null;
  if (instruction == 'a' && match[2] != null) return null;
  final first = int.parse(match[1]!);
  final last = match[2] == null ? first : int.parse(match[2]!);
  return (instruction: instruction, first: first, last: last);
}

(List<String>, int) runEditScript(List<String> original, List<String> script) {
  final lines = [...original];
  var executed = 0;
  var index = 0;
  while (index < script.length) {
    final lineNumber = index + 1;
    final command = parseEditCommand(script[index]);
    if (command == null)
      throw CommandError('EDIT ERROR line $lineNumber: bad command');
    final (:instruction, :first, :last) = command;
    final valid = instruction == 'a'
        ? first <= lines.length
        : 1 <= first && first <= last && last <= lines.length;
    if (!valid) throw CommandError('EDIT ERROR line $lineNumber: bad range');
    index++;
    var text = <String>[];
    if (instruction == 'a' || instruction == 'c') {
      var end = index;
      while (end < script.length && script[end] != '.') {
        end++;
      }
      if (end == script.length) {
        throw CommandError('EDIT ERROR line $lineNumber: missing terminator');
      }
      text = script.sublist(index, end);
      index = end + 1;
    }
    if (instruction == 'a') {
      lines.insertAll(first, text);
    } else {
      lines.replaceRange(first - 1, last, text);
    }
    executed++;
  }
  return (lines, executed);
}

enum ChunkKind { stable, a, b, both, conflict }

class Chunk {
  final ChunkKind kind;
  final int baseStart;
  final int oursStart;
  final int theirsStart;
  final List<String> base;
  final List<String> ours;
  final List<String> theirs;

  Chunk(
    this.kind,
    this.baseStart,
    this.oursStart,
    this.theirsStart,
    this.base,
    this.ours,
    this.theirs,
  );

  String get location =>
      'base ${rangeM(baseStart, base.length)} a ${rangeM(oursStart, ours.length)} '
      'b ${rangeM(theirsStart, theirs.length)}';
}

ChunkKind chunkKind(List<String> base, List<String> ours, List<String> theirs) {
  if (sameLines(ours, base)) return ChunkKind.b;
  if (sameLines(theirs, base)) return ChunkKind.a;
  if (sameLines(ours, theirs)) return ChunkKind.both;
  return ChunkKind.conflict;
}

List<int> matchTable(List<String> first, List<String> second) {
  final matches = List.filled(first.length + 2, 0);
  final pairs = matchedPairs(first, second);
  for (final (i, j) in pairs.sublist(1, pairs.length - 1)) {
    matches[i] = j;
  }
  return matches;
}

List<Chunk> threeWayChunks(
  List<String> base,
  List<String> ours,
  List<String> theirs,
) {
  final oursMatch = matchTable(base, ours);
  final theirsMatch = matchTable(base, theirs);
  final chunks = <Chunk>[];
  var x = 0;
  var y = 0;
  var z = 0;
  while (x < base.length || y < ours.length || z < theirs.length) {
    if (x < base.length &&
        oursMatch[x + 1] == y + 1 &&
        theirsMatch[x + 1] == z + 1) {
      final line = base.sublist(x, x + 1);
      chunks.add(Chunk(ChunkKind.stable, x, y, z, line, line, line));
      x++;
      y++;
      z++;
      continue;
    }
    var anchor = x + 1;
    while (anchor <= base.length &&
        (oursMatch[anchor] == 0 || theirsMatch[anchor] == 0)) {
      anchor++;
    }
    final (nextX, nextY, nextZ) = anchor <= base.length
        ? (anchor - 1, oursMatch[anchor] - 1, theirsMatch[anchor] - 1)
        : (base.length, ours.length, theirs.length);
    final basePart = base.sublist(x, nextX);
    final oursPart = ours.sublist(y, nextY);
    final theirsPart = theirs.sublist(z, nextZ);
    final kind = chunkKind(basePart, oursPart, theirsPart);
    chunks.add(Chunk(kind, x, y, z, basePart, oursPart, theirsPart));
    x = nextX;
    y = nextY;
    z = nextZ;
  }
  return chunks;
}

String kindCounts(List<Chunk> chunks) {
  int count(ChunkKind kind) =>
      chunks.where((chunk) => chunk.kind == kind).length;
  return 'a=${count(ChunkKind.a)} b=${count(ChunkKind.b)} both=${count(ChunkKind.both)} '
      'conflicts=${count(ChunkKind.conflict)}';
}

int commonPrefixLength(List<String> first, List<String> second) {
  var length = 0;
  while (length < first.length &&
      length < second.length &&
      first[length] == second[length]) {
    length++;
  }
  return length;
}

int commonSuffixLength(List<String> first, List<String> second, int limit) {
  var length = 0;
  while (length < limit &&
      first[first.length - 1 - length] == second[second.length - 1 - length]) {
    length++;
  }
  return length;
}

List<String> conflictLines(
  Chunk chunk,
  String mode,
  String baseName,
  String oursName,
  String theirsName,
) {
  if (mode == 'OURS') return chunk.ours;
  if (mode == 'THEIRS') return chunk.theirs;
  if (mode == 'DIFF3') {
    return [
      '<<<<<<< $oursName',
      ...chunk.ours,
      '||||||| $baseName',
      ...chunk.base,
      conflictSeparator,
      ...chunk.theirs,
      '>>>>>>> $theirsName',
    ];
  }
  final ours = chunk.ours;
  final theirs = chunk.theirs;
  final head = commonPrefixLength(ours, theirs);
  final tail = commonSuffixLength(
    ours,
    theirs,
    min(ours.length, theirs.length) - head,
  );
  final oursMiddle = ours.sublist(head, ours.length - tail);
  final theirsMiddle = theirs.sublist(head, theirs.length - tail);
  final middle = mode == 'UNION'
      ? [...oursMiddle, ...theirsMiddle]
      : [
          '<<<<<<< $oursName',
          ...oursMiddle,
          conflictSeparator,
          ...theirsMiddle,
          '>>>>>>> $theirsName',
        ];
  return [
    ...ours.sublist(0, head),
    ...middle,
    ...ours.sublist(ours.length - tail),
  ];
}

enum Marker { start, base, separator, end }

const markerPrefixes = {
  '<<<<<<<': Marker.start,
  '|||||||': Marker.base,
  '>>>>>>>': Marker.end,
};

Marker? markerKind(String line) {
  if (line == conflictSeparator) return Marker.separator;
  if (line.length < 7) return null;
  final marker = markerPrefixes[line.substring(0, 7)];
  return marker != null && (line.length == 7 || line[7] == ' ') ? marker : null;
}

int nextMarker(List<String> lines, int index) {
  var next = index + 1;
  while (next < lines.length && markerKind(lines[next]) == null) {
    next++;
  }
  return next;
}

class ConflictRegion {
  final int start;
  final int end;
  final List<String> ours;
  final List<String>? base;
  final List<String> theirs;

  ConflictRegion(this.start, this.end, this.ours, this.base, this.theirs);

  List<String> part(String side) => switch (side) {
    'OURS' => ours,
    'THEIRS' => theirs,
    'BASE' => base!,
    _ => [...ours, ...theirs],
  };
}

ConflictRegion? regionAt(List<String> lines, int start) {
  if (markerKind(lines[start]) != Marker.start) return null;
  var middle = nextMarker(lines, start);
  int? baseMarker;
  if (middle < lines.length && markerKind(lines[middle]) == Marker.base) {
    baseMarker = middle;
    middle = nextMarker(lines, middle);
  }
  if (middle == lines.length || markerKind(lines[middle]) != Marker.separator)
    return null;
  final end = nextMarker(lines, middle);
  if (end == lines.length || markerKind(lines[end]) != Marker.end) return null;
  return ConflictRegion(
    start + 1,
    end + 1,
    lines.sublist(start + 1, baseMarker ?? middle),
    baseMarker == null ? null : lines.sublist(baseMarker + 1, middle),
    lines.sublist(middle + 1, end),
  );
}

List<ConflictRegion> conflictRegions(List<String> lines) {
  final regions = <ConflictRegion>[];
  var index = 0;
  while (index < lines.length) {
    final region = regionAt(lines, index);
    if (region == null) {
      index++;
    } else {
      regions.add(region);
      index = region.end;
    }
  }
  return regions;
}

class Workspace {
  final files = <String, List<String>>{};
  final history = <String, List<List<String>?>>{};
  final output = StringBuffer();

  void execute(List<String> words, List<String> data) {
    final arguments = words.sublist(1);
    try {
      switch (words[0]) {
        case 'FILE':
          loadFile(arguments, data);
        case 'COPY':
          copy(arguments);
        case 'PRINT':
          printFile(arguments);
        case 'FILES':
          listFiles();
        case 'DIFF':
          diff(arguments);
        case 'WORDDIFF':
          tokenDiff(arguments, true);
        case 'CHARDIFF':
          tokenDiff(arguments, false);
        case 'STAT':
          stat(arguments);
        case 'PATCH':
          patch(arguments, data);
        case 'EDIT':
          edit(arguments, data);
        case 'DIFF3':
          diff3(arguments);
        case 'MERGE':
          merge(arguments);
        case 'CONFLICTS':
          conflicts(arguments);
        case 'RESOLVE':
          resolve(arguments);
        case 'UNDO':
          undo(arguments);
      }
    } on CommandError catch (error) {
      emit(error.message);
    }
  }

  void emit(String line) => output.writeln(line);

  void emitAll(Iterable<String> lines) => lines.forEach(emit);

  void requireFiles(List<String> names) {
    for (final name in names) {
      if (!files.containsKey(name))
        throw CommandError('ERROR no such file $name');
    }
  }

  void save(String name, List<String> lines) {
    history.putIfAbsent(name, () => []).add(files[name]);
    files[name] = List.unmodifiable(lines);
  }

  void loadFile(List<String> arguments, List<String> data) {
    final name = arguments[0];
    save(name, data);
    emit('FILE $name lines=${data.length}');
  }

  void copy(List<String> arguments) {
    final [source, target] = arguments;
    requireFiles([source]);
    final lines = files[source]!;
    save(target, lines);
    emit('COPY $source $target lines=${lines.length}');
  }

  void printFile(List<String> arguments) {
    final name = arguments[0];
    requireFiles([name]);
    final lines = files[name]!;
    emit('PRINT $name lines=${lines.length}');
    for (var number = 1; number <= lines.length; number++) {
      emit('${number.toString().padLeft(3)}| ${lines[number - 1]}');
    }
  }

  void listFiles() {
    emit('FILES count=${files.length}');
    for (final name in files.keys.toList()..sort()) {
      emit('$name lines=${files[name]!.length} undo=${history[name]!.length}');
    }
  }

  void undo(List<String> arguments) {
    final name = arguments[0];
    final states = history[name] ?? [];
    if (states.isEmpty) throw CommandError('ERROR nothing to undo $name');
    final state = states.removeLast();
    if (state == null) {
      files.remove(name);
      emit('UNDO $name removed');
    } else {
      files[name] = state;
      emit('UNDO $name lines=${state.length}');
    }
  }

  void diff(List<String> arguments) {
    final [oldName, newName, form, ...] = arguments;
    requireFiles([oldName, newName]);
    final hasParameter = formatsWithArgument.contains(form);
    final parameter = hasParameter ? arguments[3] : '';
    final options = arguments.sublist(hasParameter ? 4 : 3);
    final diff = LineDiff(files[oldName]!, files[newName]!, options);
    if (diff.blocks.isEmpty) {
      emit('Files $oldName and $newName are identical');
      return;
    }
    emitAll(switch (form) {
      'BRIEF' => ['Files $oldName and $newName differ'],
      'NORMAL' => diff.normal(),
      'ED' => diff.ed(),
      'RCS' => diff.rcs(),
      'IFDEF' => diff.ifdef(parameter),
      'UNIFIED' => diff.unified(int.parse(parameter), oldName, newName),
      'CONTEXT' => diff.context(int.parse(parameter), oldName, newName),
      _ => diff.sideBySide(int.parse(parameter)),
    });
  }

  void tokenDiff(List<String> arguments, bool byWord) {
    final [oldName, newName] = arguments;
    requireFiles([oldName, newName]);
    final oldLines = files[oldName]!;
    final newLines = files[newName]!;
    final diff = LineDiff(oldLines, newLines);
    if (diff.blocks.isEmpty) {
      emit('Files $oldName and $newName are identical');
      return;
    }
    final separator = byWord ? ' ' : '';
    final totals = TokenTotals();
    for (final block in diff.blocks) {
      for (var row = 0; row < max(block.x, block.y); row++) {
        final oldNumber = block.p + row + 1;
        final newNumber = block.q + row + 1;
        if (row < block.x && row < block.y) {
          final oldTokens = splitTokens(oldLines[oldNumber - 1], byWord);
          final newTokens = splitTokens(newLines[newNumber - 1], byWord);
          final text = compareTokens(oldTokens, newTokens, separator, totals);
          emit('a$oldNumber b$newNumber: $text');
        } else if (row < block.x) {
          final oldTokens = splitTokens(oldLines[oldNumber - 1], byWord);
          totals.deleted += oldTokens.length;
          emit('a$oldNumber: ${deletion(oldTokens, separator)}');
        } else {
          final newTokens = splitTokens(newLines[newNumber - 1], byWord);
          totals.inserted += newTokens.length;
          emit('b$newNumber: ${insertion(newTokens, separator)}');
        }
      }
    }
    final label = byWord ? 'WORDS' : 'CHARS';
    emit(
      '$label deleted=${totals.deleted} inserted=${totals.inserted} common=${totals.common}',
    );
  }

  void stat(List<String> arguments) {
    final [oldName, newName, ...options] = arguments;
    requireFiles([oldName, newName]);
    final oldLines = files[oldName]!;
    final newLines = files[newName]!;
    final diff = LineDiff(oldLines, newLines, options);
    final deleted = diff.blocks.fold(0, (sum, block) => sum + block.x);
    final inserted = diff.blocks.fold(0, (sum, block) => sum + block.y);
    final total = deleted + inserted;
    final unchanged = oldLines.length - deleted;
    final graph = total > 0 ? ' ${statGraph(inserted, deleted)}' : '';
    emit('$oldName -> $newName | $total$graph');
    final lineTotal = oldLines.length + newLines.length;
    final similarity = lineTotal > 0 ? 200 * unchanged ~/ lineTotal : 100;
    emit(
      'changes=${diff.blocks.length} insertions=$inserted deletions=$deleted '
      'unchanged=$unchanged similarity=$similarity%',
    );
  }

  void patch(List<String> arguments, List<String> data) {
    final name = arguments[0];
    requireFiles([name]);
    final options = arguments.sublist(2);
    final reverse = options.contains('REVERSE');
    final dryRun = options.contains('DRYRUN');
    final fuzzIndex = options.indexOf('FUZZ');
    final maxFuzz = fuzzIndex >= 0 ? int.parse(options[fuzzIndex + 1]) : 0;
    final hunks = parsePatch(data);
    emit('${dryRun ? 'checking' : 'patching'} file $name');
    var lines = files[name]!;
    final first = hunks.first;
    if (searchHunk(first, lines, 0, reverse, maxFuzz) == null &&
        searchHunk(first, lines, 0, !reverse, maxFuzz) != null) {
      emit('Reversed (or previously applied) patch detected! Skipping patch.');
      emit(
        'RESULT applied=0 failed=0 ignored=${hunks.length} lines=${lines.length}',
      );
      return;
    }
    var adjustment = 0;
    var applied = 0;
    var failed = 0;
    for (var number = 1; number <= hunks.length; number++) {
      final hunk = hunks[number - 1];
      final match = searchHunk(hunk, lines, adjustment, reverse, maxFuzz);
      if (match == null) {
        failed++;
        emit('Hunk #$number FAILED at ${hunk.start(reverse)}');
        continue;
      }
      final (oldLines, newLines) = hunk.sequences(reverse);
      lines = match.lines;
      adjustment += match.delta + newLines.length - oldLines.length;
      applied++;
      emit(match.report(number));
    }
    emit(
      'RESULT applied=$applied failed=$failed ignored=0 lines=${lines.length}',
    );
    if (!dryRun && applied >= 1) save(name, lines);
  }

  void edit(List<String> arguments, List<String> data) {
    final name = arguments[0];
    requireFiles([name]);
    final (lines, executed) = runEditScript(files[name]!, data);
    emit('EDIT $name commands=$executed lines=${lines.length}');
    save(name, lines);
  }

  List<Chunk> threeWay(String baseName, String oursName, String theirsName) {
    requireFiles([baseName, oursName, theirsName]);
    return threeWayChunks(
      files[baseName]!,
      files[oursName]!,
      files[theirsName]!,
    );
  }

  void diff3(List<String> arguments) {
    final [baseName, oursName, theirsName] = arguments;
    final chunks = threeWay(baseName, oursName, theirsName);
    final changes = chunks
        .where((chunk) => chunk.kind != ChunkKind.stable)
        .toList();
    for (final chunk in changes) {
      emit('==== ${chunk.kind.name} ${chunk.location}');
      emitAll(chunk.base.map((line) => 'O $line'));
      if (chunk.kind != ChunkKind.b)
        emitAll(chunk.ours.map((line) => 'A $line'));
      if (chunk.kind == ChunkKind.b || chunk.kind == ChunkKind.conflict) {
        emitAll(chunk.theirs.map((line) => 'B $line'));
      }
    }
    emit('DIFF3 chunks=${changes.length} ${kindCounts(chunks)}');
  }

  void merge(List<String> arguments) {
    final [baseName, oursName, theirsName, target, ...] = arguments;
    final mode = arguments.length == 5 ? arguments[4] : 'MARKERS';
    final chunks = threeWay(baseName, oursName, theirsName);
    final result = <String>[];
    final conflicts = <Chunk>[];
    for (final chunk in chunks) {
      switch (chunk.kind) {
        case ChunkKind.b:
          result.addAll(chunk.theirs);
        case ChunkKind.conflict:
          result.addAll(
            conflictLines(chunk, mode, baseName, oursName, theirsName),
          );
          conflicts.add(chunk);
        default:
          result.addAll(chunk.ours);
      }
    }
    emit('MERGE $target lines=${result.length} ${kindCounts(chunks)}');
    for (var number = 1; number <= conflicts.length; number++) {
      emit('CONFLICT $number ${conflicts[number - 1].location}');
    }
    save(target, result);
  }

  void conflicts(List<String> arguments) {
    final name = arguments[0];
    requireFiles([name]);
    final regions = conflictRegions(files[name]!);
    emit('CONFLICTS $name count=${regions.length}');
    for (var number = 1; number <= regions.length; number++) {
      final region = regions[number - 1];
      final base = region.base?.length.toString() ?? 'none';
      emit(
        '$number: lines ${region.start}-${region.end} ours=${region.ours.length} '
        'base=$base theirs=${region.theirs.length}',
      );
    }
  }

  void resolve(List<String> arguments) {
    final [name, numberText, side] = arguments;
    requireFiles([name]);
    final number = int.parse(numberText);
    final lines = files[name]!;
    final regions = conflictRegions(lines);
    if (regions.length < number)
      throw CommandError('ERROR no conflict $number in $name');
    final region = regions[number - 1];
    if (side == 'BASE' && region.base == null) {
      throw CommandError('ERROR no base section in conflict $number');
    }
    final content = [
      ...lines.sublist(0, region.start - 1),
      ...region.part(side),
      ...lines.sublist(region.end),
    ];
    final remaining = conflictRegions(content).length;
    emit(
      'RESOLVE $name $number $side lines=${content.length} remaining=$remaining',
    );
    save(name, content);
  }
}

Future<void> main() async {
  final lines = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  final workspace = Workspace();
  var position = 1;
  final commandCount = int.parse(lines[0]);
  for (var command = 0; command < commandCount; command++) {
    final words = lines[position].split(' ');
    position++;
    var data = <String>[];
    if (dataCommands.contains(words[0])) {
      final count = int.parse(words[2]);
      data = lines.sublist(position, position + count);
      position += count;
    }
    workspace.execute(words, data);
  }
  stdout.write(workspace.output);
}
