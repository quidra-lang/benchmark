import 'dart:io';
import 'dart:math';

const seatLetters = 'NESW';
const suitLetters = 'CDSH';
const rankLetters = '23456789TJQKA';
const twoOfClubs = 0;
const jackOfDiamonds = 22;
const queenOfSpades = 36;
const kingOfSpades = 37;
const aceOfSpades = 38;
const commands = {
  'RULE',
  'BOT',
  'SETTINGS',
  'GAME',
  'MATCH',
  'ROTATE',
  'NEW',
  'ABANDON',
  'STACK',
  'DEAL',
  'SHOW',
  'PASS',
  'PLAY',
  'AUTO',
  'UNDO',
  'CLAIM',
  'LEGAL',
  'PREVIEW',
  'SCORE',
  'TAKEN',
  'TRICKS',
  'VOIDS',
  'UNSEEN',
  'STATS',
  'HISTORY',
  'REPLAY',
};

enum Strategy {
  basic,
  low,
  high,
  smart,
  moon;

  String get label => name.toUpperCase();
}

enum State { none, between, passing, playing }

enum Direction {
  left(1),
  right(3),
  across(2),
  hold(0);

  const Direction(this.offset);

  final int offset;

  String get label => name.toUpperCase();

  static Direction fromCode(String code) =>
      values.firstWhere((direction) => direction.label[0] == code);
}

typedef Play = ({int seat, int card});
typedef LogLine = ({int level, String text});
typedef Snapshot = ({Round round, int logLength, Play play});
typedef HandRecord = ({
  int number,
  Direction direction,
  List<int> points,
  int? shooter,
  List<String> record,
});

class CommandError implements Exception {
  CommandError(this.reason);

  final String reason;
}

Never fail(String reason) => throw CommandError(reason);

String seatName(int seat) => seatLetters[seat];

String cardText(int card) => rankLetters[card % 13] + suitLetters[card ~/ 13];

String cardsText(Iterable<int> cards) =>
    cards.isEmpty ? '-' : (cards.toList()..sort()).map(cardText).join(' ');

int seatValue(String word) {
  if (word.length != 1 || !seatLetters.contains(word)) fail('bad seat $word');
  return seatLetters.indexOf(word);
}

int cardValue(String word) {
  if (word.length != 2 ||
      !rankLetters.contains(word[0]) ||
      !suitLetters.contains(word[1])) {
    fail('bad card $word');
  }
  return suitLetters.indexOf(word[1]) * 13 + rankLetters.indexOf(word[0]);
}

Strategy strategyValue(String word) => Strategy.values.firstWhere(
  (strategy) => strategy.label == word,
  orElse: () => fail('bad value $word'),
);

int bounded(String word, int low, int high) {
  final value = int.tryParse(word);
  if (value == null || value < low || value > high) fail('bad value $word');
  return value;
}

String choice(String word, List<String> allowed) =>
    allowed.contains(word) ? word : fail('bad value $word');

bool switchValue(String word) => choice(word, const ['ON', 'OFF']) == 'ON';

String passValue(String word) =>
    RegExp(r'^[LRAH]{1,8}$').hasMatch(word) ? word : fail('bad value $word');

String onOff(bool on) => on ? 'ON' : 'OFF';

int byRank(int a, int b) =>
    a % 13 != b % 13 ? a % 13 - b % 13 : a ~/ 13 - b ~/ 13;

int byRankDescending(int a, int b) =>
    a % 13 != b % 13 ? b % 13 - a % 13 : a ~/ 13 - b ~/ 13;

int lowest(Iterable<int> cards) =>
    cards.reduce((best, card) => byRank(card, best) < 0 ? card : best);

int highest(Iterable<int> cards) => cards.reduce(
  (best, card) => byRankDescending(card, best) < 0 ? card : best,
);

bool isPenalty(int card) => card == queenOfSpades || card ~/ 13 == 3;

int countSuit(Iterable<int> cards, int suit) =>
    cards.where((card) => card ~/ 13 == suit).length;

