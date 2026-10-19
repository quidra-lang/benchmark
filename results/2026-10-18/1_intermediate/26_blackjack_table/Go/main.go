package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

type Money int64
type State int
type Finish int
type Outcome string
type Action string
type Command string
type DoubleRule string

const (
	idle State = iota
	insurance
	play
)

const (
	ordinary Finish = iota
	bustFinish
	surrenderFinish
	charlieFinish
)

const (
	blackjackOutcome Outcome = "blackjack"
	winOutcome       Outcome = "win"
	loseOutcome      Outcome = "lose"
	pushOutcome      Outcome = "push"
	bustOutcome      Outcome = "bust"
	surrenderOutcome Outcome = "surrender"
	charlieOutcome   Outcome = "charlie"
)

const (
	hitAction       Action = "hit"
	standAction     Action = "stand"
	doubleAction    Action = "double"
	splitAction     Action = "split"
	surrenderAction Action = "surrender"
)

const (
	shoeCommand      Command = "SHOE"
	ruleCommand      Command = "RULE"
	rulesCommand     Command = "RULES"
	playerCommand    Command = "PLAYER"
	leaveCommand     Command = "LEAVE"
	rebuyCommand     Command = "REBUY"
	betCommand       Command = "BET"
	sideCommand      Command = "SIDE"
	dealCommand      Command = "DEAL"
	insuranceCommand Command = "INSURANCE"
	hitCommand       Command = "HIT"
	standCommand     Command = "STAND"
	doubleCommand    Command = "DOUBLE"
	splitCommand     Command = "SPLIT"
	surrenderCommand Command = "SURRENDER"
	hintCommand      Command = "HINT"
	autoCommand      Command = "AUTO"
	statusCommand    Command = "STATUS"
	countCommand     Command = "COUNT"
	statsCommand     Command = "STATS"
)

const (
	doubleAny    DoubleRule = "ANY"
	doubleHard9  DoubleRule = "9-11"
	doubleHard10 DoubleRule = "10-11"
)

func parseCommand(word string) (Command, error) {
	command := Command(word)
	switch command {
	case shoeCommand, ruleCommand, rulesCommand, playerCommand, leaveCommand, rebuyCommand,
		betCommand, sideCommand, dealCommand, insuranceCommand, hitCommand, standCommand,
		doubleCommand, splitCommand, surrenderCommand, hintCommand, autoCommand,
		statusCommand, countCommand, statsCommand:
		return command, nil
	default:
		return "", fmt.Errorf("unknown command %s", word)
	}
}

func (command Command) action() Action {
	switch command {
	case hitCommand:
		return hitAction
	case standCommand:
		return standAction
	case doubleCommand:
		return doubleAction
	case splitCommand:
		return splitAction
	case surrenderCommand:
		return surrenderAction
	default:
		return ""
	}
}

func (command Command) namedPlayer() bool {
	switch command {
	case leaveCommand, rebuyCommand, betCommand, sideCommand, insuranceCommand, autoCommand:
		return true
	default:
		return command.action() != ""
	}
}

func (command Command) idleOnly() bool {
	switch command {
	case shoeCommand, ruleCommand, playerCommand, leaveCommand, rebuyCommand, betCommand, sideCommand, dealCommand:
		return true
	default:
		return false
	}
}

func integer(word string, low, high int64) (int64, error) {
	if len(word) == 0 || len(word) > 10 || len(word) > 1 && word[0] == '0' {
		return 0, fmt.Errorf("bad value %s", word)
	}
	var value int64
	for i := range len(word) {
		if word[i] < '0' || word[i] > '9' {
			return 0, fmt.Errorf("bad value %s", word)
		}
		value = value*10 + int64(word[i]-'0')
	}
	if value < low || value > high {
		return 0, fmt.Errorf("bad value %s", word)
	}
	return value, nil
}

