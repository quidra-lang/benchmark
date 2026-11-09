import 'dart:io';

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

Never fail(String message) => throw CommandError(message);

int integer(String word, int minimum, int maximum) {
  if (word.isEmpty || word.length > 10 || word.length > 1 && word[0] == '0') {
    fail('bad value $word');
  }
  var value = 0;
  for (final digit in word.codeUnits) {
    if (digit < 48 || digit > 57) fail('bad value $word');
    value = value * 10 + digit - 48;
  }
  if (value < minimum || value > maximum) fail('bad value $word');
  return value;
}

String choice(String word, List<String> values) {
  if (!values.contains(word)) fail('bad value $word');
  return word;
}

String signed(int value) => value >= 0 ? '+$value' : '$value';
String onOff(bool enabled) => enabled ? 'ON' : 'OFF';

enum Phase { idle, insurance, play }
enum Finish { bust, surrender, charlie }
enum Outcome { blackjack, win, charlie, push, lose, bust, surrender }
enum DoubleRule { any, hard9, hard10 }
enum PlayerAction {
  hit('HIT'), stand('STAND'), doubleDown('DOUBLE'), split('SPLIT'), surrender('SURRENDER');
  final String command;
  const PlayerAction(this.command);
  String get text => command.toLowerCase();
}

class Card {
  static const ranks = 'A23456789TJQK';
  static const suits = 'CDHS';
  final int code;
  const Card(this.code);
  int get rank => code % 13;
  int get suit => code ~/ 13;
  int get points => rank >= 9 ? 10 : rank + 1;
  bool get black => suit == 0 || suit == 3;
  @override
  String toString() => '${ranks[rank]}${suits[suit]}';
}

({int value, bool soft}) total(List<Card> cards) {
  var sum = 0;
  var ace = false;
  for (final card in cards) {
    sum += card.points;
    ace = ace || card.rank == 0;
  }
  final soft = ace && sum + 10 <= 21;
  return (value: sum + (soft ? 10 : 0), soft: soft);
}

bool blackjack(List<Card> cards, {bool split = false}) =>
    !split && cards.length == 2 && total(cards).value == 21;

String handText(List<Card> cards, {bool split = false}) {
  final t = total(cards);
  final status = blackjack(cards, split: split) ? 'blackjack'
      : t.value > 21 ? 'bust ${t.value}' : t.soft ? 'soft ${t.value}' : '${t.value}';
  return '${cards.join(' ')} ($status)';
}

class Rules {
  bool hitSoft17 = false;
  int penetration = 75, minimum = 10, maximum = 500;
  bool sixToFive = false, doubleAfterSplit = true;
  DoubleRule doubling = DoubleRule.any;
  int hands = 4;
  bool resplitAces = false, surrender = true;
  int charlie = 0, sideMaximum = 25;

  Rules();
  Rules.from(Rules other) {
    hitSoft17 = other.hitSoft17;
    penetration = other.penetration;
    minimum = other.minimum;
    maximum = other.maximum;
    sixToFive = other.sixToFive;
    doubleAfterSplit = other.doubleAfterSplit;
    doubling = other.doubling;
    hands = other.hands;
    resplitAces = other.resplitAces;
    surrender = other.surrender;
    charlie = other.charlie;
    sideMaximum = other.sideMaximum;
  }

  Rules changed(String name, String word) {
    final next = Rules.from(this);
    switch (name) {
      case 'DEALER': next.hitSoft17 = choice(word, ['S17', 'H17']) == 'H17';
      case 'PEN': next.penetration = integer(word, 50, 90);
      case 'MIN': next.minimum = integer(word, 1, 10000);
      case 'MAX': next.maximum = integer(word, 1, 10000);
      case 'BJ': next.sixToFive = choice(word, ['3:2', '6:5']) == '6:5';
      case 'DAS': next.doubleAfterSplit = choice(word, ['ON', 'OFF']) == 'ON';
      case 'DOUBLE':
        next.doubling = switch (choice(word, ['ANY', '9-11', '10-11'])) {
          'ANY' => DoubleRule.any, '9-11' => DoubleRule.hard9, _ => DoubleRule.hard10,
        };
      case 'HANDS': next.hands = integer(word, 1, 4);
      case 'RSA': next.resplitAces = choice(word, ['ON', 'OFF']) == 'ON';
      case 'SURRENDER': next.surrender = choice(word, ['ON', 'OFF']) == 'ON';
      case 'CHARLIE': next.charlie = int.parse(choice(word, ['0', '5', '6', '7']));
      case 'SIDEMAX': next.sideMaximum = integer(word, 0, 1000);
      default: fail('unknown rule $name');
    }
    return next;
  }