String pairs(String label, List<Object> values) => [
  label,
  for (var seat = 0; seat < 4; seat++) '${seatLetters[seat]} ${values[seat]}',
].join(' ');

List<int> ranking(List<int> scores) =>
    [0, 1, 2, 3]
      ..sort((a, b) => scores[a] != scores[b] ? scores[a] - scores[b] : a - b);

void checkDistinct(List<int> cards) {
  final seen = <int>{};
  for (final card in cards) {
    if (!seen.add(card)) fail('duplicate card ${cardText(card)}');
  }
}

String averageText(int total, int games) {
  final numerator = 100 * total;
  final cents = (numerator - numerator % games) ~/ games;
  final sign = cents < 0 ? '-' : '';
  final fraction = (cents.abs() % 100).toString().padLeft(2, '0');
  return '$sign${cents.abs() ~/ 100}.$fraction';
}

int trickWinner(List<Play> plays) {
  final led = plays.first.card ~/ 13;
  return plays
      .where((play) => play.card ~/ 13 == led)
      .reduce((best, play) => play.card % 13 > best.card % 13 ? play : best)
      .seat;
}

String playsText(List<Play> plays) => plays
    .map((play) => '${seatName(play.seat)} ${cardText(play.card)}')
    .join(' ');

class Generator {
  Generator(this.state);

  int state;

  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }

  void shuffle(List<int> deck) {
    for (var i = deck.length - 1; i > 0; i--) {
      final j = draw() % (i + 1);
      final card = deck[i];
      deck[i] = deck[j];
      deck[j] = card;
    }
  }
}

class Rules {
  const Rules({
    this.target = 100,
    this.limit = 100,
    this.moon = 'ADD',
    this.jack = false,
    this.qsBreak = false,
    this.blood = false,
    this.pass = 'LRAH',
  });

  final int target;
  final int limit;
  final String moon;
  final bool jack;
  final bool qsBreak;
  final bool blood;
  final String pass;

  Rules copyWith({
    int? target,
    int? limit,
    String? moon,
    bool? jack,
    bool? qsBreak,
    bool? blood,
    String? pass,
  }) => Rules(
    target: target ?? this.target,
    limit: limit ?? this.limit,
    moon: moon ?? this.moon,
    jack: jack ?? this.jack,
    qsBreak: qsBreak ?? this.qsBreak,
    blood: blood ?? this.blood,
    pass: pass ?? this.pass,
  );

  Rules withRule(String name, String word) => switch (name) {
    'TARGET' => copyWith(target: bounded(word, 1, 1000)),
    'LIMIT' => copyWith(limit: bounded(word, 1, 100)),
    'MOON' => copyWith(moon: choice(word, const ['ADD', 'SUB', 'AUTO'])),
    'JACK' => copyWith(jack: switchValue(word)),
    'QSBREAK' => copyWith(qsBreak: switchValue(word)),
    'BLOOD' => copyWith(blood: switchValue(word)),
    'PASS' => copyWith(pass: passValue(word)),
    _ => fail('unknown rule $name'),
  };

  String get text =>
      'rules TARGET $target LIMIT $limit MOON $moon JACK ${onOff(jack)} '
      'QSBREAK ${onOff(qsBreak)} BLOOD ${onOff(blood)} PASS $pass';
}

class Stats {
  const Stats([
    this.tricks = 0,
    this.hearts = 0,
    this.queens = 0,
    this.moons = 0,
  ]);

  final int tricks;
  final int hearts;
  final int queens;
  final int moons;

  Stats operator +(Stats other) => Stats(
    tricks + other.tricks,
    hearts + other.hearts,
    queens + other.queens,
    moons + other.moons,
  );

  String get text =>
      'tricks $tricks hearts $hearts queens $queens moons $moons';
}

// Everything that UNDO restores when a played card is taken back.
class Round {
  var hands = List.generate(4, (_) => <int>{});
  var taken = List.generate(4, (_) => <int>{});
  var tricks = <List<Play>>[];
  var trickCounts = [0, 0, 0, 0];
  var current = <Play>[];
  var leader = 0;
  var broken = false;
  var record = <String>[];

