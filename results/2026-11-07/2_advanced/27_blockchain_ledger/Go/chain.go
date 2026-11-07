package main

import "sort"

type BlockRecord struct {
	Block           *Block
	Parent          *BlockRecord
	Utxo            Utxo
	TransactionFees []int
	Fees, Work      int
	Source          string
}

func newRecord(b *Block, p *BlockRecord, u Utxo, fees []int, source string) *BlockRecord {
	r := &BlockRecord{Block: b, Parent: p, Utxo: u, TransactionFees: fees, Source: source, Work: 1}
	for _, f := range fees {
		r.Fees += f
	}
	if p != nil {
		r.Work = p.Work + (1 << uint(4*b.Difficulty))
	}
	return r
}
func reward(height, initial, interval int) int {
	for i := 0; i < height/interval; i++ {
		initial /= 2
	}
	return initial
}
func ancestor(r *BlockRecord, height int) *BlockRecord {
	for r.Block.Height > height {
		r = r.Parent
	}
	return r
}
func chainTo(r *BlockRecord) []*BlockRecord {
	records := []*BlockRecord{}
	for ; r != nil; r = r.Parent {
		records = append(records, r)
	}
	for i, j := 0, len(records)-1; i < j; i, j = i+1, j-1 {
		records[i], records[j] = records[j], records[i]
	}
	return records
}
func forkPoint(a, b *BlockRecord) *BlockRecord {
	h := min(a.Block.Height, b.Block.Height)
	a, b = ancestor(a, h), ancestor(b, h)
	for a != b {
		a, b = a.Parent, b.Parent
	}
	return a
}
func medianTime(r *BlockRecord) int {
	times := []int{}
	for ; r != nil && len(times) < 3; r = r.Parent {
		times = append(times, r.Block.Timestamp)
	}
	sort.Ints(times)
	return times[(len(times)-1)/2]
}
func requiredDifficulty(parent *BlockRecord, initial, interval, target int) int {
	h := parent.Block.Height + 1
	d := parent.Block.Difficulty
	if h == 1 {
		return initial
	}
	if h%interval != 0 {
		return d
	}
	span := parent.Block.Timestamp - ancestor(parent, h-interval).Block.Timestamp
	expected := target * (interval - 1)
	if 2*span < expected {
		return min(d+1, 2)
	}
	if span > 2*expected {
		return max(d-1, 0)
	}
	return d
}
