package main

import (
	"bufio"
	"errors"
	"fmt"
	"maps"
	"os"
	"slices"
	"strconv"
	"strings"
)

var directions = [...]string{"north", "south", "east", "west", "up", "down"}

func direction(word string) int {
	for i, name := range directions {
		if word == name || word == name[:1] {
			return i
		}
	}
	return -1
}

func number(text string) int { value, _ := strconv.Atoi(text); return value }

func words(line string) []string {
	result := strings.Fields(strings.ToLower(line))
	return slices.DeleteFunc(result, func(word string) bool { return word == "the" || word == "a" || word == "an" })
}

func all(phrase []string) bool { return len(phrase) == 1 && phrase[0] == "all" }

type PlaceKind uint8

const (
	nowhere PlaceKind = iota
	floor
	player
	inside
)

type Place struct {
	kind  PlaceKind
	index int
}

var held = Place{kind: player}

type ContainerState uint8

const (
	open ContainerState = iota
	closed
	locked
)

func (state ContainerState) String() string { return [...]string{"open", "closed", "locked"}[state] }

type Exit struct {
	exists      bool
	destination int
	key         int
	locked      bool
}

type EndStatus uint8

const (
	playing EndStatus = iota
	won
	dead
)

type State struct {
	room                       int
	places                     []Place
	containers                 []ContainerState
	fuel                       []int
	lit                        []bool
	exits                      [][6]Exit
	flags                      map[string]bool
	visited                    []bool
	bonus, moves, darkness     int
	ended                      EndStatus
}

func newState(rooms, items int) State {
	return State{places: make([]Place, items), containers: make([]ContainerState, items), fuel: make([]int, items),
		lit: make([]bool, items), exits: make([][6]Exit, rooms), flags: make(map[string]bool), visited: make([]bool, rooms)}
}

func (state State) clone() State {
	state.places = slices.Clone(state.places)
	state.containers = slices.Clone(state.containers)
	state.fuel = slices.Clone(state.fuel)
	state.lit = slices.Clone(state.lit)
	state.exits = slices.Clone(state.exits)
	state.flags = maps.Clone(state.flags)
	state.visited = slices.Clone(state.visited)
	return state
}

type Room struct {
	name        string
	dark        bool
	description []string
}

type Item struct {
	name                      string
	nouns, nameWords          map[string]bool
	details                   []string
	weight, treasure, capacity int
	key                       int
	light, fixed              bool
}

type Trigger struct {
	enter         bool
	first, second int
}

type EffectKind uint8

const (
	messageEffect EffectKind = iota
	openEffect
	moveEffect
	flagEffect
	pointsEffect
)

type Effect struct {
	kind                         EffectKind
	text                         string
	room, direction, destination int
	item, points                 int
	place                        Place
	on                           bool
}

type Rule struct {
	trigger   Trigger
	flag      string
	expected  bool
	effect    Effect
}

func readRule(input []string, at int, trigger Trigger, rooms, items map[string]int) Rule {
	rule := Rule{trigger: trigger}
	if input[at] == "IF" || input[at] == "UNLESS" {
		rule.flag, rule.expected = input[at+1], input[at] == "IF"
		at += 2
	}
	switch input[at] {
	case "MESSAGE":
		rule.effect = Effect{kind: messageEffect, text: strings.Join(input[at+1:], " ")}
	case "OPEN":
		rule.effect = Effect{kind: openEffect, room: rooms[input[at+1]], direction: direction(input[at+2]), destination: rooms[input[at+3]]}
	case "REMOVE":
		rule.effect = Effect{kind: moveEffect, item: items[input[at+1]], place: Place{kind: nowhere}}
	case "ADD":
		rule.effect = Effect{kind: moveEffect, item: items[input[at+1]], place: Place{floor, rooms[input[at+2]]}}
	case "SET", "CLEAR":
		rule.effect = Effect{kind: flagEffect, text: input[at+1], on: input[at] == "SET"}
	case "POINTS":
		rule.effect = Effect{kind: pointsEffect, points: number(input[at+1])}
	}
	return rule
}

