package main

import "fmt"

func digest(text string) string {
	result := ""
	for _, lane := range [][2]int64{{1000003, 11}, {1500007, 23}, {2750159, 37}, {4194301, 53}} {
		h := lane[1]
		for i := 0; i < len(text); i++ {
			h = (h*lane[0] + int64(text[i])) % 2147483647
		}
		for _, extra := range []int64{int64(len(text)), 0, 0} {
			h = (h*lane[0] + extra) % 2147483647
		}
		result += fmt.Sprintf("%08x", h)
	}
	return result
}
func merkleRoot(hashes []string) string {
	level := append([]string(nil), hashes...)
	for len(level) > 1 {
		if len(level)%2 == 1 {
			level = append(level, level[len(level)-1])
		}
		next := []string{}
		for i := 0; i < len(level); i += 2 {
			next = append(next, digest(level[i]+level[i+1]))
		}
		level = next
	}
	return level[0]
}
func short(value string) string { return value[:8] }
