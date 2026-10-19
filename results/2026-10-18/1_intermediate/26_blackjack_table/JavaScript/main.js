const fs = require('node:fs');

const RANKS = 'A23456789TJQK';
const SUITS = 'CDHS';
const RULE_DEFINITIONS = [
  ['DEALER', 'S17', ['S17', 'H17']],
  ['PEN', 75, [50, 90]],
  ['MIN', 10, [1, 10000]],
  ['MAX', 500, [1, 10000]],
  ['BJ', '3:2', ['3:2', '6:5']],
  ['DAS', 'ON', ['ON', 'OFF']],
  ['DOUBLE', 'ANY', ['ANY', '9-11', '10-11']],
  ['HANDS', 4, [1, 4]],
  ['RSA', 'OFF', ['ON', 'OFF']],
  ['SURRENDER', 'ON', ['ON', 'OFF']],
  ['CHARLIE', '0', ['0', '5', '6', '7']],
  ['SIDEMAX', 25, [0, 1000]],
];
const COMMANDS = new Set([
  'SHOE', 'RULE', 'RULES', 'PLAYER', 'LEAVE', 'REBUY', 'BET', 'SIDE',
  'DEAL', 'INSURANCE', 'HIT', 'STAND', 'DOUBLE', 'SPLIT', 'SURRENDER',
  'HINT', 'AUTO', 'STATUS', 'COUNT', 'STATS',
]);
const ACTIONS = new Set(['HIT', 'STAND', 'DOUBLE', 'SPLIT', 'SURRENDER']);
const STAT_NAMES = [
  'rounds', 'hands', 'wins', 'losses', 'pushes', 'blackjacks', 'busts',
  'surrenders', 'doubles', 'splits',
];

class CommandError extends Error {}
function fail(reason) { throw new CommandError(reason); }

function integer(word, minimum, maximum) {
  if (!/^(?:0|[1-9][0-9]{0,9})$/.test(word)) fail(`bad value ${word}`);
  const value = Number(word);
  if (value < minimum || value > maximum) fail(`bad value ${word}`);
  return value;
}

const rank = card => card % 13;
const suit = card => Math.floor(card / 13);
const points = card => Math.min(rank(card) + 1, 10);
const cardText = card => RANKS[rank(card)] + SUITS[suit(card)];
const signed = value => (value >= 0 ? '+' : '') + value;

function total(cards) {
  const sum = cards.reduce((n, card) => n + points(card), 0);
  const soft = cards.some(card => rank(card) === 0) && sum + 10 <= 21;
  return { value: sum + (soft ? 10 : 0), soft };
}

function blackjack(cards, split = false) {
  return !split && cards.length === 2 && total(cards).value === 21;
}

function handText(cards, split = false) {
  const { value, soft } = total(cards);
  const status = blackjack(cards, split) ? 'blackjack'
    : value > 21 ? `bust ${value}` : soft ? `soft ${value}` : String(value);
  return `${cards.map(cardText).join(' ')} (${status})`;
}

function makeHand(cards, bet, split = false, splitAces = false) {
  return {
    cards, bet, split, splitAces,
    finished: blackjack(cards, split), reason: '',
  };
}

class Player {
  constructor(name, seat, bankroll) {
    this.name = name;
    this.seat = seat;
    this.bankroll = bankroll;
    this.bet = 0;
    this.side = 0;
    this.insurance = 0;
    this.hands = [];
    this.net = 0;
    this.stats = Object.fromEntries(STAT_NAMES.map(name => [name, 0]));
  }

  handName(index) { return `${this.name}[${index + 1}]`; }
}

class Table {
  constructor() {
    this.rules = Object.fromEntries(RULE_DEFINITIONS.map(([name, value]) => [name, value]));
    this.seats = Array(7).fill(null);
    this.participants = [];
    this.state = 'idle';
    this.round = 0;
    this.dealerBlackjacks = 0;
    this.dealerBusts = 0;
    this.decks = 0;
    this.random = 1;
    this.shoe = [];
    this.drawn = 0;
    this.running = 0;
    this.dealer = [];
    this.holeRevealed = false;
    this.insuranceTurn = 0;
    this.output = [];
  }