type Verb uint8

const (
	unknown Verb = iota
	goVerb
	look
	examine
	take
	drop
	put
	inventory
	openVerb
	closeVerb
	unlock
	lock
	use
	light
	extinguish
	wait
	score
	save
	restore
	verbose
	brief
)

func (verb Verb) String() string {
	return [...]string{"", "go", "look", "examine", "take", "drop", "put", "inventory", "open", "close", "unlock", "lock",
		"use", "light", "extinguish", "wait", "score", "save", "restore", "verbose", "brief"}[verb]
}

func parseVerb(word string) Verb {
	switch word {
	case "go", "walk", "run": return goVerb
	case "look", "l": return look
	case "examine", "x", "inspect", "read": return examine
	case "take", "get", "grab": return take
	case "drop", "discard": return drop
	case "put", "insert", "place": return put
	case "inventory", "inv", "i": return inventory
	case "open": return openVerb
	case "close", "shut": return closeVerb
	case "unlock": return unlock
	case "lock": return lock
	case "use", "apply": return use
	case "light", "ignite": return light
	case "extinguish", "douse", "snuff": return extinguish
	case "wait", "z": return wait
	case "score": return score
	case "save": return save
	case "restore", "load": return restore
	case "verbose": return verbose
	case "brief": return brief
	}
	return unknown
}

func (verb Verb) noArguments() bool {
	switch verb {
	case look, inventory, wait, score, save, restore, verbose, brief: return true
	}
	return false
}

func (verb Verb) action() bool {
	switch verb {
	case goVerb, take, drop, put, openVerb, closeVerb, unlock, lock, use, light, extinguish, wait: return true
	}
	return false
}

type Adventure struct {
	rooms             []Room
	items             []Item
	rules             []Rule
	vocabulary        map[string]bool
	trophy, maxWeight int
	state             State
	saved             *State
	pronoun           int
	previous          string
	verbose           bool
	output            []string
}

