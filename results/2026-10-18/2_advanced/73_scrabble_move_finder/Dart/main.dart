import 'dart:io';
import 'dart:math';

part 'board.dart';
part 'dictionary_trie.dart';
part 'move_generator.dart';
part 'scoring.dart';
part 'game.dart';

class Tiles {
  final List<int> value = List.filled(27, 0),
      count = List.filled(27, 0),
      weight = List.filled(27, 0);
}

class DictionaryStats {
  int lines = 0, skipped = 0, duplicates = 0;
  final List<int> lengths = List.filled(16, 0);
}

class PlayerSpec {
  final String name, strategy;
  final int threshold;
  PlayerSpec(this.name, this.strategy, [this.threshold = 0]);
}

class Job {
  final List<String> header, lines;
  Board board = Board.empty();
  String rack = '', order = '';
  int count = 0, seed = 0;
  final List<List<String>> records = [];
  final List<PlayerSpec> players = [];
  Job(this.header, this.lines);
}

class TopTotals {
  int jobs = 0, errors = 0, moves = 0, bingos = 0;
}

class ValidationTotals {
  int jobs = 0, errors = 0, moves = 0, valid = 0, invalid = 0, loss = 0;
}

class GameTotals {
  int games = 0,
      duplicates = 0,
      errors = 0,
      turns = 0,
      rounds = 0,
      plays = 0,
      exchanges = 0,
      passes = 0,
      bingos = 0;
}

class PlayerRecord {
  final String name;
  int moves = 0, valid = 0, score = 0, loss = 0;
  PlayerRecord(this.name);
}

int tileIndex(String c) {
  final code = c.codeUnitAt(0);
  return c == '?' || (code >= 97 && code <= 122) ? 26 : code - 65;
}

List<int> collectionCounts(String s) {
  final a = List.filled(27, 0);
  for (var i = 0; i < s.length; i++) {
    a[tileIndex(s[i])]++;
  }
  return a;
}

String countsString(List<int> a) =>
    '?' * a[26] +
    [for (var i = 0; i < 26; i++) String.fromCharCode(65 + i) * a[i]].join();
String sortedCollection(String s) => countsString(collectionCounts(s));
String notation(String s) => s.isEmpty ? '-' : sortedCollection(s);
bool validName(String s) =>
    s.isNotEmpty && s.length <= 20 && RegExp(r'^[a-z0-9_]+$').hasMatch(s);
int? validNumber(String s, int lo, int hi) {
  if (s.isEmpty || (s.length > 1 && s[0] == '0')) return null;
  var n = 0;
  for (final code in s.codeUnits) {
    if (code < 48 || code > 57) return null;
    final digit = code - 48;
    if (n > (hi - digit) ~/ 10) return null;
    n = 10 * n + digit;
    if (n > hi) return null;
  }
  return n >= lo && n <= hi ? n : null;
}

bool validRack(String s) =>
    s.isNotEmpty && s.length <= 7 && RegExp(r'^[A-Z?]+$').hasMatch(s);
bool validWord(String s, bool uppercaseOnly) =>
    s.length >= 2 &&
    s.length <= 15 &&
    (uppercaseOnly ? RegExp(r'^[A-Z]+$') : RegExp(r'^[A-Za-z]+$')).hasMatch(s);
bool strategy(String s) => s == 'score' || s == 'tiles' || s == 'equity';
(Tiles, Trie, DictionaryStats, List<Job>) readData() {
  final tiles = Tiles();
  for (final line in File('input/tiles.txt').readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final a = line.split(' '), i = tileIndex(a[0]);
    tiles.value[i] = int.parse(a[1]);
    tiles.count[i] = int.parse(a[2]);
    tiles.weight[i] = int.parse(a[3]);
  }
  final trie = Trie(), stats = DictionaryStats();
  for (final word in File('input/dictionary.txt').readAsLinesSync()) {
    if (word.isEmpty || word.startsWith('#')) continue;
    stats.lines++;
    if (!validWord(word, true)) {
      stats.skipped++;
      continue;
    }
    if (!trie.add(word)) {
      stats.duplicates++;
      continue;
    }
    stats.lengths[word.length]++;
  }
  final lines = File('input/jobs.txt').readAsLinesSync(), jobs = <Job>[];
  for (var pos = 0; pos < lines.length; pos++) {
    final line = lines[pos];
    if (line.isEmpty || line.startsWith('#')) continue;
    final header = line.split(' '), body = <String>[];
    for (pos++; pos < lines.length && lines[pos] != 'END'; pos++) {
      body.add(lines[pos]);
    }
    jobs.add(Job(header, body));
  }
  return (tiles, trie, stats, jobs);
}

