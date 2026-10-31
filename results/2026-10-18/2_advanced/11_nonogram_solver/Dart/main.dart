import 'dart:io';
import 'dart:math';
import 'clues.dart';
import 'line_solver.dart';
import 'propagation.dart';
import 'search.dart';
import 'render.dart';

List<List<String>> readBlocks(String name) {
  final blocks = <List<String>>[]; List<String>? block;
  for (final line in File('input/$name').readAsLinesSync()) {
    if (block == null) { if (line.isNotEmpty && !line.startsWith('#')) block = [line]; }
    else if (line == 'END') { blocks.add(block); block = null; }
    else { block.add(line); }
  }
  return blocks;
}
List<String> joinParagraphs(List<List<String>> paragraphs) { final lines = <String>[]; for (final paragraph in paragraphs) { if (lines.isNotEmpty) lines.add(''); lines.addAll(paragraph); } return lines; }
void writeLines(String name, List<String> lines) => File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
bool validName(String name) => RegExp(r'^[a-z0-9_]{1,20}$').hasMatch(name);
String numberList(List<int> numbers) => numbers.isEmpty ? '-' : numbers.join(',');
String cellText(int row, int column) => '${row + 1},${column + 1}';
Grid stateGrid(List<String> texts) => [for (final text in texts) text.split('').map(charState).toList()];
Grid gridColumns(Grid grid) => [for (var c = 0; c < grid.first.length; c++) [for (final row in grid) row[c]]];
List<(int, int)> differingCells(Grid first, Grid second) => [for (var r = 0; r < first.length; r++) for (var c = 0; c < first[r].length; c++) if (first[r][c] != second[r][c]) (r, c)];
class Puzzle {
  late final String name;
  late final int width, height;
  late final List<String> rowLines;
  final columnLines = <String>[], givenLines = <(int, int, String)>[], rows = <List<int>>[], columns = <List<int>>[], givens = <Given>[];
  late final List<String>? answerLines;
  Grid? answer;
  Puzzle(List<String> lines) {
    name = lines.first.substring(7); final size = lines[1].split(' '); width = int.parse(size[1]); height = int.parse(size[2]); final at = lines.indexOf('COLUMNS'); rowLines = lines.sublist(3, at); var position = at + 1;
    while (position < lines.length && isClueLine(lines[position])) { columnLines.add(lines[position++]); }
    while (position < lines.length && lines[position].startsWith('GIVEN ')) { final parts = lines[position++].split(' '); givenLines.add((int.parse(parts[1]), int.parse(parts[2]), parts[3])); }
    answerLines = position < lines.length ? lines.sublist(position + 1) : null;
  }
  String? validate(Set<String> earlier) {
    if (!validName(name)) return 'bad name'; if (earlier.contains(name)) return 'duplicate name'; if (width < 1 || width > 30 || height < 1 || height > 30) return 'bad size';
    if (rowLines.length != height) return 'row count ${rowLines.length} expected $height'; if (columnLines.length != width) return 'column count ${columnLines.length} expected $width';
    for (final (kind, texts, length) in [('row', rowLines, width), ('column', columnLines, height)]) {
      for (var j = 0; j < texts.length; j++) { final clue = parseClue(texts[j]); if (clue == null) return 'bad clue $kind ${j + 1}'; if (!fitsClue(clue, length)) return '$kind ${j + 1} too long'; if (kind == 'row') { rows.add(clue); } else { columns.add(clue); } }
    }
    var a = 0, b = 0; for (final clue in rows) { for (final length in clue) { a += length; } } for (final clue in columns) { for (final length in clue) { b += length; } } if (a != b) return 'total mismatch rows=$a columns=$b';
    final taken = <(int, int)>{};
    for (var j = 0; j < givenLines.length; j++) { final (r, c, value) = givenLines[j]; if (r < 1 || r > height || c < 1 || c > width || !['#', '.'].contains(value)) return 'bad given ${j + 1}'; if (!taken.add((r, c))) return 'duplicate given ${j + 1}'; givens.add((r - 1, c - 1, charState(value))); }
    final texts = answerLines;
    if (texts != null) { if (texts.length != height) return 'bad answer'; for (final text in texts) { if (text.length != width || text.split('').any((char) => !['#', '.', '?'].contains(char))) return 'bad answer'; } answer = stateGrid(texts); } return null;
  }
}
(Grid, Propagation) logicalSolve(Clues rows, Clues columns, List<Given> givens, bool precise) {
  final grid = List.generate(rows.length, (_) => List.filled(columns.length, cellUnknown)); for (final (r, c, state) in givens) { grid[r][c] = state; }
  final propagation = propagate(grid, rows, columns, precise, List.filled(rows.length, true), List.filled(columns.length, true)); return (grid, propagation);
}
String solvingResult(Grid grid, Propagation propagation) => propagation.conflict != null ? 'contradiction at=${propagation.conflict!.label()}' : determinedCount(grid) == grid.length * grid.first.length ? 'solved' : 'stuck';
class Analysis {
  late final Grid simpleGrid, logicGrid;
  late final Propagation simple, logic;
  late final String simpleResult, logicResult, status;
  String difficulty = '-';
  Search? search;
  List<Grid> solutions = [];
  late final int lineSolves, guesses, maxDepth;
  Analysis(Clues rows, Clues columns, List<Given> givens) {
    final simpleSolved = logicalSolve(rows, columns, givens, false), logicSolved = logicalSolve(rows, columns, givens, true);
    simpleGrid = simpleSolved.$1; simple = simpleSolved.$2; logicGrid = logicSolved.$1; logic = logicSolved.$2;
    simpleResult = solvingResult(simpleGrid, simple); logicResult = solvingResult(logicGrid, logic);
    if (logic.conflict != null) { status = 'contradiction'; }
    else if (logicResult == 'solved') { status = 'unique'; solutions = [logicGrid]; difficulty = simpleResult == 'solved' ? 'easy' : 'medium'; }
    else { final found = Search(rows, columns); found.run(logicGrid); search = found; solutions = [...found.solutions]; status = ['none', 'unique', 'multiple'][solutions.length]; if (status == 'unique') difficulty = 'hard'; }
    lineSolves = logic.lineSolves() + (search?.lineSolves() ?? 0); guesses = search?.guessCount() ?? 0; maxDepth = search?.maxDepth() ?? 0;
  }
}
String clueStatistics(Clues rows, Clues columns) {
  var rowBlocks = 0, columnBlocks = 0, filled = 0, maximum = 0, fixed = 0;
  for (final clue in rows) { rowBlocks += clue.length; for (final length in clue) { filled += length; maximum = max(maximum, length); } if (clue.isEmpty || clueSpan(clue) == columns.length) fixed++; }
  for (final clue in columns) { columnBlocks += clue.length; for (final length in clue) { maximum = max(maximum, length); } if (clue.isEmpty || clueSpan(clue) == rows.length) fixed++; }
  return 'row_blocks=$rowBlocks column_blocks=$columnBlocks filled=$filled max_block=$maximum fixed_lines=$fixed';
}
String stepStatistics(Propagation propagation) {
  var productive = 0, idle = 0, best = 0; var at = '-'; for (final step in propagation.steps) { if (step.contradiction) continue; if (step.gain > 0) { productive++; } else { idle++; } if (step.gain > best) { best = step.gain; at = step.label(); } } return 'productive=$productive idle=$idle best=$best at=$at';
}
String featuresText(Grid grid) {
  final height = grid.length, width = grid.first.length, seen = List.generate(grid.length, (_) => List.filled(grid.first.length, false));
  var filled = 0, components = 0, largest = 0, minRow = height, minColumn = width, maxRow = -1, maxColumn = -1;
  for (var r = 0; r < height; r++) { for (var c = 0; c < width; c++) {
    if (grid[r][c] != cellFilled) continue; filled++; minRow = min(minRow, r); minColumn = min(minColumn, c); maxRow = max(maxRow, r); maxColumn = max(maxColumn, c); if (seen[r][c]) continue;
    components++; final pending = [(r, c)]; seen[r][c] = true; var size = 0;
    while (pending.isNotEmpty) { final (rr, cc) = pending.removeLast(); size++; for (final (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)]) { final nr = rr + dr, nc = cc + dc; if (0 <= nr && nr < height && 0 <= nc && nc < width && grid[nr][nc] == cellFilled && !seen[nr][nc]) { seen[nr][nc] = true; pending.add((nr, nc)); } } } largest = max(largest, size);
  } }
  final symmetries = <String>[];
  for (final (name, flipRows, flipColumns) in [('lr', false, true), ('ud', true, false), ('rot180', true, true)]) { var matches = true; for (var r = 0; r < height; r++) { for (var c = 0; c < width; c++) { if (grid[r][c] != grid[flipRows ? height - 1 - r : r][flipColumns ? width - 1 - c : c]) matches = false; } } if (matches) symmetries.add(name); }
  final bbox = filled == 0 ? '-' : '${minRow + 1},${minColumn + 1},${maxRow + 1},${maxColumn + 1}'; return 'filled=$filled components=$components largest=$largest bbox=$bbox symmetry=${symmetries.isEmpty ? 'none' : symmetries.join(',')}';
}
String unknownSummary(Grid lines) => [for (var j = 0; j < lines.length; j++) if (lines[j].contains(cellUnknown)) '${j + 1}:${lines[j].where((state) => state == cellUnknown).length}'].join(' ');
String? evaluateGivens(Puzzle puzzle, Analysis analysis) {
  if (puzzle.givens.isEmpty || analysis.status == 'multiple') return null; final unique = analysis.status == 'unique', numbers = <int>[];
  for (var j = 0; j < puzzle.givens.length; j++) { final others = [...puzzle.givens]..removeAt(j); final status = Analysis(puzzle.rows, puzzle.columns, others).status; if (status == 'unique' || !unique && status == 'multiple') numbers.add(j + 1); } return 'givens ${unique ? 'redundant' : 'blame'}=${numberList(numbers)}';
}
class Grading {
  final Puzzle puzzle;
  final rows = <int>[], columns = <int>[], givens = <int>[];
  late final int known;
  late final String result;
  String? extendable;
  int? differs;
  Grading(this.puzzle, Analysis analysis) {
    final answer = puzzle.answer!;
    for (var r = 0; r < puzzle.height; r++) { if (!hasPlacement(answer[r], puzzle.rows[r])) rows.add(r); }
    for (var c = 0; c < puzzle.width; c++) { if (!hasPlacement(lineCells(answer, false, c), puzzle.columns[c])) columns.add(c); }
    final givenCells = <(int, int)>{};
    for (var j = 0; j < puzzle.givens.length; j++) { final (r, c, state) = puzzle.givens[j]; givenCells.add((r, c)); if (answer[r][c] != cellUnknown && answer[r][c] != state) givens.add(j + 1); }
    known = determinedCount(answer); final mismatch = rows.isNotEmpty || columns.isNotEmpty || givens.isNotEmpty;
    if (known < puzzle.width * puzzle.height) { result = 'partial'; var canExtend = false;
      if (!mismatch) { final all = [...puzzle.givens, for (var r = 0; r < puzzle.height; r++) for (var c = 0; c < puzzle.width; c++) if (answer[r][c] != cellUnknown && !givenCells.contains((r, c))) (r, c, answer[r][c])]; final status = Analysis(puzzle.rows, puzzle.columns, all).status; canExtend = status == 'unique' || status == 'multiple'; } extendable = canExtend ? 'yes' : 'no';
    } else { result = mismatch ? 'wrong' : 'correct'; }
    if (analysis.status == 'unique') { var count = 0; for (var r = 0; r < puzzle.height; r++) { for (var c = 0; c < puzzle.width; c++) { if (answer[r][c] != cellUnknown && answer[r][c] != analysis.solutions.first[r][c]) count++; } } differs = count; }
  }
  List<String> lines() {
    var text = 'answer result=$result known=$known rows=${numberList(rows.map((r) => r + 1).toList())} columns=${numberList(columns.map((c) => c + 1).toList())} givens=${numberList(givens)}';
    if (extendable != null) text += ' extendable=$extendable'; if (differs != null) text += ' differs=$differs'; final lines = [text];
    for (final (isRow, indices) in [(true, rows), (false, columns)]) { for (final index in indices) { final clue = isRow ? puzzle.rows[index] : puzzle.columns[index], cells = lineCells(puzzle.answer!, isRow, index); lines.add('mismatch ${lineLabel(isRow, index)} expected=${commaClue(clue)}${result == 'partial' ? ' cells=${stateString(cells)}' : ' got=${commaClue(runClue(cells))}'}'); } } return lines;
  }
}
class PuzzleReport {
  final Puzzle puzzle;
  late final Analysis analysis;
  late final Grading? grading;
  late final String? evaluation;
  PuzzleReport(this.puzzle) { analysis = Analysis(puzzle.rows, puzzle.columns, puzzle.givens); evaluation = evaluateGivens(puzzle, analysis); grading = puzzle.answer == null ? null : Grading(puzzle, analysis); }
  int score() => analysis.lineSolves + 25 * analysis.guesses;
  List<String> paragraph() {
    final p = puzzle, a = analysis;
    final lines = ['PUZZLE ${p.name}', 'size=${p.width}x${p.height} givens=${p.givens.length} status=${a.status} difficulty=${a.difficulty}', 'clues ${clueStatistics(p.rows, p.columns)}', 'simple known=${determinedCount(a.simpleGrid)} line_solves=${a.simple.lineSolves()} result=${a.simpleResult}', 'logic known=${determinedCount(a.logicGrid)} line_solves=${a.logic.lineSolves()} result=${a.logicResult}', 'steps ${stepStatistics(a.logic)}'];
    if (p.width * p.height <= 49) lines.add('trace ${a.logic.record()}');
    if (a.logicResult == 'stuck') lines.add('stuck rows=${unknownSummary(a.logicGrid)} columns=${unknownSummary(gridColumns(a.logicGrid))}');
    if (a.status == 'contradiction') { final step = a.logic.conflict!; final clue = step.isRow ? p.rows[step.index] : p.columns[step.index]; lines.add('conflict line=${step.label()} clue=${commaClue(clue)} cells=${stateString(lineCells(a.logicGrid, step.isRow, step.index))}'); }
    final search = a.search;
    if (search != null) { lines.add('search guesses=${search.guessCount()} max_depth=${search.maxDepth()} backtracks=${search.backtracks} solutions=${search.solutions.length} line_solves=${search.lineSolves()}'); for (final guess in search.guesses) { lines.add('guess ${guess.number} depth=${guess.depth} cell=${cellText(guess.row, guess.column)} value=${stateChar(guess.value)} solves=${guess.solves} known=${guess.known} result=${guess.result}'); } }
    if (a.status == 'multiple') { final cells = differingCells(a.solutions[0], a.solutions[1]); lines.add('differ count=${cells.length} cells=${cells.map((cell) => cellText(cell.$1, cell.$2)).join(' ')}'); }
    final names = <String>[], grids = <Grid>[];
    if (a.status == 'contradiction') { names.add('partial'); grids.add(a.logicGrid); }
    else { if (a.simpleResult == 'stuck') { names.add('simple'); grids.add(a.simpleGrid); } if (a.logicResult == 'stuck') { names.add('logic'); grids.add(a.logicGrid); } if (a.status == 'multiple') { names.addAll(['first', 'second']); grids.addAll(a.solutions); } }
    if (names.isNotEmpty) lines.addAll(gridDisplay(names, grids)); if (a.status == 'unique') { lines.add('sheet'); lines.addAll(answerSheet(p.rows, p.columns, a.solutions.first)); lines.add('picture ${featuresText(a.solutions.first)}'); }
    if (evaluation != null) lines.add(evaluation!); if (grading != null) lines.addAll(grading!.lines()); return lines;
  }
  String statsRow() => [puzzle.name, analysis.status, analysis.difficulty, puzzle.width, puzzle.height, puzzle.givens.length, determinedCount(analysis.simpleGrid), determinedCount(analysis.logicGrid), analysis.lineSolves, analysis.guesses, analysis.maxDepth, analysis.solutions.length, grading?.result ?? '-'].join(',');
}
List<PuzzleReport> processPuzzles(List<List<String>> blocks) {
  final names = <String>{}, reports = <PuzzleReport>[], paragraphs = <List<String>>[], stats = ['puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer'];
  for (final lines in blocks) { final puzzle = Puzzle(lines); final error = puzzle.validate(names); names.add(puzzle.name); if (error != null) { paragraphs.add(['PUZZLE ${puzzle.name}', 'error $error']); stats.add('${puzzle.name},invalid${',-' * 11}'); continue; } final report = PuzzleReport(puzzle); reports.add(report); paragraphs.add(report.paragraph()); stats.add(report.statsRow()); }
  final ranked = reports.where((report) => report.analysis.status == 'unique').toList(), difficulty = {'easy': 0, 'medium': 1, 'hard': 2};
  ranked.sort((a, b) { var comparison = difficulty[a.analysis.difficulty]!.compareTo(difficulty[b.analysis.difficulty]!); if (comparison == 0) comparison = a.score().compareTo(b.score()); return comparison == 0 ? a.puzzle.name.compareTo(b.puzzle.name) : comparison; });
  paragraphs.add(['RANKING', for (var j = 0; j < ranked.length; j++) 'rank ${j + 1} ${ranked[j].puzzle.name} ${ranked[j].analysis.difficulty} score=${ranked[j].score()} size=${ranked[j].puzzle.width}x${ranked[j].puzzle.height}']);
  final statuses = {for (final status in ['contradiction', 'none', 'unique', 'multiple']) status: 0}, difficulties = {for (final level in ['easy', 'medium', 'hard']) level: 0}; var lineSolves = 0, guesses = 0;
  for (final report in reports) { final a = report.analysis; statuses[a.status] = statuses[a.status]! + 1; if (difficulties.containsKey(a.difficulty)) difficulties[a.difficulty] = difficulties[a.difficulty]! + 1; lineSolves += a.lineSolves; guesses += a.guesses; }
  paragraphs.add(['SUMMARY puzzles=${blocks.length} invalid=${blocks.length - reports.length} contradiction=${statuses['contradiction']} none=${statuses['none']} unique=${statuses['unique']} multiple=${statuses['multiple']} easy=${difficulties['easy']} medium=${difficulties['medium']} hard=${difficulties['hard']} line_solves=$lineSolves guesses=$guesses']);
  writeLines('solutions.txt', joinParagraphs(paragraphs)); writeLines('stats.csv', stats); return reports;
}
class Picture {
  final String name;
  final List<String> rows;
  Picture(List<String> lines) : name = lines.first.substring(8), rows = lines.sublist(1);
  String? validate(Set<String> earlier) {
    if (!validName(name)) return 'bad name'; if (earlier.contains(name)) return 'duplicate name'; if (rows.isEmpty || rows.length > 30) return 'bad height'; final width = rows.first.length;
    for (var j = 0; j < rows.length; j++) { final row = rows[j]; if (row.isEmpty || row.length > 30 || row.length != width || row.split('').any((char) => char != '#' && char != '.')) return 'bad row ${j + 1}'; } return null;
  }
}
bool sameClues(Clues first, Clues second) { if (first.length != second.length) return false; for (var j = 0; j < first.length; j++) { if (first[j].length != second[j].length) return false; for (var k = 0; k < first[j].length; k++) { if (first[j][k] != second[j][k]) return false; } } return true; }
class Generation {
  final Grid grid;
  late final Clues rows, columns;
  List<Given> givens = [];
  final log = <String>[];
  late final Analysis initial;
  late Analysis finalAnalysis;
  Generation(this.grid) {
    rows = grid.map(runClue).toList(); columns = gridColumns(grid).map(runClue).toList(); initial = analyze([]); var analysis = initial;
    while (analysis.status == 'multiple') { final (r, c) = differingCells(analysis.solutions[0], analysis.solutions[1]).first; final added = appendGiven(r, c); analysis = analyze(givens); log.add('# hint ${givens.length} $added status=${analysis.status}'); }
    final original = [...givens]; for (final given in original) { final others = givens.where((other) => other != given).toList(); if (analyze(others).status == 'unique') { givens = others; log.add('# drop cell=${cellText(given.$1, given.$2)}'); } }
    finalAnalysis = analyze(givens); var number = 0;
    while (finalAnalysis.difficulty == 'hard') { final (r, c) = guessCell(finalAnalysis.logicGrid)!; final added = appendGiven(r, c); finalAnalysis = analyze(givens); number++; log.add('# logic hint $number $added difficulty=${finalAnalysis.difficulty}'); }
  }
  Analysis analyze(List<Given> selected) => Analysis(rows, columns, selected);
  String appendGiven(int r, int c) { final state = grid[r][c]; givens.add((r, c, state)); return 'cell=${cellText(r, c)} value=${stateChar(state)}'; }
  List<String> puzzleLines(String name) {
    final selected = [...givens]..sort((a, b) { final comparison = a.$1.compareTo(b.$1); return comparison == 0 ? a.$2.compareTo(b.$2) : comparison; });
    return ['PUZZLE $name', 'SIZE ${columns.length} ${rows.length}', 'ROWS', ...rows.map(spaced), 'COLUMNS', ...columns.map(spaced), for (final (r, c, state) in selected) 'GIVEN ${r + 1} ${c + 1} ${stateChar(state)}', 'END'];
  }
  List<String> paragraph(Picture picture, List<PuzzleReport> reports) {
    var duplicate = '-'; for (final report in reports) { if (sameClues(report.puzzle.rows, rows) && sameClues(report.puzzle.columns, columns)) { duplicate = report.puzzle.name; break; } }
    final finalResult = finalAnalysis;
    return ['# picture ${picture.name} size=${columns.length}x${rows.length} ${featuresText(grid)}', '# clues ${clueStatistics(rows, columns)} duplicate_of=$duplicate', '# plain status=${initial.status} difficulty=${initial.difficulty} line_solves=${initial.lineSolves} guesses=${initial.guesses}', ...log, '# final status=${finalResult.status} difficulty=${finalResult.difficulty} hints=${givens.length} line_solves=${finalResult.lineSolves} guesses=${finalResult.guesses}', ...puzzleLines(picture.name)];
  }
}
void processPictures(List<List<String>> blocks, List<PuzzleReport> reports) {
  final names = <String>{}, paragraphs = <List<String>>[]; var valid = 0, unique = 0, lineLogic = 0, hinted = 0, hints = 0;
  for (final lines in blocks) { final picture = Picture(lines); final error = picture.validate(names); names.add(picture.name); if (error != null) { paragraphs.add(['# picture ${picture.name} error $error']); continue; }
    final generation = Generation(stateGrid(picture.rows)); valid++; if (generation.initial.status == 'unique') unique++; if (['easy', 'medium'].contains(generation.initial.difficulty)) lineLogic++; if (generation.givens.isNotEmpty) hinted++; hints += generation.givens.length; paragraphs.add(generation.paragraph(picture, reports));
  }
  paragraphs.add(['# SUMMARY pictures=${blocks.length} invalid=${blocks.length - valid} unique=$unique line_logic=$lineLogic hinted=$hinted hints=$hints']); writeLines('generated.txt', joinParagraphs(paragraphs));
}

void main() { Directory('output').createSync(recursive: true); final reports = processPuzzles(readBlocks('puzzles.txt')); processPictures(readBlocks('pictures.txt'), reports); }