func newAdventure(definitions [][]string) *Adventure {
	roomIDs, itemIDs := make(map[string]int), make(map[string]int)
	var itemNames []string
	for _, w := range definitions {
		if w[0] == "ROOM" { roomIDs[w[1]] = len(roomIDs) }
		if w[0] == "ITEM" { itemNames = append(itemNames, w[1]) }
	}
	slices.Sort(itemNames)
	game := &Adventure{rooms: make([]Room, len(roomIDs)), items: make([]Item, len(itemNames)),
		vocabulary: make(map[string]bool), pronoun: -1, state: newState(len(roomIDs), len(itemNames))}
	for i, id := range itemNames {
		itemIDs[id] = i
		game.items[i] = Item{nouns: map[string]bool{id: true}, nameWords: make(map[string]bool), key: -1}
	}
	for _, w := range definitions {
		switch w[0] {
		case "ROOM":
			room := &game.rooms[roomIDs[w[1]]]
			room.dark = w[2] == "DARK"
			at := 2
			if room.dark { at++ }
			room.name = strings.Join(w[at:], " ")
		case "DESC":
			room := &game.rooms[roomIDs[w[1]]]
			room.description = append(room.description, strings.Join(w[2:], " "))
		case "EXIT":
			exit := Exit{exists: true, destination: roomIDs[w[3]], key: -1, locked: len(w) > 4}
			if exit.locked { exit.key = itemIDs[w[5]] }
			game.state.exits[roomIDs[w[1]]][direction(w[2])] = exit
		case "ITEM":
			x := itemIDs[w[1]]
			switch w[2] {
			case "PLAYER": game.state.places[x] = held
			case "NOWHERE": game.state.places[x] = Place{kind: nowhere}
			default: game.state.places[x] = Place{floor, roomIDs[w[2]]}
			}
			item, at := &game.items[x], 4
			item.weight = number(w[3])
			if w[at] == "TREASURE" { item.treasure = number(w[at+1]); at += 2 }
			if w[at] == "LIGHT" { item.light = true; game.state.fuel[x] = number(w[at+1]); at += 2 }
			if w[at] == "CONTAINER" {
				item.capacity = number(w[at+1]); at += 2
				if w[at] == "CLOSED" { game.state.containers[x] = closed; at++ }
				if w[at] == "LOCKED" { item.key = itemIDs[w[at+1]]; game.state.containers[x] = locked; at += 2 }
			}
			if w[at] == "FIXED" { item.fixed = true; at++ }
			item.name = strings.Join(w[at:], " ")
			for _, word := range w[at:] { item.nameWords[word] = true }
		case "INSIDE": game.state.places[itemIDs[w[1]]] = Place{inside, itemIDs[w[2]]}
		case "ALIAS": game.items[itemIDs[w[1]]].nouns[w[2]] = true
		case "DETAIL":
			item := &game.items[itemIDs[w[1]]]
			item.details = append(item.details, strings.Join(w[2:], " "))
		case "RULE": game.rules = append(game.rules, readRule(w, 3, Trigger{first: itemIDs[w[1]], second: itemIDs[w[2]]}, roomIDs, itemIDs))
		case "ENTER": game.rules = append(game.rules, readRule(w, 2, Trigger{enter: true, first: roomIDs[w[1]]}, roomIDs, itemIDs))
		case "TROPHY": game.trophy = roomIDs[w[1]]
		case "START": game.state.room = roomIDs[w[1]]
		case "MAXWEIGHT": game.maxWeight = number(w[1])
		}
	}
	game.state.visited[game.state.room] = true
	for _, item := range game.items {
		maps.Copy(game.vocabulary, item.nouns)
		maps.Copy(game.vocabulary, item.nameWords)
	}
	return game
}

func (game *Adventure) say(text string) { game.output = append(game.output, text) }
func (game *Adventure) sayf(format string, args ...any) { game.say(fmt.Sprintf(format, args...)) }
func (game *Adventure) floor() Place { return Place{floor, game.state.room} }

func (game *Adventure) direct(place Place) []int {
	var result []int
	for i, at := range game.state.places {
		if at == place { result = append(result, i) }
	}
	return result
}

func (game *Adventure) reachable(item int, root Place) bool {
	place := game.state.places[item]
	for place.kind == inside {
		if game.state.containers[place.index] != open { return false }
		place = game.state.places[place.index]
	}
	return place == root
}

func (game *Adventure) carried(item int) bool { return game.reachable(item, held) }
func (game *Adventure) roomItem(item int) bool { return game.reachable(item, game.floor()) }

func (game *Adventure) isLit() bool {
	if !game.rooms[game.state.room].dark { return true }
	for i, lit := range game.state.lit {
		if lit && (game.carried(i) || game.roomItem(i)) { return true }
	}
	return false
}

func (game *Adventure) totalWeight(item int) int { return game.items[item].weight + game.placeWeight(Place{inside, item}) }

func (game *Adventure) placeWeight(place Place) int {
	weight := 0
	for _, item := range game.direct(place) { weight += game.totalWeight(item) }
	return weight
}

func (game *Adventure) within(item, ancestor int) bool {
	for place := game.state.places[item]; place.kind == inside; place = game.state.places[place.index] {
		if place.index == ancestor { return true }
	}
	return false
}

func (game *Adventure) stored(item int) bool {
	place := game.state.places[item]
	for place.kind == inside { place = game.state.places[place.index] }
	return place == (Place{floor, game.trophy})
}

func (game *Adventure) treasures() (points, stored, total int) {
	for i, item := range game.items {
		if item.treasure > 0 {
			total++
			if game.stored(i) { stored++; points += item.treasure }
		}
	}
	return
}