  emit(line) { this.output.push(line); }
  players() { return this.seats.filter(player => player !== null); }
  cut() { return Math.floor(this.shoe.length * this.rules.PEN / 100); }

  player(name) {
    const player = this.seats.find(player => player !== null && player.name === name);
    if (!player) fail(`unknown player ${name}`);
    return player;
  }

  shuffle() {
    this.shoe = Array.from({ length: 52 * this.decks }, (_, index) => index % 52);
    for (let i = this.shoe.length - 1; i > 0; --i) {
      this.random = this.random * 48271 % 2147483647;
      const j = this.random % (i + 1);
      [this.shoe[i], this.shoe[j]] = [this.shoe[j], this.shoe[i]];
    }
    this.drawn = 0;
    this.running = 0;
  }

  countCard(card) {
    const value = points(card);
    this.running += value >= 2 && value <= 6 ? 1 : value === 1 || value === 10 ? -1 : 0;
  }

  draw(faceUp = true) {
    const card = this.shoe[this.drawn++];
    if (faceUp) this.countCard(card);
    return card;
  }

  revealDealer() {
    if (!this.holeRevealed) {
      this.countCard(this.dealer[1]);
      this.holeRevealed = true;
    }
    this.emit(`dealer: ${handText(this.dealer)}`);
  }

  current() {
    for (const player of this.participants) {
      const index = player.hands.findIndex(hand => !hand.finished);
      if (index !== -1) return { player, index, hand: player.hands[index] };
    }
    return null;
  }

  finishCheck(player, hand) {
    const value = total(hand.cards).value;
    if (value > 21) {
      hand.reason = 'bust';
      hand.finished = true;
    } else if (this.rules.CHARLIE !== '0' && hand.cards.length === Number(this.rules.CHARLIE)) {
      hand.reason = 'charlie';
      hand.finished = true;
    } else if (value === 21) {
      hand.finished = true;
    } else if (hand.splitAces && hand.cards.length === 2) {
      hand.finished = !(hand.cards.every(card => rank(card) === 0)
        && this.rules.RSA === 'ON' && player.hands.length < this.rules.HANDS);
    }
  }

  settle(dealerNatural = false) {
    const dealerTotal = total(this.dealer).value;
    for (const player of this.participants) {
      player.hands.forEach((hand, index) => {
        let result;
        if (dealerNatural) result = blackjack(hand.cards, hand.split) ? 'push' : 'lose';
        else if (blackjack(hand.cards, hand.split)) result = 'blackjack';
        else if (hand.reason) result = hand.reason;
        else {
          const value = total(hand.cards).value;
          result = dealerTotal > 21 || value > dealerTotal ? 'win'
            : value === dealerTotal ? 'push' : 'lose';
        }
        const bet = hand.bet;
        let profit;
        if (result === 'blackjack') {
          profit = this.rules.BJ === '3:2' ? Math.floor(bet * 3 / 2) : Math.floor(bet * 6 / 5);
        } else if (result === 'win' || result === 'charlie') profit = bet;
        else if (result === 'push') profit = 0;
        else if (result === 'surrender') profit = Math.floor(bet / 2) - bet;
        else profit = -bet;
        player.bankroll += bet + profit;
        player.net += profit;
        player.stats.hands++;
        if (['blackjack', 'charlie', 'win'].includes(result)) player.stats.wins++;
        else if (result === 'push') player.stats.pushes++;
        else player.stats.losses++;
        if (result === 'blackjack') player.stats.blackjacks++;
        if (result === 'bust') player.stats.busts++;
        if (result === 'surrender') player.stats.surrenders++;
        this.emit(`${player.handName(index)} ${result} ${signed(profit)}`);
      });
      this.emit(`${player.name} bankroll ${player.bankroll}`);
    }
    for (const player of this.players()) {
      player.bet = 0;
      player.side = 0;
    }
    this.state = 'idle';
  }

