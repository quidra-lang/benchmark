package main

import "strings"

type ModeItem struct {
	sign, flag, arg string
	has             bool
}

func modeItems(mode string, args []string) []ModeItem {
	var out []ModeItem
	sign := "+"
	at := 0
	for _, r := range mode {
		flag := string(r)
		if flag == "+" || flag == "-" {
			sign = flag
			continue
		}
		item := ModeItem{sign: sign,
			flag: flag}
		take := flag == "o" || flag == "v" || flag == "b" || flag == "k" || flag == "l" && sign == "+"
		if take && at < len(args) {
			item.arg = args[at]
			item.has = true
			at++
		}
		if flag == "k" && sign == "-" {
			item.arg = "*"
			item.has = true
		}
		if flag == "l" && sign == "+" && (!item.has || !digits(item.arg) || len(item.arg) > 4 || number(item.arg) < 1) {
			item.has = false
		}
		out = append(out,
			item)
	}
	return out
}
func changeString(changes []ModeItem) string {
	var mode strings.Builder
	var args []string
	last := ""
	for _, c := range changes {
		if c.sign != last {
			mode.WriteString(c.sign)
			last = c.sign
		}
		mode.WriteString(c.flag)
		if c.has {
			args = append(args,
				c.arg)
		}
	}
	if len(args) > 0 {
		return mode.String() + " " + strings.Join(args, " ")
	}
	return mode.String()
}