func (game *Adventure) score() int { points, _, _ := game.treasures(); return points + game.state.bonus }

func (game *Adventure) displayName(item int) string {
	var annotations []string
	if game.items[item].capacity > 0 { annotations = append(annotations, game.state.containers[item].String()) }
	if game.state.lit[item] { annotations = append(annotations, "lit") }
	if len(annotations) == 0 { return game.items[item].name }
	return fmt.Sprintf("%s (%s)", game.items[item].name, strings.Join(annotations, ", "))
}

func (game *Adventure) itemTree(place Place, depth int) {
	for _, item := range game.direct(place) {
		game.say(strings.Repeat("  ", depth) + game.displayName(item))
		if game.items[item].capacity > 0 && game.state.containers[item] == open { game.itemTree(Place{inside, item}, depth+1) }
	}
}

func (game *Adventure) describe(full bool) {
	if !game.isLit() { game.say("It is pitch dark."); return }
	room := game.rooms[game.state.room]
	game.say(room.name)
	if full { game.output = append(game.output, room.description...) }
	var exits []string
	for d, exit := range game.state.exits[game.state.room] {
		if exit.exists {
			name := directions[d]
			if exit.locked { name += " (locked)" }
			exits = append(exits, name)
		}
	}
	if len(exits) == 0 { exits = append(exits, "none") }
	game.say("Exits: " + strings.Join(exits, ", "))
	if len(game.direct(game.floor())) > 0 { game.say("You see:"); game.itemTree(game.floor(), 1) }
}

func (game *Adventure) resolve(phrase []string) (int, error) {
	lit := game.isLit()
	if len(phrase) == 1 && phrase[0] == "it" {
		if game.pronoun < 0 { return 0, errors.New("I don't know what \"it\" refers to.") }
		if !game.carried(game.pronoun) && !(lit && game.roomItem(game.pronoun)) { return 0, errors.New("You can't see any such thing.") }
		return game.pronoun, nil
	}
	for _, word := range phrase {
		if !game.vocabulary[word] { return 0, fmt.Errorf("I don't know the word \"%s\".", word) }
	}
	var matches []int
	for i, item := range game.items {
		if !(game.carried(i) || lit && game.roomItem(i)) || !item.nouns[phrase[len(phrase)-1]] { continue }
		if slices.ContainsFunc(phrase[:len(phrase)-1], func(word string) bool { return !item.nameWords[word] }) { continue }
		matches = append(matches, i)
	}
	if len(matches) == 0 { return 0, errors.New("You can't see any such thing.") }
	if len(matches) > 1 {
		var names []string
		for _, i := range matches { names = append(names, game.items[i].name) }
		return 0, fmt.Errorf("Which do you mean: %s?", strings.Join(names, ", "))
	}
	game.pronoun = matches[0]
	return matches[0], nil
}

func (game *Adventure) runRules(trigger Trigger) (executed int, message bool) {
	for _, rule := range game.rules {
		if rule.trigger != trigger || rule.flag != "" && game.state.flags[rule.flag] != rule.expected { continue }
		executed++
		effect := rule.effect
		switch effect.kind {
		case messageEffect: game.say(effect.text); message = true
		case openEffect: game.state.exits[effect.room][effect.direction] = Exit{exists: true, destination: effect.destination, key: -1}
		case moveEffect: game.state.places[effect.item] = effect.place
		case flagEffect:
			if effect.on { game.state.flags[effect.text] = true } else { delete(game.state.flags, effect.text) }
		case pointsEffect: game.state.bonus += effect.points
		}
	}
	return
}