  Round copy() => Round()
    ..hands = [
      for (final hand in hands) {...hand},
    ]
    ..taken = [
      for (final cards in taken) {...cards},
    ]
    ..tricks = [...tricks]
    ..trickCounts = [...trickCounts]
    ..current = [...current]
    ..leader = leader
    ..broken = broken
    ..record = [...record];
}

class Game {
  Game(this.rules, this.bots, this.generator);

  final Rules rules;
  final List<Strategy> bots;
  final Generator generator;
  var state = State.between;
  var number = 0;
  var direction = Direction.hold;
  var scores = [0, 0, 0, 0];
  var stats = List.filled(4, const Stats());
  final stacked = <int, Set<int>>{};
  final passes = <int, List<int>>{};
  var round = Round();
  final undoStack = <Snapshot>[];
  final history = <HandRecord>[];
  final log = <LogLine>[];

  Game copy() => Game(rules, bots, Generator(generator.state))
    ..state = state
    ..number = number
    ..direction = direction
    ..scores = [...scores]
    ..stats = [...stats]
    ..stacked.addAll(stacked)
    ..passes.addAll(passes)
    ..round = round.copy()
    ..undoStack.addAll(undoStack)
    ..history.addAll(history)
    ..log.addAll(log);

  int point(int card) {
    if (card == queenOfSpades) return 13;
    if (card ~/ 13 == 3) return 1;
    return card == jackOfDiamonds && rules.jack ? -10 : 0;
  }

  int points(Iterable<int> cards) =>
      cards.fold(0, (sum, card) => sum + point(card));

  int trickPoints(List<Play> plays) => points(plays.map((play) => play.card));

  void write(int level, String line) {
    log.add((level: level, text: line));
    if (level > 0) round.record.add(line);
  }

  void deal() {
    number++;
    direction = Direction.fromCode(
      rules.pass[(number - 1) % rules.pass.length],
    );
    round = Round();
    final used = {for (final cards in stacked.values) ...cards};
    final deck = [
      for (var card = 0; card < 52; card++)
        if (!used.contains(card)) card,
    ];
    generator.shuffle(deck);
    final free = [
      for (var seat = 0; seat < 4; seat++)
        if (!stacked.containsKey(seat)) seat,
    ];
    stacked.forEach((seat, cards) => round.hands[seat].addAll(cards));
    for (var i = 0; i < deck.length; i++) {
      round.hands[free[i % free.length]].add(deck[i]);
    }
    stacked.clear();
    passes.clear();
    undoStack.clear();
    write(1, 'hand $number pass ${direction.label}');
    for (var seat = 0; seat < 4; seat++) {
      write(2, '${seatName(seat)}: ${cardsText(round.hands[seat])}');
    }
    if (direction == Direction.hold) {
      beginPlay();
    } else {
      state = State.passing;
    }
  }

  void beginPlay() {
    state = State.playing;
    round.leader = [
      0,
      1,
      2,
      3,
    ].firstWhere((seat) => round.hands[seat].contains(twoOfClubs));
    write(2, 'lead ${seatName(round.leader)}');
  }

  void passCards(int seat, List<int> cards) {
    round.hands[seat].removeAll(cards);
    passes[seat] = cards;
    write(2, '${seatName(seat)} passes ${cardsText(cards)}');
    if (passes.length == 4) {
      passes.forEach(
        (source, passed) =>
            round.hands[(source + direction.offset) % 4].addAll(passed),
      );
      beginPlay();
    }
  }

  int get actor => (round.leader + round.current.length) % 4;

  Set<int> legal() {
    final hand = round.hands[actor];
    if (round.current.isEmpty) {
      if (round.tricks.isEmpty) return {twoOfClubs};
      final nonHearts = hand.where((card) => card ~/ 13 != 3).toSet();
      return !round.broken && nonHearts.isNotEmpty ? nonHearts : {...hand};
    }
    final suit = round.current.first.card ~/ 13;
    final followers = hand.where((card) => card ~/ 13 == suit).toSet();
    if (followers.isNotEmpty) return followers;
    if (round.tricks.isEmpty && !rules.blood) {
      final safe = hand.where((card) => !isPenalty(card)).toSet();
      if (safe.isNotEmpty) return safe;
    }
    return {...hand};
  }

