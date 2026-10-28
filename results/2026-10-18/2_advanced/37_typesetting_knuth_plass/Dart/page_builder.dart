part of 'main.dart';

class LayoutBlock {
  final String kind;
  final List<TextLine> lines;
  final bool list, pageBreak;
  LayoutBlock(this.kind, this.lines, this.list, this.pageBreak);
}

(List<TextLine>, List<(int, int, bool)>) buildSequence(
  List<LayoutBlock> blocks,
  int orphan,
  int widow,
) {
  final lines = <TextLine>[], boundaries = <(int, int, bool)>[];
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i], start = lines.length;
    lines.addAll(b.lines);
    final count = b.lines.length;
    if (b.kind == 'flow') {
      for (var kept = 1; kept < count; kept++) {
        if (kept >= orphan && count - kept >= widow)
          boundaries.add((start + kept, start + kept, false));
      }
    }
    if (i + 1 == blocks.length) {
      boundaries.add((lines.length, lines.length, true));
      continue;
    }
    final following = blocks[i + 1], end = lines.length;
    if (!(b.list && following.list)) lines.add(TextLine(''));
    final forced = following.pageBreak;
    if (forced || b.kind != 'heading')
      boundaries.add((end, lines.length, forced));
  }
  return (lines, boundaries);
}

List<Page> choosePages(
  List<LayoutBlock> blocks,
  Map<int, int> footnoteHeights,
  int height,
  int orphan,
  int widow,
) {
  final (lines, boundaries) = buildSequence(blocks, orphan, widow);
  final pages = <Page>[];
  var start = 0, firstBoundary = 0;
  while (start < lines.length) {
    final notes = <int>{};
    var noteHeight = 0, scanned = start;
    (int, int, int, bool, int, List<int>)? chosen;
    for (var index = firstBoundary; index < boundaries.length; index++) {
      final (end, next, forced) = boundaries[index];
      while (scanned < end) {
        for (final number in lines[scanned].footnotes) {
          if (notes.add(number)) noteHeight += footnoteHeights[number]!;
        }
        scanned++;
      }
      final used = end - start + noteHeight + (notes.isEmpty ? 0 : 1);
      if (used > height) break;
      chosen = (index, end, next, forced, used, notes.toList()..sort());
      if (forced) break;
    }
    final (index, end, next, forced, used, pageNotes) = chosen!;
    pages.add(
      Page(
        content: lines.sublist(start, end),
        footnotes: pageNotes,
        height: used,
        endsByForce: forced,
      ),
    );
    start = next;
    firstBoundary = index + 1;
  }
  return pages;
}