  @override
  String toString() {
    final doubleWord = switch (doubling) {
      DoubleRule.any => 'ANY', DoubleRule.hard9 => '9-11', DoubleRule.hard10 => '10-11',
    };
    return 'rules DEALER ${hitSoft17 ? 'H17' : 'S17'} PEN $penetration MIN $minimum MAX $maximum'
        ' BJ ${sixToFive ? '6:5' : '3:2'} DAS ${onOff(doubleAfterSplit)} DOUBLE $doubleWord'
        ' HANDS $hands RSA ${onOff(resplitAces)} SURRENDER ${onOff(surrender)}'
        ' CHARLIE $charlie SIDEMAX $sideMaximum';
  }
}

class Hand {
  final List<Card> cards;
  int bet;
  final bool split, splitAces;
  bool finished = false;
  Finish? reason;
  Hand(List<Card> cards, this.bet, {this.split = false, this.splitAces = false}) : cards = List.of(cards);
  bool get natural => blackjack(cards, split: split);
  @override
  String toString() => handText(cards, split: split);
}

class Statistics {
  int rounds = 0, hands = 0, wins = 0, losses = 0, pushes = 0;
  int blackjacks = 0, busts = 0, surrenders = 0, doubles = 0, splits = 0;
  @override
  String toString() => 'rounds $rounds hands $hands wins $wins losses $losses pushes $pushes'
      ' blackjacks $blackjacks busts $busts surrenders $surrenders doubles $doubles splits $splits';
}

class Player {
  final String name;
  final int seat;
  int bankroll;
  int bet = 0, side = 0, insurance = 0, net = 0;
  final stats = Statistics();
  final List<Hand> hands = [];
  Player(this.name, this.seat, this.bankroll);
  String handName(int index) => '$name[${index + 1}]';
}

typedef Turn = ({Player player, int index, Hand hand});

class Table {
  static const commands = {
    'SHOE', 'RULE', 'RULES', 'PLAYER', 'LEAVE', 'REBUY', 'BET', 'SIDE', 'DEAL', 'INSURANCE',
    'HIT', 'STAND', 'DOUBLE', 'SPLIT', 'SURRENDER', 'HINT', 'AUTO', 'STATUS', 'COUNT', 'STATS',
  };
  static const actions = {
    'HIT': PlayerAction.hit, 'STAND': PlayerAction.stand, 'DOUBLE': PlayerAction.doubleDown,
    'SPLIT': PlayerAction.split, 'SURRENDER': PlayerAction.surrender,
  };
  Rules rules = Rules();
  final List<Player?> seats = List.filled(7, null);
  List<Player> participants = [];
  Phase phase = Phase.idle;
  int round = 0, dealerBlackjacks = 0, dealerBusts = 0;
  int decks = 0, drawn = 0, running = 0, insuranceTurn = 0, random = 1;
  List<Card> shoe = [];
  final List<Card> dealer = [];
  bool holeRevealed = false;
  final List<String> output = [];

  Iterable<Player> get players => seats.whereType<Player>();
  int get cut => shoe.length * rules.penetration ~/ 100;
  void emit(String line) => output.add(line);
  Player find(String name) {
    for (final player in players) {
      if (player.name == name) return player;
    }
    fail('unknown player $name');
  }

  void shuffle() {
    shoe = List.generate(52 * decks, (i) => Card(i % 52));
    for (var i = shoe.length - 1; i >= 1; i--) {
      random = random * 48271 % 2147483647;
      final j = random % (i + 1);
      final saved = shoe[i];
      shoe[i] = shoe[j];
      shoe[j] = saved;
    }
    drawn = running = 0;
  }

  void countCard(Card card) {
    if (card.points >= 2 && card.points <= 6) {
      running++;
    } else if (card.points == 1 || card.points == 10) {
      running--;
    }
  }

  Card draw({bool faceUp = true}) {
    final card = shoe[drawn++];
    if (faceUp) countCard(card);
    return card;
  }

