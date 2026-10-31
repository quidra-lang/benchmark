package main

import (
	"fmt"
	"strconv"
	"strings"
)

func intMatrix(rows, columns int) [][]int {
	out := make([][]int, rows)
	for i := range out {
		out[i] = make([]int, columns)
	}
	return out
}
func gcd(a, b int64) int64 {
	if a < 0 {
		a = -a
	}
	if b < 0 {
		b = -b
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(a, b int64) string {
	if b == 0 {
		return "-"
	}
	if b < 0 {
		a, b = -a, -b
	}
	d := gcd(a, b)
	return fmt.Sprintf("%d/%d", a/d, b/d)
}
func correctCount(a, b []int) int {
	count := 0
	for i, v := range a {
		if v == b[i] {
			count++
		}
	}
	return count
}
func addConfusion(table [][]int, truth, prediction []int) {
	for i, state := range truth {
		table[state][prediction[i]]++
	}
}
func confusionLines(table [][]int, states []string) []string {
	width := 1
	for _, row := range table {
		for _, v := range row {
			width = max(width, len(strconv.Itoa(v)))
		}
	}
	header := " "
	for _, state := range states {
		header += fmt.Sprintf(" %*s", width, state)
	}
	lines := []string{header}
	for i, row := range table {
		line := states[i]
		for _, v := range row {
			line += fmt.Sprintf(" %*d", width, v)
		}
		lines = append(lines, line)
	}
	return lines
}
func metricsLines(table [][]int, states []string) []string {
	k := len(states)
	rows, columns := make([]int64, k), make([]int64, k)
	total, correct := int64(0), int64(0)
	for i, row := range table {
		for j, v := range row {
			n := int64(v)
			rows[i] += n
			columns[j] += n
			total += n
			if i == j {
				correct += n
			}
		}
	}
	expected := int64(0)
	for i := 0; i < k; i++ {
		expected += rows[i] * columns[i]
	}
	lines := []string{"ACCURACY " + fraction(correct, total), "KAPPA " + fraction(total*correct-expected, total*total-expected)}
	for i, state := range states {
		truePositive := int64(table[i][i])
		lines = append(lines, fmt.Sprintf("STATE %s precision %s recall %s f1 %s", state, fraction(truePositive,
			columns[i]), fraction(truePositive, rows[i]), fraction(2*truePositive, rows[i]+columns[i])))
	}
	return lines
}

type Run struct{ State, Start, End int }

func runs(path []int) []Run {
	out := []Run{}
	for start := 0; start < len(path); {
		end := start
		for end+1 < len(path) && path[end+1] == path[start] {
			end++
		}
		out = append(out, Run{path[start], start, end})
		start = end + 1
	}
	return out
}

type Segment struct{ Start, End int }

func overlaps(a, b Segment) bool { return max(a.Start, b.Start) <= min(a.End, b.End) }
func regionMatches(predicted, truth []Segment) (int, int) {
	a, b := 0, 0
	for _, p := range predicted {
		for _, t := range truth {
			if overlaps(p, t) {
				a++
				break
			}
		}
	}
	for _, t := range truth {
		for _, p := range predicted {
			if overlaps(p, t) {
				b++
				break
			}
		}
	}
	return a, b
}
func boundaries(path []int) []int {
	out := []int{}
	for i := 1; i < len(path); i++ {
		if path[i] != path[i-1] {
			out = append(out, i+1)
		}
	}
	return out
}
func absolute(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
func boundaryMatches(predicted, truth []int, tolerance int) (int, int) {
	a, b := 0, 0
	for _, p := range predicted {
		for _, t := range truth {
			if absolute(p-t) <= tolerance {
				a++
				break
			}
		}
	}
	for _, t := range truth {
		for _, p := range predicted {
			if absolute(p-t) <= tolerance {
				b++
				break
			}
		}
	}
	return a, b
}
func encode(indices []int, names []string) string {
	out := []string{}
	for _, i := range indices {
		out = append(out, names[i])
	}
	return strings.Join(out, "")
}