func (game *Adventure) turn(baseline bool) {
	game.state.moves++
	nearby := make([]bool, len(game.items))
	for i := range nearby { nearby[i] = game.carried(i) || game.roomItem(i) }
	for i, present := range nearby {
		if game.state.lit[i] {
			game.state.fuel[i]--
			if game.state.fuel[i] == 0 {
				game.state.lit[i] = false
				if present { game.sayf("The %s goes out.", game.items[i].name) }
			}
		}
	}
	lit := game.isLit()
	if baseline && !lit { game.say("It is now pitch dark.") } else if !baseline && lit { game.describe(true) }
	if lit { game.state.darkness = 0 } else { game.state.darkness++ }
	if game.state.darkness == 2 { game.say("You hear something moving in the dark.") }
	if game.state.darkness == 3 { game.state.ended = dead }
	points, stored, total := game.treasures()
	if game.state.ended == playing && total > 0 && stored == total { game.state.ended = won }
	if game.state.ended != playing {
		if game.state.ended == dead { game.say("*** You have died ***") } else { game.say("*** You have won ***") }
		game.sayf("You scored %d points in %d moves.", points+game.state.bonus, game.state.moves)
	}
}

func (game *Adventure) requireContainer(item int) error {
	if game.items[item].capacity == 0 { return fmt.Errorf("The %s is not a container.", game.items[item].name) }
	if game.state.containers[item] != open { return fmt.Errorf("The %s is closed.", game.items[item].name) }
	return nil
}

func (game *Adventure) putItem(item, container int) error {
	if game.within(container, item) { return fmt.Errorf("The %s is inside the %s.", game.items[container].name, game.items[item].name) }
	if game.state.places[item] == (Place{inside, container}) { return fmt.Errorf("The %s is already in the %s.", game.items[item].name, game.items[container].name) }
	weight := game.placeWeight(Place{inside, container})
	if !game.within(item, container) { weight += game.totalWeight(item) }
	if weight > game.items[container].capacity { return fmt.Errorf("The %s doesn't fit in the %s.", game.items[item].name, game.items[container].name) }
	game.state.places[item] = Place{inside, container}
	return nil
}

func (game *Adventure) take(target, from []string) (bool, error) {
	if !game.isLit() { return false, errors.New("It is pitch dark.") }
	container, source := -1, game.floor()
	if len(from) > 0 {
		var err error
		container, err = game.resolve(from)
		if err != nil { return false, err }
		if err = game.requireContainer(container); err != nil { return false, err }
		source = Place{inside, container}
	}
	if all(target) {
		candidates := slices.DeleteFunc(game.direct(source), func(i int) bool { return game.items[i].fixed })
		if len(candidates) == 0 {
			if container < 0 { return false, errors.New("There is nothing here to take.") }
			return false, fmt.Errorf("There is nothing in the %s to take.", game.items[container].name)
		}
		taken := false
		for _, item := range candidates {
			if !game.carried(item) && game.placeWeight(held)+game.totalWeight(item) > game.maxWeight {
				game.sayf("%s: You can't carry any more.", game.items[item].name)
			} else {
				game.state.places[item] = held
				game.sayf("%s: Taken.", game.items[item].name)
				taken = true
			}
		}
		return taken, nil
	}
	item, err := game.resolve(target)
	if err != nil { return false, err }
	if container >= 0 && game.state.places[item] != source { return false, fmt.Errorf("The %s is not in the %s.", game.items[item].name, game.items[container].name) }
	if game.state.places[item] == held { return false, fmt.Errorf("You already have the %s.", game.items[item].name) }
	if game.items[item].fixed { return false, fmt.Errorf("The %s is fixed in place.", game.items[item].name) }
	if !game.carried(item) && game.placeWeight(held)+game.totalWeight(item) > game.maxWeight { return false, errors.New("You can't carry any more.") }
	game.state.places[item] = held
	game.say("Taken.")
	return true, nil
}

func (game *Adventure) drop(target []string) error {
	if all(target) {
		candidates := game.direct(held)
		if len(candidates) == 0 { return errors.New("You are empty-handed.") }
		for _, item := range candidates { game.state.places[item] = game.floor(); game.sayf("%s: Dropped.", game.items[item].name) }
	} else {
		item, err := game.resolve(target)
		if err != nil { return err }
		if !game.carried(item) { return fmt.Errorf("You aren't carrying the %s.", game.items[item].name) }
		game.state.places[item] = game.floor()
		game.say("Dropped.")
	}
	return nil
}

