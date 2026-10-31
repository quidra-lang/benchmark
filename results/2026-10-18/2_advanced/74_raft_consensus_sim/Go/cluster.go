package main

import (
	"os"
	"strconv"
	"strings"
)

type Settings struct{ n, emin, emax, h, b, q, seed, end, retry, attempts, sample int }
type Control struct {
	time int
	kind string
	args []string
}
type Request struct {
	number, time, initial, destination, scheduled, attempts, redirects, index, term, latency int
	command, status, result                                                                  string
	abandoned                                                                                bool
}

func number(s string) int { n, _ := strconv.Atoi(s); return n }
func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func readSettings() Settings {
	a := readLines("input/cluster.txt")
	v := make([][]string, len(a))
	for i, s := range a {
		v[i] = strings.Fields(s)
	}
	return Settings{number(v[0][1]), number(v[1][1]), number(v[1][2]),
		number(v[2][1]), number(v[3][1]), number(v[4][1]), number(v[5][1]), number(v[6][1]), number(v[7][1]),
		number(v[8][1]), number(v[9][1])}
}
func readScript() ([]Control, []*Request) {
	var controls []Control
	var requests []*Request
	for _, line := range readLines("input/script.txt") {
		a := strings.Fields(line)
		t := number(a[0])
		if a[1] == "REQUEST" {
			v := number(a[2])
			requests = append(requests,
				&Request{number: len(requests) + 1, time: t, initial: v, destination: v, scheduled: t, command: strings.Join(a[3:],
					" ")})
		} else {
			controls = append(controls, Control{t, a[1], a[2:]})
		}
	}
	return controls, requests
}
func parseGroups(a []string) [][]int {
	out := make([][]int, len(a))
	for i, g := range a {
		for _, v := range strings.Split(g,
			",") {
			out[i] = append(out[i], number(v))
		}
	}
	return out
}