func parseSwitch(word string) (bool, error) {
	if word != "ON" && word != "OFF" {
		return false, fmt.Errorf("bad value %s", word)
	}
	return word == "ON", nil
}

func switchName(enabled bool) string {
	if enabled {
		return "ON"
	}
	return "OFF"
}

type Rules struct {
	hitSoft17, sixToFive, das bool
	pen                     int
	minimum, maximum        Money
	doubling                DoubleRule
	hands                   int
	rsa, surrender          bool
	charlie                 int
	sideMaximum             Money
}

func defaultRules() Rules {
	return Rules{pen: 75, minimum: 10, maximum: 500, das: true, doubling: doubleAny,
		hands: 4, surrender: true, sideMaximum: 25}
}

func (rules Rules) changed(name, word string) (Rules, error) {
	var err error
	switch name {
	case "DEALER":
		if word != "S17" && word != "H17" {
			return rules, fmt.Errorf("bad value %s", word)
		}
		rules.hitSoft17 = word == "H17"
	case "BJ":
		if word != "3:2" && word != "6:5" {
			return rules, fmt.Errorf("bad value %s", word)
		}
		rules.sixToFive = word == "6:5"
	case "DOUBLE":
		value := DoubleRule(word)
		if value != doubleAny && value != doubleHard9 && value != doubleHard10 {
			return rules, fmt.Errorf("bad value %s", word)
		}
		rules.doubling = value
	case "DAS":
		rules.das, err = parseSwitch(word)
	case "RSA":
		rules.rsa, err = parseSwitch(word)
	case "SURRENDER":
		rules.surrender, err = parseSwitch(word)
	case "PEN":
		value, failure := integer(word, 50, 90)
		rules.pen, err = int(value), failure
	case "MIN":
		value, failure := integer(word, 1, 10000)
		rules.minimum, err = Money(value), failure
	case "MAX":
		value, failure := integer(word, 1, 10000)
		rules.maximum, err = Money(value), failure
	case "HANDS":
		value, failure := integer(word, 1, 4)
		rules.hands, err = int(value), failure
	case "CHARLIE":
		value, failure := integer(word, 0, 7)
		if failure != nil {
			return rules, failure
		}
		if value != 0 && value < 5 {
			return rules, fmt.Errorf("bad value %s", word)
		}
		rules.charlie = int(value)
	case "SIDEMAX":
		value, failure := integer(word, 0, 1000)
		rules.sideMaximum, err = Money(value), failure
	default:
		return rules, fmt.Errorf("unknown rule %s", name)
	}
	return rules, err
}

func (rules Rules) String() string {
	dealer, bj := "S17", "3:2"
	if rules.hitSoft17 {
		dealer = "H17"
	}
	if rules.sixToFive {
		bj = "6:5"
	}
	return fmt.Sprintf("rules DEALER %s PEN %d MIN %d MAX %d BJ %s DAS %s DOUBLE %s HANDS %d RSA %s SURRENDER %s CHARLIE %d SIDEMAX %d",
		dealer, rules.pen, rules.minimum, rules.maximum, bj, switchName(rules.das), rules.doubling,
		rules.hands, switchName(rules.rsa), switchName(rules.surrender), rules.charlie, rules.sideMaximum)
}

type Card struct{ rank, suit int }

func (card Card) point() int { return min(card.rank+1, 10) }
func (card Card) black() bool { return card.suit == 0 || card.suit == 3 }
func (card Card) String() string {
	return fmt.Sprintf("%c%c", "A23456789TJQK"[card.rank], "CDHS"[card.suit])
}
func (card Card) hilo() int {
	value := card.point()
	if value >= 2 && value <= 6 {
		return 1
	}
	if value == 1 || value == 10 {
		return -1
	}
	return 0
}

type Total struct {
	value int
	soft  bool
}

type Hand struct {
	cards                      []Card
	bet                        Money
	split, splitAces, finished  bool
	reason                     Finish
}