  void revealDealer() {
    if (!holeRevealed) {
      countCard(dealer[1]);
      holeRevealed = true;
    }
    emit('dealer: ${handText(dealer)}');
  }

  Turn? current() {
    for (final player in participants) {
      for (var i = 0; i < player.hands.length; i++) {
        if (!player.hands[i].finished) return (player: player, index: i, hand: player.hands[i]);
      }
    }
    return null;
  }

  void finishCheck(Player player, Hand hand) {
    final value = total(hand.cards).value;
    if (value > 21) {
      hand.reason = Finish.bust;
      hand.finished = true;
    } else if (rules.charlie != 0 && hand.cards.length == rules.charlie) {
      hand.reason = Finish.charlie;
      hand.finished = true;
    } else if (value == 21) {
      hand.finished = true;
    } else if (hand.splitAces && hand.cards.length == 2) {
      hand.finished = !(hand.cards.every((c) => c.rank == 0) && rules.resplitAces && player.hands.length < rules.hands);
    }
  }

  void settle({bool dealerNatural = false}) {
    final dealerTotal = total(dealer).value;
    for (final player in participants) {
      for (var i = 0; i < player.hands.length; i++) {
        final hand = player.hands[i];
        final value = total(hand.cards).value;
        final result = dealerNatural ? (hand.natural ? Outcome.push : Outcome.lose)
            : hand.natural ? Outcome.blackjack : switch (hand.reason) {
              Finish.bust => Outcome.bust, Finish.surrender => Outcome.surrender, Finish.charlie => Outcome.charlie,
              null => dealerTotal > 21 || value > dealerTotal ? Outcome.win : value == dealerTotal ? Outcome.push : Outcome.lose,
            };
        final profit = switch (result) {
          Outcome.blackjack => rules.sixToFive ? hand.bet * 6 ~/ 5 : hand.bet * 3 ~/ 2,
          Outcome.win || Outcome.charlie => hand.bet,
          Outcome.push => 0,
          Outcome.surrender => hand.bet ~/ 2 - hand.bet,
          Outcome.lose || Outcome.bust => -hand.bet,
        };
        player.bankroll += hand.bet + profit;
        player.net += profit;
        player.stats.hands++;
        if (result == Outcome.blackjack || result == Outcome.win || result == Outcome.charlie) {
          player.stats.wins++;
        } else if (result == Outcome.push) {
          player.stats.pushes++;
        } else {
          player.stats.losses++;
        }
        if (result == Outcome.blackjack) player.stats.blackjacks++;
        if (result == Outcome.bust) player.stats.busts++;
        if (result == Outcome.surrender) player.stats.surrenders++;
        emit('${player.handName(i)} ${result.name} ${signed(profit)}');
      }
      emit('${player.name} bankroll ${player.bankroll}');
    }
    for (final player in players) {
      player.bet = player.side = 0;
    }
    phase = Phase.idle;
  }

  void dealerTurn() {
    revealDealer();
    final mustPlay = participants.any((p) => p.hands.any((h) => h.reason == null && !h.natural));
    var drew = false;
    if (mustPlay) {
      while (true) {
        final t = total(dealer);
        if (!(t.value <= 16 || t.value == 17 && t.soft && rules.hitSoft17)) break;
        dealer.add(draw());
        drew = true;
        emit('dealer hits: ${handText(dealer)}');
      }
    }
    if (drew && total(dealer).value > 21) dealerBusts++;
    settle();
  }

  void advance() {
    while (true) {
      final turn = current();
      if (turn == null) {
        dealerTurn();
        return;
      }
      if (turn.hand.cards.length != 1) return;
      turn.hand.cards.add(draw());
      emit('${turn.player.handName(turn.index)}: ${turn.hand}');
      finishCheck(turn.player, turn.hand);
      if (!turn.hand.finished) return;
    }
  }

  void peek() {
    final natural = blackjack(dealer);
    emit('dealer peeks: ${natural ? 'blackjack' : 'no blackjack'}');
    for (final player in participants.where((p) => p.insurance != 0)) {
      final profit = player.insurance * (natural ? 2 : -1);
      player.bankroll += player.insurance + profit;
      player.net += profit;
      emit('${player.name} insurance ${signed(profit)}');
    }
    if (natural) {
      dealerBlackjacks++;
      revealDealer();
      settle(dealerNatural: true);
    } else {
      phase = Phase.play;
      advance();
    }
  }

