package main

import "strings"

var targetModes = []string{"FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST"}

type Level struct{ Cost, Range, Power, Interval, ShotSpeed, Splash, SlowRate, SlowTime, BurnAmount, BurnTime int }
type TowerType struct {
	Name, Symbol, Targets string
	Levels                []Level
}

func parseTowerTypes(lines []string) []*TowerType {
	types := []*TowerType{}
	for index := 0; index < len(lines); {
		fields := strings.Fields(lines[index])
		kind := &TowerType{Name: fields[1], Symbol: fields[2], Targets: fields[3]}
		count := integer(fields[4])
		for _, line := range lines[index+1 : index+count+1] {
			fields := strings.Fields(line)
			values := make([]int, 10)
			for i := range values {
				values[i] = integer(fields[i+1])
			}
			kind.Levels = append(kind.Levels, Level{values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8], values[9]})
		}
		types = append(types, kind)
		index += count + 1
	}
	return types
}
func canAim(targets string, enemy *Enemy) bool {
	return targets == "both" || targets == enemy.Kind.Movement
}

type Tower struct {
	Number                                                              int
	Kind                                                                *TowerType
	Cell                                                                Point
	Level                                                               int
	Mode                                                                string
	Ready, Investment, Built, Sold, Shots, Hits, Fizzles, Kills, Damage int
}

func newTower(number int, kind *TowerType, cell Point, tick int) *Tower {
	return &Tower{Number: number, Kind: kind, Cell: cell, Level: 1, Mode: "FIRST", Ready: tick, Investment: kind.Levels[0].Cost, Built: tick}
}
func (t *Tower) Stats() Level   { return t.Kind.Levels[t.Level-1] }
func (t *Tower) Center() Point  { return cellCenter(t.Cell) }
func (t *Tower) Standing() bool { return t.Sold == 0 }
func (t *Tower) InRange(point Point) bool {
	reach := t.Stats().Range
	return squaredDistance(t.Center(), point) <= reach*reach
}
func (t *Tower) TargetKey(enemy *Enemy, field *DistanceField) int {
	switch t.Mode {
	case "FIRST":
		return enemy.Remaining(field)
	case "LAST":
		return -enemy.Remaining(field)
	case "STRONGEST":
		return -enemy.HP
	case "WEAKEST":
		return enemy.HP
	}
	return squaredDistance(t.Center(), enemy.Position())
}
func (t *Tower) SelectTarget(enemies []*Enemy, field *DistanceField) *Enemy {
	var best *Enemy
	bestKey := 0
	for _, enemy := range enemies {
		if !canAim(t.Kind.Targets, enemy) || !t.InRange(enemy.Position()) {
			continue
		}
		key := t.TargetKey(enemy, field)
		if best == nil || key < bestKey {
			best, bestKey = enemy, key
		}
	}
	return best
}
