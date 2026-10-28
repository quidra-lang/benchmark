package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Scenario struct {
	name, protocol, l1, l2 string
	order                  int
}
type Region struct {
	name        string
	first, last int
}
type Config struct {
	n, line, l1Size, l1Ways, l2Size, l2Ways, l1Sets, l2Sets, t1, t2, tm, tb, interval, top int
	scenarios                                                                              []Scenario
	primary                                                                                string
	regions                                                                                []Region
	watch                                                                                  []int
}

func number(s string) int    { v, _ := strconv.Atoi(s); return v }
func hexNumber(s string) int { v, _ := strconv.ParseInt(s, 16, 64); return int(v) }
func decimal(s string) bool {
	if s == "" || len(s) > 1 && s[0] == '0' {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
func hexDigits(s string) bool {
	if len(s) != 8 {
		return false
	}
	for _, c := range s {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return true
}
func address(a int) string { return fmt.Sprintf("%08x", a) }
func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data),
		"\n"), "\n")
}
func readConfig() Config {
	c := Config{}
	for _, line := range readLines("input/config.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "CORES":
			c.n = number(a[1])
		case "LINE":
			c.line = number(a[1])
		case "L1":
			c.l1Size = number(a[1])
			c.l1Ways = number(a[2])
		case "L2":
			c.l2Size = number(a[1])
			c.l2Ways = number(a[2])
		case "LATENCY":
			c.t1 = number(a[1])
			c.t2 = number(a[2])
			c.tm = number(a[3])
			c.tb = number(a[4])
		case "SCENARIO":
			c.scenarios = append(c.scenarios,
				Scenario{a[1], a[2], a[3], a[4], len(c.scenarios)})
		case "PRIMARY":
			c.primary = a[1]
		case "INTERVAL":
			c.interval = number(a[1])
		case "TOP":
			c.top = number(a[1])
		case "REGION":
			c.regions = append(c.regions,
				Region{a[1], hexNumber(a[2]), hexNumber(a[3])})
		case "WATCH":
			c.watch = append(c.watch, hexNumber(a[1])/c.line)
		}
	}
	c.l1Sets = c.l1Size / (c.line * c.l1Ways)
	c.l2Sets = c.l2Size / (c.line * c.l2Ways)
	return c
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name,
		[]byte(text), 0644); e != nil {
		panic(e)
	}
}