  List<int> choosePass(int seat) {
    final hand = round.hands[seat];
    final low = hand.toList()..sort(byRank);
    final high = hand.toList()..sort(byRankDescending);
    final hearts = high.where((card) => card ~/ 13 == 3);
    final special = [
      queenOfSpades,
      kingOfSpades,
      aceOfSpades,
    ].where(hand.contains);
    final List<int> order;
    switch (bots[seat]) {
      case Strategy.low:
        order = high;
      case Strategy.high:
        order = low;
      case Strategy.moon:
        order = [
          ...low.where((card) => card ~/ 13 != 3),
          ...low.where((card) => card ~/ 13 == 3),
        ];
      case Strategy.smart:
        final isProtected =
            hand.contains(queenOfSpades) && countSuit(hand, 2) >= 5;
        final minorSuits = [0, 1].where((suit) => countSuit(hand, suit) > 0);
        final shortSuit = minorSuits.isEmpty
            ? null
            : minorSuits.reduce(
                (best, suit) =>
                    countSuit(hand, suit) < countSuit(hand, best) ? suit : best,
              );
        order = [
          if (!isProtected) ...special,
          if (shortSuit != null)
            ...high.where((card) => card ~/ 13 == shortSuit),
          ...hearts,
          ...high,
        ];
      case Strategy.basic:
        order = [...special, ...hearts, ...high];
    }
    return order.toSet().take(3).toList();
  }

  bool queenPlayed() =>
      round.taken.any((cards) => cards.contains(queenOfSpades)) ||
      round.current.any((play) => play.card == queenOfSpades);

  bool othersTookPenalty(int seat) => [
    0,
    1,
    2,
    3,
  ].any((other) => other != seat && round.taken[other].any(isPenalty));

  int choosePlay() {
    final seat = actor;
    final hand = round.hands[seat];
    final playable = legal();
    var strategy = bots[seat];
    if (strategy == Strategy.low) return lowest(playable);
    if (strategy == Strategy.high) return highest(playable);
    if (strategy == Strategy.moon && othersTookPenalty(seat)) {
      strategy = Strategy.basic;
    }
    if (round.current.isEmpty) {
      if (strategy == Strategy.smart &&
          !queenPlayed() &&
          !hand.contains(queenOfSpades)) {
        final smallSpades = playable.where(
          (card) => card ~/ 13 == 2 && card % 13 < 10,
        );
        if (smallSpades.isNotEmpty) return lowest(smallSpades);
      }
      final moon = strategy == Strategy.moon;
      final playableSuits = playable.map((card) => card ~/ 13).toSet().toList()
        ..sort();
      final suit = playableSuits.reduce((best, candidate) {
        final difference =
            countSuit(playable, candidate) - countSuit(playable, best);
        return (moon ? difference > 0 : difference < 0) ? candidate : best;
      });
      final suited = playable.where((card) => card ~/ 13 == suit);
      return moon ? highest(suited) : lowest(suited);
    }
    final led = round.current.first.card ~/ 13;
    if (countSuit(hand, led) > 0) {
      final winning = round.current
          .where((play) => play.card ~/ 13 == led)
          .map((play) => play.card % 13)
          .reduce(max);
      if (strategy == Strategy.moon) {
        final high = highest(playable);
        return high % 13 > winning ? high : lowest(playable);
      }
      final lower = playable.where((card) => card % 13 < winning);
      if (lower.isNotEmpty) return highest(lower);
      if (strategy == Strategy.smart && round.current.length == 3) {
        final withoutQueen = playable.difference({queenOfSpades});
        return withoutQueen.isEmpty ? queenOfSpades : highest(withoutQueen);
      }
      return lowest(playable);
    }
    if (strategy == Strategy.moon) {
      final safe = playable.where((card) => !isPenalty(card));
      return lowest(safe.isEmpty ? playable : safe);
    }
    if (playable.contains(queenOfSpades)) return queenOfSpades;
    if (strategy == Strategy.smart && !queenPlayed()) {
      if (playable.contains(aceOfSpades)) return aceOfSpades;
      if (playable.contains(kingOfSpades)) return kingOfSpades;
    }
    final hearts = playable.where((card) => card ~/ 13 == 3);
    return highest(hearts.isEmpty ? playable : hearts);
  }

