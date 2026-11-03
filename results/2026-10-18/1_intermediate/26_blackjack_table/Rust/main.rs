use std::fmt::{self, Display};
use std::io::{self, Read, Write};

type Money = i64;
type CommandResult<T> = Result<T, String>;

#[derive(Clone, Copy)]
struct Card { rank: u8, suit: u8 }

impl Card {
    fn point(self) -> i32 { if self.rank == 0 { 1 } else { i32::from(self.rank + 1).min(10) } }
    fn black(self) -> bool { self.suit == 0 || self.suit == 3 }
    fn hilo(self) -> i32 { match self.point() { 2..=6 => 1, 7..=9 => 0, _ => -1 } }
}

impl Display for Card {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}{}", b"A23456789TJQK"[self.rank as usize] as char, b"CDHS"[self.suit as usize] as char)
    }
}

#[derive(Clone, Copy)]
struct Total { value: i32, soft: bool }

#[derive(Clone, Copy, PartialEq, Eq)]
enum Finish { Ordinary, Bust, Surrender, Charlie }

#[derive(Default)]
struct Hand {
    cards: Vec<Card>,
    bet: Money,
    split: bool,
    split_aces: bool,
    finish: Option<Finish>,
}

impl Hand {
    fn new(bet: Money) -> Self { Self { bet, ..Self::default() } }
    fn total(&self) -> Total {
        let sum: i32 = self.cards.iter().map(|card| card.point()).sum();
        let soft = self.cards.iter().any(|card| card.rank == 0) && sum + 10 <= 21;
        Total { value: sum + if soft { 10 } else { 0 }, soft }
    }
    fn blackjack(&self) -> bool { !self.split && self.cards.len() == 2 && self.total().value == 21 }
    fn automatic_finish(&mut self, rules: Rules, hands: usize) {
        let total = self.total().value;
        self.finish = if total > 21 { Some(Finish::Bust) }
        else if rules.charlie != 0 && self.cards.len() == rules.charlie { Some(Finish::Charlie) }
        else if total == 21 { Some(Finish::Ordinary) }
        else if self.split_aces && self.cards.len() == 2 &&
            !(self.cards.iter().all(|card| card.rank == 0) && rules.rsa && hands < rules.hands) {
            Some(Finish::Ordinary)
        } else { None };
    }
    fn outcome(&self, dealer: i32, dealer_blackjack: bool) -> Outcome {
        if dealer_blackjack { return if self.blackjack() { Outcome::Push } else { Outcome::Lose }; }
        if self.blackjack() { return Outcome::Blackjack; }
        match self.finish {
            Some(Finish::Bust) => Outcome::Bust,
            Some(Finish::Surrender) => Outcome::Surrender,
            Some(Finish::Charlie) => Outcome::Charlie,
            _ if dealer > 21 || self.total().value > dealer => Outcome::Win,
            _ if self.total().value == dealer => Outcome::Push,
            _ => Outcome::Lose,
        }
    }
}

