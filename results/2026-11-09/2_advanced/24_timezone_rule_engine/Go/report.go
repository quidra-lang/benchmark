package main

import (
	"fmt"
	"os"
	"strings"
)

func localText(time int64) string {
	year, month, day, hour, minute, second := splitTime(time)
	return fmt.Sprintf("%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
}
func utText(time int64) string { return localText(time) + "Z" }
func offsetText(value int64) string {
	sign := "+"
	if value < 0 {
		sign = "-"
		value = -value
	}
	text := fmt.Sprintf("%s%02d:%02d", sign, value/3600, value/60%60)
	if value%60 != 0 {
		text += fmt.Sprintf(":%02d", value%60)
	}
	return text
}
func durationText(value int64) string {
	sign := ""
	if value < 0 {
		sign = "-"
		value = -value
	}
	return fmt.Sprintf("%s%d:%02d:%02d", sign, value/3600, value/60%60, value%60)
}
func clockText(value int64) string {
	text := fmt.Sprintf("%d:%02d", value/3600, value/60%60)
	if value%60 != 0 {
		text += fmt.Sprintf(":%02d", value%60)
	}
	return text
}
func stateText(period Period) string {
	kind := "STD"
	if period.DST {
		kind = "DST"
	}
	return offsetText(period.Offset) + " " + kind + " " + period.Abbreviation
}
func changeText(time int64, before, after Period) string {
	return utText(time) + " " + stateText(before) + " -> " + stateText(after)
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func writeBlocks(name string, blocks [][]string) {
	lines := []string{}
	for i, block := range blocks {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, block...)
	}
	writeLines(name, lines)
}
