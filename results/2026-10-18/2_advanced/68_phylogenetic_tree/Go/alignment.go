package main

import (
	"os"
	"strings"
)

type Record struct {
	Name, Sequence string
	Line           int
}
type ColumnClass struct{ Constant, Variable, Informative, Gapped, Empty int }

var baseSets = map[byte]int{'A': 1, 'C': 2, 'G': 4, 'T': 8, 'R': 5, 'Y': 10, 'S': 6, 'W': 9, 'K': 12, 'M': 3, 'B': 14, 'D': 13, 'H': 11, 'V': 7, 'N': 15, '-': 15}

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func readText(path string) string { b, e := os.ReadFile(path); must(e); return string(b) }
func readFASTA() []Record {
	var a []Record
	for i, line := range strings.Split(strings.TrimSpace(readText("input/alignment.fasta")),
		"\n") {
		if line[0] == '>' {
			name := strings.SplitN(line[1:], " ", 2)[0]
			a = append(a, Record{Name: name, Line: i + 1})
		} else {
			a[len(a)-1].Sequence += strings.ToUpper(line)
		}
	}
	return a
}
func isBase(c byte) bool { return c == 'A' || c == 'C' || c == 'G' || c == 'T' }
func patterns(taxa []Record, length int) ([]string, int) {
	a := make([]string, length)
	unique := map[string]bool{}
	for col := 0; col < length; col++ {
		b := make([]byte,
			len(taxa))
		for i, t := range taxa {
			b[i] = t.Sequence[col]
		}
		a[col] = string(b)
		unique[a[col]] = true
	}
	return a,
		len(unique)
}
func classify(taxa []Record, length int) ColumnClass {
	var a ColumnClass
	for col := 0; col < length; col++ {
		count := [4]int{}
		gap := false
		for _, t := range taxa {
			c := t.Sequence[col]
			if c == '-' {
				gap = true
			}
			for i, b := range []byte("ACGT") {
				if c == b {
					count[i]++
				}
			}
		}
		kinds,
			repeated := 0, 0
		for _, n := range count {
			if n > 0 {
				kinds++
			}
			if n >= 2 {
				repeated++
			}
		}
		switch {
		case kinds == 0:
			a.Empty++
		case kinds == 1:
			a.Constant++
		default:
			a.Variable++
		}
		if repeated >= 2 {
			a.Informative++
		}
		if gap {
			a.Gapped++
		}
	}
	return a
}