List<int> boardCounts(Board board) {
  final count = List.filled(27, 0);
  for (final row in board.cells) {
    for (final letter in row) {
      if (letter != '.') count[tileIndex(letter)]++;
    }
  }
  return count;
}

String countError(Board board, String rack, Tiles tiles) {
  final count = boardCounts(board), r = collectionCounts(rack);
  for (var i = 0; i < 27; i++) {
    if (count[i] + r[i] > tiles.count[i])
      return 'too many ${i == 26 ? '?' : String.fromCharCode(65 + i)}';
  }
  return '';
}

String unseen(Board board, String rack, Tiles tiles) {
  final used = boardCounts(board), r = collectionCounts(rack);
  return countsString([
    for (var i = 0; i < 27; i++) tiles.count[i] - used[i] - r[i],
  ]);
}

(Board, String) checkBoard(
  List<String> lines,
  String rack,
  Tiles tiles,
  Trie trie,
) {
  final board = Board.empty();
  if (lines.length != 15) return (board, 'board rows ${lines.length}');
  for (var i = 0; i < 15; i++) {
    final row = lines[i];
    if (row.length != 15 || !RegExp(r'^[.A-Za-z]+$').hasMatch(row))
      return (board, 'bad board row ${i + 1}');
    board.cells[i] = row.split('');
  }
  final reason = countError(board, rack, tiles);
  if (reason.isNotEmpty) return (board, reason);
  if (tileCount(board) > 0) {
    if (board.cells[center][center] == '.') return (board, 'center empty');
    if (!connected(board)) return (board, 'disconnected');
  }
  for (final word in boardWords(board)) {
    if (!trie.contains(word.word))
      return (
        board,
        'unknown word ${word.word} at ${positionName(word.row, word.col, word.direction)}',
      );
  }
  return (board, '');
}

String checkJob(Job job, Set<String> seen, Tiles tiles, Trie trie) {
  final h = job.header, name = h[1];
  var reason = '';
  if (!validName(name)) {
    reason = 'bad name';
  } else if (seen.contains(name)) {
    reason = 'duplicate name';
  }
  seen.add(name);
  if (reason.isNotEmpty) return reason;
  if (h[0] == 'TOPN') {
    final count = validNumber(h[2], 1, 99);
    if (count == null) return 'bad count';
    if (!strategy(h[3])) return 'bad order';
    final rack = job.lines[0].split(' ')[1];
    if (!validRack(rack)) return 'bad rack';
    job.count = count;
    job.order = h[3];
    job.rack = rack;
    final (board, error) = checkBoard(job.lines.sublist(2), rack, tiles, trie);
    job.board = board;
    return error;
  }
  if (h[0] == 'VALIDATE') {
    final boardLines = <String>[];
    var records = false;
    for (final line in job.lines.skip(1)) {
      if (line.startsWith('MOVE')) records = true;
      if (records) {
        job.records.add(line.split(' '));
      } else {
        boardLines.add(line);
      }
    }
    final (board, error) = checkBoard(boardLines, '', tiles, trie);
    job.board = board;
    return error;
  }
  final seed = validNumber(h[2], 1, 2147483646);
  if (seed == null) return 'bad seed';
  job.seed = seed;
  if (job.lines.length < 2 || job.lines.length > 4)
    return 'bad player count ${job.lines.length}';
  final names = <String>{};
  for (var i = 0; i < job.lines.length; i++) {
    final a = job.lines[i].split(' '),
        threshold = h[0] == 'GAME' ? validNumber(a[3], 0, 99) : 0;
    if (!validName(a[1]) || !strategy(a[2]) || threshold == null)
      return 'bad player ${i + 1}';
    if (!names.add(a[1])) return 'duplicate player ${i + 1}';
    job.players.add(PlayerSpec(a[1], a[2], threshold));
  }
  return '';
}

