import 'dart:io';

const files = 'abcdefgh',
    ranks = '12345678',
    initial = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const rook = [(0, 1), (0, -1), (-1, 0), (1, 0)],
    bishop = [(1, 1), (-1, 1), (1, -1), (-1, -1)];
const king = [...rook, ...bishop],
    knight = [
      (1, 2),
      (2, 1),
      (2, -1),
      (1, -2),
      (-1, -2),
      (-2, -1),
      (-2, 1),
      (-1, 2),
    ];

class InputError implements Exception {
  final String reason;
  const InputError(this.reason);
}

Never fail(String reason) => throw InputError(reason);
void emit(String s) => stdout.writeln(s);
String opposite(String c) => c == 'w' ? 'b' : 'w';
String color(String p) => p == p.toUpperCase() ? 'w' : 'b';
String colored(String p, String c) => c == 'w' ? p : p.toLowerCase();
int step(String c) => c == 'w' ? 8 : -8;
int square(String s) => RegExp(r'^[a-h][1-8]$').hasMatch(s)
    ? files.indexOf(s[0]) + 8 * ranks.indexOf(s[1])
    : -1;
String name(int s) => files[s % 8] + ranks[s ~/ 8];
int number(String s, int lo, int hi) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,8})$').hasMatch(s)) return -1;
  final n = int.parse(s);
  return n >= lo && n <= hi ? n : -1;
}

int shift(int s, int dx, int dy) {
  final x = s % 8 + dx, y = s ~/ 8 + dy;
  return x >= 0 && x < 8 && y >= 0 && y < 8 ? 8 * y + x : -1;
}

class Rule {
  final int king, rook, target, rookTarget;
  final List<int> path;
  const Rule(this.king, this.rook, this.target, this.rookTarget, this.path);
}

const rules = {
  'K': Rule(4, 7, 6, 5, [5, 6]),
  'Q': Rule(4, 0, 2, 3, [1, 2, 3]),
  'k': Rule(60, 63, 62, 61, [61, 62]),
  'q': Rule(60, 56, 58, 59, [57, 58, 59]),
};

class Move {
  final int source, target;
  final String promotion;
  const Move(this.source, this.target, [this.promotion = '']);
}

class MoveRecord {
  final String san, uci, captured;
  const MoveRecord(this.san, this.uci, this.captured);
}

List<int> targets(List<String> b, int s) {
  final p = b[s], kind = p.toUpperCase();
  final result = <int>[];
  if ('PNK'.contains(kind)) {
    final directions = kind == 'P'
        ? [(-1, color(p) == 'w' ? 1 : -1), (1, color(p) == 'w' ? 1 : -1)]
        : kind == 'N'
        ? knight
        : king;
    for (final (dx, dy) in directions) {
      final t = shift(s, dx, dy);
      if (t >= 0) result.add(t);
    }
  } else {
    final directions = kind == 'Q'
        ? king
        : kind == 'R'
        ? rook
        : bishop;
    for (final (dx, dy) in directions)
      for (var t = shift(s, dx, dy); t >= 0; t = shift(t, dx, dy)) {
        result.add(t);
        if (b[t] != '.') break;
      }
  }
  return result;
}

List<int> attackers(List<String> b, int t, String c) => [
  for (var s = 0; s < 64; s++)
    if (b[s] != '.' && color(b[s]) == c && targets(b, s).contains(t)) s,
];

class Position {
  final List<String> board;
  final String side, rights;
  final int ep, half, full;
  List<Move>? _cached;
  Position(this.board, this.side, this.rights, this.ep, this.half, this.full);
  bool check([String? c]) {
    c ??= side;
    return attackers(
      board,
      board.indexOf(colored('K', c)),
      opposite(c),
    ).isNotEmpty;
  }

