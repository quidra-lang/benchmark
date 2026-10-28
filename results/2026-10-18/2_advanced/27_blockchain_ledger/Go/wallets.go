package main

import "fmt"

type Wallet struct{ Name, Secret, Address string }

func readWallets() []*Wallet {
	wallets := []*Wallet{}
	for _, line := range readLines("input/wallets.txt") {
		var name, secret string
		fmt.Sscan(line, &name, &secret)
		wallets = append(wallets, &Wallet{name, secret, digest("addr:" + secret)[:16]})
	}
	return wallets
}
func sign(secret string, index int, body string) string {
	return digest(fmt.Sprintf("%s:%d:%s", secret, index, body))[:16]
}
