package main

import (
	"strconv"
	"strings"
)

type Tile struct {
	kind int
	red  bool
}
type Tiles struct {
	tiles  []Tile
	counts [34]int
	reds   [3]int
}

func parseTiles(s string, allowEmpty bool) (Tiles, bool) {
	out := Tiles{}
	if s == "-" && allowEmpty {
		return out,
			true
	}
	if s == "" || s == "-" {
		return out, false
	}
	for i := 0; i < len(s); {
		start := i
		for i < len(s) && s[i] >= '0' && s[i] <= '9' {
			i++
		}
		if i == start || i == len(s) {
			return out,
				false
		}
		suit := strings.IndexByte("mpsz", s[i])
		if suit < 0 {
			return out, false
		}
		for _, c := range []byte(s[start:i]) {
			rank := int(c - '0')
			red := rank == 0
			if suit == 3 {
				if rank < 1 || rank > 7 {
					return out,
						false
				}
			} else if red {
				rank = 5
			}
			kind := 9*suit + rank - 1
			tile := Tile{kind, red}
			out.tiles = append(out.tiles,
				tile)
			out.counts[kind]++
			if red {
				out.reds[suit]++
			}
		}
		i++
	}
	return out, true
}
func tileName(kind int) string { return strconv.Itoa(kind%9+1) + string("mpsz"[kind/9]) }
func blockNotation(kind, size int, sequence bool) string {
	var out strings.Builder
	for i := 0; i < size; i++ {
		rank := kind%9 + 1
		if sequence {
			rank += i
		}
		out.WriteByte(byte('0' + rank))
	}
	out.WriteByte("mpsz"[kind/9])
	return out.String()
}
func honor(kind int) bool    { return kind >= 27 }
func terminal(kind int) bool { return kind < 27 && (kind%9 == 0 || kind%9 == 8) }
func yaochuu(kind int) bool  { return honor(kind) || terminal(kind) }
func nextDora(kind int) int {
	if kind < 27 {
		return kind/9*9 + (kind%9+1)%9
	}
	if kind < 31 {
		return 27 + (kind-27+1)%4
	}
	return 31 + (kind-31+1)%3
}
func combineTiles(groups ...Tiles) Tiles {
	out := Tiles{}
	for _, group := range groups {
		out.tiles = append(out.tiles,
			group.tiles...)
		for i, c := range group.counts {
			out.counts[i] += c
		}
		for i, c := range group.reds {
			out.reds[i] += c
		}
	}
	return out
}
func addKind(a Tiles, kind int) Tiles {
	a.tiles = append(append([]Tile(nil), a.tiles...), Tile{kind: kind})
	a.counts[kind]++
	return a
}
