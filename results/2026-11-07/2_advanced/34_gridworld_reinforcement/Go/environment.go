package main

import (
	"os"
	"strconv"
	"strings"
)

const actionLetters = "NESW"

var rowSteps = [4]int{-1, 0, 1, 0}
var colSteps = [4]int{0, 1, 0, -1}

type World struct {
	Rows, Cols, Start, StartState                int
	Kinds                                        string
	Wind                                         []int
	Rewards                                      []int64
	States, Terminals, StateIndex, TerminalIndex []int
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(text string) int {
	n, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return n
}
func numbers(words []string) []int {
	values := make([]int, len(words))
	for i, s := range words {
		values[i] = integer(s)
	}
	return values
}
func readWorld() *World {
	lines := readLines("input/world.txt")
	w := &World{Rows: integer(strings.Fields(lines[0])[1]), Cols: integer(strings.Fields(lines[1])[1])}
	w.Kinds = strings.Join(lines[2:2+w.Rows], "")
	w.StateIndex = make([]int, len(w.Kinds))
	w.TerminalIndex = make([]int, len(w.Kinds))
	for i := range w.Kinds {
		w.StateIndex[i] = -1
		w.TerminalIndex[i] = -1
	}
	for cell, kind := range w.Kinds {
		if kind == 'G' || kind == 'P' {
			w.TerminalIndex[cell] = len(w.Terminals)
			w.Terminals = append(w.Terminals, cell)
		} else if kind != '#' {
			w.StateIndex[cell] = len(w.States)
			w.States = append(w.States, cell)
		}
		if kind == 'S' {
			w.Start = cell
			w.StartState = w.StateIndex[cell]
		}
	}
	for _, c := range strings.Fields(lines[2+w.Rows])[1] {
		w.Wind = append(w.Wind, int(c-'0'))
	}
	for _, s := range strings.Fields(lines[3+w.Rows])[1:] {
		w.Rewards = append(w.Rewards, int64(integer(s)))
	}
	return w
}
func (w *World) IsTerminal(cell int) bool { return w.TerminalIndex[cell] >= 0 }
func (w *World) TerminalName(cell int) string {
	if w.Kinds[cell] == 'G' {
		return "goal"
	}
	return "pit"
}
func (w *World) Move(cell, direction int) int {
	target := cell + rowSteps[direction]*w.Cols + colSteps[direction]
	if w.Kinds[target] == '#' {
		target = cell
	}
	if w.IsTerminal(target) {
		return target
	}
	for range w.Wind[cell%w.Cols] {
		above := target - w.Cols
		if w.Kinds[above] == '#' {
			break
		}
		target = above
		if w.IsTerminal(target) {
			break
		}
	}
	return target
}

type RandomGenerator struct{ Value int64 }

func (g *RandomGenerator) Draw() int64 { g.Value = g.Value * 48271 % 2147483647; return g.Value }

type Transition struct {
	Cell      int
	Numerator int64
}
type Environment struct {
	World                                     *World
	StepReward, SlipTotal, FloorSlip, IceSlip int64
	Moves                                     [][4]int
	Transitions                               [][4][]Transition
}

func newEnvironment(w *World, reward, total, floor, ice int64) *Environment {
	e := &Environment{World: w, StepReward: reward, SlipTotal: total, FloorSlip: floor, IceSlip: ice,
		Moves: make([][4]int, len(w.States)), Transitions: make([][4][]Transition, len(w.States))}
	for state, cell := range w.States {
		for d := range 4 {
			e.Moves[state][d] = w.Move(cell, d)
		}
		p := e.Slip(state)
		for a := range 4 {
			for _, outcome := range []struct {
				Direction int
				Weight    int64
			}{{a, total - 2*p}, {(a + 1) % 4, p}, {(a + 3) % 4, p}} {
				if outcome.Weight > 0 {
					e.Transitions[state][a] = append(e.Transitions[state][a], Transition{e.Moves[state][outcome.Direction], outcome.Weight})
				}
			}
		}
	}
	return e
}
func (e *Environment) Slip(state int) int64 {
	if e.World.Kinds[e.World.States[state]] == '~' {
		return e.IceSlip
	}
	return e.FloorSlip
}
func (e *Environment) Reward(cell int) int64 {
	if index := e.World.TerminalIndex[cell]; index >= 0 {
		return e.World.Rewards[index]
	}
	return e.StepReward
}
func (e *Environment) Step(g *RandomGenerator, state, action int) (int, int64) {
	draw, p := g.Draw()%e.SlipTotal, e.Slip(state)
	d := action
	if draw >= e.SlipTotal-p {
		d = (action + 3) % 4
	} else if draw >= e.SlipTotal-2*p {
		d = (action + 1) % 4
	}
	cell := e.Moves[state][d]
	return cell, e.Reward(cell)
}
