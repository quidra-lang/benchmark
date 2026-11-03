package main

import (
	"fmt"
	"strconv"
	"strings"
)

type Point struct{ X, Y int }
type MonsterType struct {
	Name                                                         string
	Symbol                                                       byte
	Index, MinDepth, MaxDepth, Weight, ToHit, Defense, Speed, XP int
	HP, Damage                                                   Dice
	Erratic, Stationary, Regenerates, Poisonous                  bool
}

func number(text string) int {
	value, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return value
}
func newMonsterType(tokens []string, index int) *MonsterType {
	traits := tokens[11]
	return &MonsterType{Name: tokens[0], Symbol: tokens[1][0], Index: index, MinDepth: number(tokens[2]), MaxDepth: number(tokens[3]), Weight: number(tokens[4]), HP: parseDice(tokens[5]), ToHit: number(tokens[6]), Defense: number(tokens[7]), Damage: parseDice(tokens[8]), Speed: number(tokens[9]), XP: number(tokens[10]), Erratic: strings.Contains(traits, "E"), Stationary: strings.Contains(traits, "S"), Regenerates: strings.Contains(traits, "R"), Poisonous: strings.Contains(traits, "P")}
}

type ItemType struct {
	Category, Name, Effect                                           string
	MinDepth, MaxDepth, Weight, ToHit, Armor, PoisonTurns, Nutrition int
	Dice                                                             Dice
}

func parseItemType(tokens []string) *ItemType {
	kind := &ItemType{Category: tokens[0], Name: tokens[1], MinDepth: number(tokens[2]), MaxDepth: number(tokens[3]), Weight: number(tokens[4])}
	args := tokens[5:]
	switch kind.Category {
	case "weapon":
		kind.Dice = parseDice(args[0])
		kind.ToHit = number(args[1])
	case "armor":
		kind.Armor = number(args[0])
	case "potion":
		kind.Effect = args[0]
		if kind.Effect == "heal" {
			kind.Dice = parseDice(args[1])
		} else if kind.Effect == "poison" {
			kind.PoisonTurns = number(args[1])
		}
	case "scroll":
		kind.Effect = args[0]
	case "food":
		kind.Nutrition = number(args[0])
	case "gold":
		kind.Dice = parseDice(args[0])
	}
	return kind
}

type Monster struct {
	ID                 int
	Kind               *MonsterType
	Position           Point
	HP, MaxHP, Energy  int
	Asleep, WasVisible bool
}

type Item struct {
	Kind          *ItemType
	Position      Point
	Amount, Bonus int
}

func (item *Item) Symbol() byte {
	switch item.Kind.Category {
	case "weapon":
		return ')'
	case "armor":
		return '['
	case "potion":
		return '!'
	case "scroll":
		return '?'
	case "food":
		return '%'
	case "gold":
		return '$'
	case "amulet":
		return '"'
	}
	panic("unknown item class")
}
func (item *Item) DisplayName() string {
	name := strings.ReplaceAll(item.Kind.Name, "_", " ")
	if item.Kind.Category == "weapon" || item.Kind.Category == "armor" {
		return fmt.Sprintf("+%d %s", item.Bonus, name)
	}
	if item.Kind.Category == "gold" {
		return fmt.Sprintf("%d gold", item.Amount)
	}
	return name
}
func (item *Item) ReferenceName() string {
	if item.Kind.Category == "gold" {
		return item.DisplayName()
	}
	return "the " + item.DisplayName()
}