func (game *Adventure) put(first, second []string) (bool, error) {
	item := -1
	var err error
	if !all(first) { item, err = game.resolve(first); if err != nil { return false, err } }
	container, err := game.resolve(second)
	if err != nil { return false, err }
	if item >= 0 {
		if !game.carried(item) { return false, fmt.Errorf("You aren't carrying the %s.", game.items[item].name) }
		if item == container { return false, fmt.Errorf("You can't put the %s inside itself.", game.items[item].name) }
	}
	if err = game.requireContainer(container); err != nil { return false, err }
	if item >= 0 {
		if err = game.putItem(item, container); err != nil { return false, err }
		game.sayf("You put the %s in the %s.", game.items[item].name, game.items[container].name)
		return true, nil
	}
	candidates := slices.DeleteFunc(game.direct(held), func(i int) bool { return i == container })
	if len(candidates) == 0 { return false, fmt.Errorf("You have nothing to put in the %s.", game.items[container].name) }
	moved := false
	for _, item := range candidates {
		message := "Done."
		if err := game.putItem(item, container); err != nil { message = err.Error() } else { moved = true }
		game.sayf("%s: %s", game.items[item].name, message)
	}
	return moved, nil
}

func (game *Adventure) keyCheck(key int, phrase []string) error {
	if len(phrase) == 0 {
		if !game.carried(key) { return errors.New("You don't have the right key.") }
		game.sayf("(with the %s)", game.items[key].name)
	} else {
		item, err := game.resolve(phrase)
		if err != nil { return err }
		if !game.carried(item) { return fmt.Errorf("You aren't carrying the %s.", game.items[item].name) }
		if item != key { return fmt.Errorf("The %s doesn't fit.", game.items[item].name) }
	}
	return nil
}

func (game *Adventure) changeLock(target, keyPhrase []string, locking bool) error {
	d, status := -1, "not locked"
	if len(target) == 1 { d = direction(target[0]) }
	if locking { status = "already locked" }
	if d >= 0 {
		exit := game.state.exits[game.state.room][d]
		if !exit.exists { return fmt.Errorf("There is no exit %s.", directions[d]) }
		if exit.key < 0 { return fmt.Errorf("The way %s has no lock.", directions[d]) }
		if exit.locked == locking { return fmt.Errorf("The way %s is %s.", directions[d], status) }
		if err := game.keyCheck(exit.key, keyPhrase); err != nil { return err }
		exit.locked = locking
		game.state.exits[game.state.room][d] = exit
		opposite := game.state.exits[exit.destination][d^1]
		if opposite.exists && opposite.destination == game.state.room && opposite.key == exit.key {
			opposite.locked = locking
			game.state.exits[exit.destination][d^1] = opposite
		}
	} else {
		item, err := game.resolve(target)
		if err != nil { return err }
		if game.items[item].capacity == 0 || game.items[item].key < 0 { return fmt.Errorf("The %s has no lock.", game.items[item].name) }
		if (game.state.containers[item] == locked) == locking { return fmt.Errorf("The %s is %s.", game.items[item].name, status) }
		if locking && game.state.containers[item] == open { return fmt.Errorf("You must close the %s first.", game.items[item].name) }
		if err := game.keyCheck(game.items[item].key, keyPhrase); err != nil { return err }
		game.state.containers[item] = closed
		if locking { game.state.containers[item] = locked }
	}
	if locking { game.say("Locked.") } else { game.say("Unlocked.") }
	return nil
}

