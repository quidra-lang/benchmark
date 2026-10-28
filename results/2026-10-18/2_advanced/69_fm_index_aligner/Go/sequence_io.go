package main

import (
	"os"
	"strconv"
	"strings"
)

type Reference struct {
	Name, Sequence string
	Masked, Offset int
}
type Read struct{ Name, Bases, Quality string }

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func readText(path string) string { b, e := os.ReadFile(path); must(e); return string(b) }
func integer(s string) int        { v, e := strconv.Atoi(s); must(e); return v }
func readInput() ([]Reference, []Read, map[string][]int) {
	var references []Reference
	for _, line := range strings.Split(strings.TrimSpace(readText("input/reference.fasta")),
		"\n") {
		if line[0] == '>' {
			references = append(references, Reference{Name: strings.SplitN(line[1:], " ",
				2)[0]})
		} else {
			r := &references[len(references)-1]
			for _, c := range line {
				if c >= 'a' && c <= 'z' {
					r.Masked++
				}
			}
			r.Sequence += strings.ToUpper(line)
		}
	}
	lines := strings.Split(strings.TrimSuffix(readText("input/reads.fastq"),
		"\n"), "\n")
	var reads []Read
	for i := 0; i < len(lines); i += 4 {
		reads = append(reads, Read{lines[i][1:],
			lines[i+1], lines[i+3]})
	}
	params := map[string][]int{}
	for _, line := range strings.Split(strings.TrimSpace(readText("input/params.txt")),
		"\n") {
		a := strings.Fields(line)
		for _, s := range a[1:] {
			params[a[0]] = append(params[a[0]], integer(s))
		}
	}
	return references,
		reads, params
}
func reverse(s string) string {
	b := []byte(s)
	for i, j := 0, len(b)-1; i < j; i, j = i+1, j-1 {
		b[i], b[j] = b[j], b[i]
	}
	return string(b)
}
func reverseComplement(s string) string {
	b := make([]byte, len(s))
	for i := range s {
		c := s[len(s)-1-i]
		switch c {
		case 'A':
			c = 'T'
		case 'C':
			c = 'G'
		case 'G':
			c = 'C'
		case 'T':
			c = 'A'
		}
		b[i] = c
	}
	return string(b)
}
