package main

import (
	"strconv"
	"strings"
)

type Dice struct{ Count, Sides int }

func (dice Dice) Roll(rng *Minstd) int { return rng.Roll(dice.Count, dice.Sides) }
func parseDice(text string) Dice {
	first, second, _ := strings.Cut(text, "d")
	count, err := strconv.Atoi(first)
	if err != nil {
		panic(err)
	}
	sides, err := strconv.Atoi(second)
	if err != nil {
		panic(err)
	}
	return Dice{count, sides}
}

func resolveAttack(rng *Minstd, toHit, defense int, dice Dice, bonus int) (string, int) {
	roll := 1 + rng.Rnd(20)
	if roll == 1 {
		return "miss", 0
	}
	outcome, damage := "hit", 0
	if roll == 20 {
		outcome = "critical"
		damage = dice.Roll(rng) + dice.Roll(rng) + bonus
	} else if roll+toHit >= defense {
		damage = dice.Roll(rng) + bonus
	} else {
		return "miss", 0
	}
	return outcome, max(damage, 1)
}