func (game *Adventure) examine(item int) {
	definition := game.items[item]
	if len(definition.details) == 0 { game.sayf("You see nothing special about the %s.", definition.name) } else { game.output = append(game.output, definition.details...) }
	if definition.light {
		status := "unlit"
		if game.state.lit[item] { status = "lit" }
		game.sayf("It is %s (fuel %d).", status, game.state.fuel[item])
	}
	if definition.capacity > 0 {
		switch game.state.containers[item] {
		case locked: game.say("It is locked.")
		case closed: game.say("It is closed.")
		case open:
			if len(game.direct(Place{inside, item})) == 0 { game.say("It is empty.") } else { game.say("It contains:"); game.itemTree(Place{inside, item}, 1) }
		}
	}
	if definition.treasure > 0 { game.sayf("It is a treasure worth %d points.", definition.treasure) }
	game.sayf("It weighs %d.", game.totalWeight(item))
}

func (game *Adventure) execute(verb Verb, first, second []string, d int, baseline *bool) (bool, error) {
	switch verb {
	case goVerb:
		exit := game.state.exits[game.state.room][d]
		if !exit.exists { return false, errors.New("You can't go that way.") }
		if exit.locked { return false, fmt.Errorf("The way %s is locked.", directions[d]) }
		game.state.room = exit.destination
		*baseline = game.isLit()
		game.describe(game.verbose || !game.state.visited[game.state.room])
		game.state.visited[game.state.room] = true
		game.runRules(Trigger{enter: true, first: game.state.room})
	case look: game.describe(true)
	case examine:
		item, err := game.resolve(first)
		if err != nil { return false, err }
		game.examine(item)
	case take: return game.take(first, second)
	case drop: if err := game.drop(first); err != nil { return false, err }
	case put: return game.put(first, second)
	case inventory:
		if len(game.direct(held)) == 0 { game.say("You are empty-handed.") } else {
			game.say("You are carrying:"); game.itemTree(held, 1)
			game.sayf("Total weight: %d/%d", game.placeWeight(held), game.maxWeight)
		}
	case openVerb:
		item, err := game.resolve(first)
		if err != nil { return false, err }
		if game.items[item].capacity == 0 { return false, fmt.Errorf("You can't open the %s.", game.items[item].name) }
		if game.state.containers[item] == open { return false, fmt.Errorf("The %s is already open.", game.items[item].name) }
		if game.state.containers[item] == locked { return false, fmt.Errorf("The %s is locked.", game.items[item].name) }
		game.state.containers[item] = open
		var names []string
		for _, child := range game.direct(Place{inside, item}) { names = append(names, game.items[child].name) }
		if len(names) == 0 { game.say("Opened.") } else { game.sayf("Opening the %s reveals %s.", game.items[item].name, strings.Join(names, ", ")) }
	case closeVerb:
		item, err := game.resolve(first)
		if err != nil { return false, err }
		if game.items[item].capacity == 0 { return false, fmt.Errorf("You can't close the %s.", game.items[item].name) }
		if game.state.containers[item] != open { return false, fmt.Errorf("The %s is already closed.", game.items[item].name) }
		game.state.containers[item] = closed
		game.say("Closed.")
	case unlock, lock: if err := game.changeLock(first, second, verb == lock); err != nil { return false, err }
	case use:
		a, err := game.resolve(first)
		if err != nil { return false, err }
		b, err := game.resolve(second)
		if err != nil { return false, err }
		if !game.carried(a) { return false, fmt.Errorf("You aren't carrying the %s.", game.items[a].name) }
		executed, message := game.runRules(Trigger{first: a, second: b})
		if executed == 0 { return false, errors.New("Nothing happens.") }
		if !message { game.say("Done.") }
	case light, extinguish:
		item, err := game.resolve(first)
		if err != nil { return false, err }
		lighting := verb == light
		if !game.items[item].light { return false, fmt.Errorf("You can't %s the %s.", verb, game.items[item].name) }
		if game.state.lit[item] == lighting {
			status := "not lit"
			if lighting { status = "already lit" }
			return false, fmt.Errorf("The %s is %s.", game.items[item].name, status)
		}
		if lighting && game.state.fuel[item] == 0 { return false, fmt.Errorf("The %s has no fuel.", game.items[item].name) }
		game.state.lit[item] = lighting
		status := "out"
		if lighting { status = "lit" }
		game.sayf("The %s is now %s.", game.items[item].name, status)
	case wait: game.say("Time passes.")
	case score:
		points, stored, total := game.treasures()
		game.sayf("You have scored %d points (treasure %d, bonus %d) in %d moves.", points+game.state.bonus, points, game.state.bonus, game.state.moves)
		game.sayf("Treasures stored: %d of %d.", stored, total)
	case save:
		copy := game.state.clone()
		game.saved = &copy
		game.say("Game saved.")
	case restore:
		if game.saved == nil { return false, errors.New("There is no saved game.") }
		game.state = game.saved.clone()
		game.say("Game restored.")
		game.describe(true)
	case verbose: game.verbose = true; game.say("Verbose mode.")
	case brief: game.verbose = false; game.say("Brief mode.")
	}
	return true, nil
}