  String trickLine(List<Play> plays, int number) =>
      'trick $number: ${playsText(plays)} -> '
      '${seatName(trickWinner(plays))} ${trickPoints(plays)}';

  void play(int card) {
    final seat = actor;
    undoStack.add((
      round: round.copy(),
      logLength: log.length,
      play: (seat: seat, card: card),
    ));
    round.hands[seat].remove(card);
    round.current.add((seat: seat, card: card));
    if (card ~/ 13 == 3 || (card == queenOfSpades && rules.qsBreak)) {
      round.broken = true;
    }
    if (round.current.length == 4) {
      final winner = trickWinner(round.current);
      round.taken[winner].addAll(round.current.map((play) => play.card));
      round.trickCounts[winner]++;
      round.tricks.add(round.current);
      write(2, trickLine(round.current, round.tricks.length));
      round.current = [];
      round.leader = winner;
      if (round.tricks.length == 13) finishHand();
    }
  }

  Play undoCard() {
    final snapshot = undoStack.removeLast();
    round = snapshot.round;
    log.removeRange(snapshot.logLength, log.length);
    return snapshot.play;
  }

  void claim(int seat) {
    final remaining = round.hands.expand((hand) => hand).toList();
    for (final hand in round.hands) {
      hand.clear();
    }
    final count = 13 - round.tricks.length;
    round.taken[seat].addAll(remaining);
    round.trickCounts[seat] += count;
    write(
      2,
      'claim ${seatName(seat)} tricks $count points ${points(remaining)}',
    );
    finishHand();
  }

  bool gameOver(List<int> totals) =>
      number >= rules.limit || totals.reduce(max) >= rules.target;

  void finishHand() {
    final handPoints = [for (final cards in round.taken) points(cards)];
    final shooter = [0, 1, 2, 3]
        .where((seat) => round.taken[seat].where(isPenalty).length == 14)
        .firstOrNull;
    if (shooter != null) {
      handPoints[shooter] -= 26;
      var method = rules.moon;
      if (method == 'AUTO') {
        final added = [
          for (var seat = 0; seat < 4; seat++)
            scores[seat] + handPoints[seat] + (seat == shooter ? 0 : 26),
        ];
        method = gameOver(added) && ranking(added).first != shooter
            ? 'SUB'
            : 'ADD';
      }
      if (method == 'SUB') {
        handPoints[shooter] -= 26;
      } else {
        for (var seat = 0; seat < 4; seat++) {
          if (seat != shooter) handPoints[seat] += 26;
        }
      }
      write(1, 'moon ${seatName(shooter)} $method');
    }
    for (var seat = 0; seat < 4; seat++) {
      final cards = round.taken[seat];
      scores[seat] += handPoints[seat];
      stats[seat] += Stats(
        round.trickCounts[seat],
        countSuit(cards, 3),
        cards.contains(queenOfSpades) ? 1 : 0,
        shooter == seat ? 1 : 0,
      );
    }
    write(1, pairs('points', handPoints));
    write(1, pairs('scores', scores));
    history.add((
      number: number,
      direction: direction,
      points: handPoints,
      shooter: shooter,
      record: [...round.record],
    ));
    final over = gameOver(scores);
    state = over ? State.none : State.between;
    if (over) {
      write(0, 'game over hands $number');
      final order = ranking(scores);
      for (var place = 0; place < 4; place++) {
        final seat = order[place];
        write(0, 'rank ${place + 1} ${seatName(seat)} ${scores[seat]}');
      }
      for (final line in statsLines()) {
        write(0, line);
      }
    }
  }