impl Display for Hand {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (index, card) in self.cards.iter().enumerate() {
            if index != 0 { write!(f, " ")?; }
            write!(f, "{card}")?;
        }
        let total = self.total();
        if self.blackjack() { write!(f, " (blackjack)") }
        else if total.value > 21 { write!(f, " (bust {})", total.value) }
        else if total.soft { write!(f, " (soft {})", total.value) }
        else { write!(f, " ({})", total.value) }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum DealerRule { S17, H17 }
#[derive(Clone, Copy, PartialEq, Eq)]
enum BlackjackPay { ThreeTwo, SixFive }
#[derive(Clone, Copy, PartialEq, Eq)]
enum DoubleRule { Any, NineEleven, TenEleven }

#[derive(Clone, Copy)]
struct Rules {
    dealer: DealerRule,
    pen: usize,
    min: Money,
    max: Money,
    bj: BlackjackPay,
    das: bool,
    doubling: DoubleRule,
    hands: usize,
    rsa: bool,
    surrender: bool,
    charlie: usize,
    side_max: Money,
}

impl Default for Rules {
    fn default() -> Self {
        Self { dealer: DealerRule::S17, pen: 75, min: 10, max: 500, bj: BlackjackPay::ThreeTwo,
            das: true, doubling: DoubleRule::Any, hands: 4, rsa: false,
            surrender: true, charlie: 0, side_max: 25 }
    }
}

fn integer(word: &str, low: i64, high: i64) -> CommandResult<i64> {
    let bytes = word.as_bytes();
    if bytes.is_empty() || bytes.len() > 10 || (bytes.len() > 1 && bytes[0] == b'0') ||
        !bytes.iter().all(u8::is_ascii_digit) {
        return Err(format!("bad value {word}"));
    }
    let value = word.parse::<i64>().unwrap();
    if value < low || value > high { Err(format!("bad value {word}")) } else { Ok(value) }
}

fn switch(word: &str) -> CommandResult<bool> {
    match word { "ON" => Ok(true), "OFF" => Ok(false), _ => Err(format!("bad value {word}")) }
}
fn switch_name(value: bool) -> &'static str { if value { "ON" } else { "OFF" } }

impl Rules {
    fn changed(self, name: &str, word: &str) -> CommandResult<Self> {
        let mut changed = self;
        match name {
            "DEALER" => changed.dealer = match word {
                "S17" => DealerRule::S17, "H17" => DealerRule::H17,
                _ => return Err(format!("bad value {word}")),
            },
            "PEN" => changed.pen = integer(word, 50, 90)? as usize,
            "MIN" => changed.min = integer(word, 1, 10000)?,
            "MAX" => changed.max = integer(word, 1, 10000)?,
            "BJ" => changed.bj = match word {
                "3:2" => BlackjackPay::ThreeTwo, "6:5" => BlackjackPay::SixFive,
                _ => return Err(format!("bad value {word}")),
            },
            "DAS" => changed.das = switch(word)?,
            "DOUBLE" => changed.doubling = match word {
                "ANY" => DoubleRule::Any, "9-11" => DoubleRule::NineEleven, "10-11" => DoubleRule::TenEleven,
                _ => return Err(format!("bad value {word}")),
            },
            "HANDS" => changed.hands = integer(word, 1, 4)? as usize,
            "RSA" => changed.rsa = switch(word)?,
            "SURRENDER" => changed.surrender = switch(word)?,
            "CHARLIE" => {
                let value = integer(word, 0, 7)?;
                if value != 0 && value < 5 { return Err(format!("bad value {word}")); }
                changed.charlie = value as usize;
            }
            "SIDEMAX" => changed.side_max = integer(word, 0, 1000)?,
            _ => return Err(format!("unknown rule {name}")),
        }
        Ok(changed)
    }
}

impl Display for Rules {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let dealer = if self.dealer == DealerRule::S17 { "S17" } else { "H17" };
        let bj = if self.bj == BlackjackPay::ThreeTwo { "3:2" } else { "6:5" };
        let doubling = match self.doubling { DoubleRule::Any => "ANY", DoubleRule::NineEleven => "9-11", DoubleRule::TenEleven => "10-11" };
        write!(f, "DEALER {dealer} PEN {} MIN {} MAX {} BJ {bj} DAS {} DOUBLE {doubling} HANDS {} RSA {} SURRENDER {} CHARLIE {} SIDEMAX {}",
            self.pen, self.min, self.max, switch_name(self.das), self.hands, switch_name(self.rsa),
            switch_name(self.surrender), self.charlie, self.side_max)
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Outcome { Blackjack, Win, Lose, Push, Bust, Surrender, Charlie }

impl Outcome {
    fn name(self) -> &'static str {
        match self { Self::Blackjack => "blackjack", Self::Win => "win", Self::Lose => "lose",
            Self::Push => "push", Self::Bust => "bust", Self::Surrender => "surrender", Self::Charlie => "charlie" }
    }
    fn profit(self, bet: Money, rules: Rules) -> Money {
        match self {
            Self::Blackjack => if rules.bj == BlackjackPay::ThreeTwo { bet * 3 / 2 } else { bet * 6 / 5 },
            Self::Win | Self::Charlie => bet,
            Self::Push => 0,
            Self::Surrender => bet / 2 - bet,
            Self::Lose | Self::Bust => -bet,
        }
    }
}

#[derive(Default)]
struct Stats {
    rounds: i32, hands: i32, wins: i32, losses: i32, pushes: i32,
    blackjacks: i32, busts: i32, surrenders: i32, doubles: i32, splits: i32,
}

impl Stats {
    fn record(&mut self, result: Outcome) {
        self.hands += 1;
        match result {
            Outcome::Blackjack | Outcome::Win | Outcome::Charlie => self.wins += 1,
            Outcome::Push => self.pushes += 1,
            _ => self.losses += 1,
        }
        match result {
            Outcome::Blackjack => self.blackjacks += 1,
            Outcome::Bust => self.busts += 1,
            Outcome::Surrender => self.surrenders += 1,
            _ => {}
        }
    }
}

struct Player {
    name: String,
    bankroll: Money,
    bet: Money,
    side: Money,
    insurance: Money,
    net: Money,
    participating: bool,
    hands: Vec<Hand>,
    stats: Stats,
}

impl Player {
    fn new(name: &str, bankroll: Money) -> Self {
        Self { name: name.to_owned(), bankroll, bet: 0, side: 0, insurance: 0, net: 0,
            participating: false, hands: Vec::new(), stats: Stats::default() }
    }
    fn hand_name(&self, index: usize) -> String { format!("{}[{}]", self.name, index + 1) }
}

struct Shoe {
    cards: Vec<Card>,
    decks: usize,
    drawn: usize,
    running: i32,
    random: i64,
}

impl Shoe {
    fn new(decks: usize, seed: i64) -> Self {
        let mut shoe = Self { cards: Vec::new(), decks, drawn: 0, running: 0, random: seed };
        shoe.shuffle();
        shoe
    }
    fn shuffle(&mut self) {
        self.cards = (0..self.decks * 52).map(|i| Card { rank: (i % 13) as u8, suit: (i / 13 % 4) as u8 }).collect();
        for i in (1..self.cards.len()).rev() {
            self.random = 48271 * self.random % 2147483647;
            self.cards.swap(i, (self.random % (i + 1) as i64) as usize);
        }
        self.drawn = 0;
        self.running = 0;
    }
    fn cut(&self, pen: usize) -> usize { self.cards.len() * pen / 100 }
    fn draw(&mut self, visible: bool) -> Card {
        let card = self.cards[self.drawn];
        self.drawn += 1;
        if visible { self.running += card.hilo(); }
        card
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Action { Hit, Stand, Double, Split, Surrender }

impl Action {
    fn name(self) -> &'static str {
        match self { Self::Hit => "hit", Self::Stand => "stand", Self::Double => "double", Self::Split => "split", Self::Surrender => "surrender" }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Command {
    Shoe, Rule, Rules, Player, Leave, Rebuy, Bet, Side, Deal, Insurance,
    Action(Action), Hint, Auto, Status, Count, Stats,
}

impl Command {
    fn parse(word: &str) -> CommandResult<Self> {
        Ok(match word {
            "SHOE" => Self::Shoe, "RULE" => Self::Rule, "RULES" => Self::Rules,
            "PLAYER" => Self::Player, "LEAVE" => Self::Leave, "REBUY" => Self::Rebuy,
            "BET" => Self::Bet, "SIDE" => Self::Side, "DEAL" => Self::Deal, "INSURANCE" => Self::Insurance,
            "HIT" => Self::Action(Action::Hit), "STAND" => Self::Action(Action::Stand),
            "DOUBLE" => Self::Action(Action::Double), "SPLIT" => Self::Action(Action::Split),
            "SURRENDER" => Self::Action(Action::Surrender), "HINT" => Self::Hint,
            "AUTO" => Self::Auto, "STATUS" => Self::Status, "COUNT" => Self::Count, "STATS" => Self::Stats,
            _ => return Err(format!("unknown command {word}")),
        })
    }
    fn named_player(self) -> bool {
        matches!(self, Self::Leave | Self::Rebuy | Self::Bet | Self::Side | Self::Insurance | Self::Action(_) | Self::Auto)
    }
    fn idle_only(self) -> bool {
        matches!(self, Self::Shoe | Self::Rule | Self::Player | Self::Leave | Self::Rebuy | Self::Bet | Self::Side | Self::Deal)
    }
}

#[derive(Default, PartialEq, Eq)]
enum State { #[default] Idle, Insurance, Play }

#[derive(Default)]
struct Table {
    rules: Rules,
    players: [Option<Player>; 7],
    shoe: Option<Shoe>,
    state: State,
    round: i32,
    insurance_seat: usize,
    current_seat: usize,
    current_hand: usize,
    dealer: Hand,
    hole_visible: bool,
    dealer_blackjack: bool,
    dealer_blackjacks: i32,
    dealer_busts: i32,
}

impl Table {
    fn player(&self, seat: usize) -> &Player { self.players[seat].as_ref().unwrap() }
    fn player_mut(&mut self, seat: usize) -> &mut Player { self.players[seat].as_mut().unwrap() }
    fn find_player(&self, name: &str) -> Option<usize> {
        self.players.iter().position(|player| player.as_ref().is_some_and(|player| player.name == name))
    }
    fn participants(&self) -> Vec<usize> {
        self.players.iter().enumerate().filter_map(|(seat, player)|
            player.as_ref().filter(|player| player.participating).map(|_| seat)).collect()
    }
    fn current_name(&self) -> String { self.player(self.current_seat).hand_name(self.current_hand) }
    fn hand_line(&self, seat: usize, index: usize, verb: &str) -> String {
        let player = self.player(seat);
        format!("{}{}: {}", player.hand_name(index), verb, player.hands[index])
    }
    fn add_player_card(&mut self, seat: usize, index: usize) {
        let card = self.shoe.as_mut().unwrap().draw(true);
        self.player_mut(seat).hands[index].cards.push(card);
    }
    fn add_dealer_card(&mut self, visible: bool) {
        let card = self.shoe.as_mut().unwrap().draw(visible);
        self.dealer.cards.push(card);
    }
    fn reveal(&mut self) {
        if !self.hole_visible {
            self.shoe.as_mut().unwrap().running += self.dealer.cards[1].hilo();
            self.hole_visible = true;
        }
    }
    fn automatic_finish(&mut self, seat: usize, index: usize) {
        let rules = self.rules;
        let player = self.player_mut(seat);
        let hands = player.hands.len();
        player.hands[index].automatic_finish(rules, hands);
    }
    fn settle(&mut self, output: &mut Vec<String>) {
        let dealer = self.dealer.total().value;
        let peek_blackjack = self.dealer_blackjack;
        let rules = self.rules;
        for seat in self.participants() {
            let player = self.player_mut(seat);
            for index in 0..player.hands.len() {
                let hand = &player.hands[index];
                let result = hand.outcome(dealer, peek_blackjack);
                let bet = hand.bet;
                let profit = result.profit(bet, rules);
                player.bankroll += bet + profit;
                player.net += profit;
                player.stats.record(result);
                output.push(format!("{} {} {profit:+}", player.hand_name(index), result.name()));
            }
            output.push(format!("{} bankroll {}", player.name, player.bankroll));
        }
        for player in self.players.iter_mut().flatten() {
            player.bet = 0;
            player.side = 0;
            player.participating = false;
        }
        self.state = State::Idle;
    }
    fn dealer_turn(&mut self, output: &mut Vec<String>) {
        self.reveal();
        output.push(format!("dealer: {}", self.dealer));
        let needs_draw = self.players.iter().flatten().filter(|player| player.participating)
            .flat_map(|player| &player.hands).any(|hand| hand.finish == Some(Finish::Ordinary) && !hand.blackjack());
        let mut drew = false;
        if needs_draw {
            loop {
                let total = self.dealer.total();
                if !(total.value <= 16 || (total.value == 17 && total.soft && self.rules.dealer == DealerRule::H17)) { break; }
                self.add_dealer_card(true);
                output.push(format!("dealer hits: {}", self.dealer));
                drew = true;
            }
        }
        if drew && self.dealer.total().value > 21 { self.dealer_busts += 1; }
        self.settle(output);
    }
    fn next_hand(&mut self, output: &mut Vec<String>) {
        loop {
            let next = self.players.iter().enumerate().find_map(|(seat, player)| {
                player.as_ref().filter(|player| player.participating).and_then(|player|
                    player.hands.iter().position(|hand| hand.finish.is_none()).map(|index| (seat, index)))
            });
            let Some((seat, index)) = next else { self.dealer_turn(output); return; };
            self.current_seat = seat;
            self.current_hand = index;
            if self.player(seat).hands[index].cards.len() != 1 { return; }
            self.add_player_card(seat, index);
            output.push(self.hand_line(seat, index, ""));
            self.automatic_finish(seat, index);
            if self.player(seat).hands[index].finish.is_none() { return; }
        }
    }
    fn peek(&mut self, output: &mut Vec<String>) {
        self.dealer_blackjack = self.dealer.blackjack();
        output.push(format!("dealer peeks: {}", if self.dealer_blackjack { "blackjack" } else { "no blackjack" }));
        if self.dealer_blackjack { self.dealer_blackjacks += 1; }
        let dealer_blackjack = self.dealer_blackjack;
        for seat in self.participants() {
            let player = self.player_mut(seat);
            if player.insurance == 0 { continue; }
            let profit = if dealer_blackjack { player.insurance * 2 } else { -player.insurance };
            player.bankroll += player.insurance + profit;
            player.net += profit;
            output.push(format!("{} insurance {profit:+}", player.name));
        }
        if self.dealer_blackjack {
            self.reveal();
            output.push(format!("dealer: {}", self.dealer));
            self.settle(output);
        } else {
            self.state = State::Play;
            self.next_hand(output);
        }
    }
    fn deal(&mut self, output: &mut Vec<String>) {
        let shoe = self.shoe.as_mut().unwrap();
        if shoe.drawn >= shoe.cut(self.rules.pen) {
            shoe.shuffle();
            output.push("shuffle".to_owned());
        }
        self.round += 1;
        output.push(format!("round {}", self.round));
        self.dealer = Hand::default();
        self.hole_visible = false;
        self.dealer_blackjack = false;
        for player in self.players.iter_mut().flatten() {
            player.participating = player.bet != 0;
            player.hands.clear();
            if player.participating {
                player.bankroll -= player.bet + player.side;
                player.insurance = 0;
                player.stats.rounds += 1;
                player.hands.push(Hand::new(player.bet));
            }
        }
        let participants = self.participants();
        for &seat in &participants { self.add_player_card(seat, 0); }
        self.add_dealer_card(true);
        for &seat in &participants {
            self.add_player_card(seat, 0);
            let hand = &mut self.player_mut(seat).hands[0];
            if hand.blackjack() { hand.finish = Some(Finish::Ordinary); }
        }
        self.add_dealer_card(false);
        for &seat in &participants { output.push(self.hand_line(seat, 0, "")); }
        output.push(format!("dealer: {} ??", self.dealer.cards[0]));
        for &seat in &participants {
            let player = self.player_mut(seat);
            if player.side == 0 { continue; }
            let a = player.hands[0].cards[0];
            let b = player.hands[0].cards[1];
            let (result, multiplier) = if a.rank != b.rank { ("lose", -1) }
                else if a.suit == b.suit { ("perfect", 25) }
                else if a.black() == b.black() { ("colored", 12) } else { ("mixed", 6) };
            let profit = player.side * multiplier;
            player.bankroll += player.side + profit;
            player.net += profit;
            output.push(format!("{} side {result} {profit:+}", player.name));
        }
        match self.dealer.cards[0].point() {
            1 => {
                self.state = State::Insurance;
                self.insurance_seat = participants[0];
                output.push("insurance offered".to_owned());
            }
            10 => self.peek(output),
            _ => { self.state = State::Play; self.next_hand(output); }
        }
    }
    fn action_problem(&self, action: Action) -> Option<&'static str> {
        let player = self.player(self.current_seat);
        let hand = &player.hands[self.current_hand];
        let total = hand.total();
        match action {
            Action::Hit if hand.split_aces => return Some("split aces"),
            Action::Double => {
                if hand.split_aces { return Some("split aces"); }
                if hand.cards.len() != 2 { return Some("two cards only"); }
                let allowed = match self.rules.doubling {
                    DoubleRule::Any => true,
                    DoubleRule::NineEleven => !total.soft && (9..=11).contains(&total.value),
                    DoubleRule::TenEleven => !total.soft && (10..=11).contains(&total.value),
                };
                if !allowed || (!self.rules.das && hand.split) { return Some("double not allowed"); }
                if player.bankroll < hand.bet { return Some("insufficient funds"); }
            }
            Action::Split => {
                if hand.cards.len() != 2 { return Some("two cards only"); }
                if hand.cards[0].point() != hand.cards[1].point() { return Some("not a pair"); }
                if player.hands.len() >= self.rules.hands { return Some("hand limit"); }
                if player.bankroll < hand.bet { return Some("insufficient funds"); }
            }
            Action::Surrender => {
                if !self.rules.surrender || hand.split { return Some("surrender not allowed"); }
                if hand.cards.len() != 2 { return Some("two cards only"); }
            }
            _ => {}
        }
        None
    }
    fn recommendation(&self) -> Action {
        let hand = &self.player(self.current_seat).hands[self.current_hand];
        let mut up = self.dealer.cards[0].point();
        if up == 1 { up = 11; }
        let can_split = self.action_problem(Action::Split).is_none();
        if hand.split_aces { return if can_split { Action::Split } else { Action::Stand }; }
        if can_split {
            let preferred = match hand.cards[0].point() {
                1 | 8 => true, 9 => !matches!(up, 7 | 10 | 11),
                2 | 3 | 7 => up <= 7, 6 => up <= 6, 4 => up == 5 || up == 6, _ => false,
            };
            if preferred { return Action::Split; }
        }
        let total = hand.total();
        let value = total.value;
        let can_double = self.action_problem(Action::Double).is_none();
        if total.soft {
            if value >= 19 { return Action::Stand; }
            if value == 18 {
                if (3..=6).contains(&up) { return if can_double { Action::Double } else { Action::Stand }; }
                return if matches!(up, 2 | 7 | 8) { Action::Stand } else { Action::Hit };
            }
            let wants_double = match value {
                17 => (3..=6).contains(&up), 15 | 16 => (4..=6).contains(&up),
                13 | 14 => up == 5 || up == 6, _ => false,
            };
            return if wants_double && can_double { Action::Double } else { Action::Hit };
        }
        if value >= 17 { return Action::Stand; }
        if value >= 13 {
            if up <= 6 { return Action::Stand; }
            if ((value == 16 && up >= 9) || (value == 15 && up == 10)) && self.action_problem(Action::Surrender).is_none() { return Action::Surrender; }
            return Action::Hit;
        }
        if value == 12 { return if (4..=6).contains(&up) { Action::Stand } else { Action::Hit }; }
        let wants_double = (value == 11 && up <= 10) || (value == 10 && up <= 9) || (value == 9 && (3..=6).contains(&up));
        if wants_double && can_double { Action::Double } else { Action::Hit }
    }
    fn perform_action(&mut self, action: Action, output: &mut Vec<String>) {
        let seat = self.current_seat;
        let index = self.current_hand;
        match action {
            Action::Hit | Action::Double => {
                if action == Action::Double {
                    let player = self.player_mut(seat);
                    player.bankroll -= player.hands[index].bet;
                    player.hands[index].bet *= 2;
                    player.stats.doubles += 1;
                }
                self.add_player_card(seat, index);
                output.push(self.hand_line(seat, index, if action == Action::Hit { " hits" } else { " doubles" }));
                self.automatic_finish(seat, index);
                if action == Action::Double { self.player_mut(seat).hands[index].finish.get_or_insert(Finish::Ordinary); }
            }
            Action::Stand | Action::Surrender => {
                self.player_mut(seat).hands[index].finish = Some(if action == Action::Stand { Finish::Ordinary } else { Finish::Surrender });
                output.push(self.hand_line(seat, index, if action == Action::Stand { " stands" } else { " surrenders" }));
            }
            Action::Split => {
                let player = self.player_mut(seat);
                let old = &player.hands[index];
                let (first, second, bet, aces) = (old.cards[0], old.cards[1], old.bet, old.split_aces || old.cards[0].rank == 0);
                player.bankroll -= bet;
                player.stats.splits += 1;
                output.push(format!("{} splits {first} {second}", player.hand_name(index)));
                player.hands[index] = Hand { cards: vec![first], bet, split: true, split_aces: aces, finish: None };
                player.hands.insert(index + 1, Hand { cards: vec![second], bet, split: true, split_aces: aces, finish: None });
                self.add_player_card(seat, index);
                output.push(self.hand_line(seat, index, ""));
                self.automatic_finish(seat, index);
            }
        }
        self.next_hand(output);
    }
    fn status(&self, output: &mut Vec<String>) {
        output.push(match self.state {
            State::Idle => format!("table idle round {}", self.round),
            State::Insurance => format!("table insurance round {} next {}", self.round, self.player(self.insurance_seat).name),
            State::Play => format!("table play round {} turn {}", self.round, self.current_name()),
        });
        if self.state != State::Idle { output.push(format!("dealer: {} ??", self.dealer.cards[0])); }
        for (seat, player) in self.players.iter().enumerate() {
            let Some(player) = player else { continue; };
            output.push(format!("seat {} {} bankroll {} bet {} side {}", seat + 1, player.name, player.bankroll, player.bet, player.side));
            if self.state != State::Idle && player.participating {
                for (index, hand) in player.hands.iter().enumerate() {
                    output.push(format!("{}: {hand} bet {}", player.hand_name(index), hand.bet));
                }
            }
        }
    }
    fn stats(&self, output: &mut Vec<String>) {
        for player in self.players.iter().flatten() {
            let s = &player.stats;
            output.push(format!("stats {} rounds {} hands {} wins {} losses {} pushes {} blackjacks {} busts {} surrenders {} doubles {} splits {} net {:+}",
                player.name, s.rounds, s.hands, s.wins, s.losses, s.pushes, s.blackjacks, s.busts, s.surrenders, s.doubles, s.splits, player.net));
        }
        output.push(format!("stats dealer rounds {} blackjacks {} busts {}", self.round, self.dealer_blackjacks, self.dealer_busts));
    }
    fn execute(&mut self, words: &[&str]) -> CommandResult<Vec<String>> {
        let command = Command::parse(words[0])?;
        let mut seat = None;
        let mut amount = 0;
        let mut seed = 0;
        let mut changed_rules = None;
        match command {
            Command::Shoe => { amount = integer(words[1], 1, 8)?; seed = integer(words[2], 1, 2147483646)?; }
            Command::Rule => changed_rules = Some(self.rules.changed(words[1], words[2])?),
            Command::Player => {
                if words[1].is_empty() || words[1].len() > 8 || !words[1].bytes().all(|byte| byte.is_ascii_uppercase()) {
                    return Err(format!("bad name {}", words[1]));
                }
                amount = integer(words[2], 1, 1000000)?;
            }
            _ if command.named_player() => {
                seat = Some(self.find_player(words[1]).ok_or_else(|| format!("unknown player {}", words[1]))?);
                if matches!(command, Command::Rebuy | Command::Bet | Command::Side | Command::Insurance) {
                    amount = integer(words[2], if command == Command::Rebuy { 1 } else { 0 }, 1000000)?;
                }
            }
            _ => {}
        }
        if command.idle_only() && self.state != State::Idle { return Err("round in progress".to_owned()); }
        if command == Command::Insurance && self.state != State::Insurance { return Err("no insurance".to_owned()); }
        if matches!(command, Command::Action(_) | Command::Auto | Command::Hint) {
            match self.state {
                State::Idle => return Err("no round".to_owned()),
                State::Insurance => return Err("insurance pending".to_owned()),
                State::Play => {}
            }
            if command != Command::Hint && seat != Some(self.current_seat) { return Err(format!("waiting for {}", self.current_name())); }
        }
        let mut output = Vec::new();
        match command {
            Command::Shoe => {
                let shoe = Shoe::new(amount as usize, seed);
                output.push(format!("shoe {} decks {} cards cut {}", shoe.decks, shoe.cards.len(), shoe.cut(self.rules.pen)));
                self.shoe = Some(shoe);
            }
            Command::Rule => {
                let rules = changed_rules.unwrap();
                if rules.min > rules.max { return Err("min above max".to_owned()); }
                self.rules = rules;
                output.push(format!("rule {} {}", words[1], words[2]));
            }
            Command::Rules => output.push(format!("rules {}", self.rules)),
            Command::Player => {
                if self.find_player(words[1]).is_some() { return Err("player exists".to_owned()); }
                let seat = self.players.iter().position(Option::is_none).ok_or("table full")?;
                self.players[seat] = Some(Player::new(words[1], amount));
                output.push(format!("{} sits at seat {} with {amount}", words[1], seat + 1));
            }
            Command::Leave => {
                let player = self.players[seat.unwrap()].take().unwrap();
                output.push(format!("{} leaves with {} net {:+}", player.name, player.bankroll, player.net));
            }
            Command::Rebuy => {
                let player = self.player_mut(seat.unwrap());
                player.bankroll += amount;
                output.push(format!("{} rebuys {amount} bankroll {}", player.name, player.bankroll));
            }
            Command::Bet => {
                let rules = self.rules;
                let player = self.player_mut(seat.unwrap());
                if amount == 0 {
                    player.bet = 0;
                    player.side = 0;
                    output.push(format!("{} bet cleared", player.name));
                } else {
                    if amount < rules.min || amount > rules.max { return Err("bet out of limits".to_owned()); }
                    if amount + player.side > player.bankroll { return Err("insufficient funds".to_owned()); }
                    player.bet = amount;
                    output.push(format!("{} bets {amount}", player.name));
                }
            }
            Command::Side => {
                let side_max = self.rules.side_max;
                let player = self.player_mut(seat.unwrap());
                if amount == 0 {
                    player.side = 0;
                    output.push(format!("{} side cleared", player.name));
                } else {
                    if player.bet == 0 { return Err("no bet".to_owned()); }
                    if amount > side_max { return Err("side out of limits".to_owned()); }
                    if player.bet + amount > player.bankroll { return Err("insufficient funds".to_owned()); }
                    player.side = amount;
                    output.push(format!("{} side {amount}", player.name));
                }
            }
            Command::Deal => {
                if self.shoe.is_none() { return Err("no shoe".to_owned()); }
                if !self.players.iter().flatten().any(|player| player.bet != 0) { return Err("no bets".to_owned()); }
                self.deal(&mut output);
            }
            Command::Insurance => {
                let seat = seat.unwrap();
                if seat != self.insurance_seat { return Err(format!("waiting for {}", self.player(self.insurance_seat).name)); }
                let player = self.player_mut(seat);
                if amount > player.bet / 2 { return Err("insurance out of limits".to_owned()); }
                if amount > player.bankroll { return Err("insufficient funds".to_owned()); }
                player.bankroll -= amount;
                player.insurance = amount;
                output.push(if amount == 0 { format!("{} declines insurance", player.name) } else { format!("{} insures {amount}", player.name) });
                if let Some(next) = self.participants().into_iter().find(|&next| next > seat) { self.insurance_seat = next; }
                else { self.peek(&mut output); }
            }
            Command::Action(action) => {
                if let Some(problem) = self.action_problem(action) { return Err(problem.to_owned()); }
                self.perform_action(action, &mut output);
            }
            Command::Hint => output.push(format!("hint {}: {}", self.current_name(), self.recommendation().name())),
            Command::Auto => {
                while self.state == State::Play && self.current_seat == seat.unwrap() {
                    self.perform_action(self.recommendation(), &mut output);
                }
            }
            Command::Status => self.status(&mut output),
            Command::Count => {
                let shoe = self.shoe.as_ref().ok_or("no shoe")?;
                let remaining = shoe.cards.len() - shoe.drawn;
                let scaled = i64::from(shoe.running.abs()) * 5200 / remaining as i64;
                output.push(format!("count running {} true {}{}.{:02} remaining {remaining}", shoe.running,
                    if shoe.running < 0 { "-" } else { "" }, scaled / 100, scaled % 100));
            }
            Command::Stats => {
                if self.players.iter().all(Option::is_none) { return Err("no players".to_owned()); }
                self.stats(&mut output);
            }
        }
        Ok(output)
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut table = Table::default();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for line in lines.take(count) {
        let words: Vec<&str> = line.split_ascii_whitespace().collect();
        match table.execute(&words) {
            Ok(lines) => for line in lines { writeln!(output, "{line}").unwrap(); },
            Err(error) => writeln!(output, "error: {error}").unwrap(),
        }
    }
}
