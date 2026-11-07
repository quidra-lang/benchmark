package main

import (
	"sort"
	"strings"
)

type Block struct {
	kind          int
	sequence, kan bool
	source        string
	winning       bool
}

func (b Block) notation() string {
	size := 3
	if b.kan {
		size = 4
	}
	return blockNotation(b.kind, size, b.sequence)
}

type Decomposition struct {
	pair int
	sets []Block
}

func standardDecompositions(counts [34]int, melds int) []Decomposition {
	var out []Decomposition
	seen := map[string]bool{}
	needed := 4 - melds
	for pair := 0; pair < 34; pair++ {
		if counts[pair] < 2 {
			continue
		}
		counts[pair] -= 2
		var search func([34]int,
			[]Block)
		search = func(a [34]int, sets []Block) {
			first := -1
			for i, c := range a {
				if c > 0 {
					first = i
					break
				}
			}
			if first < 0 {
				if len(sets) != needed {
					return
				}
				blocks := append([]Block(nil),
					sets...)
				sort.Slice(blocks, func(i, j int) bool {
					if blocks[i].kind != blocks[j].kind {
						return blocks[i].kind < blocks[j].kind
					}
					return !blocks[i].sequence && blocks[j].sequence
				})
				var names []string
				for _, b := range blocks {
					names = append(names, b.notation())
				}
				key := tileName(pair) + " " + strings.Join(names,
					" ")
				if !seen[key] {
					seen[key] = true
					out = append(out, Decomposition{pair, blocks})
				}
				return
			}
			if len(sets) >= needed {
				return
			}
			if a[first] >= 3 {
				a[first] -= 3
				next := append(append([]Block(nil),
					sets...), Block{kind: first, source: "concealed"})
				search(a, next)
				a[first] += 3
			}
			if first < 27 && first%9 <= 6 && a[first+1] > 0 && a[first+2] > 0 {
				a[first]--
				a[first+1]--
				a[first+2]--
				next := append(append([]Block(nil),
					sets...), Block{kind: first, sequence: true, source: "concealed"})
				search(a, next)
			}
		}
		search(counts, nil)
		counts[pair] += 2
	}
	return out
}
func sevenPairs(a [34]int, melds int) bool {
	if melds != 0 {
		return false
	}
	pairs := 0
	for _, n := range a {
		if n == 2 {
			pairs++
		} else if n != 0 {
			return false
		}
	}
	return pairs == 7
}
func thirteenOrphans(a [34]int, melds int) bool {
	if melds != 0 {
		return false
	}
	total := 0
	for kind, n := range a {
		if yaochuu(kind) {
			if n == 0 {
				return false
			}
		} else if n > 0 {
			return false
		}
		total += n
	}
	return total == 14
}
func winningForm(a [34]int, melds int) bool {
	return sevenPairs(a, melds) || thirteenOrphans(a, melds) || len(standardDecompositions(a, melds)) > 0
}
func waitingTiles(hand Tiles, melds []Meld) []int {
	counts := hand.counts
	var all [34]int
	all = counts
	for _, meld := range melds {
		for kind, n := range meld.tiles.counts {
			all[kind] += n
		}
	}
	var out []int
	for kind := 0; kind < 34; kind++ {
		if all[kind] >= 4 {
			continue
		}
		counts[kind]++
		if winningForm(counts,
			len(melds)) {
			out = append(out, kind)
		}
		counts[kind]--
	}
	return out
}
func waitShape(b Block, win int) string {
	if !b.sequence {
		return "shanpon"
	}
	rank := win - b.kind
	if rank == 1 {
		return "kanchan"
	}
	if b.kind%9 == 0 && rank == 2 || b.kind%9 == 6 && rank == 0 {
		return "penchan"
	}
	return "ryanmen"
}
