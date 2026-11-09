package main

func samplesPerTick(rate, tempo int64) int { return int(rate * 5 / (tempo * 2)) }
func nextRow(song *Song, position, row int) ([2]int, bool) {
	jump, br := -1, -1
	for _, cell := range song.Cells(position, row) {
		e := cell.Effect
		if e == nil {
			continue
		}
		if e.Name == "F" && e.Value == 0 {
			return [2]int{}, false
		}
		if e.Name == "B" {
			jump = int(e.Value)
		} else if e.Name == "D" {
			br = int(e.Value)
		}
	}
	if jump < 0 && br < 0 {
		if row < 63 {
			return [2]int{position, row + 1}, true
		}
		return [2]int{position + 1, 0}, true
	}
	target := position + 1
	if jump >= 0 {
		target = jump
	}
	if br < 0 || br >= 64 {
		br = 0
	}
	return [2]int{target, br}, true
}
func reachableRows(song *Song) map[[2]int]bool {
	reached := map[[2]int]bool{}
	current := [2]int{0, 0}
	for !reached[current] {
		reached[current] = true
		next, ok := nextRow(song, current[0], current[1])
		if !ok || next[0] >= len(song.Order) {
			break
		}
		current = next
	}
	return reached
}