  bool castle(Move m) =>
      board[m.source].toUpperCase() == 'K' && (m.target - m.source).abs() == 2;
  bool enpassant(Move m) =>
      board[m.source].toUpperCase() == 'P' &&
      m.source % 8 != m.target % 8 &&
      board[m.target] == '.';
  bool capture(Move m) => board[m.target] != '.' || enpassant(m);
  String captured(Move m) => board[m.target] != '.'
      ? board[m.target].toLowerCase()
      : enpassant(m)
      ? 'p'
      : '-';
  Position play(Move m) {
    final b = [...board], piece = board[m.source], kind = piece.toUpperCase();
    if (enpassant(m)) b[m.target - step(side)] = '.';
    if (castle(m)) {
      final r = rules[colored(m.target > m.source ? 'K' : 'Q', side)]!;
      b[r.rookTarget] = b[r.rook];
      b[r.rook] = '.';
    }
    b[m.target] = m.promotion.isEmpty ? piece : colored(m.promotion, side);
    b[m.source] = '.';
    final nextRights = rights
        .split('')
        .where(
          (r) =>
              (kind != 'K' || color(r) != side) &&
              rules[r]!.rook != m.source &&
              rules[r]!.rook != m.target,
        )
        .join();
    return Position(
      b,
      opposite(side),
      nextRights,
      kind == 'P' && (m.target - m.source).abs() == 16
          ? (m.source + m.target) ~/ 2
          : -1,
      kind == 'P' || capture(m) ? 0 : half + 1,
      full + (side == 'b' ? 1 : 0),
    );
  }

  List<Move> pseudo() {
    final result = <Move>[];
    for (var s = 0; s < 64; s++) {
      final piece = board[s];
      if (piece == '.' || color(piece) != side) continue;
      final pawn = piece.toUpperCase() == 'P';
      final a = <int>[];
      if (pawn) {
        final d = step(side);
        if (board[s + d] == '.') {
          a.add(s + d);
          if (s ~/ 8 == (side == 'w' ? 1 : 6) && board[s + 2 * d] == '.')
            a.add(s + 2 * d);
        }
        a.addAll(
          targets(board, s).where(
            (t) => (board[t] != '.' && color(board[t]) != side) || t == ep,
          ),
        );
      } else
        a.addAll(
          targets(
            board,
            s,
          ).where((t) => board[t] == '.' || color(board[t]) != side),
        );
      for (final t in a)
        for (final p
            in pawn && t ~/ 8 == (side == 'w' ? 7 : 0)
                ? 'QRBN'.split('')
                : [''])
          result.add(Move(s, t, p));
    }
    return result;
  }

  Move castlingMove(bool kingside) {
    final r = rules[colored(kingside ? 'K' : 'Q', side)]!;
    return Move(r.king, r.target);
  }

  String castlingProblem(bool kingside) {
    final right = colored(kingside ? 'K' : 'Q', side),
        r = rules[colored(kingside ? 'K' : 'Q', side)]!;
    if (!rights.contains(right)) return 'no castling right';
    if (r.path.any((s) => board[s] != '.')) return 'path blocked';
    if (check()) return 'in check';
    if (attackers(board, r.rookTarget, opposite(side)).isNotEmpty)
      return 'through check';
    if (play(castlingMove(kingside)).check(side)) return 'into check';
    return '';
  }

  List<Move> legal() {
    if (_cached != null) return _cached!;
    final a = pseudo().where((m) => !play(m).check(side)).toList();
    for (final k in [true, false])
      if (castlingProblem(k).isEmpty) a.add(castlingMove(k));
    return _cached = a;
  }

  String mark(Move m) {
    final q = play(m);
    return q.check() ? (q.legal().isEmpty ? '#' : '+') : '';
  }

  String disambiguation(Move m) {
    final a = legal()
        .where(
          (x) =>
              !castle(x) &&
              x.target == m.target &&
              x.source != m.source &&
              board[x.source] == board[m.source],
        )
        .toList();
    if (a.isEmpty) return '';
    if (a.every((x) => x.source % 8 != m.source % 8))
      return files[m.source % 8];
    if (a.every((x) => x.source ~/ 8 != m.source ~/ 8))
      return ranks[m.source ~/ 8];
    return name(m.source);
  }