func (hand *Hand) total() Total {
	sum, ace := 0, false
	for _, card := range hand.cards {
		sum += card.point()
		ace = ace || card.rank == 0
	}
	soft := ace && sum+10 <= 21
	if soft {
		sum += 10
	}
	return Total{sum, soft}
}

func (hand *Hand) blackjack() bool {
	return !hand.split && len(hand.cards) == 2 && hand.total().value == 21
}

func (hand *Hand) String() string {
	cards := make([]string, len(hand.cards))
	for i, card := range hand.cards {
		cards[i] = card.String()
	}
	total := hand.total()
	status := strconv.Itoa(total.value)
	if hand.blackjack() {
		status = "blackjack"
	} else if total.value > 21 {
		status = "bust " + status
	} else if total.soft {
		status = "soft " + status
	}
	return strings.Join(cards, " ") + " (" + status + ")"
}

func (hand *Hand) outcome(dealer int, dealerBlackjack bool) Outcome {
	if dealerBlackjack {
		if hand.blackjack() {
			return pushOutcome
		}
		return loseOutcome
	}
	if hand.blackjack() {
		return blackjackOutcome
	}
	switch hand.reason {
	case bustFinish:
		return bustOutcome
	case surrenderFinish:
		return surrenderOutcome
	case charlieFinish:
		return charlieOutcome
	}
	value := hand.total().value
	if dealer > 21 || value > dealer {
		return winOutcome
	}
	if value == dealer {
		return pushOutcome
	}
	return loseOutcome
}

func (result Outcome) profit(bet Money, rules Rules) Money {
	switch result {
	case blackjackOutcome:
		if rules.sixToFive {
			return bet * 6 / 5
		}
		return bet * 3 / 2
	case winOutcome, charlieOutcome:
		return bet
	case pushOutcome:
		return 0
	case surrenderOutcome:
		return bet/2 - bet
	default:
		return -bet
	}
}

type Stats struct {
	rounds, hands, wins, losses, pushes             int
	blackjacks, busts, surrenders, doubles, splits   int
}

func (stats *Stats) record(result Outcome) {
	stats.hands++
	switch result {
	case blackjackOutcome, winOutcome, charlieOutcome:
		stats.wins++
	case pushOutcome:
		stats.pushes++
	default:
		stats.losses++
	}
	switch result {
	case blackjackOutcome:
		stats.blackjacks++
	case bustOutcome:
		stats.busts++
	case surrenderOutcome:
		stats.surrenders++
	}
}

func (stats Stats) String() string {
	return fmt.Sprintf("rounds %d hands %d wins %d losses %d pushes %d blackjacks %d busts %d surrenders %d doubles %d splits %d",
		stats.rounds, stats.hands, stats.wins, stats.losses, stats.pushes, stats.blackjacks,
		stats.busts, stats.surrenders, stats.doubles, stats.splits)
}

type Player struct {
	name                                string
	seat                                int
	bankroll, bet, side, insurance, net  Money
	hands                               []*Hand
	stats                               Stats
}

func (player *Player) handName(index int) string {
	return fmt.Sprintf("%s[%d]", player.name, index+1)
}

type Shoe struct {
	cards                         []Card
	decks, drawn, running          int
	random                        int64
}

func newShoe(decks int, seed int64) *Shoe {
	shoe := &Shoe{decks: decks, random: seed}
	shoe.shuffle()
	return shoe
}

func (shoe *Shoe) shuffle() {
	shoe.cards = make([]Card, 52*shoe.decks)
	for i := range shoe.cards {
		shoe.cards[i] = Card{i % 13, i / 13 % 4}
	}
	for i := len(shoe.cards) - 1; i > 0; i-- {
		shoe.random = shoe.random * 48271 % 2147483647
		j := int(shoe.random % int64(i+1))
		shoe.cards[i], shoe.cards[j] = shoe.cards[j], shoe.cards[i]
	}
	shoe.drawn, shoe.running = 0, 0
}

