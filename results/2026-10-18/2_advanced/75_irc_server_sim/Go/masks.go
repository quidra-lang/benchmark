package main

import "strings"

func matchMask(mask, text string) bool {
	mask, text = fold(mask), fold(text)
	i, j, star, mark := 0, 0, -1, 0
	for j < len(text) {
		if i < len(mask) && (mask[i] == '?' || mask[i] == text[j]) {
			i++
			j++
		} else if i < len(mask) && mask[i] == '*' {
			star = i
			i++
			mark = j
		} else if star >= 0 {
			mark++
			j = mark
			i = star + 1
		} else {
			return false
		}
	}
	for i < len(mask) && mask[i] == '*' {
		i++
	}
	return i == len(mask)
}
func normalizeMask(s string) string {
	bang, at := strings.Contains(s, "!"), strings.Contains(s, "@")
	if bang && at {
		return s
	}
	if at {
		return "*!" + s
	}
	if bang {
		return s + "@*"
	}
	if strings.Contains(s,
		".") {
		return "*!*@" + s
	}
	return s + "!*@*"
}
