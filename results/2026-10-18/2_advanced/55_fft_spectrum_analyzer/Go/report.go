package main

import (
	"fmt"
	"math"
	"os"
	"strings"
)

func realString(v float64) string {
	s := fmt.Sprintf("%.4f", v)
	if s == "-0.0000" {
		return "0.0000"
	}
	return s
}
func textValue(v any) string {
	if x, ok := v.(float64); ok {
		return realString(x)
	}
	return fmt.Sprint(v)
}
func fields(items ...any) string {
	a := make([]string, 0, len(items)/2)
	for i := 0; i < len(items); i += 2 {
		a = append(a, fmt.Sprint(items[i])+"="+textValue(items[i+1]))
	}
	return strings.Join(a, " ")
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func writeCSV(name, header string, rows [][]any) {
	out := []string{header}
	for _, row := range rows {
		a := make([]string, len(row))
		for i, v := range row {
			a[i] = textValue(v)
		}
		out = append(out, strings.Join(a, ","))
	}
	writeLines(name, out)
}
func shadeLines(g [][]float64, fs, f, b int, maximum float64) []string {
	out := []string{}
	for k := f / 2; k >= 0; k-- {
		var s strings.Builder
		for _, frame := range g {
			level := max(0, 9-int(math.Floor(-20*math.Log10(frame[k]/maximum)/float64(b))))
			s.WriteByte(" .:-=+*#%@"[level])
		}
		out = append(out, fmt.Sprintf("%9s |%s|", realString(float64(k*fs)/float64(f)), s.String()))
	}
	return out
}