  List<String> statsLines() => [
    for (var seat = 0; seat < 4; seat++)
      'stats ${seatName(seat)} ${stats[seat].text}',
  ];

  void autoPass() {
    for (var seat = 0; seat < 4; seat++) {
      if (!passes.containsKey(seat)) passCards(seat, choosePass(seat));
    }
  }

  void autoHand() {
    if (state == State.passing) autoPass();
    while (state == State.playing) {
      play(choosePlay());
    }
  }

  void autoGame() {
    if (state == State.passing || state == State.playing) autoHand();
    while (state != State.none) {
      deal();
      autoHand();
    }
  }
}

class Table {
  var rules = const Rules();
  final bots = List.filled(4, Strategy.basic);
  Game? game;

  bool get active => (game?.state ?? State.none) != State.none;

  Game requireGame() {
    final game = this.game;
    if (game == null || game.state == State.none) fail('no game');
    return game;
  }

  Game requireHand() {
    final game = this.game;
    if (game == null ||
        (game.state != State.passing && game.state != State.playing)) {
      fail('no hand');
    }
    return game;
  }

  Game requirePlaying() {
    final game = this.game;
    if (game == null || game.state != State.playing) fail('not playing');
    return game;
  }

  Game requirePassing() {
    final game = this.game;
    if (game == null || game.state != State.passing) fail('not passing');
    return game;
  }

  Game requireBetween() {
    final game = requireGame();
    if (game.state != State.between) fail('hand in progress');
    return game;
  }

  List<String> simulate(String command, int seed, int count) {
    final generator = Generator(seed);
    if (command == 'GAME') {
      final game = Game(rules, bots, generator)..autoGame();
      return [
        'game seed $seed',
        for (final line in game.log)
          if (line.level <= count) line.text,
      ];
    }
    final rounds = command == 'ROTATE' ? 4 : 1;
    final places = List.generate(4, (_) => [0, 0, 0, 0]);
    final totals = [0, 0, 0, 0];
    final stats = List.filled(4, const Stats());
    var hands = 0;
    for (var rotation = 0; rotation < rounds; rotation++) {
      final strategies = [
        for (var seat = 0; seat < 4; seat++) bots[(seat - rotation) % 4],
      ];
      for (var i = 0; i < count; i++) {
        final game = Game(rules, strategies, generator)..autoGame();
        hands += game.number;
        final order = ranking(game.scores);
        for (var original = 0; original < 4; original++) {
          final actual = (original + rotation) % 4;
          places[original][order.indexOf(actual)]++;
          totals[original] += game.scores[actual];
          stats[original] += game.stats[actual];
        }
      }
    }
    final games = rounds * count;
    return [
      '${command.toLowerCase()} seed $seed games $games hands $hands',
      for (var seat = 0; seat < 4; seat++)
        '${seatName(seat)}${command == 'ROTATE' ? ' ${bots[seat].label}' : ''} '
            'places ${places[seat].join(' ')} total ${totals[seat]} '
            'average ${averageText(totals[seat], games)} ${stats[seat].text}',
    ];
  }

  List<String> command(List<String> words) {
    final name = words.first;
    final args = words.sublist(1);
    if (!commands.contains(name)) fail('unknown command $name');
    switch (name) {
      case 'RULE':
        final changed = rules.withRule(args[0], args[1]);
        if (active) fail('game in progress');
        rules = changed;
        return ['rule ${args[0]} ${args[1]}'];
      case 'BOT':
        final seat = seatValue(args[0]);
        bots[seat] = strategyValue(args[1]);
        return ['bot ${seatName(seat)} ${args[1]}'];
      case 'SETTINGS':
        return [
          rules.text,
          pairs('bots', [for (final bot in bots) bot.label]),
        ];
      case 'GAME' || 'MATCH' || 'ROTATE':
        final seed = bounded(args[0], 1, 2147483646);
        final count = switch (name) {
          'GAME' => bounded(args[1], 0, 2),
          'MATCH' => bounded(args[1], 1, 50),
          _ => bounded(args[1], 1, 10),
        };
        return simulate(name, seed, count);
      case 'NEW':
        final seed = bounded(args[0], 1, 2147483646);
        if (active) fail('game in progress');
        game = Game(rules, bots, Generator(seed));
        return ['new game seed $seed'];
      case 'ABANDON':
        requireGame();
        game = null;
        return ['game abandoned'];
    }
    return tableCommand(name, args);
  }