func (shoe *Shoe) cut(pen int) int { return len(shoe.cards) * pen / 100 }
func (shoe *Shoe) draw(visible bool) Card {
	card := shoe.cards[shoe.drawn]
	shoe.drawn++
	if visible {
		shoe.running += card.hilo()
	}
	return card
}

type Turn struct {
	player *Player
	index  int
	hand   *Hand
}

func (turn Turn) name() string { return turn.player.handName(turn.index) }

type Table struct {
	rules                         Rules
	seats                         [7]*Player
	participants                  []*Player
	shoe                          *Shoe
	state                         State
	round, dealerBlackjacks        int
	dealerBusts, insuranceTurn     int
	dealer                        Hand
	holeVisible                   bool
	output                        []string
}

func (table *Table) emit(format string, args ...any) {
	table.output = append(table.output, fmt.Sprintf(format, args...))
}

func (table *Table) seated() []*Player {
	players := make([]*Player, 0, 7)
	for _, player := range table.seats {
		if player != nil {
			players = append(players, player)
		}
	}
	return players
}

func (table *Table) find(name string) *Player {
	for _, player := range table.seats {
		if player != nil && player.name == name {
			return player
		}
	}
	return nil
}

func (table *Table) current() (Turn, bool) {
	for _, player := range table.participants {
		for index, hand := range player.hands {
			if !hand.finished {
				return Turn{player, index, hand}, true
			}
		}
	}
	return Turn{}, false
}

func (table *Table) reveal() {
	if !table.holeVisible {
		table.shoe.running += table.dealer.cards[1].hilo()
		table.holeVisible = true
	}
	table.emit("dealer: %s", &table.dealer)
}

func (table *Table) finishCheck(player *Player, hand *Hand) {
	value := hand.total().value
	switch {
	case value > 21:
		hand.finished, hand.reason = true, bustFinish
	case table.rules.charlie != 0 && len(hand.cards) == table.rules.charlie:
		hand.finished, hand.reason = true, charlieFinish
	case value == 21:
		hand.finished = true
	case hand.splitAces && len(hand.cards) == 2:
		resplit := hand.cards[0].rank == 0 && hand.cards[1].rank == 0 && table.rules.rsa && len(player.hands) < table.rules.hands
		hand.finished = !resplit
	}
}

func (table *Table) settle(dealerBlackjack bool) {
	dealer := table.dealer.total().value
	for _, player := range table.participants {
		for index, hand := range player.hands {
			result := hand.outcome(dealer, dealerBlackjack)
			profit := result.profit(hand.bet, table.rules)
			player.bankroll += hand.bet + profit
			player.net += profit
			player.stats.record(result)
			table.emit("%s %s %+d", player.handName(index), result, profit)
		}
		table.emit("%s bankroll %d", player.name, player.bankroll)
	}
	for _, player := range table.seated() {
		player.bet, player.side = 0, 0
	}
	table.state = idle
}

func (table *Table) dealerTurn() {
	table.reveal()
	needsDraw := false
	for _, player := range table.participants {
		for _, hand := range player.hands {
			if hand.reason == ordinary && !hand.blackjack() {
				needsDraw = true
			}
		}
	}
	drew := false
	if needsDraw {
		for {
			total := table.dealer.total()
			if !(total.value <= 16 || total.value == 17 && total.soft && table.rules.hitSoft17) {
				break
			}
			table.dealer.cards = append(table.dealer.cards, table.shoe.draw(true))
			drew = true
			table.emit("dealer hits: %s", &table.dealer)
		}
	}
	if drew && table.dealer.total().value > 21 {
		table.dealerBusts++
	}
	table.settle(false)
}

func (table *Table) advance() {
	for {
		turn, ok := table.current()
		if !ok {
			table.dealerTurn()
			return
		}
		if len(turn.hand.cards) != 1 {
			return
		}
		turn.hand.cards = append(turn.hand.cards, table.shoe.draw(true))
		table.emit("%s: %s", turn.name(), turn.hand)
		table.finishCheck(turn.player, turn.hand)
		if !turn.hand.finished {
			return
		}
	}
}

