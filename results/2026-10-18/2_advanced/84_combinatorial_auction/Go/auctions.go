package main

import "math/bits"

type Candidate struct {
	Mask  int
	Value int64
}

func candidates(bids []*Bid, xor bool) []Candidate {
	out := []Candidate{}
	for code := 1; code < (1 << len(bids)); code++ {
		if xor && bits.OnesCount(uint(code)) != 1 {
			continue
		}
		mask := 0
		value := int64(0)
		valid := true
		for i, b := range bids {
			if code&(1<<i) == 0 {
				continue
			}
			if mask&b.Mask != 0 {
				valid = false
				break
			}
			mask |= b.Mask
			value += b.Amount
		}
		if valid {
			out = append(out, Candidate{mask, value})
		}
	}
	return out
}
func candidateValue(candidates []Candidate, mask int) int64 {
	value := int64(0)
	for _, c := range candidates {
		if c.Mask&mask == c.Mask {
			value = max(value, c.Value)
		}
	}
	return value
}

type ClockResult struct {
	Winner, Steps int
	Price         int64
	Drops         []int64
}

func english(participants []Participant, reserve, increment int64) ClockResult {
	r := ClockResult{Winner: -1, Price: reserve, Drops: make([]int64, len(participants))}
	for i := range r.Drops {
		r.Drops[i] = -1
	}
	remaining := func(price int64) []int {
		out := []int{}
		for i, p := range participants {
			if p.Value >= price {
				out = append(out, i)
			} else if r.Drops[i] < 0 {
				r.Drops[i] = price
			}
		}
		return out
	}
	active := remaining(reserve)
	if len(active) == 0 {
		return r
	}
	if len(active) == 1 {
		r.Winner = active[0]
		return r
	}
	for {
		previous, price := active, r.Price
		r.Price += increment
		r.Steps++
		active = remaining(r.Price)
		if len(active) == 1 {
			r.Winner = active[0]
			return r
		}
		if len(active) == 0 {
			r.Winner = previous[0]
			r.Price = price
			return r
		}
	}
}
func dutch(participants []Participant, reserve, start, decrement int64) ClockResult {
	r := ClockResult{Winner: -1, Price: start}
	for r.Price >= reserve {
		winner := -1
		for i, p := range participants {
			if p.Bid >= r.Price && (winner < 0 || p.Bid > participants[winner].Bid) {
				winner = i
			}
		}
		if winner >= 0 {
			r.Winner = winner
			return r
		}
		r.Price -= decrement
		r.Steps++
	}
	return r
}
