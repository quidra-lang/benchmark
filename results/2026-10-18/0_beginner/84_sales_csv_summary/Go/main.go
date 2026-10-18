package main

import (
	"fmt"
	"strings"
	"strconv"
	"sort"
)

func main() {
	lines := []string{"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",
		"2026-04-01,east,marker,6,150", "2026-04-01,south,eraser,25,80", "2026-04-02,west,stapler,4,600",
		"2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",
		"2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",
		"2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"}
	regions, products, days := map[string]int{}, map[string]int{}, map[string]int{}
	total := 0
	for _, line := range lines[1:] {
		fields := strings.Split(line, ",")
		quantity, _ := strconv.Atoi(fields[3])
		price, _ := strconv.Atoi(fields[4])
		amount := quantity * price
		total += amount
		regions[fields[1]] += amount
		products[fields[2]] += quantity
		days[fields[0]] += amount
	}
	regionNames := []string{}
	for name := range regions {
		regionNames = append(regionNames, name)
	}
	sort.Slice(regionNames, func(i, j int) bool {
		a, b := regionNames[i], regionNames[j]
		if regions[a] != regions[b] {
			return regions[a] > regions[b]
		}
		return a < b
	})
	fmt.Printf("total: %d\n", total)
	for _, name := range regionNames {
		fmt.Printf("%s: %d\n", name, regions[name])
	}
	productNames := []string{}
	for name := range products {
		productNames = append(productNames, name)
	}
	sort.Strings(productNames)
	for _, name := range productNames {
		fmt.Printf("%s: %d\n", name, products[name])
	}
	best, bestTotal := "", -1
	for date, sales := range days {
		if sales > bestTotal || sales == bestTotal && (best == "" || date < best) {
			best, bestTotal = date, sales
		}
	}
	fmt.Printf("best day: %s (%d)\n", best, bestTotal)
}