func (table *Table) peek() {
	natural := table.dealer.blackjack()
	if natural {
		table.emit("dealer peeks: blackjack")
	} else {
		table.emit("dealer peeks: no blackjack")
	}
	for _, player := range table.participants {
		if player.insurance == 0 {
			continue
		}
		profit := -player.insurance
		if natural {
			profit = player.insurance * 2
		}
		player.bankroll += player.insurance + profit
		player.net += profit
		table.emit("%s insurance %+d", player.name, profit)
	}
	if natural {
		table.dealerBlackjacks++
		table.reveal()
		table.settle(true)
	} else {
		table.state = play
		table.advance()
	}
}

func (table *Table) deal() {
	if table.shoe.drawn >= table.shoe.cut(table.rules.pen) {
		table.shoe.shuffle()
		table.emit("shuffle")
	}
	table.round++
	table.emit("round %d", table.round)
	table.participants = nil
	for _, player := range table.seated() {
		if player.bet != 0 {
			table.participants = append(table.participants, player)
			player.bankroll -= player.bet + player.side
			player.insurance = 0
			player.stats.rounds++
			player.hands = []*Hand{{bet: player.bet}}
		}
	}
	table.dealer = Hand{}
	table.holeVisible = false
	for _, player := range table.participants {
		player.hands[0].cards = append(player.hands[0].cards, table.shoe.draw(true))
	}
	table.dealer.cards = append(table.dealer.cards, table.shoe.draw(true))
	for _, player := range table.participants {
		hand := player.hands[0]
		hand.cards = append(hand.cards, table.shoe.draw(true))
		hand.finished = hand.blackjack()
	}
	table.dealer.cards = append(table.dealer.cards, table.shoe.draw(false))
	for _, player := range table.participants {
		table.emit("%s: %s", player.handName(0), player.hands[0])
	}
	table.emit("dealer: %s ??", table.dealer.cards[0])
	for _, player := range table.participants {
		if player.side == 0 {
			continue
		}
		a, b := player.hands[0].cards[0], player.hands[0].cards[1]
		result, multiplier := "lose", Money(-1)
		if a.rank == b.rank {
			switch {
			case a.suit == b.suit:
				result, multiplier = "perfect", 25
			case a.black() == b.black():
				result, multiplier = "colored", 12
			default:
				result, multiplier = "mixed", 6
			}
		}
		profit := player.side * multiplier
		player.bankroll += player.side + profit
		player.net += profit
		table.emit("%s side %s %+d", player.name, result, profit)
	}
	switch table.dealer.cards[0].point() {
	case 1:
		table.state = insurance
		table.insuranceTurn = 0
		table.emit("insurance offered")
	case 10:
		table.peek()
	default:
		table.state = play
		table.advance()
	}
}

func (table *Table) actionProblem(action Action, player *Player, hand *Hand) string {
	switch action {
	case hitAction:
		if hand.splitAces {
			return "split aces"
		}
	case doubleAction:
		if hand.splitAces {
			return "split aces"
		}
		if len(hand.cards) != 2 {
			return "two cards only"
		}
		total := hand.total()
		low := 9
		if table.rules.doubling == doubleHard10 {
			low = 10
		}
		if table.rules.doubling != doubleAny && (total.soft || total.value < low || total.value > 11) || !table.rules.das && hand.split {
			return "double not allowed"
		}
		if player.bankroll < hand.bet {
			return "insufficient funds"
		}
	case splitAction:
		if len(hand.cards) != 2 {
			return "two cards only"
		}
		if hand.cards[0].point() != hand.cards[1].point() {
			return "not a pair"
		}
		if len(player.hands) >= table.rules.hands {
			return "hand limit"
		}
		if player.bankroll < hand.bet {
			return "insufficient funds"
		}
	case surrenderAction:
		if !table.rules.surrender || hand.split {
			return "surrender not allowed"
		}
		if len(hand.cards) != 2 {
			return "two cards only"
		}
	}
	return ""
}

