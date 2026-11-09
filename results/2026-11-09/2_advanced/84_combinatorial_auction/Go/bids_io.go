package main

import (
	"os"
	"strconv"
	"strings"
)

type Item struct {
	Name    string
	Reserve int64
}
type BidLine struct {
	Name, Language string
	Raw            []string
}
type RawAuction struct {
	Name    string
	Offered []string
	Lines   []BidLine
}
type Participant struct {
	Name       string
	Value, Bid int64
}
type Group struct {
	Kind, Name   string
	Arguments    []string
	Participants []Participant
}
type Input struct {
	Items      []Item
	Auctions   map[string]RawAuction
	Groups     []Group
	Runs       []string
	Parameters map[string]int64
}
type Bid struct {
	Number, Bidder, Mask, Size int
	Amount, Reserve            int64
	XOR                        bool
}

func integer(s string) int64 {
	n, e := strconv.ParseInt(s, 10, 64)
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
func readInput() Input {
	in := Input{Auctions: map[string]RawAuction{}, Parameters: map[string]int64{}}
	for _, line := range lines("input/items.txt") {
		a := strings.Fields(line)
		in.Items = append(in.Items, Item{a[0], integer(a[1])})
	}
	var current *RawAuction
	for _, line := range lines("input/bids.txt") {
		a := strings.Fields(line)
		if a[0] == "auction" {
			if current != nil {
				in.Auctions[current.Name] = *current
			}
			current = &RawAuction{Name: a[1], Offered: a[2:]}
		} else {
			current.Lines = append(current.Lines, BidLine{a[1], a[2], a[3:]})
		}
	}
	if current != nil {
		in.Auctions[current.Name] = *current
	}
	for _, line := range lines("input/single_item.txt") {
		a := strings.Fields(line)
		if a[0] == "lot" || a[0] == "slots" {
			in.Groups = append(in.Groups, Group{Kind: a[0], Name: a[1], Arguments: a[2:]})
		} else {
			i := len(in.Groups) - 1
			in.Groups[i].Participants = append(in.Groups[i].Participants, Participant{a[1], integer(a[2]), integer(a[3])})
		}
	}
	for _, line := range lines("input/params.txt") {
		a := strings.Fields(line)
		if a[0] == "run" {
			in.Runs = a[1:]
		} else {
			in.Parameters[a[0]] = integer(a[1])
		}
	}
	return in
}