  String san(Move m) {
    final kind = board[m.source].toUpperCase();
    String text;
    if (castle(m))
      text = m.target > m.source ? 'O-O' : 'O-O-O';
    else if (kind == 'P')
      text =
          (capture(m) ? '${files[m.source % 8]}x' : '') +
          name(m.target) +
          (m.promotion.isEmpty ? '' : '=${m.promotion}');
    else
      text =
          kind + disambiguation(m) + (capture(m) ? 'x' : '') + name(m.target);
    return text + mark(m);
  }

  String key() =>
      board.join() +
      ' $side $rights ' +
      (ep >= 0 && legal().any(enpassant) ? ep : -1).toString();
  String state() => check()
      ? (legal().isEmpty ? 'checkmate' : 'check')
      : (legal().isEmpty ? 'stalemate' : 'normal');
  bool insufficient() {
    final a = [
      for (var s = 0; s < 64; s++)
        if (board[s] != '.' && board[s].toUpperCase() != 'K') s,
    ];
    if (a.any((s) => 'PRQ'.contains(board[s].toUpperCase()))) return false;
    return a.length <= 1 ||
        a.every((s) => board[s].toUpperCase() == 'B') &&
            a.map((s) => (s % 8 + s ~/ 8) % 2).toSet().length == 1;
  }

  List<(int, int)> pins() {
    final k = board.indexOf(colored('K', side)), found = <(int, int)>[];
    for (final (dx, dy) in king) {
      var first = -1;
      for (var t = shift(k, dx, dy); t >= 0; t = shift(t, dx, dy)) {
        final p = board[t];
        if (p == '.') continue;
        if (first < 0) {
          if (color(p) != side) break;
          first = t;
        } else {
          if (color(p) != side &&
              ('Q' + (dx == 0 || dy == 0 ? 'R' : 'B')).contains(
                p.toUpperCase(),
              ))
            found.add((first, t));
          break;
        }
      }
    }
    found.sort((x, y) => x.$1.compareTo(y.$1));
    return found;
  }

  String fen() {
    final rows = <String>[];
    for (var r = 7; r >= 0; r--) {
      final row = StringBuffer();
      var empty = 0;
      for (var f = 0; f < 8; f++) {
        final p = board[r * 8 + f];
        if (p == '.')
          empty++;
        else {
          if (empty > 0) row.write(empty);
          empty = 0;
          row.write(p);
        }
      }
      if (empty > 0) row.write(empty);
      rows.add(row.toString());
    }
    return '${rows.join('/')} $side ${rights.isEmpty ? '-' : rights} ${ep < 0 ? '-' : name(ep)} $half $full';
  }
}

Position parseFen(List<String> a) {
  if (a.length != 6) fail('fields');
  final rows = a[0].split('/');
  if (rows.length != 8) fail('placement');
  final b = List.filled(64, '.');
  for (var i = 0; i < 8; i++) {
    var f = 0, digit = false;
    for (final c in rows[i].split('')) {
      if ('12345678'.contains(c)) {
        if (digit) fail('placement');
        f += int.parse(c);
        digit = true;
      } else {
        if (!'KQRBNPkqrbnp'.contains(c) || f >= 8) fail('placement');
        b[(7 - i) * 8 + f++] = c;
        digit = false;
      }
    }
    if (f != 8) fail('placement');
  }
  if (b.where((p) => p == 'K').length != 1 ||
      b.where((p) => p == 'k').length != 1)
    fail('kings');
  if ([...b.take(8), ...b.skip(56)].any((p) => p == 'P' || p == 'p'))
    fail('pawns');
  final side = a[1];
  if (side != 'w' && side != 'b') fail('side');
  if (a[2] != '-' && (a[2].isEmpty || !RegExp(r'^K?Q?k?q?$').hasMatch(a[2])))
    fail('castling');
  final rights = a[2] == '-' ? '' : a[2];
  for (final r in rights.split(''))
    if (b[rules[r]!.king] != colored('K', color(r)) ||
        b[rules[r]!.rook] != colored('R', color(r)))
      fail('castling');
  var ep = -1;
  if (a[3] != '-') {
    ep = square(a[3]);
    final d = step(side);
    if (ep < 0 ||
        ep ~/ 8 != (side == 'w' ? 5 : 2) ||
        b[ep] != '.' ||
        b[ep + d] != '.' ||
        b[ep - d] != colored('P', opposite(side)))
      fail('en passant');
  }
  final half = number(a[4], 0, 999), full = number(a[5], 1, 999);
  if (half < 0 || full < 0 || (ep >= 0 && half != 0)) fail('clocks');
  final p = Position(b, side, rights, ep, half, full);
  if (p.check(opposite(side))) fail('check');
  return p;
}