  void deal() {
    if (drawn >= cut) {
      shuffle();
      emit('shuffle');
    }
    emit('round ${++round}');
    participants = players.where((p) => p.bet != 0).toList();
    for (final player in participants) {
      player.bankroll -= player.bet + player.side;
      player.insurance = 0;
      player.stats.rounds++;
      player.hands.clear();
      player.hands.add(Hand([draw()], player.bet));
    }
    dealer.clear();
    dealer.add(draw());
    for (final player in participants) {
      final hand = player.hands[0];
      hand.cards.add(draw());
      hand.finished = hand.natural;
    }
    dealer.add(draw(faceUp: false));
    holeRevealed = false;
    for (final player in participants) {
      emit('${player.handName(0)}: ${player.hands[0]}');
    }
    emit('dealer: ${dealer[0]} ??');
    for (final player in participants.where((p) => p.side != 0)) {
      final first = player.hands[0].cards[0], second = player.hands[0].cards[1];
      final (result, multiplier) = first.rank != second.rank ? ('lose', -1)
          : first.suit == second.suit ? ('perfect', 25) : first.black == second.black ? ('colored', 12) : ('mixed', 6);
      final profit = player.side * multiplier;
      player.bankroll += player.side + profit;
      player.net += profit;
      emit('${player.name} side $result ${signed(profit)}');
    }
    if (dealer[0].points == 1) {
      phase = Phase.insurance;
      insuranceTurn = 0;
      emit('insurance offered');
    } else if (dealer[0].points == 10) {
      peek();
    } else {
      phase = Phase.play;
      advance();
    }
  }

  String? actionError(PlayerAction action, Player player, Hand hand) {
    switch (action) {
      case PlayerAction.hit:
        if (hand.splitAces) return 'split aces';
      case PlayerAction.doubleDown:
        if (hand.splitAces) return 'split aces';
        if (hand.cards.length != 2) return 'two cards only';
        final t = total(hand.cards);
        if (rules.doubling != DoubleRule.any && (t.soft || t.value < (rules.doubling == DoubleRule.hard9 ? 9 : 10) || t.value > 11)
            || !rules.doubleAfterSplit && hand.split) return 'double not allowed';
        if (player.bankroll < hand.bet) return 'insufficient funds';
      case PlayerAction.split:
        if (hand.cards.length != 2) return 'two cards only';
        if (hand.cards[0].points != hand.cards[1].points) return 'not a pair';
        if (player.hands.length >= rules.hands) return 'hand limit';
        if (player.bankroll < hand.bet) return 'insufficient funds';
      case PlayerAction.surrender:
        if (!rules.surrender || hand.split) return 'surrender not allowed';
        if (hand.cards.length != 2) return 'two cards only';
      case PlayerAction.stand: break;
    }
    return null;
  }

  void perform(PlayerAction action) {
    final turn = current()!;
    final player = turn.player;
    final hand = turn.hand;
    final name = player.handName(turn.index);
    if (action == PlayerAction.split) {
      final first = hand.cards[0], second = hand.cards[1];
      final aces = hand.splitAces || first.points == 1;
      player.bankroll -= hand.bet;
      player.stats.splits++;
      emit('$name splits $first $second');
      final replacement = Hand([first], hand.bet, split: true, splitAces: aces);
      player.hands[turn.index] = replacement;
      player.hands.insert(turn.index + 1, Hand([second], hand.bet, split: true, splitAces: aces));
      replacement.cards.add(draw());
      emit('$name: $replacement');
      finishCheck(player, replacement);
    } else if (action == PlayerAction.stand || action == PlayerAction.surrender) {
      hand.finished = true;
      if (action == PlayerAction.surrender) hand.reason = Finish.surrender;
      emit('$name ${action == PlayerAction.stand ? 'stands' : 'surrenders'}: $hand');
    } else {
      if (action == PlayerAction.doubleDown) {
        player.bankroll -= hand.bet;
        hand.bet *= 2;
        player.stats.doubles++;
      }
      hand.cards.add(draw());
      emit('$name ${action == PlayerAction.doubleDown ? 'doubles' : 'hits'}: $hand');
      finishCheck(player, hand);
      if (action == PlayerAction.doubleDown) hand.finished = true;
    }
    advance();
  }

