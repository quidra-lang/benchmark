package main

import (
	"math/bits"
	"slices"
	"sort"
)

type VCGPayment struct {
	Value, Without, Payment, Utility int64
	Won, Alternative                 []*Bid
}

func vcgPayments(items []Item, offered, n int, eligible, winning []*Bid, welfare int64) []VCGPayment {
	out := make([]VCGPayment, n)
	for k := 0; k < n; k++ {
		for _, b := range winning {
			if b.Bidder == k {
				out[k].Won = append(out[k].Won, b)
				out[k].Value += b.Amount
			}
		}
		if len(out[k].Won) == 0 {
			continue
		}
		without := []*Bid{}
		for _, b := range eligible {
			if b.Bidder != k {
				without = append(without, b)
			}
		}
		r := solveWDP(items, offered, without)
		out[k].Without = r.Welfare
		out[k].Alternative = r.Bids
		out[k].Payment = r.Welfare - (welfare - out[k].Value)
		out[k].Utility = out[k].Value - out[k].Payment
	}
	return out
}

type Critical struct {
	Payment int64
	Rival   int
}

func criticalPayments(order, winning []*Bid) map[int]Critical {
	out := map[int]Critical{}
	for _, b := range winning {
		rival := (*Bid)(nil)
		for _, c := range greedySelect(order, b.Number) {
			if c.Mask&b.Mask != 0 || (b.XOR && b.Bidder == c.Bidder) {
				rival = c
				break
			}
		}
		payment := b.Reserve
		against := 0
		if rival != nil {
			against = rival.Number
			before := func(t int64) bool {
				left, right := t*t*int64(rival.Size), rival.Amount*rival.Amount*int64(b.Size)
				return left > right || (left == right && b.Number < rival.Number)
			}
			lo, hi := int64(1), int64(1)
			for !before(hi) {
				hi *= 2
			}
			for lo < hi {
				mid := (lo + hi) / 2
				if before(mid) {
					hi = mid
				} else {
					lo = mid + 1
				}
			}
			payment = max(payment, lo)
		}
		out[b.Number] = Critical{payment, against}
	}
	return out
}

type Coalition struct {
	Mask    int
	Welfare int64
	Bids    []*Bid
	Members []int
}

func coalitions(items []Item, offered, n int, bids []*Bid) []Coalition {
	out := make([]Coalition, 1<<n)
	for mask := range out {
		members := []int{}
		for i := 0; i < n; i++ {
			if mask&(1<<i) != 0 {
				members = append(members, i)
			}
		}
		eligible := []*Bid{}
		for _, b := range bids {
			if mask&(1<<b.Bidder) != 0 {
				eligible = append(eligible, b)
			}
		}
		r := solveWDP(items, offered, eligible)
		out[mask] = Coalition{mask, r.Welfare, r.Bids, members}
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		ac, bc := bits.OnesCount(uint(a.Mask)), bits.OnesCount(uint(b.Mask))
		if ac != bc {
			return ac < bc
		}
		return slices.Compare(a.Members, b.Members) < 0
	})
	return out
}

type Blocking struct {
	Coalition       Coalition
	Payoff, Deficit int64
	Minimal         bool
}

func blockers(cs []Coalition, seller int64, utilities []int64) []Blocking {
	out := []Blocking{}
	for _, c := range cs {
		payoff := seller
		for _, i := range c.Members {
			payoff += utilities[i]
		}
		if c.Welfare <= payoff {
			continue
		}
		minimal := true
		for _, old := range out {
			if old.Coalition.Mask&c.Mask == old.Coalition.Mask {
				minimal = false
				break
			}
		}
		out = append(out, Blocking{c, payoff, c.Welfare - payoff, minimal})
	}
	return out
}
func gspPrice(participants []Participant, order []int, rank int) int64 {
	if rank+1 >= len(order) {
		return 0
	}
	return participants[order[rank+1]].Bid
}
func slotVCG(participants []Participant, order []int, ctr []Fraction, rank int) Fraction {
	value := whole(0)
	rate := func(i int) Fraction {
		if i >= len(ctr) {
			return whole(0)
		}
		return ctr[i]
	}
	for t := rank + 1; t < min(len(order), len(ctr)+1); t++ {
		value = value.Add(whole(participants[order[t]].Value).Mul(rate(t - 1).Sub(rate(t))))
	}
	return value
}
