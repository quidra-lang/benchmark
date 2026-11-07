package main

import "fmt"

func main() {
	board := []string{"MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN", "KUVNGSBPRO",
		"RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR"}
	names := []string{"E", "SE", "S", "SW", "W", "NW", "N", "NE"}
	dr, dc := []int{0, 1, 1, 1, 0, -1, -1, -1}, []int{1, 1, 0, -1, -1, -1, 0, 1}
	for _, word := range []string{"TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"} {
		found := false
		for r := 0; r < 10 && !found; r++ {
			for c := 0; c < 10 && !found; c++ {
				for d := 0; d < 8; d++ {
					match := true
					for k := range word {
						rr, cc := r+dr[d]*k, c+dc[d]*k
						if rr < 0 || rr >= 10 || cc < 0 || cc >= 10 || board[rr][cc] != word[k] {
							match = false
							break
						}
					}
					if match {
						fmt.Printf("%s: (%d, %d) %s\n", word, r, c, names[d])
						found = true
						break
					}
				}
			}
		}
		if !found {
			fmt.Printf("%s: not found\n", word)
		}
	}
}
