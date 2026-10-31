package main

import (
	"fmt"
	"os"
	"strings"
)

func ratio(x, y int) string {
	if y == 0 {
		return "-"
	}
	value := (int64(x)*10000 + int64(y)/2) / int64(y)
	return fmt.Sprintf("%d.%04d", value/10000, value%10000)
}
func samHeader(refs []Reference) string {
	var s strings.Builder
	line(&s, "@HD\tVN:1.6\tSO:unsorted")
	for _, r := range refs {
		line(&s, "@SQ\tSN:%s\tLN:%d", r.Name, len(r.Sequence))
	}
	line(&s, "@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0")
	return s.String()
}
func samRecord(read Read, m Mapping, refs []Reference, maxAlternatives int) string {
	if !m.Mapped {
		return strings.Join([]string{read.Name,
			"4", "*", "0", "0", "*", "*", "0", "0", read.Bases, read.Quality, "YM:Z:" + m.Method}, "\t")
	}
	a := m.Alignments[0]
	cigar,
		nm, md := describe(a, m.Core, refs, m.Trim)
	flag := 0
	bases, quality := read.Bases, read.Quality
	if a.Strand == 1 {
		flag = 16
		bases = reverseComplement(bases)
		quality = reverse(quality)
	}
	fields := []string{read.Name,
		fmt.Sprint(flag), refs[a.R].Name, fmt.Sprint(a.Pos + 1), fmt.Sprint(m.MapQ), cigar, "*", "0", "0", bases,
		quality, fmt.Sprintf("NM:i:%d", nm), "MD:Z:" + md, fmt.Sprintf("AS:i:%d", m.Score), fmt.Sprintf("X0:i:%d",
			m.X0), fmt.Sprintf("X1:i:%d", m.X1), "YM:Z:" + m.Method}
	others := len(m.Alignments) - 1
	if others > 0 && others <= maxAlternatives {
		var xa strings.Builder
		xa.WriteString("XA:Z:")
		for _, a := range m.Alignments[1:] {
			cigar, nm, _ := describe(a, m.Core, refs, m.Trim)
			strand := "+"
			if a.Strand == 1 {
				strand = "-"
			}
			fmt.Fprintf(&xa,
				"%s,%s%d,%s,%d;", refs[a.R].Name, strand, a.Pos+1, cigar, nm)
		}
		fields = append(fields, xa.String())
	}
	return strings.Join(fields,
		"\t")
}
func line(s *strings.Builder, template string, a ...any) { fmt.Fprintf(s, template+"\n", a...) }
func write(path string, s *strings.Builder)              { must(os.WriteFile(path, []byte(s.String()), 0644)) }