(int, int, int) rackBreakdown(String rack) {
  var v = 0, c = 0, b = 0;
  for (var i = 0; i < rack.length; i++) {
    final letter = rack[i];
    if (letter == '?') {
      b++;
    } else if ('AEIOU'.contains(letter)) {
      v++;
    } else {
      c++;
    }
  }
  return (v, c, b);
}

int leaveValue(String rack, Tiles tiles) {
  final counts = collectionCounts(rack);
  var value = 0, duplicates = 0;
  for (var i = 0; i < 27; i++) {
    final n = counts[i];
    value += n * tiles.weight[i];
    if (i < 26 && n > 0) duplicates += n - 1;
  }
  final (v, c, _) = rackBreakdown(rack);
  return value - 4 * duplicates - 3 * max(0, (v - c).abs() - 1);
}

(String, int) bestLeave(String rack, Tiles tiles) {
  var best = '', value = leaveValue('', tiles);
  final seen = <String>{};
  for (var mask = 0; mask < (1 << rack.length) - 1; mask++) {
    final candidate = sortedCollection(
      [
        for (var i = 0; i < rack.length; i++)
          if (((mask >> i) & 1) != 0) rack[i],
      ].join(),
    );
    if (!seen.add(candidate)) continue;
    final score = leaveValue(candidate, tiles);
    if (score > value ||
        (score == value &&
            (candidate.length > best.length ||
                (candidate.length == best.length &&
                    candidate.compareTo(best) < 0)))) {
      best = candidate;
      value = score;
    }
  }
  return (best, value);
}

int compareStandard(Move a, Move b) {
  var c = b.score.compareTo(a.score);
  if (c != 0) return c;
  c = a.raw.row.compareTo(b.raw.row);
  if (c != 0) return c;
  c = a.raw.col.compareTo(b.raw.col);
  if (c != 0) return c;
  c = a.raw.direction.compareTo(b.raw.direction);
  return c != 0 ? c : a.raw.word.compareTo(b.raw.word);
}

List<Move> legalMoves(Board board, String rack, Tiles tiles, Trie trie) {
  final moves = [
    for (final raw in generateMoves(board, rack, trie))
      evaluateMove(board, rack, raw, tiles),
  ];
  for (final move in moves) {
    move.leaveValue = leaveValue(move.leave, tiles);
  }
  moves.sort(compareStandard);
  for (var i = 0; i < moves.length; i++) {
    moves[i].rank = i + 1;
  }
  return moves;
}

List<Move> orderedMoves(List<Move> moves, String strategy) =>
    List<Move>.of(moves)..sort((a, b) {
      var c = 0;
      if (strategy == 'tiles') c = b.tiles.compareTo(a.tiles);
      if (strategy == 'equity')
        c = (b.score + b.leaveValue).compareTo(a.score + a.leaveValue);
      return c != 0 ? c : compareStandard(a, b);
    });
String moveName(Move m) =>
    '${positionName(m.raw.row, m.raw.col, m.raw.direction)} ${m.raw.word}';
String positionSummary(Board board) {
  final words = boardWords(board);
  var longest = '-', length = 0, blanks = 0;
  for (final word in words) {
    if (word.word.length > length) {
      longest = word.word;
      length = word.word.length;
    }
  }
  final premiumsUsed = <String, int>{};
  for (var r = 0; r < 15; r++) {
    for (var c = 0; c < 15; c++) {
      final tile = board.cells[r][c];
      if (tile != '.') {
        final code = tile.codeUnitAt(0);
        if (code >= 97 && code <= 122) blanks++;
        premiumsUsed[premiums[r][c]] = (premiumsUsed[premiums[r][c]] ?? 0) + 1;
      }
    }
  }
  return 'position tiles=${tileCount(board)} words=${words.length} longest=$longest blanks=$blanks premiums=TW:${premiumsUsed['#'] ?? 0},DW:${premiumsUsed['*'] ?? 0},TL:${premiumsUsed['^'] ?? 0},DL:${premiumsUsed['+'] ?? 0}';
}

void boardReport(StringBuffer s, Board board) {
  s.writeln(positionSummary(board));
  for (final row in display(board)) {
    s.writeln(row);
  }
}

