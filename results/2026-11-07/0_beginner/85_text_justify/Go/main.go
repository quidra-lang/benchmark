package main

import (
	"fmt"
	"strings"
)

func main() {
	paragraph := "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week."
	width := 30
	words := strings.Split(paragraph, " ")
	for start := 0; start < len(words); {
		end, letters := start, 0
		for end < len(words) && letters+len(words[end])+end-start <= width {
			letters += len(words[end])
			end++
		}
		gaps, last := end-start-1, end == len(words)
		line := ""
		for i := start; i < end; i++ {
			line += words[i]
			if i+1 < end {
				spaces := 1
				if !last && gaps > 0 {
					spaces = (width - letters) / gaps
					if i-start < (width-letters)%gaps {
						spaces++
					}
				}
				line += strings.Repeat(" ", spaces)
			}
		}
		line += strings.Repeat(" ", width-len(line))
		fmt.Printf("|%s|\n", line)
		start = end
	}
}
