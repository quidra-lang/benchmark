package main

import (
	"os"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
)

var settingNames = []string{"layering", "width", "promotion", "heuristic", "sweeps", "node_sep", "dummy_sep", "layer_gap", "direction", "sifting", "reduce", "restarts", "seed"}

type Settings struct {
	Layering, Promotion, Heuristic, Direction, Sifting, Reduce string
	Width, Sweeps, NodeSep, DummySep, LayerGap, Restarts       int
	Seed                                                       int64
}

func defaultSettings() Settings {
	return Settings{Layering: "longest", Width: 4, Promotion: "off", Heuristic: "barycenter", Sweeps: 12, NodeSep: 2, DummySep: 1, LayerGap: 3, Direction: "TB", Sifting: "off", Reduce: "off", Seed: 1}
}
func (s Settings) Values() []string {
	return []string{s.Layering, strconv.Itoa(s.Width), s.Promotion, s.Heuristic, strconv.Itoa(s.Sweeps), strconv.Itoa(s.NodeSep), strconv.Itoa(s.DummySep), strconv.Itoa(s.LayerGap), s.Direction, s.Sifting, s.Reduce, strconv.Itoa(s.Restarts), strconv.FormatInt(s.Seed, 10)}
}

var integerWord = regexp.MustCompile(`^[0-9]{1,10}$`)

func (s *Settings) Set(name, value string) bool {
	options := map[string][]string{"layering": {"longest", "coffman"}, "promotion": {"on", "off"}, "heuristic": {"barycenter", "median"}, "direction": {"TB", "BT", "LR", "RL"}, "sifting": {"on", "off"}, "reduce": {"on", "off"}}
	if choices, ok := options[name]; ok {
		if !slices.Contains(choices, value) {
			return false
		}
		switch name {
		case "layering":
			s.Layering = value
		case "promotion":
			s.Promotion = value
		case "heuristic":
			s.Heuristic = value
		case "direction":
			s.Direction = value
		case "sifting":
			s.Sifting = value
		case "reduce":
			s.Reduce = value
		}
		return true
	}
	ranges := map[string][2]int64{"width": {1, 40}, "sweeps": {0, 50}, "node_sep": {1, 9}, "dummy_sep": {1, 9}, "layer_gap": {2, 9}, "restarts": {0, 9}, "seed": {1, 2147483646}}
	bounds, ok := ranges[name]
	if !ok || !integerWord.MatchString(value) {
		return false
	}
	number, _ := strconv.ParseInt(value, 10, 64)
	if number < bounds[0] || number > bounds[1] {
		return false
	}
	switch name {
	case "width":
		s.Width = int(number)
	case "sweeps":
		s.Sweeps = int(number)
	case "node_sep":
		s.NodeSep = int(number)
	case "dummy_sep":
		s.DummySep = int(number)
	case "layer_gap":
		s.LayerGap = int(number)
	case "restarts":
		s.Restarts = int(number)
	case "seed":
		s.Seed = number
	}
	return true
}

type NodeData struct {
	ID    int
	Label string
}
type RawEdge struct{ From, To int }
type Block struct {
	Name                                    string
	Settings                                Settings
	Nodes                                   []NodeData
	Edges                                   []RawEdge
	HasPath                                 bool
	PathFrom, PathTo, SelfLoops, Duplicates int
	Error                                   string
	ErrorLine                               int
}

func readBlocks() []*Block {
	defaults := defaultSettings()
	for _, line := range lines("input/params.txt") {
		if ignored(line) {
			continue
		}
		a := strings.Split(line, " ")
		defaults.Set(a[0], a[1])
	}
	out := []*Block{}
	var block *Block
	declared := map[int]bool{}
	accepted := map[[2]int]bool{}
	for index, line := range lines("input/graphs.txt") {
		if ignored(line) {
			continue
		}
		a := strings.Split(line, " ")
		if a[0] == "GRAPH" {
			block = &Block{Name: a[1], Settings: defaults}
			out = append(out, block)
			declared = map[int]bool{}
			accepted = map[[2]int]bool{}
			continue
		}
		if block.Error != "" {
			continue
		}
		reason := ""
		switch a[0] {
		case "OPTION":
			if !block.Settings.Set(a[1], a[2]) {
				reason = "bad_option"
			}
		case "NODE":
			id := integer(a[1])
			if declared[id] {
				reason = "duplicate_node"
			} else if len(block.Nodes) == 40 {
				reason = "too_many_nodes"
			} else {
				declared[id] = true
				block.Nodes = append(block.Nodes, NodeData{id, a[2]})
			}
		case "EDGE":
			from, to := integer(a[1]), integer(a[2])
			if !declared[from] || !declared[to] {
				reason = "unknown_node"
			} else if from == to {
				block.SelfLoops++
			} else if accepted[[2]int{from, to}] {
				block.Duplicates++
			} else {
				accepted[[2]int{from, to}] = true
				block.Edges = append(block.Edges, RawEdge{from, to})
			}
		case "PATH":
			from, to := integer(a[1]), integer(a[2])
			if !declared[from] || !declared[to] {
				reason = "unknown_node"
			} else {
				block.HasPath = true
				block.PathFrom = from
				block.PathTo = to
			}
		case "END":
			if len(block.Nodes) == 0 {
				reason = "no_nodes"
			}
		}
		if reason != "" {
			block.Error = reason
			block.ErrorLine = index + 1
		}
	}
	for _, b := range out {
		sort.Slice(b.Nodes, func(i, j int) bool { return b.Nodes[i].ID < b.Nodes[j].ID })
	}
	return out
}
func integer(s string) int {
	n, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return n
}
func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func ignored(s string) bool { return s == "" || s[0] == '#' }
