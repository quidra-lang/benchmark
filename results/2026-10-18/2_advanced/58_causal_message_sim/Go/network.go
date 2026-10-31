package main

import (
	"os"
	"strconv"
	"strings"
)

type ChannelKey struct{ Source, Destination int }
type Channel struct {
	Source, Destination                                                       int
	Kind                                                                      string
	A, B, Sequence, LastArrival, Copies, Markers, Buffered, MaxDelay, Entries int
	Previous                                                                  []int
}
type Network struct {
	Names    []string
	Index    map[string]int
	Channels map[ChannelKey]*Channel
	Order    []ChannelKey
	State    int64
	Draws    int
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
func readNetwork(seed int) Network {
	lines := readLines("input/topology.txt")
	n := Network{Names: strings.Fields(lines[0])[1:], Index: map[string]int{}, Channels: map[ChannelKey]*Channel{}, State: int64(seed)}
	for i, name := range n.Names {
		n.Index[name] = i
	}
	for _, line := range lines[1:] {
		a := strings.Fields(line)
		src, dst := n.Index[a[1]], n.Index[a[2]]
		lo := integer(a[4])
		hi := lo
		if len(a) == 6 {
			hi = integer(a[5])
		}
		n.Channels[ChannelKey{src, dst}] = &Channel{Source: src, Destination: dst, Kind: a[3], A: lo, B: hi, Previous: make([]int, len(n.Names))}
	}
	for src := range n.Names {
		for dst := range n.Names {
			if src != dst {
				n.Order = append(n.Order, ChannelKey{src, dst})
			}
		}
	}
	return n
}
func (n *Network) dispatch(src, dst, time int, copy *Copy) (int, int) {
	c := n.Channels[ChannelKey{src, dst}]
	c.Sequence++
	delay := c.A
	if c.A != c.B {
		n.State = 48271 * n.State % 2147483647
		n.Draws++
		delay += int(n.State % int64(c.B-c.A+1))
	}
	arrival := time + delay
	if c.Kind == "FIFO" {
		arrival = max(arrival, c.LastArrival)
	}
	c.LastArrival = max(c.LastArrival, arrival)
	c.MaxDelay = max(c.MaxDelay, arrival-time)
	if copy == nil {
		c.Markers++
	} else {
		c.Copies++
		v := copy.Message.Event.V
		for i, x := range v {
			if x != c.Previous[i] {
				c.Entries++
			}
		}
		c.Previous = append([]int(nil), v...)
	}
	return c.Sequence, arrival
}
