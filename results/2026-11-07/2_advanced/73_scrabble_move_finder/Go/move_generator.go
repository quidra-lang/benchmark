package main

import (
	"fmt"
	"strings"
)

type RawMove struct {
	Row, Col, Direction int
	Word                string
}
type Check struct {
	IsCheck bool
	Letters uint32
}
type CrossStats struct{ Squares, Empty, Letters int }

func anchors(b Board) [15][15]bool {
	var a [15][15]bool
	empty := tileCount(b) == 0
	for r := 0; r < 15; r++ {
		for c := 0; c < 15; c++ {
			a[r][c] = b[r][c] == '.' && ((empty && r == center && c == center) || (!empty && adjacent(b,
				r, c)))
		}
	}
	return a
}
func crossChecks(b Board, direction int, trie Trie) ([15][15]Check, CrossStats) {
	var checks [15][15]Check
	var stats CrossStats
	perpendicular := 1 - direction
	dr,
		dc := directions(perpendicular)
	for r := 0; r < 15; r++ {
		for c := 0; c < 15; c++ {
			if b[r][c] != '.' {
				continue
			}
			has := (inside(r-dr,
				c-dc) && b[r-dr][c-dc] != '.') || (inside(r+dr, c+dc) && b[r+dr][c+dc] != '.')
			checks[r][c].IsCheck = has
			if !has {
				checks[r][c].Letters = (1 << 26) - 1
				continue
			}
			stats.Squares++
			for letter := 0; letter < 26; letter++ {
				after := b
				after[r][c] = byte('A' + letter)
				if trie.contains(wordAt(after,
					r, c, perpendicular).Word) {
					checks[r][c].Letters |= 1 << letter
					stats.Letters++
				}
			}
			if checks[r][c].Letters == 0 {
				stats.Empty++
			}
		}
	}
	return checks,
		stats
}
func placementKey(b Board, move RawMove) string {
	dr, dc := directions(move.Direction)
	var s strings.Builder
	for i := range move.Word {
		r,
			c := move.Row+i*dr, move.Col+i*dc
		if b[r][c] == '.' {
			fmt.Fprintf(&s, "%03d%c", r*15+c, move.Word[i])
		}
	}
	return s.String()
}
func generateMoves(board Board, rack string, trie Trie) []RawMove {
	var moves []RawMove
	seen := map[string]bool{}
	for direction := 0; direction < 2; direction++ {
		b := board
		if direction == 1 {
			b = b.transpose()
		}
		anchor := anchors(b)
		checks,
			_ := crossChecks(b, 0, trie)
		for row := 0; row < 15; row++ {
			for col := 0; col < 15; col++ {
				if !anchor[row][col] {
					continue
				}
				counts := collectionCounts(rack)
				record := func(start int,
					word string, placed int) {
					if placed == 0 || len(word) < 2 {
						return
					}
					move := RawMove{row, start, direction,
						word}
					if direction == 1 {
						move.Row, move.Col = start, row
					}
					if placed == 1 && direction == 1 {
						after := board
						dr,
							dc := directions(direction)
						newRow, newCol := 0, 0
						for i := range word {
							r, c := move.Row+i*dr, move.Col+i*dc
							if board[r][c] == '.' {
								after[r][c] = word[i]
								newRow,
									newCol = r, c
							}
						}
						if len(wordAt(after, newRow, newCol, 0).Word) >= 2 {
							return
						}
					}
					key := placementKey(board,
						move)
					if !seen[key] {
						seen[key] = true
						moves = append(moves, move)
					}
				}
				var extend func(int, int, int, string,
					int, bool)
				extend = func(at, start, node int, word string, placed int, filled bool) {
					if at >= 15 {
						if trie.Nodes[node].Terminal && filled {
							record(start,
								word, placed)
						}
						return
					}
					tile := b[row][at]
					if tile != '.' {
						next := trie.Nodes[node].Children[upper(tile)-'A']
						if next >= 0 {
							extend(at+1,
								start, next, word+string(tile), placed, filled)
						}
						return
					}
					if trie.Nodes[node].Terminal && filled {
						record(start,
							word, placed)
					}
					for letter, next := range trie.Nodes[node].Children {
						if next < 0 || checks[row][at].Letters>>letter&1 == 0 {
							continue
						}
						if counts[letter] > 0 {
							counts[letter]--
							extend(at+1,
								start, next, word+string(byte('A'+letter)), placed+1, filled || at == col)
							counts[letter]++
						}
						if counts[26] > 0 {
							counts[26]--
							extend(at+1,
								start, next, word+string(byte('a'+letter)), placed+1, filled || at == col)
							counts[26]++
						}
					}
				}
				if col > 0 && b[row][col-1] != '.' {
					start := col - 1
					for start > 0 && b[row][start-1] != '.' {
						start--
					}
					prefix := string(b[row][start:col])
					node := trie.find(prefix)
					if node >= 0 {
						extend(col,
							start, node, prefix, 0, false)
					}
				} else {
					limit := 0
					for c := col - 1; c >= 0 && b[row][c] == '.' && !anchor[row][c]; c-- {
						limit++
					}
					var left func(string,
						int, int)
					left = func(prefix string, node, length int) {
						extend(col, col-length, node, prefix, length, false)
						if length == limit {
							return
						}
						for letter, next := range trie.Nodes[node].Children {
							if next < 0 {
								continue
							}
							if counts[letter] > 0 {
								counts[letter]--
								left(prefix+string(byte('A'+letter)),
									next, length+1)
								counts[letter]++
							}
							if counts[26] > 0 {
								counts[26]--
								left(prefix+string(byte('a'+letter)),
									next, length+1)
								counts[26]++
							}
						}
					}
					left("", 0, 0)
				}
			}
		}
	}
	return moves
}