func (game *Adventure) interpret(input []string) error {
	if len(input) == 0 { return errors.New("I beg your pardon?") }
	if direction(input[0]) >= 0 { input = append([]string{"go"}, input...) }
	verb := parseVerb(input[0])
	if verb == unknown { return fmt.Errorf("I don't know the verb \"%s\".", input[0]) }
	if game.state.ended != playing && verb != restore { return errors.New("The game is over.") }
	first, second, d := input[1:], []string(nil), -1
	if verb == look && len(first) > 0 {
		if first[0] != "at" { return errors.New("I don't understand that.") }
		verb, first = examine, first[1:]
	}
	if verb.noArguments() {
		if len(first) > 0 { return errors.New("I don't understand that.") }
	} else {
		if len(first) == 0 {
			if verb == goVerb { return errors.New("Which way do you want to go?") }
			return fmt.Errorf("What do you want to %s?", verb)
		}
		if verb == goVerb {
			if len(first) == 1 { d = direction(first[0]) }
			if d < 0 { return errors.New("I don't understand that.") }
		} else {
			at := slices.IndexFunc(first, func(word string) bool {
				switch verb {
				case put: return word == "in" || word == "into"
				case use: return word == "on" || word == "with"
				case unlock, lock: return word == "with"
				case take: return word == "from"
				}
				return false
			})
			if at >= 0 {
				if at == 0 || at+1 == len(first) { return errors.New("I don't understand that.") }
				first, second = first[:at], first[at+1:]
			} else if verb == put || verb == use { return errors.New("I don't understand that.") }
		}
	}
	baseline := game.isLit()
	succeeded, err := game.execute(verb, first, second, d, &baseline)
	if err != nil { return err }
	if succeeded && verb.action() { game.turn(baseline) }
	return nil
}

func (game *Adventure) dispatch(line string) error {
	input := words(line)
	if len(input) > 0 && (input[0] == "again" || input[0] == "g") {
		if len(input) != 1 { return errors.New("I don't understand that.") }
		if game.previous == "" { return errors.New("There is nothing to repeat.") }
		input = words(game.previous)
	} else { game.previous = line }
	return game.interpret(input)
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	var definitions [][]string
	for input.Scan() {
		if input.Text() == "BEGIN" { break }
		definitions = append(definitions, strings.Fields(input.Text()))
	}
	game := newAdventure(definitions)
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	flush := func() {
		for _, line := range game.output { fmt.Fprintln(output, line) }
		game.output = nil
	}
	game.describe(true)
	flush()
	for input.Scan() {
		line := input.Text()
		if line == "QUIT" { break }
		game.say("> " + line)
		if err := game.dispatch(line); err != nil { game.say(err.Error()) }
		flush()
	}
	fmt.Fprintf(output, "Final score: %d points in %d moves.\n", game.score(), game.state.moves)
}