  List<String> tableCommand(String name, List<String> args) {
    // Validate argument words before any state-dependent checks or mutation.
    final seat = const {'STACK', 'PASS', 'PLAY', 'CLAIM'}.contains(name)
        ? seatValue(args[0])
        : -1;
    final cards = const {'STACK', 'PASS', 'PLAY'}.contains(name)
        ? args.skip(1).map(cardValue).toList()
        : <int>[];
    if (name == 'STACK' && cards.length != 13) fail('need 13 cards');
    if (name == 'AUTO' &&
        !const {'PASS', 'CARD', 'TRICK', 'HAND', 'GAME'}.contains(args[0])) {
      fail('bad value ${args[0]}');
    }

    final game = switch (name) {
      'STACK' || 'DEAL' => requireBetween(),
      'SHOW' => requireHand(),
      'PASS' => requirePassing(),
      'PLAY' ||
      'UNDO' ||
      'CLAIM' ||
      'LEGAL' ||
      'PREVIEW' ||
      'TAKEN' ||
      'TRICKS' ||
      'VOIDS' ||
      'UNSEEN' => requirePlaying(),
      'AUTO' => switch (args[0]) {
        'PASS' => requirePassing(),
        'CARD' || 'TRICK' => requirePlaying(),
        'HAND' => requireHand(),
        _ => requireGame(),
      },
      _ => requireGame(),
    };
    final round = game.round;
    final before = game.log.length;
    final prefix = <String>[];
    switch (name) {
      case 'STACK':
        checkDistinct(cards);
        for (final card in cards) {
          for (var other = 0; other < 4; other++) {
            if (other != seat &&
                (game.stacked[other]?.contains(card) ?? false)) {
              fail('${cardText(card)} stacked for ${seatName(other)}');
            }
          }
        }
        game.stacked[seat] = cards.toSet();
        return ['stacked ${seatName(seat)}'];
      case 'DEAL':
        game.deal();
      case 'SHOW':
        return [
          for (var other = 0; other < 4; other++)
            '${seatName(other)}: ${cardsText(round.hands[other])}',
        ];
      case 'PASS':
        if (game.passes.containsKey(seat)) {
          fail('${seatName(seat)} already passed');
        }
        checkDistinct(cards);
        for (final card in cards) {
          if (!round.hands[seat].contains(card)) {
            fail('${seatName(seat)} does not hold ${cardText(card)}');
          }
        }
        game.passCards(seat, cards);
      case 'PLAY':
        final card = cards.first;
        if (seat != game.actor) fail('waiting for ${seatName(game.actor)}');
        if (!round.hands[seat].contains(card)) {
          fail('${seatName(seat)} does not hold ${cardText(card)}');
        }
        if (!game.legal().contains(card)) {
          if (round.current.isEmpty) {
            fail(round.tricks.isEmpty ? 'must lead 2C' : 'hearts not broken');
          }
          final led = round.current.first.card ~/ 13;
          if (countSuit(round.hands[seat], led) > 0) {
            fail('must follow ${suitLetters[led]}');
          }
          fail('no points on first trick');
        }
        prefix.add('${seatName(seat)} plays ${cardText(card)}');
        game.play(card);
      case 'AUTO':
        switch (args[0]) {
          case 'PASS':
            game.autoPass();
          case 'CARD':
            final actor = game.actor;
            final card = game.choosePlay();
            prefix.add('${seatName(actor)} plays ${cardText(card)}');
            game.play(card);
          case 'TRICK':
            final count = round.tricks.length;
            while (game.state == State.playing &&
                game.round.tricks.length == count) {
              game.play(game.choosePlay());
            }
          case 'HAND':
            game.autoHand();
          default:
            game.autoGame();
        }
      case 'UNDO':
        if (game.undoStack.isEmpty) fail('nothing to undo');
        final undone = game.undoCard();
        return ['undo ${seatName(undone.seat)} ${cardText(undone.card)}'];
      case 'CLAIM':
        if (seat != game.actor) fail('waiting for ${seatName(game.actor)}');
        if (round.current.isNotEmpty) fail('trick in progress');
        for (final card in round.hands[seat]) {
          for (var other = 0; other < 4; other++) {
            if (other != seat &&
                round.hands[other].any(
                  (held) => held ~/ 13 == card ~/ 13 && held % 13 > card % 13,
                )) {
              fail('claim rejected');
            }
          }
        }
        game.claim(seat);
      case 'LEGAL':
        final bot = cardText(game.choosePlay());
        return [
          'legal ${seatName(game.actor)}: ${cardsText(game.legal())} bot $bot',
        ];
      case 'PREVIEW':
        final output = <String>[];
        for (final card in game.legal().toList()..sort()) {
          final copy = game.copy();
          final count = copy.round.tricks.length;
          copy.play(card);
          while (copy.state == State.playing &&
              copy.round.tricks.length == count) {
            copy.play(copy.choosePlay());
          }
          final trick = copy.round.tricks.last;
          output.add(
            'preview ${cardText(card)} -> ${seatName(trickWinner(trick))} '
            '${copy.trickPoints(trick)}',
          );
        }
        return output;
      case 'SCORE':
        return [
          pairs('scores', game.scores),
          if (game.state == State.playing)
            pairs('taken', [
              for (final cards in round.taken) game.points(cards),
            ]),
        ];
      case 'TAKEN':
        return [
          for (var other = 0; other < 4; other++)
            '${seatName(other)}: '
                '${cardsText(round.taken[other].where((card) => game.point(card) != 0))}',
        ];
      case 'TRICKS':
        final output = [
          for (var i = 0; i < round.tricks.length; i++)
            game.trickLine(round.tricks[i], i + 1),
          if (round.current.isNotEmpty) 'current: ${playsText(round.current)}',
        ];
        return output.isEmpty ? ['no tricks'] : output;
      case 'VOIDS':
        final voids = List.generate(4, (_) => <int>{});
        for (final trick in [
          ...round.tricks,
          if (round.current.isNotEmpty) round.current,
        ]) {
          final led = trick.first.card ~/ 13;
          for (final play in trick) {
            if (play.card ~/ 13 != led) voids[play.seat].add(led);
          }
        }
        final texts = [
          for (final missing in voids)
            missing.isEmpty
                ? '-'
                : (missing.toList()..sort())
                      .map((suit) => suitLetters[suit])
                      .join(),
        ];
        return [pairs('voids', texts)];
      case 'UNSEEN':
        final actor = game.actor;
        final played = {
          for (final cards in round.taken) ...cards,
          for (final play in round.current) play.card,
        };
        final unseen = [
          for (var card = 0; card < 52; card++)
            if (!round.hands[actor].contains(card) && !played.contains(card))
              card,
        ];
        return ['unseen ${seatName(actor)}: ${cardsText(unseen)}'];
      case 'STATS':
        return game.statsLines();
      case 'HISTORY':
        final output = <String>[];
        for (final hand in game.history) {
          final moon = switch (hand.shooter) {
            final shooter? => ' moon ${seatName(shooter)}',
            null => '',
          };
          output.add(
            'hand ${hand.number} pass ${hand.direction.label} '
            '${pairs('points', hand.points)}$moon',
          );
        }
        return output.isEmpty ? ['no hands'] : output;
      case 'REPLAY':
        final hand = bounded(args[0], 1, game.history.length);
        return game.history[hand - 1].record;
    }
    return [...prefix, for (final line in game.log.skip(before)) line.text];
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final table = Table();
  final output = StringBuffer();
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync();
    if (line == null) break;
    try {
      table.command(line.split(' ')).forEach(output.writeln);
    } on CommandError catch (error) {
      output.writeln('error: ${error.reason}');
    }
  }
  stdout.write(output);
}