String reportTop(Job job, Tiles tiles, Trie trie, TopTotals total) {
  final out = StringBuffer(),
      moves = legalMoves(job.board, job.rack, tiles, trie),
      a = anchors(job.board);
  final anchorCount = a.expand((r) => r).where((v) => v).length,
      unseenTiles = unseen(job.board, job.rack, tiles);
  final (vowels, consonants, blanks) = rackBreakdown(job.rack);
  final (_, acrossChecks) = crossChecks(job.board, 0, trie);
  final (_, downChecks) = crossChecks(job.board, 1, trie);
  var across = 0, down = 0, bingos = 0, blankMoves = 0;
  final byTiles = List.filled(8, -1);
  for (final move in moves) {
    if (move.raw.direction == 0) {
      across++;
    } else {
      down++;
    }
    if (move.tiles == 7) bingos++;
    if (move.placed.any((tile) => RegExp(r'^[a-z]$').hasMatch(tile.letter)))
      blankMoves++;
    byTiles[move.tiles] = max(byTiles[move.tiles], move.score);
  }
  total.moves += moves.length;
  total.bingos += bingos;
  final (keep, keepValue) = bestLeave(job.rack, tiles);
  final anagrams = trie.anagrams(job.rack)
    ..sort((a, b) {
      final c = b.length.compareTo(a.length);
      return c != 0 ? c : a.compareTo(b);
    });
  out.writeln(
    'TOPN ${job.header[1]} n=${job.count} order=${job.order} rack=${notation(job.rack)}',
  );
  out.writeln('board tiles=${tileCount(job.board)} anchors=$anchorCount');
  out.writeln(
    'unseen count=${unseenTiles.length} tiles=${notation(unseenTiles)}',
  );
  out.writeln(
    'rack vowels=$vowels consonants=$consonants blanks=$blanks value=${collectionValue(job.rack, tiles)}',
  );
  out.writeln(
    'checks across=${acrossChecks.squares},${acrossChecks.empty},${acrossChecks.letters} down=${downChecks.squares},${downChecks.empty},${downChecks.letters}',
  );
  out.writeln(
    'moves total=${moves.length} across=$across down=$down bingos=$bingos blanks=$blankMoves',
  );
  out.writeln(
    [
      'best_by_tiles',
      for (var t = 1; t <= 7; t++)
        '$t=${byTiles[t] < 0 ? '-' : byTiles[t].toString()}',
    ].join(' '),
  );
  out.writeln('exchange keep=${notation(keep)} value=$keepValue');
  out.writeln(
    'anagrams total=${anagrams.length} top=${anagrams.isEmpty ? '-' : anagrams.take(10).join(',')}',
  );
  for (final word in boardWords(job.board)) {
    if (word.word.length < 3) continue;
    final upperWord = word.word.toUpperCase();
    var front = '', back = '';
    for (var code = 65; code <= 90; code++) {
      final letter = String.fromCharCode(code);
      if (trie.contains(letter + upperWord)) front += letter;
      if (trie.contains(upperWord + letter)) back += letter;
    }
    if (front.isEmpty && back.isEmpty) continue;
    out.writeln(
      'hook ${positionName(word.row, word.col, word.direction)} ${word.word} front=${front.isEmpty ? '-' : front} back=${back.isEmpty ? '-' : back}',
    );
  }
  final shown = orderedMoves(moves, job.order).take(job.count).toList(),
      endgame =
          unseenTiles.length >= 1 &&
          unseenTiles.length <= 7 &&
          shown.isNotEmpty;
  final nets = List.filled(shown.length, 0);
  if (endgame) {
    var best = 0;
    for (var i = 0; i < shown.length; i++) {
      final move = shown[i], after = job.board.copy();
      play(after, move);
      final reply = legalMoves(after, unseenTiles, tiles, trie),
          score = reply.isEmpty ? 0 : reply[0].score;
      nets[i] = move.score - score;
      if (nets[i] > nets[best]) best = i;
    }
    out.writeln(
      'endgame opponent=${notation(unseenTiles)} best=${best + 1} net=${nets[best]}',
    );
  }
  for (var i = 0; i < shown.length; i++) {
    final move = shown[i];
    out.write(
      '${i + 1} ${moveName(move)} score=${move.score} tiles=${move.tiles} leave=${notation(move.leave)} value=${move.leaveValue}',
    );
    if (endgame) out.write(' net=${nets[i]}');
    out.writeln(' words=${wordList(move)}');
  }
  return out.toString();
}

