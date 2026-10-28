package main

import (
	"os"
	"strconv"
	"strings"
)

type PredictorConfig struct {
	Name, Scheme string
	Parameters   []int
}
type Variant struct {
	Name    string
	Forward bool
	Stage   string
	Latency int
}
type Config struct {
	BTB, RAS                         int
	Predictors                       []PredictorConfig
	Variants                         []Variant
	PrimaryVariant, PrimaryPredictor string
	Start, End, Top, Interval        int
}

func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return []string{}
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func hexValue(s string) (int, bool) {
	if len(s) != 8 {
		return 0, false
	}
	v := 0
	for _, c := range s {
		if c >= '0' && c <= '9' {
			v = v*16 + int(c-'0')
		} else if c >= 'a' && c <= 'f' {
			v = v*16 + int(c-'a'+10)
		} else {
			return 0, false
		}
	}
	return v, true
}
func register(s string) (int, bool) {
	if s == "-" {
		return -1, true
	}
	if len(s) < 2 || s[0] != 'r' {
		return 0, false
	}
	digits := s[1:]
	if len(digits) > 1 && digits[0] == '0' {
		return 0, false
	}
	v := 0
	for _, c := range digits {
		if c < '0' || c > '9' {
			return 0, false
		}
		v = v*10 + int(c-'0')
		if v > 31 {
			return 0, false
		}
	}
	return v, true
}
func readConfig() Config {
	c := Config{}
	for _, line := range readLines("input/config.txt") {
		a := strings.Split(line, " ")
		switch a[0] {
		case "BTB":
			c.BTB = integer(a[1])
		case "RAS":
			c.RAS = integer(a[1])
		case "PREDICTOR":
			p := PredictorConfig{Name: a[1], Scheme: a[2]}
			for _, s := range a[3:] {
				p.Parameters = append(p.Parameters, integer(s))
			}
			c.Predictors = append(c.Predictors, p)
		case "VARIANT":
			c.Variants = append(c.Variants, Variant{a[1], a[2] == "ON", a[3], integer(a[4])})
		case "PRIMARY":
			c.PrimaryVariant, c.PrimaryPredictor = a[1], a[2]
		case "WINDOW":
			c.Start, c.End = integer(a[1]), integer(a[2])
		case "TOP":
			c.Top = integer(a[1])
		case "INTERVAL":
			c.Interval = integer(a[1])
		}
	}
	return c
}
