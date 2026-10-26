package main

import (
	"os"
	"strconv"
	"strings"
)

type Params struct {
	referenceDay, snapshotDay, outcomeDays, kMin, kMax, restarts, maxIterations, subsamples, subsamplePercent, overdueFactor, topCategories, topCustomers, periodDays, periods int
	seed                                                                                                                                                                       int64
	methods                                                                                                                                                                    []string
	outlierSD                                                                                                                                                                  float64
	orderBins                                                                                                                                                                  []int64
}
type Row struct {
	customer, orderID, category string
	day                         int
	amount                      int64
}
type TransactionData struct {
	rowCount, duplicates, free int
	validRows                  []Row
	customers                  map[string]bool
}
type Order struct {
	id, customer string
	day          int
	net          int64
	rows         []Row
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func parseInteger(text string) int64 {
	value, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		panic(err)
	}
	return value
}
func parseReal(text string) float64 {
	value, err := strconv.ParseFloat(text, 64)
	if err != nil {
		panic(err)
	}
	return value
}
func readParams() Params {
	values := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		fields := strings.Split(line, " ")
		values[fields[0]] = fields[1:]
	}
	number := func(key string) int { return int(parseInteger(values[key][0])) }
	p := Params{referenceDay: number("REFERENCE_DAY"), snapshotDay: number("SNAPSHOT_DAY"), outcomeDays: number("OUTCOME_DAYS"), kMin: int(parseInteger(values["K_RANGE"][0])), kMax: int(parseInteger(values["K_RANGE"][1])), methods: values["METHODS"], restarts: number("RESTARTS"), maxIterations: number("MAX_ITERATIONS"), seed: parseInteger(values["SEED"][0]), subsamples: number("SUBSAMPLES"), subsamplePercent: number("SUBSAMPLE_PERCENT"), outlierSD: parseReal(values["OUTLIER_SD"][0]), overdueFactor: number("OVERDUE_FACTOR"), topCategories: number("TOP_CATEGORIES"), topCustomers: number("TOP_CUSTOMERS"), periodDays: number("PERIOD_DAYS"), periods: number("PERIODS")}
	for _, value := range values["ORDER_BINS"] {
		p.orderBins = append(p.orderBins, parseInteger(value))
	}
	return p
}
func readTransactions() TransactionData {
	data := TransactionData{customers: map[string]bool{}}
	seen := map[string]bool{}
	for _, line := range readLines("input/transactions.csv")[1:] {
		fields := strings.Split(line, ",")
		row := Row{fields[0], fields[2], fields[3], int(parseInteger(fields[1])), parseInteger(fields[4])}
		data.rowCount++
		data.customers[row.customer] = true
		if seen[line] {
			data.duplicates++
		} else if row.amount == 0 {
			data.free++
		} else {
			data.validRows = append(data.validRows, row)
		}
		seen[line] = true
	}
	return data
}
func groupOrders(rows []Row, first, last int) []*Order {
	orders := []*Order{}
	byID := map[string]*Order{}
	for _, row := range rows {
		if row.day < first || row.day > last {
			continue
		}
		order := byID[row.orderID]
		if order == nil {
			order = &Order{id: row.orderID, customer: row.customer, day: row.day}
			byID[row.orderID] = order
			orders = append(orders, order)
		}
		order.day = min(order.day, row.day)
		order.net += row.amount
		order.rows = append(order.rows, row)
	}
	return orders
}
func ordersByCustomer(orders []*Order) map[string][]*Order {
	groups := map[string][]*Order{}
	for _, order := range orders {
		groups[order.customer] = append(groups[order.customer], order)
	}
	return groups
}