  dealerTurn() {
    this.revealDealer();
    const mustPlay = this.participants.some(player => player.hands.some(hand =>
      !['bust', 'surrender', 'charlie'].includes(hand.reason) && !blackjack(hand.cards, hand.split)));
    let drew = false;
    if (mustPlay) {
      while (true) {
        const { value, soft } = total(this.dealer);
        if (!(value <= 16 || value === 17 && soft && this.rules.DEALER === 'H17')) break;
        this.dealer.push(this.draw());
        drew = true;
        this.emit(`dealer hits: ${handText(this.dealer)}`);
      }
    }
    if (drew && total(this.dealer).value > 21) this.dealerBusts++;
    this.settle();
  }

  advance() {
    while (true) {
      const turn = this.current();
      if (!turn) {
        this.dealerTurn();
        return;
      }
      const { player, index, hand } = turn;
      if (hand.cards.length !== 1) return;
      hand.cards.push(this.draw());
      this.emit(`${player.handName(index)}: ${handText(hand.cards, hand.split)}`);
      this.finishCheck(player, hand);
      if (!hand.finished) return;
    }
  }

  peek() {
    const natural = blackjack(this.dealer);
    this.emit(`dealer peeks: ${natural ? 'blackjack' : 'no blackjack'}`);
    for (const player of this.participants) {
      if (player.insurance === 0) continue;
      const profit = player.insurance * (natural ? 2 : -1);
      player.bankroll += player.insurance + profit;
      player.net += profit;
      this.emit(`${player.name} insurance ${signed(profit)}`);
    }
    if (natural) {
      this.dealerBlackjacks++;
      this.revealDealer();
      this.settle(true);
    } else {
      this.state = 'play';
      this.advance();
    }
  }

  deal() {
    if (this.drawn >= this.cut()) {
      this.shuffle();
      this.emit('shuffle');
    }
    this.emit(`round ${++this.round}`);
    this.participants = this.players().filter(player => player.bet !== 0);
    for (const player of this.participants) {
      player.bankroll -= player.bet + player.side;
      player.insurance = 0;
      player.stats.rounds++;
      player.hands = [makeHand([this.draw()], player.bet)];
    }
    this.dealer = [this.draw()];
    for (const player of this.participants) {
      const hand = player.hands[0];
      hand.cards.push(this.draw());
      hand.finished = blackjack(hand.cards);
    }
    this.dealer.push(this.draw(false));
    this.holeRevealed = false;
    for (const player of this.participants) {
      this.emit(`${player.handName(0)}: ${handText(player.hands[0].cards)}`);
    }
    this.emit(`dealer: ${cardText(this.dealer[0])} ??`);
    for (const player of this.participants) {
      if (player.side === 0) continue;
      const [a, b] = player.hands[0].cards;
      let result = 'lose', multiplier = -1;
      if (rank(a) === rank(b)) {
        if (suit(a) === suit(b)) { result = 'perfect'; multiplier = 25; }
        else if ([0, 3].includes(suit(a)) === [0, 3].includes(suit(b))) {
          result = 'colored'; multiplier = 12;
        } else { result = 'mixed'; multiplier = 6; }
      }
      const profit = player.side * multiplier;
      player.bankroll += player.side + profit;
      player.net += profit;
      this.emit(`${player.name} side ${result} ${signed(profit)}`);
    }
    if (points(this.dealer[0]) === 1) {
      this.state = 'insurance';
      this.insuranceTurn = 0;
      this.emit('insurance offered');
    } else if (points(this.dealer[0]) === 10) this.peek();
    else {
      this.state = 'play';
      this.advance();
    }
  }