func (table *Table) recommend() Action {
	turn, _ := table.current()
	hand, player := turn.hand, turn.player
	possible := func(action Action) bool { return table.actionProblem(action, player, hand) == "" }
	up := table.dealer.cards[0].point()
	if up == 1 {
		up = 11
	}
	if hand.splitAces {
		if possible(splitAction) {
			return splitAction
		}
		return standAction
	}
	if possible(splitAction) {
		pair := hand.cards[0].point()
		if pair == 1 || pair == 8 || pair == 9 && up != 7 && up != 10 && up != 11 ||
			(pair == 2 || pair == 3 || pair == 7) && up <= 7 || pair == 6 && up <= 6 || pair == 4 && (up == 5 || up == 6) {
			return splitAction
		}
	}
	total := hand.total()
	value, symbol := total.value, "H"
	if total.soft {
		switch {
		case value >= 19:
			symbol = "S"
		case value == 18:
			if up >= 3 && up <= 6 {
				symbol = "Ds"
			} else if up == 2 || up == 7 || up == 8 {
				symbol = "S"
			}
		case value == 17 && up >= 3 && up <= 6,
			(value == 15 || value == 16) && up >= 4 && up <= 6,
			(value == 13 || value == 14) && (up == 5 || up == 6):
			symbol = "D"
		}
	} else {
		switch {
		case value >= 17:
			symbol = "S"
		case value >= 13:
			if up <= 6 {
				symbol = "S"
			} else if value == 16 && up >= 9 || value == 15 && up == 10 {
				symbol = "R"
			}
		case value == 12:
			if up >= 4 && up <= 6 {
				symbol = "S"
			}
		case value == 11 && up <= 10, value == 10 && up <= 9, value == 9 && up >= 3 && up <= 6:
			symbol = "D"
		}
	}
	switch symbol {
	case "S":
		return standAction
	case "D", "Ds":
		if possible(doubleAction) {
			return doubleAction
		}
		if symbol == "Ds" {
			return standAction
		}
	case "R":
		if possible(surrenderAction) {
			return surrenderAction
		}
	}
	return hitAction
}

func (table *Table) perform(action Action) {
	turn, _ := table.current()
	player, hand, name := turn.player, turn.hand, turn.name()
	switch action {
	case splitAction:
		first, second := hand.cards[0], hand.cards[1]
		aces := hand.splitAces || first.rank == 0
		player.bankroll -= hand.bet
		player.stats.splits++
		table.emit("%s splits %s %s", name, first, second)
		firstHand := &Hand{cards: []Card{first}, bet: hand.bet, split: true, splitAces: aces}
		secondHand := &Hand{cards: []Card{second}, bet: hand.bet, split: true, splitAces: aces}
		player.hands[turn.index] = firstHand
		player.hands = slices.Insert(player.hands, turn.index+1, secondHand)
		firstHand.cards = append(firstHand.cards, table.shoe.draw(true))
		table.emit("%s: %s", name, firstHand)
		table.finishCheck(player, firstHand)
	case standAction, surrenderAction:
		hand.finished = true
		verb := "stands"
		if action == surrenderAction {
			hand.reason, verb = surrenderFinish, "surrenders"
		}
		table.emit("%s %s: %s", name, verb, hand)
	case hitAction, doubleAction:
		verb := "hits"
		if action == doubleAction {
			player.bankroll -= hand.bet
			hand.bet *= 2
			player.stats.doubles++
			verb = "doubles"
		}
		hand.cards = append(hand.cards, table.shoe.draw(true))
		table.emit("%s %s: %s", name, verb, hand)
		table.finishCheck(player, hand)
		if action == doubleAction {
			hand.finished = true
		}
	}
	table.advance()
}

