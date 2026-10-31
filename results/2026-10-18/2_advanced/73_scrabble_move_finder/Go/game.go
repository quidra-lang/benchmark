package main

import "sort"

type Generator struct{ State int64 }

func (g *Generator) next() int64 { g.State = 48271 * g.State % 2147483647; return g.State }
func (g *Generator) shuffle(bag []byte) {
	for i := len(bag) - 1; i >= 1; i-- {
		j := int(g.next() % int64(i+1))
		bag[i], bag[j] = bag[j], bag[i]
	}
}
func newBag(tiles Tiles, g *Generator) []byte {
	var bag []byte
	for i, n := range tiles.Count {
		letter := byte('A' + i)
		if i == 26 {
			letter = '?'
		}
		for k := 0; k < n; k++ {
			bag = append(bag,
				letter)
		}
	}
	g.shuffle(bag)
	return bag
}
func draw(bag *[]byte, k int) string {
	var drawn []byte
	for i := 0; i < k && len(*bag) > 0; i++ {
		last := len(*bag) - 1
		drawn = append(drawn,
			(*bag)[last])
		*bag = (*bag)[:last]
	}
	return string(drawn)
}
func exchange(bag *[]byte, putBack string, g *Generator) string {
	drawn := draw(bag, len(putBack))
	letters := []byte(putBack)
	sort.Slice(letters,
		func(i, j int) bool { return letters[i] < letters[j] })
	*bag = append(*bag, letters...)
	g.shuffle(*bag)
	return drawn
}
func collectionValue(collection string, tiles Tiles) int {
	value := 0
	for i := range collection {
		value += tiles.Value[tileIndex(collection[i])]
	}
	return value
}