Move readSan(Position p, String text) {
  final mark = text.endsWith('+') || text.endsWith('#')
      ? text[text.length - 1]
      : '';
  var body = mark.isEmpty ? text : text.substring(0, text.length - 1);
  final castling = body == 'O-O' || body == 'O-O-O';
  var promotion = '',
      target = -1,
      capture = false,
      kind = 'P',
      file = '',
      rank = '';
  if (!castling) {
    if (body.length >= 2 && body[body.length - 2] == '=') {
      promotion = body[body.length - 1];
      if (!'QRBN'.contains(promotion)) fail('syntax');
      body = body.substring(0, body.length - 2);
    }
    if (body.length < 2) fail('syntax');
    target = square(body.substring(body.length - 2));
    if (target < 0) fail('syntax');
    body = body.substring(0, body.length - 2);
    capture = body.endsWith('x');
    if (capture) body = body.substring(0, body.length - 1);
    if (body.isNotEmpty && 'KQRBN'.contains(body[0])) {
      kind = body[0];
      final h = RegExp(r'^([a-h]?)([1-8]?)$').firstMatch(body.substring(1));
      if (h == null || promotion.isNotEmpty) fail('syntax');
      file = h.group(1)!;
      rank = h.group(2)!;
    } else {
      if (!RegExp(capture ? r'^[a-h]$' : r'^$').hasMatch(body)) fail('syntax');
      file = body;
    }
  }
  final legal = p.legal();
  if (legal.isEmpty) fail('game over');
  Move move;
  if (castling) {
    final k = body == 'O-O', problem = p.castlingProblem(body == 'O-O');
    if (problem.isNotEmpty) fail(problem);
    move = p.castlingMove(k);
  } else {
    bool matches(Move m) =>
        p.board[m.source].toUpperCase() == kind &&
        m.target == target &&
        !p.castle(m) &&
        (file.isEmpty || files[m.source % 8] == file) &&
        (rank.isEmpty || ranks[m.source ~/ 8] == rank) &&
        (kind != 'P' || (m.source % 8 != m.target % 8) == capture);
    final candidates = legal.where(matches).toList();
    if (candidates.isEmpty)
      fail(p.pseudo().any(matches) ? 'leaves king in check' : 'no such move');
    if (candidates.map((m) => m.source).toSet().length > 1) fail('ambiguous');
    move = candidates[0];
    if (p.capture(move) != capture) fail('capture mark');
    if (move.promotion.isNotEmpty && promotion.isEmpty)
      fail('missing promotion');
    if (promotion.isNotEmpty && move.promotion.isEmpty)
      fail('invalid promotion');
    if (kind != 'P' && file + rank != p.disambiguation(move))
      fail('disambiguation');
    move = Move(move.source, move.target, promotion);
  }
  if (p.mark(move) != mark) fail('check mark');
  return move;
}