func (table *Table) status() {
	switch table.state {
	case idle:
		table.emit("table idle round %d", table.round)
	case insurance:
		table.emit("table insurance round %d next %s", table.round, table.participants[table.insuranceTurn].name)
	case play:
		turn, _ := table.current()
		table.emit("table play round %d turn %s", table.round, turn.name())
	}
	if table.state != idle {
		table.emit("dealer: %s ??", table.dealer.cards[0])
	}
	for _, player := range table.seated() {
		table.emit("seat %d %s bankroll %d bet %d side %d", player.seat+1, player.name, player.bankroll, player.bet, player.side)
		if table.state != idle && slices.Contains(table.participants, player) {
			for index, hand := range player.hands {
				table.emit("%s: %s bet %d", player.handName(index), hand, hand.bet)
			}
		}
	}
}

func (table *Table) execute(words []string) ([]string, error) {
	table.output = nil
	command, err := parseCommand(words[0])
	if err != nil {
		return nil, err
	}
	var player *Player
	var amount, seed int64
	var proposed Rules
	switch command {
	case shoeCommand:
		amount, err = integer(words[1], 1, 8)
		if err != nil {
			return nil, err
		}
		seed, err = integer(words[2], 1, 2147483646)
	case ruleCommand:
		proposed, err = table.rules.changed(words[1], words[2])
	case playerCommand:
		name := words[1]
		if len(name) == 0 || len(name) > 8 {
			return nil, fmt.Errorf("bad name %s", name)
		}
		for i := range len(name) {
			if name[i] < 'A' || name[i] > 'Z' {
				return nil, fmt.Errorf("bad name %s", name)
			}
		}
		amount, err = integer(words[2], 1, 1000000)
	default:
		if command.namedPlayer() {
			player = table.find(words[1])
			if player == nil {
				return nil, fmt.Errorf("unknown player %s", words[1])
			}
			switch command {
			case rebuyCommand:
				amount, err = integer(words[2], 1, 1000000)
			case betCommand, sideCommand, insuranceCommand:
				amount, err = integer(words[2], 0, 1000000)
			}
		}
	}
	if err != nil {
		return nil, err
	}
	if command.idleOnly() && table.state != idle {
		return nil, errors.New("round in progress")
	}
	if command == insuranceCommand && table.state != insurance {
		return nil, errors.New("no insurance")
	}
	action := command.action()
	if action != "" || command == autoCommand || command == hintCommand {
		if table.state == idle {
			return nil, errors.New("no round")
		}
		if table.state == insurance {
			return nil, errors.New("insurance pending")
		}
	}
	if action != "" || command == autoCommand {
		turn, _ := table.current()
		if turn.player != player {
			return nil, fmt.Errorf("waiting for %s", turn.name())
		}
		if action != "" {
			if problem := table.actionProblem(action, player, turn.hand); problem != "" {
				return nil, errors.New(problem)
			}
			table.perform(action)
		} else {
			for table.state == play {
				turn, _ := table.current()
				if turn.player != player {
					break
				}
				table.perform(table.recommend())
			}
		}
		return table.output, nil
	}
	switch command {
	case shoeCommand:
		table.shoe = newShoe(int(amount), seed)
		table.emit("shoe %d decks %d cards cut %d", amount, len(table.shoe.cards), table.shoe.cut(table.rules.pen))
	case ruleCommand:
		if proposed.minimum > proposed.maximum {
			return nil, errors.New("min above max")
		}
		table.rules = proposed
		table.emit("rule %s %s", words[1], words[2])
	case rulesCommand:
		table.emit("%s", table.rules)
	case playerCommand:
		if table.find(words[1]) != nil {
			return nil, errors.New("player exists")
		}
		seat := slices.Index(table.seats[:], (*Player)(nil))
		if seat < 0 {
			return nil, errors.New("table full")
		}
		table.seats[seat] = &Player{name: words[1], seat: seat, bankroll: Money(amount)}
		table.emit("%s sits at seat %d with %d", words[1], seat+1, amount)
	case leaveCommand:
		table.emit("%s leaves with %d net %+d", player.name, player.bankroll, player.net)
		table.seats[player.seat] = nil
	case rebuyCommand:
		player.bankroll += Money(amount)
		table.emit("%s rebuys %d bankroll %d", player.name, amount, player.bankroll)
	case betCommand:
		if amount != 0 {
			if Money(amount) < table.rules.minimum || Money(amount) > table.rules.maximum {
				return nil, errors.New("bet out of limits")
			}
			if Money(amount)+player.side > player.bankroll {
				return nil, errors.New("insufficient funds")
			}
		}
		player.bet = Money(amount)
		if amount == 0 {
			player.side = 0
			table.emit("%s bet cleared", player.name)
		} else {
			table.emit("%s bets %d", player.name, amount)
		}
	case sideCommand:
		if amount != 0 {
			if player.bet == 0 {
				return nil, errors.New("no bet")
			}
			if Money(amount) > table.rules.sideMaximum {
				return nil, errors.New("side out of limits")
			}
			if player.bet+Money(amount) > player.bankroll {
				return nil, errors.New("insufficient funds")
			}
		}
		player.side = Money(amount)
		if amount == 0 {
			table.emit("%s side cleared", player.name)
		} else {
			table.emit("%s side %d", player.name, amount)
		}
	case dealCommand:
		if table.shoe == nil {
			return nil, errors.New("no shoe")
		}
		hasBet := false
		for _, player := range table.seated() {
			hasBet = hasBet || player.bet != 0
		}
		if !hasBet {
			return nil, errors.New("no bets")
		}
		table.deal()
	case insuranceCommand:
		if player != table.participants[table.insuranceTurn] {
			return nil, fmt.Errorf("waiting for %s", table.participants[table.insuranceTurn].name)
		}
		if Money(amount) > player.bet/2 {
			return nil, errors.New("insurance out of limits")
		}
		if Money(amount) > player.bankroll {
			return nil, errors.New("insufficient funds")
		}
		player.bankroll -= Money(amount)
		player.insurance = Money(amount)
		if amount == 0 {
			table.emit("%s declines insurance", player.name)
		} else {
			table.emit("%s insures %d", player.name, amount)
		}
		table.insuranceTurn++
		if table.insuranceTurn == len(table.participants) {
			table.peek()
		}
	case hintCommand:
		turn, _ := table.current()
		table.emit("hint %s: %s", turn.name(), table.recommend())
	case statusCommand:
		table.status()
	case countCommand:
		if table.shoe == nil {
			return nil, errors.New("no shoe")
		}
		remaining := len(table.shoe.cards) - table.shoe.drawn
		running := table.shoe.running
		magnitude, sign := running, ""
		if running < 0 {
			magnitude, sign = -running, "-"
		}
		scaled := int64(magnitude) * 5200 / int64(remaining)
		table.emit("count running %d true %s%d.%02d remaining %d", running, sign, scaled/100, scaled%100, remaining)
	case statsCommand:
		players := table.seated()
		if len(players) == 0 {
			return nil, errors.New("no players")
		}
		for _, player := range players {
			table.emit("stats %s %s net %+d", player.name, player.stats, player.net)
		}
		table.emit("stats dealer rounds %d blackjacks %d busts %d", table.round, table.dealerBlackjacks, table.dealerBusts)
	}
	return table.output, nil
}

func main() {
	input := bufio.NewReader(os.Stdin)
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	line, _ := input.ReadString('\n')
	count, _ := strconv.Atoi(strings.TrimSpace(line))
	table := Table{rules: defaultRules()}
	for range count {
		line, _ = input.ReadString('\n')
		lines, err := table.execute(strings.Fields(line))
		if err != nil {
			fmt.Fprintf(output, "error: %s\n", err)
		} else {
			for _, result := range lines {
				fmt.Fprintln(output, result)
			}
		}
	}
}
