package main

import "sort"

type LayoutBlock struct {
	Kind            string
	Lines           []*TextLine
	List, PageBreak bool
}
type Boundary struct {
	End, Next int
	Forced    bool
}

func buildSequence(blocks []*LayoutBlock, orphan, widow int) ([]*TextLine, []Boundary) {
	lines := []*TextLine{}
	boundaries := []Boundary{}
	for i, b := range blocks {
		start := len(lines)
		lines = append(lines, b.Lines...)
		count := len(b.Lines)
		if b.Kind == "flow" {
			for kept := 1; kept < count; kept++ {
				if kept >= orphan && count-kept >= widow {
					position := start + kept
					boundaries = append(boundaries, Boundary{position, position, false})
				}
			}
		}
		if i+1 == len(blocks) {
			boundaries = append(boundaries, Boundary{len(lines), len(lines), true})
			continue
		}
		following := blocks[i+1]
		end := len(lines)
		if !(b.List && following.List) {
			lines = append(lines, textLine(""))
		}
		forced := following.PageBreak
		if forced || b.Kind != "heading" {
			boundaries = append(boundaries, Boundary{end, len(lines), forced})
		}
	}
	return lines, boundaries
}
func choosePages(blocks []*LayoutBlock, footnoteHeights map[int]int, height, orphan, widow int) []*Page {
	lines, boundaries := buildSequence(blocks, orphan, widow)
	pages := []*Page{}
	start, firstBoundary := 0, 0
	for start < len(lines) {
		notes := map[int]bool{}
		noteHeight, scanned := 0, start
		chosenIndex, chosenEnd, chosenNext, chosenHeight := -1, 0, 0, 0
		chosenForced := false
		chosenNotes := []int{}
		for i := firstBoundary; i < len(boundaries); i++ {
			b := boundaries[i]
			for scanned < b.End {
				for _, number := range lines[scanned].Footnotes {
					if !notes[number] {
						notes[number] = true
						noteHeight += footnoteHeights[number]
					}
				}
				scanned++
			}
			used := b.End - start + noteHeight
			if len(notes) > 0 {
				used++
			}
			if used > height {
				break
			}
			chosenIndex, chosenEnd, chosenNext, chosenHeight = i, b.End, b.Next, used
			chosenForced = b.Forced
			chosenNotes = []int{}
			for number := range notes {
				chosenNotes = append(chosenNotes, number)
			}
			sort.Ints(chosenNotes)
			if b.Forced {
				break
			}
		}
		if chosenIndex < 0 {
			panic("no feasible page break")
		}
		pages = append(pages, &Page{Content: lines[start:chosenEnd], Footnotes: chosenNotes, Height: chosenHeight, EndsByForce: chosenForced})
		start = chosenNext
		firstBoundary = chosenIndex + 1
	}
	return pages
}