Move readUci(Position p, String text) {
  if (!RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(text)) fail('syntax');
  final s = square(text.substring(0, 2)),
      t = square(text.substring(2, 4)),
      promotion = text.substring(4).toUpperCase(),
      legal = p.legal();
  if (legal.isEmpty) fail('game over');
  if (p.board[s] == '.' || color(p.board[s]) != p.side) fail('no piece');
  final candidates = legal
      .where((m) => m.source == s && m.target == t)
      .toList();
  if (candidates.isEmpty)
    fail(
      p.pseudo().any((m) => m.source == s && m.target == t)
          ? 'leaves king in check'
          : 'no such move',
    );
  if (candidates[0].promotion.isNotEmpty && promotion.isEmpty)
    fail('missing promotion');
  if (promotion.isNotEmpty && candidates[0].promotion.isEmpty)
    fail('invalid promotion');
  return Move(s, t, promotion);
}

int perft(Position p, int d, [List<int>? stats]) {
  if (d == 0) return 1;
  var total = 0;
  for (final m in p.legal()) {
    final q = p.play(m);
    total += perft(q, d - 1, stats);
    if (d == 1 && stats != null) {
      stats[0]++;
      if (p.capture(m)) stats[1]++;
      if (p.enpassant(m)) stats[2]++;
      if (p.castle(m)) stats[3]++;
      if (m.promotion.isNotEmpty) stats[4]++;
      if (q.check()) {
        stats[5]++;
        if (q.legal().isEmpty) stats[6]++;
      }
    }
  }
  return total;
}

class Game {
  final List<Position> positions;
  final records = <MoveRecord>[];
  final bool loaded;
  Game([Position? start, this.loaded = false])
    : positions = [start ?? parseFen(initial.split(' '))];
  Position get current => positions.last;
  void play(Move m) {
    final p = current;
    records.add(
      MoveRecord(
        p.san(m),
        name(m.source) + name(m.target) + m.promotion.toLowerCase(),
        p.captured(m),
      ),
    );
    positions.add(p.play(m));
  }

  int repetition() {
    final key = current.key();
    return positions.where((p) => p.key() == key).length;
  }

  List<String> draws() => [
    if (current.half >= 100) 'fifty',
    if (repetition() >= 3) 'threefold',
    if (current.insufficient()) 'insufficient',
  ];
  String result() {
    final s = current.state();
    return s == 'checkmate'
        ? (current.side == 'b' ? '1-0' : '0-1')
        : s == 'stalemate' || draws().isNotEmpty
        ? '1/2-1/2'
        : '*';
  }
}