(Move?, String) validatePlacement(
  Board board,
  String rack,
  String position,
  String word,
  Tiles tiles,
  Trie trie,
) {
  final parsed = parsePosition(position);
  if (parsed == null) return (null, 'bad position');
  final (row, col, direction) = parsed;
  if (!validWord(word, false)) return (null, 'bad word');
  final raw = RawMove(row, col, direction, word), squares = moveSquares(raw);
  for (final (r, c) in squares) {
    if (!inside(r, c)) return (null, 'off board');
  }
  final newTiles = <PlacedTile>[];
  for (var i = 0; i < squares.length; i++) {
    final (r, c) = squares[i];
    final existing = board.cells[r][c];
    if (existing != '.' && existing != word[i])
      return (null, 'mismatch at ${squareName(r, c)}');
    if (existing == '.') newTiles.add(PlacedTile(r, c, word[i]));
  }
  final (dr, dc) = directions(direction);
  final before = (row - dr, col - dc),
      last = squares.last,
      after = (last.$1 + dr, last.$2 + dc);
  if ((inside(before.$1, before.$2) &&
          board.cells[before.$1][before.$2] != '.') ||
      (inside(after.$1, after.$2) && board.cells[after.$1][after.$2] != '.'))
    return (null, 'not whole word');
  if (newTiles.isEmpty) return (null, 'no new tiles');
  final counts = collectionCounts(rack);
  var touches = false, centerCovered = false;
  for (final tile in newTiles) {
    final i = tileIndex(tile.letter);
    if (counts[i] == 0)
      return (
        null,
        'rack lacks ${i == 26 ? '?' : String.fromCharCode(65 + i)}',
      );
    counts[i]--;
    if (adjacent(board, tile.row, tile.col)) touches = true;
    if (tile.row == center && tile.col == center) centerCovered = true;
  }
  if (tileCount(board) == 0) {
    if (!centerCovered) return (null, 'center not covered');
  } else if (!touches) {
    return (null, 'not connected');
  }
  final move = evaluateMove(board, rack, raw, tiles);
  for (final w in move.words) {
    final word = w.boardWord;
    if (!trie.contains(word.word))
      return (
        null,
        'unknown word ${word.word} at ${positionName(word.row, word.col, word.direction)}',
      );
  }
  move.leaveValue = leaveValue(move.leave, tiles);
  return (move, '');
}

(Move?, String) validateRecord(
  Board board,
  List<String> record,
  Tiles tiles,
  Trie trie,
) {
  if (!validName(record[1])) return (null, 'bad player');
  final rack = record[2];
  if (!validRack(rack)) return (null, 'bad rack');
  final reason = countError(board, rack, tiles);
  if (reason.isNotEmpty) return (null, reason);
  if (record.length == 4) return (null, '');
  if (record[3] == 'EXCHANGE') {
    final putBack = record[4];
    if (!validRack(putBack)) return (null, 'bad exchange');
    final count = collectionCounts(putBack), r = collectionCounts(rack);
    for (var i = 0; i < putBack.length; i++) {
      final letter = putBack[i], index = tileIndex(putBack[i]);
      if (count[index] > r[index]) return (null, 'rack lacks $letter');
    }
    return (null, '');
  }
  return validatePlacement(board, rack, record[3], record[4], tiles, trie);
}

