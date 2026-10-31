package main

import (
	"math/bits"
	"slices"
	"sort"
)

type Improvement struct {
	Node    int
	Welfare int64
	Bids    []*Bid
}
type SearchResult struct {
	Welfare                             int64
	Bids                                []*Bid
	Nodes, Pruned, Leaves, Improvements int
	Records                             []Improvement
	Shares                              []Fraction
	Sources                             []int
	Bound                               Fraction
}

func usable(bids []*Bid, decided, xorWinners int) []*Bid {
	out := []*Bid{}
	for _, b := range bids {
		if b.Mask&decided == 0 && (!b.XOR || xorWinners&(1<<b.Bidder) == 0) {
			out = append(out, b)
		}
	}
	return out
}
func shares(items []Item, offered, decided int, bids []*Bid, w int64) ([]Fraction, []int, Fraction) {
	values := make([]Fraction, len(items))
	sources := make([]int, len(items))
	bound := whole(w)
	for i, item := range items {
		if offered&(1<<i) == 0 || decided&(1<<i) != 0 {
			continue
		}
		value := whole(item.Reserve)
		for _, b := range bids {
			if b.Mask&(1<<i) != 0 {
				v := fraction(b.Amount, int64(b.Size))
				if v.Cmp(value) > 0 {
					value = v
					sources[i] = b.Number
				}
			}
		}
		values[i] = value
		bound = bound.Add(value)
	}
	return values, sources, bound
}
func bidNumbers(a []*Bid) []int {
	out := make([]int, len(a))
	for i, b := range a {
		out[i] = b.Number
	}
	return out
}
func solveWDP(items []Item, offered int, bids []*Bid) *SearchResult {
	r := &SearchResult{}
	r.Shares, r.Sources, r.Bound = shares(items, offered, 0, bids, 0)
	incumbent := false
	var visit func(int, int, int64, []*Bid)
	visit = func(decided, xorWinners int, w int64, chosen []*Bid) {
		r.Nodes++
		if decided == offered {
			r.Leaves++
			list := slices.Clone(chosen)
			sort.Slice(list, func(i, j int) bool { return list[i].Number < list[j].Number })
			if !incumbent || w > r.Welfare || (w == r.Welfare && slices.Compare(bidNumbers(list), bidNumbers(r.Bids)) < 0) {
				incumbent = true
				r.Welfare = w
				r.Bids = list
				r.Improvements++
				r.Records = append(r.Records, Improvement{r.Nodes, w, list})
			}
			return
		}
		available := usable(bids, decided, xorWinners)
		_, _, bound := shares(items, offered, decided, available, w)
		if incumbent && bound.Cmp(whole(r.Welfare)) < 0 {
			r.Pruned++
			return
		}
		j := bits.TrailingZeros(uint(offered &^ decided))
		for _, b := range available {
			if b.Mask&(1<<j) == 0 {
				continue
			}
			nextXOR := xorWinners
			if b.XOR {
				nextXOR |= 1 << b.Bidder
			}
			next := append(slices.Clone(chosen), b)
			visit(decided|b.Mask, nextXOR, w+b.Amount, next)
		}
		visit(decided|(1<<j), xorWinners, w+items[j].Reserve, chosen)
	}
	visit(0, 0, 0, nil)
	return r
}
func greedyOrder(bids []*Bid) []*Bid {
	out := slices.Clone(bids)
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		left, right := a.Amount*a.Amount*int64(b.Size), b.Amount*b.Amount*int64(a.Size)
		if left != right {
			return left > right
		}
		return a.Number < b.Number
	})
	return out
}
func greedySelect(order []*Bid, excluded int) []*Bid {
	mask, xorWinners := 0, 0
	out := []*Bid{}
	for _, b := range order {
		if b.Number == excluded || b.Mask&mask != 0 || (b.XOR && xorWinners&(1<<b.Bidder) != 0) {
			continue
		}
		out = append(out, b)
		mask |= b.Mask
		if b.XOR {
			xorWinners |= 1 << b.Bidder
		}
	}
	return out
}