class Session {
  var game = Game();
  void execute(String line) {
    final w = line.split(' '), cmd = w[0], a = w.sublist(1);
    if (!'NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN'
        .split(' ')
        .contains(cmd)) {
      emit('ERROR unknown command');
      return;
    }
    var bad =
        [
          'NEW',
          'FEN',
          'BOARD',
          'STATUS',
          'PINS',
          'HISTORY',
          'PGN',
        ].contains(cmd) &&
        a.isNotEmpty;
    if (cmd == 'MOVE' || cmd == 'UCI') bad = a.isEmpty;
    if (cmd == 'LEGAL') bad = a.length > 1 || a.length == 1 && square(a[0]) < 0;
    if (cmd == 'ATTACKS')
      bad = a.length != 1 || a.length == 1 && square(a[0]) < 0;
    var n = -1;
    if (['UNDO', 'PERFT', 'DIVIDE'].contains(cmd)) {
      n = a.length == 1 ? number(a[0], 1, cmd == 'UNDO' ? 9999 : 3) : -1;
      bad = n < 0;
    }
    if (bad) {
      emit('ERROR bad arguments');
      return;
    }
    final p = game.current;
    if (cmd == 'NEW') {
      game = Game();
      emit('OK');
    } else if (cmd == 'LOAD') {
      try {
        final q = parseFen(a);
        game = Game(q, true);
        emit('OK');
      } on InputError catch (e) {
        emit('ERROR bad fen (${e.reason})');
      }
    } else if (cmd == 'FEN')
      emit(p.fen());
    else if (cmd == 'BOARD') {
      for (var r = 7; r >= 0; r--)
        emit([r + 1, ...p.board.sublist(8 * r, 8 * r + 8)].join(' '));
      emit('  a b c d e f g h');
    } else if (cmd == 'MOVE' || cmd == 'UCI') {
      final played = <String>[];
      var failure = '';
      for (var i = 0; i < a.length; i++) {
        try {
          final m = cmd == 'MOVE'
              ? readSan(game.current, a[i])
              : readUci(game.current, a[i]);
          game.play(m);
          played.add(game.records.last.san);
        } on InputError catch (e) {
          failure = 'ILLEGAL move ${i + 1}: ${a[i]} (${e.reason})';
          break;
        }
      }
      if (cmd == 'UCI' && played.isNotEmpty) emit('san ${played.join(' ')}');
      if (failure.isNotEmpty)
        emit(failure);
      else if (cmd == 'MOVE')
        emit('OK');
    } else if (cmd == 'LEGAL') {
      final list =
          p
              .legal()
              .where((m) => a.isEmpty || m.source == square(a[0]))
              .map(p.san)
              .toList()
            ..sort();
      emit(['legal', list.length, ...list].join(' '));
    } else if (cmd == 'STATUS')
      emit(
        [
          'status',
          p.side == 'w' ? 'white' : 'black',
          p.state(),
          'rep',
          game.repetition(),
          ...game.draws(),
        ].join(' '),
      );
    else if (cmd == 'UNDO') {
      if (n > game.records.length)
        emit('ERROR cannot undo');
      else {
        game.records.removeRange(game.records.length - n, game.records.length);
        game.positions.removeRange(
          game.positions.length - n,
          game.positions.length,
        );
        emit('OK');
      }
    } else if (cmd == 'PERFT') {
      final stats = List.filled(7, 0);
      perft(p, n, stats);
      const fields = [
        'nodes',
        'captures',
        'ep',
        'castles',
        'promotions',
        'checks',
        'mates',
      ];
      emit(
        [
          'perft',
          n,
          for (var i = 0; i < 7; i++) ...[fields[i], stats[i]],
        ].join(' '),
      );
    } else if (cmd == 'DIVIDE') {
      final rows =
          p.legal().map((m) => (p.san(m), perft(p.play(m), n - 1))).toList()
            ..sort((x, y) => x.$1.compareTo(y.$1));
      var total = 0;
      for (final (san, count) in rows) {
        emit('$san $count');
        total += count;
      }
      emit('total $total');
    } else if (cmd == 'ATTACKS') {
      final row = <Object>['attacks', a[0]];
      for (final c in ['w', 'b']) {
        final found = attackers(p.board, square(a[0]), c);
        row.addAll([
          c == 'w' ? 'white' : 'black',
          found.length,
          ...found.map(name),
        ]);
      }
      emit(row.join(' '));
    } else if (cmd == 'PINS') {
      final pins = p.pins();
      emit(
        [
          'pins',
          pins.length,
          ...pins.map((pair) => '${name(pair.$1)}-${name(pair.$2)}'),
        ].join(' '),
      );
    } else if (cmd == 'HISTORY') {
      emit('history ${game.records.length}');
      for (var i = 0; i < game.records.length; i++) {
        final r = game.records[i];
        emit('${i + 1} ${r.uci} ${r.san} ${r.captured}');
      }
    } else if (cmd == 'PGN') {
      final result = game.result();
      emit('[Result "$result"]');
      if (game.loaded) {
        emit('[SetUp "1"]');
        emit('[FEN "${game.positions[0].fen()}"]');
      }
      final row = <String>[];
      for (var i = 0; i < game.records.length; i++) {
        final q = game.positions[i];
        if (q.side == 'w')
          row.add('${q.full}.');
        else if (i == 0)
          row.add('${q.full}...');
        row.add(game.records[i].san);
      }
      row.add(result);
      emit(row.join(' '));
    }
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final session = Session();
  for (var i = 0; i < count; i++) session.execute(stdin.readLineSync()!);
}
