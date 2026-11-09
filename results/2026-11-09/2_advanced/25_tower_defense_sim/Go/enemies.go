package main

import "strings"

type EnemyType struct {
	Name, Symbol, Movement                    string
	HP, Armor, Speed, Bounty, Lives, Regen    int
	SplitInto                                 *EnemyType
	SplitCount, Spawned, Kills, Leaks, Damage int
}
type Group struct {
	Kind                                      *EnemyType
	Spawn, Count, Delay, Interval, Multiplier int
}

func (g Group) SpawnTick(start, index int) int { return start + g.Delay + index*g.Interval }

type Wave struct {
	Reward int
	Groups []Group
}

func (w *Wave) EnemyCount() int {
	total := 0
	for _, group := range w.Groups {
		total += group.Count
	}
	return total
}
func parseWaves(lines []string) ([]*EnemyType, []*Wave) {
	types := []*EnemyType{}
	known := map[string]*EnemyType{}
	waves := []*Wave{}
	for _, line := range lines {
		fields := strings.Fields(line)
		switch fields[0] {
		case "enemy":
			kind := &EnemyType{Name: fields[1], Symbol: fields[2], Movement: fields[3], HP: integer(fields[4]), Armor: integer(fields[5]), Speed: integer(fields[6]), Bounty: integer(fields[7]), Lives: integer(fields[8]), Regen: integer(fields[9]), SplitInto: known[fields[10]], SplitCount: integer(fields[11])}
			types = append(types, kind)
			known[kind.Name] = kind
		case "wave":
			waves = append(waves, &Wave{Reward: integer(fields[1])})
		case "group":
			wave := waves[len(waves)-1]
			wave.Groups = append(wave.Groups, Group{known[fields[1]], integer(fields[2]), integer(fields[3]), integer(fields[4]), integer(fields[5]), integer(fields[6])})
		}
	}
	return types, waves
}

type Enemy struct {
	Number                int
	Kind                  *EnemyType
	Multiplier, MaxHP, HP int
	Slow, Burn            Effect
	Alive                 bool
	Cell, NextCell        Point
	Progress              int
	Point                 Point
}

func newEnemy(number int, kind *EnemyType, multiplier int) *Enemy {
	hp := kind.HP * multiplier / 100
	return &Enemy{Number: number, Kind: kind, Multiplier: multiplier, MaxHP: hp, HP: hp, Alive: true}
}
func (e *Enemy) Flying() bool { return e.Kind.Movement == "air" }
func (e *Enemy) Position() Point {
	if e.Flying() {
		return e.Point
	}
	return Point{100*e.Cell.X + (e.NextCell.X-e.Cell.X)*e.Progress, 100*e.Cell.Y + (e.NextCell.Y-e.Cell.Y)*e.Progress}
}
func (e *Enemy) OccupiedCell() Point {
	if e.Flying() {
		return Point{(e.Point.X + 50) / 100, (e.Point.Y + 50) / 100}
	}
	if e.Progress < 50 {
		return e.Cell
	}
	return e.NextCell
}
func (e *Enemy) Remaining(field *DistanceField) int {
	if e.Flying() {
		return integerSqrt(squaredDistance(e.Point, cellCenter(field.Exit)))
	}
	return 100*field.At(e.NextCell) + 100 - e.Progress
}
func (e *Enemy) SlowedSpeed() int {
	if e.Slow.Active() {
		return e.Kind.Speed * (100 - e.Slow.Strength) / 100
	}
	return e.Kind.Speed
}
func (e *Enemy) Split(number int) *Enemy {
	child := newEnemy(number, e.Kind.SplitInto, e.Multiplier)
	child.Cell, child.NextCell, child.Progress, child.Point = e.Cell, e.NextCell, e.Progress, e.Point
	return child
}
