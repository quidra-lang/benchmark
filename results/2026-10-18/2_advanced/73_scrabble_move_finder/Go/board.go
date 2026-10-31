package main

import (
	"fmt"
	"strings"
)

const boardSize = 15
const center = 7

type Board [15][15]byte
type Square struct{ Row, Col int }
type BoardWord struct {
	Row, Col, Direction int
	Word                string
}

var premiums = [15]string{"#..+...#...+..#", ".*...^...^...*.", "..*...+.+...*..", "+..*...+...*..+", "....*.....*....",
	".^...^...^...^.", "..+...+.+...+..", "#..+...*...+..#", "..+...+.+...+..", ".^...^...^...^.", "....*.....*....",
	"+..*...+...*..+", "..*...+.+...*..", ".*...^...^...*.", "#..+...#...+..#"}

func newBoard() Board {
	var b Board
	for r := 0; r < 15; r++ {
		for c := 0; c < 15; c++ {
			b[r][c] = '.'
		}
	}
	return b
}
func inside(r, c int) bool       { return r >= 0 && r < 15 && c >= 0 && c < 15 }
func squareName(r, c int) string { return fmt.Sprintf("%c%d", 'A'+c, r+1) }
func positionName(r, c, direction int) string {
	if direction == 0 {
		return fmt.Sprintf("%d%c", r+1, 'A'+c)
	}
	return squareName(r, c)
}
func parsePosition(s string) (int, int, int, bool) {
	if len(s) < 2 {
		return 0, 0, 0, false
	}
	if s[0] >= 'A' && s[0] <= 'O' {
		row,
			ok := validNumber(s[1:], 1, 15)
		return row - 1, int(s[0] - 'A'), 1, ok
	}
	last := s[len(s)-1]
	if last < 'A' || last > 'O' {
		return 0,
			0, 0, false
	}
	row, ok := validNumber(s[:len(s)-1], 1, 15)
	return row - 1, int(last - 'A'), 0, ok
}
func (b Board) transpose() Board {
	var a Board
	for r := 0; r < 15; r++ {
		for c := 0; c < 15; c++ {
			a[r][c] = b[c][r]
		}
	}
	return a
}
func transposeSquares(a []Square) []Square {
	b := make([]Square, len(a))
	for i, p := range a {
		b[i] = Square{p.Col, p.Row}
	}
	return b
}
func directions(direction int) (int, int) {
	if direction == 0 {
		return 0, 1
	}
	return 1, 0
}
func boardWords(b Board) []BoardWord {
	var words []BoardWord
	for direction := 0; direction < 2; direction++ {
		for fixed := 0; fixed < 15; fixed++ {
			for start := 0; start < 15; {
				r,
					c := fixed, start
				if direction == 1 {
					r, c = start, fixed
				}
				if b[r][c] == '.' {
					start++
					continue
				}
				end := start
				var word strings.Builder
				for end < 15 {
					rr,
						cc := fixed, end
					if direction == 1 {
						rr, cc = end, fixed
					}
					if b[rr][cc] == '.' {
						break
					}
					word.WriteByte(b[rr][cc])
					end++
				}
				if end-start >= 2 {
					words = append(words,
						BoardWord{r, c, direction, word.String()})
				}
				start = end
			}
		}
	}
	return words
}
func wordAt(b Board, r, c, direction int) BoardWord {
	dr, dc := directions(direction)
	for inside(r-dr, c-dc) && b[r-dr][c-dc] != '.' {
		r -= dr
		c -= dc
	}
	word := BoardWord{Row: r,
		Col: c, Direction: direction}
	var s strings.Builder
	for inside(r, c) && b[r][c] != '.' {
		s.WriteByte(b[r][c])
		r += dr
		c += dc
	}
	word.Word = s.String()
	return word
}
func adjacent(b Board, r, c int) bool {
	for _, d := range [][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}} {
		rr, cc := r+d[0],
			c+d[1]
		if inside(rr, cc) && b[rr][cc] != '.' {
			return true
		}
	}
	return false
}
func tileCount(b Board) int {
	n := 0
	for _, row := range b {
		for _, c := range row {
			if c != '.' {
				n++
			}
		}
	}
	return n
}
func connected(b Board) bool {
	var queue []Square
	for r := 0; r < 15 && len(queue) == 0; r++ {
		for c := 0; c < 15; c++ {
			if b[r][c] != '.' {
				queue = append(queue,
					Square{r, c})
				break
			}
		}
	}
	if len(queue) == 0 {
		return true
	}
	seen := map[Square]bool{queue[0]: true}
	for pos := 0; pos < len(queue); pos++ {
		p := queue[pos]
		for _, d := range [][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}} {
			q := Square{p.Row + d[0], p.Col + d[1]}
			if inside(q.Row,
				q.Col) && b[q.Row][q.Col] != '.' && !seen[q] {
				seen[q] = true
				queue = append(queue, q)
			}
		}
	}
	return len(seen) == tileCount(b)
}
func display(b Board) []string {
	a := []string{"   A B C D E F G H I J K L M N O"}
	for r := 0; r < 15; r++ {
		var row []string
		for c := 0; c < 15; c++ {
			v := b[r][c]
			if v == '.' {
				v = premiums[r][c]
			}
			row = append(row,
				string(v))
		}
		a = append(a, fmt.Sprintf("%2d %s", r+1, strings.Join(row, " ")))
	}
	return a
}
