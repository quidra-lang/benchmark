package main

import (
	"fmt"
	"strings"
)

const rackSize = 7
const bingoBonus = 50

type PlacedTile struct {
	Row, Col int
	Letter   byte
}
type ScoredWord struct {
	BoardWord BoardWord
	Score     int
}
type Move struct {
	Raw                            RawMove
	Score, Tiles, LeaveValue, Rank int
	Leave                          string
	Words                          []ScoredWord
	Placed                         []PlacedTile
}

func moveSquares(move RawMove) []Square {
	a := make([]Square, len(move.Word))
	dr, dc := directions(move.Direction)
	for i := range a {
		a[i] = Square{move.Row + i*dr,
			move.Col + i*dc}
	}
	return a
}
func wordScore(word BoardWord, newTiles map[Square]bool, tiles Tiles) int {
	dr, dc := directions(word.Direction)
	sum,
		multiplier := 0, 1
	for i := range word.Word {
		r, c := word.Row+i*dr, word.Col+i*dc
		value := 0
		letter := word.Word[i]
		if letter >= 'A' && letter <= 'Z' {
			value = tiles.Value[letter-'A']
		}
		if newTiles[Square{r,
			c}] {
			switch premiums[r][c] {
			case '+':
				value *= 2
			case '^':
				value *= 3
			case '*':
				multiplier *= 2
			case '#':
				multiplier *= 3
			}
		}
		sum += value
	}
	return sum * multiplier
}
func evaluateMove(board Board, rack string, raw RawMove, tiles Tiles) Move {
	m := Move{Raw: raw}
	after := board
	newTiles := map[Square]bool{}
	counts := collectionCounts(rack)
	for i, p := range moveSquares(raw) {
		if board[p.Row][p.Col] == '.' {
			letter := raw.Word[i]
			m.Placed = append(m.Placed,
				PlacedTile{p.Row, p.Col, letter})
			newTiles[p] = true
			after[p.Row][p.Col] = letter
			counts[tileIndex(letter)]--
		}
	}
	words := []BoardWord{{raw.Row,
		raw.Col, raw.Direction, raw.Word}}
	for _, tile := range m.Placed {
		word := wordAt(after, tile.Row, tile.Col,
			1-raw.Direction)
		if len(word.Word) >= 2 {
			words = append(words, word)
		}
	}
	for _, word := range words {
		score := wordScore(word,
			newTiles, tiles)
		m.Score += score
		m.Words = append(m.Words, ScoredWord{word, score})
	}
	m.Tiles = len(m.Placed)
	if m.Tiles == rackSize {
		m.Score += bingoBonus
	}
	m.Leave = countsString(counts)
	return m
}
func play(board *Board, move Move) {
	for _, tile := range move.Placed {
		board[tile.Row][tile.Col] = tile.Letter
	}
}
func wordList(move Move) string {
	a := make([]string, len(move.Words))
	for i, w := range move.Words {
		a[i] = fmt.Sprintf("%s:%d",
			w.BoardWord.Word, w.Score)
	}
	return strings.Join(a, ",")
}