String reportValidation(
  Job job,
  Tiles tiles,
  Trie trie,
  ValidationTotals total,
) {
  final out = StringBuffer('VALIDATE ${job.header[1]}\n'),
      board = job.board.copy(),
      players = <PlayerRecord>[],
      byName = <String, PlayerRecord>{};
  var valid = 0, invalid = 0, scoreTotal = 0, bestTotal = 0, lossTotal = 0;
  for (var i = 0; i < job.records.length; i++) {
    final record = job.records[i];
    final (move, reason) = validateRecord(board, record, tiles, trie);
    PlayerRecord? player;
    if (reason != 'bad player') {
      player = byName[record[1]];
      if (player == null) {
        player = PlayerRecord(record[1]);
        byName[record[1]] = player;
        players.add(player);
      }
      player.moves++;
    }
    out.write('move ${i + 1} ${record[1]} ${record.skip(3).join(' ')}');
    if (reason.isNotEmpty) {
      invalid++;
      out.writeln(' invalid $reason');
      continue;
    }
    valid++;
    final moves = legalMoves(board, record[2], tiles, trie),
        best = moves.isEmpty ? 0 : moves[0].score;
    final isPlacement = record.length == 5 && record[3] != 'EXCHANGE',
        score = isPlacement ? move!.score : 0;
    final loss = best - score;
    final currentPlayer = player!;
    currentPlayer.valid++;
    currentPlayer.score += score;
    currentPlayer.loss += loss;
    scoreTotal += score;
    bestTotal += best;
    lossTotal += loss;
    if (isPlacement) {
      final played = move!;
      final placement = placementKey(board, played.raw);
      var rank = 0;
      for (final candidate in moves) {
        if (placementKey(board, candidate.raw) == placement) {
          rank = candidate.rank;
          break;
        }
      }
      out.writeln(
        ' score=$score total=${currentPlayer.score} tiles=${played.tiles} rank=$rank/${moves.length} best=$best words=${wordList(played)}',
      );
      play(board, played);
    } else {
      out.writeln(
        ' score=0 total=${currentPlayer.score} moves=${moves.length} best=$best',
      );
    }
  }
  for (final player in players) {
    out.writeln(
      'player ${player.name} moves=${player.moves} valid=${player.valid} score=${player.score} loss=${player.loss}',
    );
  }
  out.writeln(
    'total valid=$valid invalid=$invalid score=$scoreTotal best=$bestTotal loss=$lossTotal',
  );
  boardReport(out, board);
  total.moves += job.records.length;
  total.valid += valid;
  total.invalid += invalid;
  total.loss += lossTotal;
  return out.toString();
}

class GamePlayer {
  final PlayerSpec spec;
  String rack;
  int score = 0,
      adjust = 0,
      total = 0,
      plays = 0,
      bingos = 0,
      exchanges = 0,
      passes = 0,
      top = 0,
      loss = 0;
  GamePlayer(this.spec, this.rack);
}

String subtractCollection(String a, String b) {
  final counts = collectionCounts(a), remove = collectionCounts(b);
  for (var i = 0; i < 27; i++) {
    counts[i] -= remove[i];
  }
  return countsString(counts);
}