  actionError(action, player, hand) {
    if (action === 'HIT') return hand.splitAces ? 'split aces' : null;
    if (action === 'DOUBLE') {
      if (hand.splitAces) return 'split aces';
      if (hand.cards.length !== 2) return 'two cards only';
      const { value, soft } = total(hand.cards);
      if (this.rules.DOUBLE !== 'ANY'
          && (soft || value < (this.rules.DOUBLE === '9-11' ? 9 : 10) || value > 11)
          || this.rules.DAS === 'OFF' && hand.split) return 'double not allowed';
      if (player.bankroll < hand.bet) return 'insufficient funds';
    } else if (action === 'SPLIT') {
      if (hand.cards.length !== 2) return 'two cards only';
      if (points(hand.cards[0]) !== points(hand.cards[1])) return 'not a pair';
      if (player.hands.length >= this.rules.HANDS) return 'hand limit';
      if (player.bankroll < hand.bet) return 'insufficient funds';
    } else if (action === 'SURRENDER') {
      if (this.rules.SURRENDER === 'OFF' || hand.split) return 'surrender not allowed';
      if (hand.cards.length !== 2) return 'two cards only';
    }
    return null;
  }

  action(action) {
    const { player, index, hand } = this.current();
    const name = player.handName(index);
    if (action === 'SPLIT') {
      const [first, second] = hand.cards;
      player.bankroll -= hand.bet;
      player.stats.splits++;
      this.emit(`${name} splits ${cardText(first)} ${cardText(second)}`);
      const aces = hand.splitAces || points(first) === 1;
      const replacement = makeHand([first], hand.bet, true, aces);
      player.hands.splice(index, 1, replacement, makeHand([second], hand.bet, true, aces));
      replacement.cards.push(this.draw());
      this.emit(`${name}: ${handText(replacement.cards, true)}`);
      this.finishCheck(player, replacement);
    } else if (action === 'STAND' || action === 'SURRENDER') {
      hand.finished = true;
      if (action === 'SURRENDER') hand.reason = 'surrender';
      this.emit(`${name} ${action === 'STAND' ? 'stands' : 'surrenders'}: ${handText(hand.cards, hand.split)}`);
    } else {
      if (action === 'DOUBLE') {
        player.bankroll -= hand.bet;
        hand.bet *= 2;
        player.stats.doubles++;
      }
      hand.cards.push(this.draw());
      this.emit(`${name} ${action === 'DOUBLE' ? 'doubles' : 'hits'}: ${handText(hand.cards, hand.split)}`);
      this.finishCheck(player, hand);
      if (action === 'DOUBLE') hand.finished = true;
    }
    this.advance();
  }

  recommend() {
    const { player, hand } = this.current();
    const possible = action => this.actionError(action, player, hand) === null;
    const upcard = points(this.dealer[0]);
    const u = upcard === 1 ? 11 : upcard;
    if (hand.splitAces) return possible('SPLIT') ? 'SPLIT' : 'STAND';
    if (hand.cards.length === 2 && points(hand.cards[0]) === points(hand.cards[1]) && possible('SPLIT')) {
      const v = points(hand.cards[0]);
      if (v === 1 || v === 8 || v === 9 && ![7, 10, 11].includes(u)
          || [2, 3, 7].includes(v) && u <= 7 || v === 6 && u <= 6 || v === 4 && (u === 5 || u === 6)) {
        return 'SPLIT';
      }
    }
    const { value: t, soft } = total(hand.cards);
    let symbol = 'H';
    if (soft) {
      if (t >= 19) symbol = 'S';
      else if (t === 18) symbol = u >= 3 && u <= 6 ? 'Ds' : [2, 7, 8].includes(u) ? 'S' : 'H';
      else if (t === 17 && u >= 3 && u <= 6 || (t === 15 || t === 16) && u >= 4 && u <= 6
          || (t === 13 || t === 14) && (u === 5 || u === 6)) symbol = 'D';
    } else {
      if (t >= 17) symbol = 'S';
      else if (t >= 13) {
        symbol = u <= 6 ? 'S' : t === 16 && u >= 9 || t === 15 && u === 10 ? 'R' : 'H';
      } else if (t === 12) symbol = u >= 4 && u <= 6 ? 'S' : 'H';
      else if (t === 11 && u <= 10 || t === 10 && u <= 9 || t === 9 && u >= 3 && u <= 6) symbol = 'D';
    }
    if (symbol === 'S') return 'STAND';
    if (symbol === 'D' || symbol === 'Ds') return possible('DOUBLE') ? 'DOUBLE' : symbol === 'Ds' ? 'STAND' : 'HIT';
    if (symbol === 'R') return possible('SURRENDER') ? 'SURRENDER' : 'HIT';
    return 'HIT';
  }

