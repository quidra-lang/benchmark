package main

import (
	"fmt"
	"strings"
)

type Reference struct {
	Txid  string
	Index int
}

func (r Reference) String() string { return fmt.Sprintf("%s:%d", r.Txid, r.Index) }
func referenceLess(a, b Reference) bool {
	if a.Txid != b.Txid {
		return a.Txid < b.Txid
	}
	return a.Index < b.Index
}

type Output struct {
	Address string
	Amount  int
}
type Coin struct {
	Output
	Height   int
	Coinbase bool
}
type Utxo map[Reference]Coin
type Transaction struct {
	Text, Txid, Body string
	Size, Height     int
	Coinbase         bool
	Inputs           []Reference
	Outputs          []Output
	Signatures       []string
}

func parseTransaction(text string) *Transaction {
	parts := strings.Split(text, ";")
	t := &Transaction{Text: text, Txid: digest(text), Size: len(text), Coinbase: strings.HasPrefix(text, "cb=")}
	for _, entry := range strings.Split(parts[1][4:], ",") {
		fields := strings.Split(entry, ":")
		t.Outputs = append(t.Outputs, Output{fields[0], integer(fields[1])})
	}
	if t.Coinbase {
		t.Height = integer(parts[0][3:])
	} else {
		for _, entry := range strings.Split(parts[0][3:], ",") {
			fields := strings.Split(entry, ":")
			t.Inputs = append(t.Inputs, Reference{fields[0], integer(fields[1])})
		}
		t.Signatures = strings.Split(parts[2][4:], ",")
		t.Body = text[:strings.Index(text, ";sig=")]
	}
	return t
}
func outputsText(outputs []Output) string {
	parts := []string{}
	for _, out := range outputs {
		parts = append(parts, fmt.Sprintf("%s:%d", out.Address, out.Amount))
	}
	return strings.Join(parts, ",")
}
func payment(inputs []Reference, outputs []Output, secret string) *Transaction {
	parts := []string{}
	for _, ref := range inputs {
		parts = append(parts, ref.String())
	}
	body := "in=" + strings.Join(parts, ",") + ";out=" + outputsText(outputs)
	signatures := []string{}
	for i := range inputs {
		signatures = append(signatures, sign(secret, i, body))
	}
	return parseTransaction(body + ";sig=" + strings.Join(signatures, ","))
}
func coinbase(height int, outputs []Output) *Transaction {
	return parseTransaction(fmt.Sprintf("cb=%d;out=%s", height, outputsText(outputs)))
}
func (t *Transaction) OutputTotal() int {
	total := 0
	for _, out := range t.Outputs {
		total += out.Amount
	}
	return total
}
func (c Coin) Mature(height, maturity int) bool {
	return !c.Coinbase || c.Height == 0 || height >= c.Height+maturity
}
func checkTransaction(t *Transaction, utxo Utxo, spent map[Reference]bool, height, maturity int, owners map[string]*Wallet) (string, int) {
	for _, out := range t.Outputs {
		if owners[out.Address] == nil || out.Amount == 0 {
			return "bad-output", 0
		}
	}
	seen := map[Reference]bool{}
	total := 0
	for i, ref := range t.Inputs {
		if spent[ref] || seen[ref] {
			return "double-spend", 0
		}
		c, ok := utxo[ref]
		if !ok {
			return "missing-input", 0
		}
		if !c.Mature(height, maturity) {
			return "immature", 0
		}
		if t.Signatures[i] != sign(owners[c.Address].Secret, i, t.Body) {
			return "bad-sig", 0
		}
		seen[ref] = true
		total += c.Amount
	}
	if total < t.OutputTotal() {
		return "overspend", 0
	}
	return "", total - t.OutputTotal()
}
func applyTransaction(utxo Utxo, t *Transaction, height int) {
	for _, ref := range t.Inputs {
		delete(utxo, ref)
	}
	for j, out := range t.Outputs {
		utxo[Reference{t.Txid, j}] = Coin{out, height, t.Coinbase}
	}
}
func copyUtxo(source Utxo) Utxo {
	target := Utxo{}
	for k, v := range source {
		target[k] = v
	}
	return target
}