String signed(int value) => value > 0 ? '+$value' : '$value';
String reportGame(Job job, Tiles tiles, Trie trie, GameTotals total) {
  final out = StringBuffer(
        'GAME ${job.header[1]} seed=${job.seed} players=${job.players.length}\n',
      ),
      players = <GamePlayer>[],
      generator = Generator(job.seed);
  final bag = newBag(tiles, generator);
  for (var i = 0; i < job.players.length; i++) {
    final spec = job.players[i];
    players.add(GamePlayer(spec, draw(bag, rackSize)));
    out.writeln(
      'player ${i + 1} ${spec.name} strategy=${spec.strategy} threshold=${spec.threshold}',
    );
  }
  final board = Board.empty();
  var scoreless = 0,
      turn = 0,
      goingOut = -1,
      reason = '',
      highlightTurn = -1,
      highlightPlayer = -1;
  Move? highlight;
  while (true) {
    turn++;
    final index = (turn - 1) % players.length, player = players[index];
    final rack = player.rack, moves = legalMoves(board, rack, tiles, trie);
    out.write(
      'turn $turn ${player.spec.name} rack=${notation(rack)} moves=${moves.length}',
    );
    final candidate = moves.isEmpty
        ? null
        : orderedMoves(moves, player.spec.strategy)[0];
    if (candidate != null &&
        !(candidate.score < player.spec.threshold && bag.length >= 7)) {
      final best = moves[0].score;
      play(board, candidate);
      player.score += candidate.score;
      player.plays++;
      player.top = max(player.top, candidate.score);
      player.loss += best - candidate.score;
      if (candidate.tiles == 7) player.bingos++;
      final drawn = draw(bag, rackSize - candidate.leave.length);
      player.rack = candidate.leave + drawn;
      scoreless = 0;
      out.writeln(
        ' best=$best play ${moveName(candidate)} score=${candidate.score} total=${player.score} draw=${notation(drawn)} bag=${bag.length}',
      );
      if (highlight == null || candidate.score > highlight.score) {
        highlightTurn = turn;
        highlightPlayer = index;
        highlight = candidate;
      }
      if (player.rack.isEmpty && bag.isEmpty) {
        reason = 'out';
        goingOut = index;
        break;
      }
    } else if (bag.length >= 7) {
      final (keep, _) = bestLeave(rack, tiles);
      final putBack = subtractCollection(rack, keep),
          drawn = exchange(bag, putBack, generator);
      player.rack = keep + drawn;
      player.exchanges++;
      scoreless++;
      out.writeln(
        ' exchange keep=${notation(keep)} draw=${notation(drawn)} bag=${bag.length}',
      );
    } else {
      player.passes++;
      scoreless++;
      out.writeln(' pass bag=${bag.length}');
    }
    if (scoreless == 6) {
      reason = 'scoreless';
      break;
    }
  }
  out.writeln(
    reason == 'out'
        ? 'end reason=out player=${players[goingOut].spec.name} turns=$turn'
        : 'end reason=scoreless turns=$turn',
  );
  for (var i = 0; i < players.length; i++) {
    if (i != goingOut) {
      final value = collectionValue(players[i].rack, tiles);
      players[i].adjust = -value;
      if (goingOut >= 0) players[goingOut].adjust += value;
    }
  }
  for (final p in players) {
    p.total = p.score + p.adjust;
    out.writeln(
      'final ${p.spec.name} score=${p.score} rack=${notation(p.rack)} adjust=${signed(p.adjust)} total=${p.total}',
    );
    total.plays += p.plays;
    total.exchanges += p.exchanges;
    total.passes += p.passes;
    total.bingos += p.bingos;
  }
  final standing = [for (var i = 0; i < players.length; i++) i]
    ..sort((a, b) {
      final c = players[b].total.compareTo(players[a].total);
      return c != 0 ? c : a.compareTo(b);
    });
  for (var rank = 0; rank < standing.length; rank++) {
    final p = players[standing[rank]];
    out.writeln(
      'standing ${rank + 1} ${p.spec.name} total=${p.total} plays=${p.plays} bingos=${p.bingos} exchanges=${p.exchanges} passes=${p.passes} top=${p.top} loss=${p.loss}',
    );
  }
  final bestTotal = players[standing[0]].total,
      winners = [
        for (final p in players)
          if (p.total == bestTotal) p.spec.name,
      ];
  out.writeln('winner ${winners.join(',')}');
  if (highlight != null)
    out.writeln(
      'highlight turn=$highlightTurn player=${players[highlightPlayer].spec.name} play ${moveName(highlight)} score=${highlight.score}',
    );
  boardReport(out, board);
  total.turns += turn;
  return out.toString();
}

String reportDuplicate(Job job, Tiles tiles, Trie trie, GameTotals total) {
  final out = StringBuffer(
    'DUPLICATE ${job.header[1]} seed=${job.seed} players=${job.players.length}\n',
  );
  for (var i = 0; i < job.players.length; i++) {
    final p = job.players[i];
    out.writeln('player ${i + 1} ${p.name} strategy=${p.strategy}');
  }
  final generator = Generator(job.seed), bag = newBag(tiles, generator);
  var rack = draw(bag, rackSize);
  final board = Board.empty(), totals = List.filled(job.players.length, 0);
  var masterTotal = 0, round = 0, reason = 'stuck';
  while (true) {
    final moves = legalMoves(board, rack, tiles, trie);
    if (moves.isEmpty) {
      reason = 'stuck';
      break;
    }
    round++;
    final master = moves[0], picks = <String>[];
    for (var i = 0; i < job.players.length; i++) {
      final choice = orderedMoves(moves, job.players[i].strategy)[0];
      totals[i] += choice.score;
      picks.add('${choice.score}');
    }
    masterTotal += master.score;
    out.writeln(
      'round $round rack=${notation(rack)} moves=${moves.length} master ${moveName(master)} score=${master.score} picks=${picks.join(',')}',
    );
    play(board, master);
    rack = master.leave + draw(bag, rackSize - master.leave.length);
    if (rack.isEmpty) {
      reason = 'out';
      break;
    }
  }
  out.writeln(
    reason == 'out'
        ? 'end reason=out rounds=$round'
        : 'end reason=stuck rounds=$round rack=${notation(rack)}',
  );
  out.writeln('master total=$masterTotal');
  var best = totals[0];
  for (final value in totals) {
    best = max(best, value);
  }
  final winners = <String>[];
  for (var i = 0; i < job.players.length; i++) {
    final p = job.players[i],
        percentage = masterTotal >= 1 ? 100 * totals[i] ~/ masterTotal : 0;
    out.writeln('final ${p.name} total=${totals[i]} percent=$percentage');
    if (totals[i] == best) winners.add(p.name);
  }
  out.writeln('winner ${winners.join(',')}');
  boardReport(out, board);
  total.rounds += round;
  return out.toString();
}