  PlayerAction recommend() {
    final turn = current()!;
    final player = turn.player;
    final hand = turn.hand;
    bool possible(PlayerAction action) => actionError(action, player, hand) == null;
    final up = dealer[0].points == 1 ? 11 : dealer[0].points;
    if (hand.splitAces) return possible(PlayerAction.split) ? PlayerAction.split : PlayerAction.stand;
    if (hand.cards.length == 2 && hand.cards[0].points == hand.cards[1].points && possible(PlayerAction.split)) {
      final pair = hand.cards[0].points;
      if (pair == 1 || pair == 8 || pair == 9 && ![7, 10, 11].contains(up)
          || [2, 3, 7].contains(pair) && up <= 7 || pair == 6 && up <= 6 || pair == 4 && (up == 5 || up == 6)) {
        return PlayerAction.split;
      }
    }
    final t = total(hand.cards);
    var symbol = 'H';
    if (t.soft) {
      if (t.value >= 19) {
        symbol = 'S';
      } else if (t.value == 18) {
        symbol = up >= 3 && up <= 6 ? 'Ds' : [2, 7, 8].contains(up) ? 'S' : 'H';
      } else if (t.value == 17 && up >= 3 && up <= 6 || [15, 16].contains(t.value) && up >= 4 && up <= 6
          || [13, 14].contains(t.value) && (up == 5 || up == 6)) {
        symbol = 'D';
      }
    } else {
      if (t.value >= 17) {
        symbol = 'S';
      } else if (t.value >= 13) {
        symbol = up <= 6 ? 'S' : t.value == 16 && up >= 9 || t.value == 15 && up == 10 ? 'R' : 'H';
      } else if (t.value == 12) {
        symbol = up >= 4 && up <= 6 ? 'S' : 'H';
      } else if (t.value == 11 && up <= 10 || t.value == 10 && up <= 9 || t.value == 9 && up >= 3 && up <= 6) {
        symbol = 'D';
      }
    }
    return switch (symbol) {
      'S' => PlayerAction.stand,
      'D' => possible(PlayerAction.doubleDown) ? PlayerAction.doubleDown : PlayerAction.hit,
      'Ds' => possible(PlayerAction.doubleDown) ? PlayerAction.doubleDown : PlayerAction.stand,
      'R' => possible(PlayerAction.surrender) ? PlayerAction.surrender : PlayerAction.hit,
      _ => PlayerAction.hit,
    };
  }

  void status() {
    var line = 'table ${phase.name} round $round';
    if (phase == Phase.insurance) {
      line += ' next ${participants[insuranceTurn].name}';
    } else if (phase == Phase.play) {
      final turn = current()!;
      line += ' turn ${turn.player.handName(turn.index)}';
    }
    emit(line);
    if (phase != Phase.idle) emit('dealer: ${dealer[0]} ??');
    for (final player in players) {
      emit('seat ${player.seat} ${player.name} bankroll ${player.bankroll} bet ${player.bet} side ${player.side}');
      if (phase != Phase.idle && participants.contains(player)) {
        for (var i = 0; i < player.hands.length; i++) {
          emit('${player.handName(i)}: ${player.hands[i]} bet ${player.hands[i].bet}');
        }
      }
    }
  }