  status() {
    let line = `table ${this.state} round ${this.round}`;
    if (this.state === 'insurance') line += ` next ${this.participants[this.insuranceTurn].name}`;
    else if (this.state === 'play') {
      const { player, index } = this.current();
      line += ` turn ${player.handName(index)}`;
    }
    this.emit(line);
    if (this.state !== 'idle') this.emit(`dealer: ${cardText(this.dealer[0])} ??`);
    for (const player of this.players()) {
      this.emit(`seat ${player.seat} ${player.name} bankroll ${player.bankroll} bet ${player.bet} side ${player.side}`);
      if (this.state !== 'idle' && this.participants.includes(player)) {
        player.hands.forEach((hand, index) => {
          this.emit(`${player.handName(index)}: ${handText(hand.cards, hand.split)} bet ${hand.bet}`);
        });
      }
    }
  }

  command(line) {
    const [command, first, second] = line.split(' ');
    if (!COMMANDS.has(command)) fail(`unknown command ${command}`);

    // Validate every argument, left to right, before checking table state.
    let player, value, seed;
    if (command === 'SHOE') {
      value = integer(first, 1, 8);
      seed = integer(second, 1, 2147483646);
    } else if (command === 'RULE') {
      const definition = RULE_DEFINITIONS.find(([name]) => name === first);
      if (!definition) fail(`unknown rule ${first}`);
      const allowed = definition[2];
      if (typeof allowed[0] === 'number') value = integer(second, allowed[0], allowed[1]);
      else {
        if (!allowed.includes(second)) fail(`bad value ${second}`);
        value = second;
      }
    } else if (command === 'PLAYER') {
      if (!/^[A-Z]{1,8}$/.test(first)) fail(`bad name ${first}`);
      value = integer(second, 1, 1000000);
    } else if (['LEAVE', 'REBUY', 'BET', 'SIDE', 'INSURANCE', 'AUTO'].includes(command) || ACTIONS.has(command)) {
      player = this.player(first);
      if (['REBUY', 'BET', 'SIDE', 'INSURANCE'].includes(command)) {
        value = integer(second, command === 'REBUY' ? 1 : 0, 1000000);
      }
    }
    if (['SHOE', 'RULE', 'PLAYER', 'LEAVE', 'REBUY', 'BET', 'SIDE', 'DEAL'].includes(command)) {
      if (this.state !== 'idle') fail('round in progress');
    } else if (command === 'INSURANCE') {
      if (this.state !== 'insurance') fail('no insurance');
    } else if (ACTIONS.has(command) || command === 'AUTO' || command === 'HINT') {
      if (this.state === 'idle') fail('no round');
      if (this.state === 'insurance') fail('insurance pending');
    }

    if (ACTIONS.has(command) || command === 'AUTO') {
      const turn = this.current();
      if (turn.player !== player) fail(`waiting for ${turn.player.handName(turn.index)}`);
      if (command === 'AUTO') {
        while (this.state === 'play' && this.current().player === player) this.action(this.recommend());
      } else {
        const error = this.actionError(command, player, turn.hand);
        if (error) fail(error);
        this.action(command);
      }
      return;
    }
    switch (command) {
      case 'SHOE':
        this.decks = value;
        this.random = seed;
        this.shuffle();
        this.emit(`shoe ${value} decks ${this.shoe.length} cards cut ${this.cut()}`);
        break;
      case 'RULE':
        if ((first === 'MIN' ? value : this.rules.MIN) > (first === 'MAX' ? value : this.rules.MAX)) fail('min above max');
        this.rules[first] = value;
        this.emit(`rule ${first} ${value}`);
        break;
      case 'RULES':
        this.emit('rules ' + RULE_DEFINITIONS.map(([name]) => `${name} ${this.rules[name]}`).join(' '));
        break;
      case 'PLAYER': {
        if (this.seats.some(player => player !== null && player.name === first)) fail('player exists');
        const seat = this.seats.indexOf(null);
        if (seat === -1) fail('table full');
        this.seats[seat] = new Player(first, seat + 1, value);
        this.emit(`${first} sits at seat ${seat + 1} with ${value}`);
        break;
      }
      case 'LEAVE':
        this.emit(`${player.name} leaves with ${player.bankroll} net ${signed(player.net)}`);
        this.seats[player.seat - 1] = null;
        break;
      case 'REBUY':
        player.bankroll += value;
        this.emit(`${player.name} rebuys ${value} bankroll ${player.bankroll}`);
        break;
      case 'BET':
        if (value !== 0) {
          if (value < this.rules.MIN || value > this.rules.MAX) fail('bet out of limits');
          if (value + player.side > player.bankroll) fail('insufficient funds');
        }
        player.bet = value;
        if (value === 0) player.side = 0;
        this.emit(value === 0 ? `${player.name} bet cleared` : `${player.name} bets ${value}`);
        break;
      case 'SIDE':
        if (value !== 0) {
          if (player.bet === 0) fail('no bet');
          if (value > this.rules.SIDEMAX) fail('side out of limits');
          if (player.bet + value > player.bankroll) fail('insufficient funds');
        }
        player.side = value;
        this.emit(value === 0 ? `${player.name} side cleared` : `${player.name} side ${value}`);
        break;
      case 'DEAL':
        if (this.decks === 0) fail('no shoe');
        if (!this.players().some(player => player.bet !== 0)) fail('no bets');
        this.deal();
        break;
      case 'INSURANCE':
        if (this.participants[this.insuranceTurn] !== player) fail(`waiting for ${this.participants[this.insuranceTurn].name}`);
        if (value > Math.floor(player.bet / 2)) fail('insurance out of limits');
        if (value > player.bankroll) fail('insufficient funds');
        player.bankroll -= value;
        player.insurance = value;
        this.emit(value === 0 ? `${player.name} declines insurance` : `${player.name} insures ${value}`);
        if (++this.insuranceTurn === this.participants.length) this.peek();
        break;
      case 'HINT': {
        const { player, index } = this.current();
        this.emit(`hint ${player.handName(index)}: ${this.recommend().toLowerCase()}`);
        break;
      }
      case 'STATUS':
        this.status();
        break;
      case 'COUNT': {
        if (this.decks === 0) fail('no shoe');
        const remaining = this.shoe.length - this.drawn;
        const hundredths = Math.floor(Math.abs(this.running) * 5200 / remaining);
        const count = `${this.running < 0 ? '-' : ''}${Math.floor(hundredths / 100)}.${String(hundredths % 100).padStart(2, '0')}`;
        this.emit(`count running ${this.running} true ${count} remaining ${remaining}`);
        break;
      }
      case 'STATS':
        if (this.players().length === 0) fail('no players');
        for (const player of this.players()) {
          this.emit(`stats ${player.name} ${STAT_NAMES.map(name => `${name} ${player.stats[name]}`).join(' ')} net ${signed(player.net)}`);
        }
        this.emit(`stats dealer rounds ${this.round} blackjacks ${this.dealerBlackjacks} busts ${this.dealerBusts}`);
        break;
    }
  }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
const table = new Table();
const count = Number(lines[0]);
for (let i = 1; i <= count; ++i) {
  try {
    table.command(lines[i]);
  } catch (error) {
    if (!(error instanceof CommandError)) throw error;
    table.emit(`error: ${error.message}`);
  }
}
process.stdout.write(table.output.join('\n') + '\n');