String paragraph(String s) =>
    s.endsWith('\n') ? s.substring(0, s.length - 1) : s;
void writeParagraphs(String path, List<String> paragraphs) =>
    File(path).writeAsStringSync('${paragraphs.join('\n\n')}\n');
void main() {
  final (tiles, trie, stats, jobs) = readData();
  final dictionary = StringBuffer(
    'DICTIONARY lines=${stats.lines} words=${trie.words} skipped=${stats.skipped} duplicates=${stats.duplicates} nodes=${trie.nodes.length}\n',
  );
  dictionary.writeln(
    [
      'lengths',
      for (var length = 0; length < stats.lengths.length; length++)
        if (stats.lengths[length] > 0) '$length=${stats.lengths[length]}',
    ].join(' '),
  );
  final movesParagraphs = [paragraph(dictionary.toString())],
      validationParagraphs = <String>[],
      gameParagraphs = <String>[],
      topTotals = TopTotals(),
      validationTotals = ValidationTotals(),
      gameTotals = GameTotals(),
      seen = <String>{};
  for (final job in jobs) {
    final kind = job.header[0], name = h[1];
    if (kind == 'TOPN') {
      topTotals.jobs++;
    } else if (kind == 'VALIDATE') {
      validationTotals.jobs++;
    } else if (kind == 'GAME') {
      gameTotals.games++;
    } else {
      gameTotals.duplicates++;
    }
    final reason = checkJob(job, seen, tiles, trie);
    if (reason.isNotEmpty) {
      final error = '$kind $name\nerror $reason';
      if (kind == 'TOPN') {
        topTotals.errors++;
        movesParagraphs.add(error);
      } else if (kind == 'VALIDATE') {
        validationTotals.errors++;
        validationParagraphs.add(error);
      } else {
        gameTotals.errors++;
        gameParagraphs.add(error);
      }
      continue;
    }
    if (kind == 'TOPN') {
      movesParagraphs.add(paragraph(reportTop(job, tiles, trie, topTotals)));
    } else if (kind == 'VALIDATE') {
      validationParagraphs.add(
        paragraph(reportValidation(job, tiles, trie, validationTotals)),
      );
    } else if (kind == 'GAME') {
      gameParagraphs.add(paragraph(reportGame(job, tiles, trie, gameTotals)));
    } else {
      gameParagraphs.add(
        paragraph(reportDuplicate(job, tiles, trie, gameTotals)),
      );
    }
  }
  movesParagraphs.add(
    'SUMMARY jobs=${topTotals.jobs} errors=${topTotals.errors} moves=${topTotals.moves} bingos=${topTotals.bingos}',
  );
  validationParagraphs.add(
    'SUMMARY jobs=${validationTotals.jobs} errors=${validationTotals.errors} moves=${validationTotals.moves} valid=${validationTotals.valid} invalid=${validationTotals.invalid} loss=${validationTotals.loss}',
  );
  gameParagraphs.add(
    'SUMMARY games=${gameTotals.games} duplicates=${gameTotals.duplicates} errors=${gameTotals.errors} turns=${gameTotals.turns} rounds=${gameTotals.rounds} plays=${gameTotals.plays} exchanges=${gameTotals.exchanges} passes=${gameTotals.passes} bingos=${gameTotals.bingos}',
  );
  Directory('output').createSync(recursive: true);
  writeParagraphs('output/moves.txt', movesParagraphs);
  writeParagraphs('output/validation.txt', validationParagraphs);
  writeParagraphs('output/game.txt', gameParagraphs);
}