  List<String> execute(List<String> words) {
    output.clear();
    final command = words[0];
    if (!commands.contains(command)) fail('unknown command $command');
    final first = words.length > 1 ? words[1] : '', second = words.length > 2 ? words[2] : '';
    final action = actions[command];
    Player? target;
    var amount = 0, seed = 0;
    Rules? proposed;

    if (command == 'SHOE') {
      amount = integer(first, 1, 8);
      seed = integer(second, 1, 2147483646);
    } else if (command == 'RULE') {
      proposed = rules.changed(first, second);
    } else if (command == 'PLAYER') {
      if (first.isEmpty || first.length > 8 || first.codeUnits.any((c) => c < 65 || c > 90)) fail('bad name $first');
      amount = integer(second, 1, 1000000);
    } else if (action != null || ['LEAVE', 'REBUY', 'BET', 'SIDE', 'INSURANCE', 'AUTO'].contains(command)) {
      target = find(first);
      if (['REBUY', 'BET', 'SIDE', 'INSURANCE'].contains(command)) {
        amount = integer(second, command == 'REBUY' ? 1 : 0, 1000000);
      }
    }
    if (['SHOE', 'RULE', 'PLAYER', 'LEAVE', 'REBUY', 'BET', 'SIDE', 'DEAL'].contains(command)) {
      if (phase != Phase.idle) fail('round in progress');
    } else if (command == 'INSURANCE') {
      if (phase != Phase.insurance) fail('no insurance');
    } else if (action != null || command == 'AUTO' || command == 'HINT') {
      if (phase == Phase.idle) fail('no round');
      if (phase == Phase.insurance) fail('insurance pending');
    }
    if (action != null || command == 'AUTO') {
      final turn = current()!;
      if (turn.player != target) fail('waiting for ${turn.player.handName(turn.index)}');
      if (action != null) {
        final error = actionError(action, turn.player, turn.hand);
        if (error != null) fail(error);
        perform(action);
      } else {
        while (phase == Phase.play && current()!.player == target) {
          perform(recommend());
        }
      }
      return output;
    }
    switch (command) {
      case 'SHOE':
        decks = amount;
        random = seed;
        shuffle();
        emit('shoe $decks decks ${shoe.length} cards cut $cut');
      case 'RULE':
        final next = proposed!;
        if (next.minimum > next.maximum) fail('min above max');
        rules = next;
        emit('rule $first $second');
      case 'RULES': emit('$rules');
      case 'PLAYER':
        if (players.any((p) => p.name == first)) fail('player exists');
        final seat = seats.indexWhere((p) => p == null);
        if (seat < 0) fail('table full');
        seats[seat] = Player(first, seat + 1, amount);
        emit('$first sits at seat ${seat + 1} with $amount');
      case 'LEAVE':
        final player = target!;
        emit('${player.name} leaves with ${player.bankroll} net ${signed(player.net)}');
        seats[player.seat - 1] = null;
      case 'REBUY':
        final player = target!;
        player.bankroll += amount;
        emit('${player.name} rebuys $amount bankroll ${player.bankroll}');
      case 'BET':
        final player = target!;
        if (amount != 0) {
          if (amount < rules.minimum || amount > rules.maximum) fail('bet out of limits');
          if (amount + player.side > player.bankroll) fail('insufficient funds');
        }
        player.bet = amount;
        if (amount == 0) player.side = 0;
        emit(amount == 0 ? '${player.name} bet cleared' : '${player.name} bets $amount');
      case 'SIDE':
        final player = target!;
        if (amount != 0) {
          if (player.bet == 0) fail('no bet');
          if (amount > rules.sideMaximum) fail('side out of limits');
          if (player.bet + amount > player.bankroll) fail('insufficient funds');
        }
        player.side = amount;
        emit(amount == 0 ? '${player.name} side cleared' : '${player.name} side $amount');
      case 'DEAL':
        if (decks == 0) fail('no shoe');
        if (!players.any((p) => p.bet != 0)) fail('no bets');
        deal();
      case 'INSURANCE':
        final player = target!;
        if (participants[insuranceTurn] != player) fail('waiting for ${participants[insuranceTurn].name}');
        if (amount > player.bet ~/ 2) fail('insurance out of limits');
        if (amount > player.bankroll) fail('insufficient funds');
        player.bankroll -= amount;
        player.insurance = amount;
        emit(amount == 0 ? '${player.name} declines insurance' : '${player.name} insures $amount');
        if (++insuranceTurn == participants.length) peek();
      case 'HINT':
        final turn = current()!;
        emit('hint ${turn.player.handName(turn.index)}: ${recommend().text}');
      case 'STATUS': status();
      case 'COUNT':
        if (decks == 0) fail('no shoe');
        final remaining = shoe.length - drawn;
        final hundredths = running.abs() * 5200 ~/ remaining;
        final count = '${running < 0 ? '-' : ''}${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}';
        emit('count running $running true $count remaining $remaining');
      case 'STATS':
        if (players.isEmpty) fail('no players');
        for (final player in players) {
          emit('stats ${player.name} ${player.stats} net ${signed(player.net)}');
        }
        emit('stats dealer rounds $round blackjacks $dealerBlackjacks busts $dealerBusts');
    }
    return output;
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final table = Table();
  for (var i = 0; i < count; i++) {
    final words = stdin.readLineSync()!.split(' ');
    try {
      for (final line in table.execute(words)) { stdout.writeln(line); }
    } on CommandError catch (error) {
      stdout.writeln('error: ${error.message}');
    }
  }
}
