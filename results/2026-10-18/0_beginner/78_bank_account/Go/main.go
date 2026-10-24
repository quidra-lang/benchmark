package main

import (
	"fmt"
	"strings"
	"strconv"
	"sort"
)

func main() {
	balances := map[string]int{"Nina": 12000, "Leo": 3500, "Emma": 800}
	for k, transaction := range []string{"deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000",
		"withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000", "withdraw Emma 300",
		"deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800"} {
		parts := strings.Fields(transaction)
		op, from := parts[0], parts[1]
		amount, _ := strconv.Atoi(parts[len(parts) - 1])
		ok := op == "deposit" || balances[from] >= amount
		if ok {
			if op == "deposit" {
				balances[from] += amount
			} else {
				balances[from] -= amount
				if op == "transfer" {
					balances[parts[2]] += amount
				}
			}
		}
		result := "failed (insufficient funds)"
		if ok {
			result = "ok"
		}
		fmt.Printf("op %d: %s %s\n", k + 1, transaction, result)
	}
	names := []string{}
	for name := range balances {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		fmt.Printf("%s: %d\n", name, balances[name])
	}
}
