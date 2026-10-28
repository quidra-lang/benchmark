package main

import (
	"fmt"
	"strings"
)

type Block struct {
	Height                       int
	Previous, Merkle             string
	Timestamp, Difficulty, Nonce int
	Transactions                 []*Transaction
	Hash                         string
}

func newBlock(height int, previous, root string, timestamp, difficulty, nonce int, txs []*Transaction) *Block {
	return &Block{height, previous, root, timestamp, difficulty, nonce, txs, digest(headerText(height, previous, root, timestamp, difficulty, nonce))}
}
func headerText(h int, p, m string, t, d, n int) string {
	return fmt.Sprintf("%d|%s|%s|%d|%d|%d", h, p, m, t, d, n)
}
func (b *Block) Size() int {
	total := 0
	for _, t := range b.Transactions[1:] {
		total += t.Size
	}
	return total
}
func (b *Block) Txids() []string {
	ids := []string{}
	for _, t := range b.Transactions {
		ids = append(ids, t.Txid)
	}
	return ids
}
func parseBlock(fields, texts []string) *Block {
	txs := []*Transaction{}
	for _, text := range texts {
		txs = append(txs, parseTransaction(text))
	}
	return newBlock(integer(fields[3]), fields[4], fields[5], integer(fields[6]), integer(fields[7]), integer(fields[8]), txs)
}
func mineBlock(height int, previous string, txs []*Transaction, timestamp, difficulty int) *Block {
	ids := []string{}
	for _, t := range txs {
		ids = append(ids, t.Txid)
	}
	root := merkleRoot(ids)
	for nonce := 0; ; nonce++ {
		b := newBlock(height, previous, root, timestamp, difficulty, nonce, txs)
		if strings.HasPrefix(b.Hash, strings.Repeat("0", difficulty)) {
			return b
		}
	}
}
func contextFreeError(b *Block, maxSize int) string {
	if !strings.HasPrefix(b.Hash, strings.Repeat("0", b.Difficulty)) {
		return "bad-pow"
	}
	if merkleRoot(b.Txids()) != b.Merkle {
		return "bad-merkle"
	}
	if !b.Transactions[0].Coinbase || b.Transactions[0].Height != b.Height {
		return "bad-structure"
	}
	for _, t := range b.Transactions[1:] {
		if t.Coinbase {
			return "bad-structure"
		}
	}
	if b.Size() > maxSize {
		return "too-large"
	}
	return ""
}
