package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var categories = []string{
	"received", "returned", "adjusted-in", "adjusted-out",
	"shipped", "written-down", "expired", "recalled",
}

type Item struct {
	Code, Name string
	Level int64
	LastCost *int64
	Card []CardEntry
}

type Lot struct {
	Number int
	Item, Warehouse, Kind string
	Day, InitialQuantity, InitialCost, Removed int64
}

type StockLot struct {
	Lot *Lot
	Quantity, Cost int64
}

type Part struct {
	Lot *Lot
	Quantity, Cost int64
}

type Order struct {
	Number int
	Warehouse, Item string
	Day, Price, Ordered, Shipped, Backorder, Cancelled, Returned int64
	Revenue, COGS int64
	Issues []Part
}

type CardEntry struct {
	Day int64
	Kind, Warehouse string
	Quantity, Value int64
}

type Total struct {
	Quantity, Value int64
}

type Inventory struct {
	Day int64
	Stock map[string]map[string]map[int]*StockLot
	Items map[string]*Item
	Lots []*Lot
	Orders []*Order
	Totals map[string]*Total
	Output []string
}

func newInventory() *Inventory {
	inv := &Inventory{
		Day: 1,
		Stock: make(map[string]map[string]map[int]*StockLot),
		Items: make(map[string]*Item),
		Totals: make(map[string]*Total),
	}
	for _, category := range categories {
		inv.Totals[category] = &Total{}
	}
	return inv
}

func integer(text string) int64 {
	value, _ := strconv.ParseInt(text, 10, 64)
	return value
}

func cents(text string) int64 {
	return integer(strings.ReplaceAll(text, ".", ""))
}

func money(amount int64) string {
	sign := ""
	if amount < 0 {
		sign = "-"
		amount = -amount
	}
	return fmt.Sprintf("%s%d.%02d", sign, amount / 100, amount % 100)
}

func signedQuantity(q int64) string {
	if q > 0 {
		return fmt.Sprint("+", q)
	}
	return fmt.Sprint(q)
}

func signedMoney(amount int64) string {
	if amount > 0 {
		return "+" + money(amount)
	}
	return money(amount)
}

func margin(profit, revenue int64) string {
	if revenue == 0 {
		return "n/a"
	}
	absolute := profit
	if absolute < 0 {
		absolute = -absolute
	}
	tenths := absolute * 1000 / revenue
	sign := ""
	if profit < 0 && tenths > 0 {
		sign = "-"
	}
	return fmt.Sprintf("%s%d.%d%%", sign, tenths / 10, tenths % 10)
}

func sumQuantity(stocks []*StockLot) int64 {
	var quantity int64
	for _, stock := range stocks {
		quantity += stock.Quantity
	}
	return quantity
}

func sumValue(stocks []*StockLot) int64 {
	var value int64
	for _, stock := range stocks {
		value += stock.Quantity * stock.Cost
	}
	return value
}

func sortedNames[T any](entries map[string]T) []string {
	names := make([]string, 0, len(entries))
	for name := range entries {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

func (inv *Inventory) emit(indent int, parts ...any) {
	fields := make([]string, len(parts))
	for i, part := range parts {
		fields[i] = fmt.Sprint(part)
	}
	inv.Output = append(inv.Output, strings.Repeat(" ", indent) + strings.Join(fields, " "))
}

func (inv *Inventory) warehouse(code string) error {
	if _, ok := inv.Stock[code]; !ok {
		return fmt.Errorf("unknown warehouse %s", code)
	}
	return nil
}

func (inv *Inventory) item(code string) (*Item, error) {
	item := inv.Items[code]
	if item == nil {
		return nil, fmt.Errorf("unknown item %s", code)
	}
	return item, nil
}

func (inv *Inventory) pair(warehouse, code string) (*Item, error) {
	if err := inv.warehouse(warehouse); err != nil {
		return nil, err
	}
	return inv.item(code)
}

func (inv *Inventory) order(text string) (*Order, error) {
	number := integer(text)
	if number < 1 || number > int64(len(inv.Orders)) {
		return nil, fmt.Errorf("unknown order %s", text)
	}
	return inv.Orders[number-1], nil
}

func (inv *Inventory) lot(text string) (*Lot, error) {
	number := integer(text)
	if number < 1 || number > int64(len(inv.Lots)) {
		return nil, fmt.Errorf("unknown lot %s", text)
	}
	return inv.Lots[number-1], nil
}

func (inv *Inventory) holdings(warehouse, code string) map[int]*StockLot {
	return inv.Stock[warehouse][code]
}

func (inv *Inventory) stocks(warehouse, code string) []*StockLot {
	result := make([]*StockLot, 0)
	for _, stock := range inv.holdings(warehouse, code) {
		result = append(result, stock)
	}
	return result
}

func (inv *Inventory) fifo(warehouse, code string) []*StockLot {
	stocks := inv.stocks(warehouse, code)
	sort.Slice(stocks, func(i, j int) bool {
		if stocks[i].Lot.Day != stocks[j].Lot.Day {
			return stocks[i].Lot.Day < stocks[j].Lot.Day
		}
		return stocks[i].Lot.Number < stocks[j].Lot.Number
	})
	return stocks
}

func (inv *Inventory) quantity(warehouse, code string) int64 {
	return sumQuantity(inv.stocks(warehouse, code))
}

func (inv *Inventory) totalQuantity(code string) int64 {
	var result int64
	for warehouse := range inv.Stock {
		result += inv.quantity(warehouse, code)
	}
	return result
}

func (inv *Inventory) backorder(code string) int64 {
	var result int64
	for _, order := range inv.Orders {
		if order.Item == code {
			result += order.Backorder
		}
	}
	return result
}

func (inv *Inventory) allStocks() []*StockLot {
	result := make([]*StockLot, 0)
	for warehouse := range inv.Stock {
		for code := range inv.Stock[warehouse] {
			result = append(result, inv.stocks(warehouse, code)...)
		}
	}
	return result
}

func (inv *Inventory) requireStock(warehouse, code string, quantity int64) error {
	held := inv.quantity(warehouse, code)
	if held < quantity {
		return fmt.Errorf("insufficient stock %s %s %d", warehouse, code, held)
	}
	return nil
}

func (inv *Inventory) cardEntry(code, kind, warehouse string, quantity, value int64) {
	inv.Items[code].Card = append(inv.Items[code].Card, CardEntry{
		Day: inv.Day, Kind: kind, Warehouse: warehouse, Quantity: quantity, Value: value,
	})
}

func (inv *Inventory) accumulate(category string, quantity, value int64) {
	inv.Totals[category].Quantity += quantity
	inv.Totals[category].Value += value
}

func (inv *Inventory) addStock(warehouse string, lot *Lot, quantity, cost int64) {
	if inv.Stock[warehouse][lot.Item] == nil {
		inv.Stock[warehouse][lot.Item] = make(map[int]*StockLot)
	}
	stocks := inv.Stock[warehouse][lot.Item]
	if stock := stocks[lot.Number]; stock != nil {
		stock.Quantity += quantity
	} else {
		stocks[lot.Number] = &StockLot{Lot: lot, Quantity: quantity, Cost: cost}
	}
}

func (inv *Inventory) createLot(warehouse, code string, day, quantity, cost int64, kind string) *Lot {
	lot := &Lot{
		Number: len(inv.Lots) + 1, Item: code, Warehouse: warehouse, Kind: kind,
		Day: day, InitialQuantity: quantity, InitialCost: cost,
	}
	inv.Lots = append(inv.Lots, lot)
	inv.addStock(warehouse, lot, quantity, cost)
	return lot
}

func (inv *Inventory) issue(warehouse, code string, quantity int64) ([]Part, int64) {
	var parts []Part
	var cost int64
	for _, stock := range inv.fifo(warehouse, code) {
		if quantity == 0 {
			break
		}
		taken := min(quantity, stock.Quantity)
		parts = append(parts, Part{Lot: stock.Lot, Quantity: taken, Cost: stock.Cost})
		cost += taken * stock.Cost
		stock.Quantity -= taken
		quantity -= taken
		if stock.Quantity == 0 {
			delete(inv.Stock[warehouse][code], stock.Lot.Number)
		}
	}
	return parts, cost
}

func (inv *Inventory) fulfil(order *Order, quantity int64, kind string) int64 {
	if quantity == 0 {
		return 0
	}
	parts, cost := inv.issue(order.Warehouse, order.Item, quantity)
	order.Shipped += quantity
	order.Backorder -= quantity
	order.Revenue += quantity * order.Price
	order.COGS += cost
	order.Issues = append(order.Issues, parts...)
	inv.accumulate("shipped", quantity, cost)
	inv.cardEntry(order.Item, kind, order.Warehouse, -quantity, -cost)
	return cost
}

func (inv *Inventory) allocate(warehouse, code string) {
	available := inv.quantity(warehouse, code)
	for _, order := range inv.Orders {
		if available == 0 {
			break
		}
		if order.Warehouse != warehouse || order.Item != code || order.Backorder == 0 {
			continue
		}
		quantity := min(available, order.Backorder)
		cost := inv.fulfil(order, quantity, "fill")
		revenue := quantity * order.Price
		available -= quantity
		inv.emit(2, "FILL", "order", order.Number, "qty", quantity,
			"revenue", money(revenue), "cogs", money(cost),
			"profit", money(revenue-cost), "backorder", order.Backorder)
	}
}

func (inv *Inventory) removeParts(parts []Part) {
	for _, part := range parts {
		part.Lot.Removed += part.Quantity
	}
}

func (inv *Inventory) salesRows() map[string]struct{Quantity, Revenue, COGS int64} {
	rows := make(map[string]struct{Quantity, Revenue, COGS int64})
	for _, order := range inv.Orders {
		row := rows[order.Item]
		row.Quantity += order.Shipped - order.Returned
		row.Revenue += order.Revenue
		row.COGS += order.COGS
		rows[order.Item] = row
	}
	return rows
}

func (inv *Inventory) marginLine(label string, quantity, revenue, cogs int64) {
	profit := revenue - cogs
	inv.emit(2, label, "sold", quantity, "revenue", money(revenue),
		"cogs", money(cogs), "profit", money(profit), "margin", margin(profit, revenue))
}

func (inv *Inventory) agingLine(label string, buckets [4]int64, monetary bool) {
	labels := [4]string{"0-30", "31-60", "61-90", "91+"}
	parts := []any{label}
	for index, name := range labels {
		parts = append(parts, name)
		if monetary {
			parts = append(parts, money(buckets[index]))
		} else {
			parts = append(parts, buckets[index])
		}
	}
	inv.emit(2, parts...)
}

func (inv *Inventory) command(cmd string, a []string) error {
	switch cmd {
	case "DAY":
		day := integer(a[0])
		if day <= inv.Day {
			return fmt.Errorf("invalid day %s", a[0])
		}
		inv.Day = day
		inv.emit(0, "DAY", day)

	case "WAREHOUSE":
		if _, exists := inv.Stock[a[0]]; exists {
			return fmt.Errorf("duplicate warehouse %s", a[0])
		}
		inv.Stock[a[0]] = make(map[string]map[int]*StockLot)
		inv.emit(0, "WAREHOUSE", a[0])

	case "ITEM":
		code, name, level := a[0], a[2], integer(a[1])
		action := "added"
		if item := inv.Items[code]; item != nil {
			item.Level, item.Name = level, name
			action = "updated"
		} else {
			inv.Items[code] = &Item{Code: code, Name: name, Level: level}
		}
		inv.emit(0, "ITEM", code, action, name, "level", level)

	case "RECEIVE":
		warehouse, code := a[0], a[1]
		item, err := inv.pair(warehouse, code)
		if err != nil {
			return err
		}
		quantity, cost, day := integer(a[2]), cents(a[3]), integer(a[4])
		if quantity == 0 {
			return fmt.Errorf("invalid quantity")
		}
		if day > inv.Day {
			return fmt.Errorf("future day %s", a[4])
		}
		lot := inv.createLot(warehouse, code, day, quantity, cost, "receive")
		item.LastCost = &cost
		amount := quantity * cost
		inv.accumulate("received", quantity, amount)
		inv.cardEntry(code, "receive", warehouse, quantity, amount)
		inv.emit(0, "RECEIVE", warehouse, code, "lot", lot.Number, "qty", quantity,
			"cost", money(cost), "day", day, "value", money(amount))
		inv.allocate(warehouse, code)

	case "SHIP":
		warehouse, code := a[0], a[1]
		if _, err := inv.pair(warehouse, code); err != nil {
			return err
		}
		quantity := integer(a[2])
		if quantity == 0 {
			return fmt.Errorf("invalid quantity")
		}
		order := &Order{
			Number: len(inv.Orders) + 1, Warehouse: warehouse, Item: code,
			Day: inv.Day, Price: cents(a[3]), Ordered: quantity, Backorder: quantity,
		}
		inv.Orders = append(inv.Orders, order)
		filled := min(quantity, inv.quantity(warehouse, code))
		cost := inv.fulfil(order, filled, "ship")
		inv.emit(0, "SHIP", "order", order.Number, warehouse, code, "shipped",
			filled, "revenue", money(order.Revenue), "cogs", money(cost),
			"profit", money(order.Revenue-cost), "backorder", order.Backorder)

	case "CANCEL":
		order, err := inv.order(a[0])
		if err != nil {
			return err
		}
		if order.Backorder == 0 {
			return fmt.Errorf("no backorder %s", a[0])
		}
		order.Cancelled += order.Backorder
		order.Backorder = 0
		inv.emit(0, "CANCEL", "order", order.Number, "qty", order.Cancelled)

	case "TRANSFER":
		source, destination, code := a[0], a[1], a[2]
		if err := inv.warehouse(source); err != nil {
			return err
		}
		if err := inv.warehouse(destination); err != nil {
			return err
		}
		if source == destination {
			return fmt.Errorf("same warehouse %s", source)
		}
		if _, err := inv.item(code); err != nil {
			return err
		}
		quantity := integer(a[3])
		if quantity == 0 {
			return fmt.Errorf("invalid quantity")
		}
		if err := inv.requireStock(source, code, quantity); err != nil {
			return err
		}
		parts, cost := inv.issue(source, code, quantity)
		for _, part := range parts {
			inv.addStock(destination, part.Lot, part.Quantity, part.Cost)
		}
		inv.cardEntry(code, "transfer-out", source, -quantity, -cost)
		inv.cardEntry(code, "transfer-in", destination, quantity, cost)
		inv.emit(0, "TRANSFER", source, "->", destination, code, "qty",
			quantity, "value", money(cost), "lots", len(parts))
		inv.allocate(destination, code)

	case "ADJUST":
		warehouse, code, change := a[0], a[1], a[2]
		if _, err := inv.pair(warehouse, code); err != nil {
			return err
		}
		quantity := integer(change[1:])
		if quantity == 0 {
			return fmt.Errorf("invalid quantity")
		}
		if change[0] == '+' {
			cost := cents(a[3])
			lot := inv.createLot(warehouse, code, inv.Day, quantity, cost, "adjust")
			amount := quantity * cost
			inv.accumulate("adjusted-in", quantity, amount)
			inv.cardEntry(code, "adjust", warehouse, quantity, amount)
			inv.emit(0, "ADJUST", warehouse, code, fmt.Sprint("+", quantity),
				"lot", lot.Number, "value", money(amount))
			inv.allocate(warehouse, code)
		} else {
			if err := inv.requireStock(warehouse, code, quantity); err != nil {
				return err
			}
			parts, cost := inv.issue(warehouse, code, quantity)
			inv.removeParts(parts)
			inv.accumulate("adjusted-out", quantity, cost)
			inv.cardEntry(code, "adjust", warehouse, -quantity, -cost)
			inv.emit(0, "ADJUST", warehouse, code, fmt.Sprint("-", quantity), "value", money(cost))
		}

	case "RETURN":
		order, err := inv.order(a[0])
		if err != nil {
			return err
		}
		quantity, cost := integer(a[1]), cents(a[2])
		if quantity == 0 {
			return fmt.Errorf("invalid quantity")
		}
		available := order.Shipped - order.Returned
		if quantity > available {
			return fmt.Errorf("return exceeds shipped %s %d", a[0], available)
		}
		lot := inv.createLot(order.Warehouse, order.Item, inv.Day, quantity, cost, "return")
		amount := quantity * cost
		refund := quantity * order.Price
		order.Returned += quantity
		order.Revenue -= refund
		order.COGS -= amount
		inv.accumulate("returned", quantity, amount)
		inv.cardEntry(order.Item, "return", order.Warehouse, quantity, amount)
		inv.emit(0, "RETURN", "order", order.Number, order.Warehouse, order.Item, "qty",
			quantity, "lot", lot.Number, "refund", money(refund), "value", money(amount))
		inv.allocate(order.Warehouse, order.Item)

	case "COUNT":
		warehouse, code := a[0], a[1]
		item, err := inv.pair(warehouse, code)
		if err != nil {
			return err
		}
		actual, held := integer(a[2]), inv.quantity(warehouse, code)
		if actual == held {
			inv.emit(0, "COUNT", warehouse, code, "qty", actual, "ok")
		} else if actual < held {
			quantity := held - actual
			parts, cost := inv.issue(warehouse, code, quantity)
			inv.removeParts(parts)
			inv.accumulate("adjusted-out", quantity, cost)
			inv.cardEntry(code, "count", warehouse, -quantity, -cost)
			inv.emit(0, "COUNT", warehouse, code, "qty", held, "->", actual,
				"shortage", quantity, "value", money(cost))
		} else {
			quantity := actual - held
			var cost int64
			if item.LastCost != nil {
				cost = *item.LastCost
			}
			lot := inv.createLot(warehouse, code, inv.Day, quantity, cost, "count")
			amount := quantity * cost
			inv.accumulate("adjusted-in", quantity, amount)
			inv.cardEntry(code, "count", warehouse, quantity, amount)
			inv.emit(0, "COUNT", warehouse, code, "qty", held, "->", actual,
				"surplus", quantity, "lot", lot.Number, "value", money(amount))
			inv.allocate(warehouse, code)
		}

	case "MARKET":
		if _, err := inv.item(a[0]); err != nil {
			return err
		}
		price := cents(a[1])
		var changed int
		var quantity, loss int64
		for _, warehouse := range sortedNames(inv.Stock) {
			var warehouseLoss int64
			for _, stock := range inv.holdings(warehouse, a[0]) {
				if stock.Cost <= price {
					continue
				}
				warehouseLoss += stock.Quantity * (stock.Cost - price)
				changed++
				quantity += stock.Quantity
				stock.Cost = price
			}
			if warehouseLoss > 0 {
				inv.cardEntry(a[0], "writedown", warehouse, 0, -warehouseLoss)
			}
			loss += warehouseLoss
		}
		inv.accumulate("written-down", quantity, loss)
		inv.emit(0, "MARKET", a[0], "price", money(price),
			"lots", changed, "qty", quantity, "loss", money(loss))

	case "RECALL":
		lot, err := inv.lot(a[0])
		if err != nil {
			return err
		}
		type Holding struct {
			Warehouse string
			Stock *StockLot
		}
		var held []Holding
		for _, warehouse := range sortedNames(inv.Stock) {
			if stock := inv.holdings(warehouse, lot.Item)[lot.Number]; stock != nil {
				held = append(held, Holding{warehouse, stock})
			}
		}
		if len(held) == 0 {
			return fmt.Errorf("nothing to recall %s", a[0])
		}
		var quantity, amount int64
		for _, holding := range held {
			quantity += holding.Stock.Quantity
			amount += holding.Stock.Quantity * holding.Stock.Cost
			delete(inv.Stock[holding.Warehouse][lot.Item], lot.Number)
			inv.cardEntry(lot.Item, "recall", holding.Warehouse,
				-holding.Stock.Quantity, -holding.Stock.Quantity*holding.Stock.Cost)
		}
		lot.Removed += quantity
		inv.accumulate("recalled", quantity, amount)
		inv.emit(0, "RECALL", "lot", lot.Number, lot.Item, "qty", quantity, "value", money(amount))
		for _, holding := range held {
			inv.emit(2, holding.Warehouse, "qty", holding.Stock.Quantity,
				"value", money(holding.Stock.Quantity*holding.Stock.Cost))
		}

	case "EXPIRE":
		days := integer(a[0])
		inv.emit(0, "EXPIRE", days)
		var totalQuantity, totalValue int64
		for _, code := range sortedNames(inv.Items) {
			for _, warehouse := range sortedNames(inv.Stock) {
				var expired []*StockLot
				for _, stock := range inv.holdings(warehouse, code) {
					if inv.Day-stock.Lot.Day > days {
						expired = append(expired, stock)
					}
				}
				if len(expired) == 0 {
					continue
				}
				quantity, amount := sumQuantity(expired), sumValue(expired)
				for _, stock := range expired {
					stock.Lot.Removed += stock.Quantity
					delete(inv.Stock[warehouse][code], stock.Lot.Number)
				}
				inv.accumulate("expired", quantity, amount)
				inv.cardEntry(code, "expire", warehouse, -quantity, -amount)
				totalQuantity += quantity
				totalValue += amount
				inv.emit(2, code, warehouse, "lots", len(expired),
					"qty", quantity, "value", money(amount))
			}
		}
		inv.emit(2, "total", "qty", totalQuantity, "value", money(totalValue))

	case "VALUE", "AGING":
		warehouses := sortedNames(inv.Stock)
		if len(a) == 1 {
			if err := inv.warehouse(a[0]); err != nil {
				return err
			}
			warehouses = []string{a[0]}
		}
		if cmd == "VALUE" {
			header := []any{"VALUE"}
			for _, arg := range a { header = append(header, arg) }
			inv.emit(0, header...)
		} else {
			header := []any{"AGING"}
			for _, arg := range a { header = append(header, arg) }
			header = append(header, "day", inv.Day)
			inv.emit(0, header...)
		}
		var totalQuantity, totalValue int64
		var bucketQ, bucketV [4]int64
		for _, code := range sortedNames(inv.Items) {
			var stocks []*StockLot
			rows := make(map[string][]*StockLot)
			for _, warehouse := range warehouses {
				current := inv.stocks(warehouse, code)
				rows[warehouse] = current
				stocks = append(stocks, current...)
			}
			quantity := sumQuantity(stocks)
			if quantity == 0 {
				continue
			}
			value := sumValue(stocks)
			if cmd == "VALUE" {
				inv.emit(2, code, "qty", quantity, "value", money(value),
					"avg", money(value/quantity))
				if len(a) == 0 {
					for _, warehouse := range warehouses {
						held := rows[warehouse]
						if q := sumQuantity(held); q > 0 {
							inv.emit(4, warehouse, "qty", q, "value", money(sumValue(held)))
						}
					}
				}
			} else {
				var itemBuckets [4]int64
				for _, stock := range stocks {
					age := inv.Day - stock.Lot.Day
					bucket := 3
					if age <= 30 {
						bucket = 0
					} else if age <= 60 {
						bucket = 1
					} else if age <= 90 {
						bucket = 2
					}
					itemBuckets[bucket] += stock.Quantity
					bucketQ[bucket] += stock.Quantity
					bucketV[bucket] += stock.Quantity * stock.Cost
				}
				inv.agingLine(code, itemBuckets, false)
			}
			totalQuantity += quantity
			totalValue += value
		}
		if cmd == "VALUE" {
			inv.emit(2, "total", "qty", totalQuantity, "value", money(totalValue))
		} else {
			inv.agingLine("total", bucketQ, false)
			inv.agingLine("value", bucketV, true)
		}

	case "LOTS":
		warehouse, code := a[0], a[1]
		if _, err := inv.pair(warehouse, code); err != nil {
			return err
		}
		inv.emit(0, "LOTS", warehouse, code)
		stocks := inv.fifo(warehouse, code)
		var backorders []*Order
		for _, order := range inv.Orders {
			if order.Warehouse == warehouse && order.Item == code && order.Backorder > 0 {
				backorders = append(backorders, order)
			}
		}
		for _, stock := range stocks {
			inv.emit(2, "lot", stock.Lot.Number, "day", stock.Lot.Day,
				"qty", stock.Quantity, "cost", money(stock.Cost),
				"value", money(stock.Quantity*stock.Cost), "age", inv.Day-stock.Lot.Day)
		}
		for _, order := range backorders {
			inv.emit(2, "backorder", "order", order.Number, "qty", order.Backorder)
		}
		if len(stocks) == 0 && len(backorders) == 0 {
			inv.emit(2, "(none)")
		}

	case "REORDER", "ITEMS":
		inv.emit(0, cmd)
		found := false
		for _, code := range sortedNames(inv.Items) {
			item := inv.Items[code]
			quantity, backorder := inv.totalQuantity(code), inv.backorder(code)
			if cmd == "REORDER" {
				if quantity-backorder > item.Level {
					continue
				}
				inv.emit(2, code, item.Name, "onhand", quantity,
					"backorder", backorder, "level", item.Level)
			} else {
				cost := "none"
				if item.LastCost != nil {
					cost = money(*item.LastCost)
				}
				inv.emit(2, code, item.Name, "level", item.Level,
					"onhand", quantity, "backorder", backorder, "cost", cost)
			}
			found = true
		}
		if !found {
			inv.emit(2, "(none)")
		}

	case "MARGIN", "TOP":
		rows := inv.salesRows()
		if cmd == "MARGIN" {
			inv.emit(0, "MARGIN")
			var totalQuantity, totalRevenue, totalCOGS int64
			for _, code := range sortedNames(rows) {
				row := rows[code]
				inv.marginLine(code, row.Quantity, row.Revenue, row.COGS)
				totalQuantity += row.Quantity
				totalRevenue += row.Revenue
				totalCOGS += row.COGS
			}
			inv.marginLine("total", totalQuantity, totalRevenue, totalCOGS)
		} else {
			k := integer(a[0])
			inv.emit(0, "TOP", k)
			codes := sortedNames(rows)
			sort.Slice(codes, func(i, j int) bool {
				x, y := rows[codes[i]], rows[codes[j]]
				xProfit, yProfit := x.Revenue-x.COGS, y.Revenue-y.COGS
				if xProfit != yProfit {
					return xProfit > yProfit
				}
				if x.Revenue != y.Revenue {
					return x.Revenue > y.Revenue
				}
				return codes[i] < codes[j]
			})
			for rank := 0; rank < len(codes) && int64(rank) < k; rank++ {
				row := rows[codes[rank]]
				profit := row.Revenue - row.COGS
				inv.emit(2, rank+1, codes[rank], "profit", money(profit),
					"revenue", money(row.Revenue), "margin", margin(profit, row.Revenue))
			}
			if len(codes) == 0 {
				inv.emit(2, "(none)")
			}
		}

	case "BACKORDERS":
		inv.emit(0, "BACKORDERS")
		found := false
		for _, order := range inv.Orders {
			if order.Backorder > 0 {
				inv.emit(2, "order", order.Number, order.Warehouse, order.Item,
					"qty", order.Backorder, "day", order.Day, "price", money(order.Price))
				found = true
			}
		}
		if !found {
			inv.emit(2, "(none)")
		}

	case "ORDER":
		order, err := inv.order(a[0])
		if err != nil {
			return err
		}
		inv.emit(0, "ORDER", order.Number, order.Warehouse, order.Item,
			"day", order.Day, "price", money(order.Price))
		inv.emit(2, "ordered", order.Ordered, "shipped", order.Shipped,
			"backorder", order.Backorder, "cancelled", order.Cancelled, "returned", order.Returned)
		for _, part := range order.Issues {
			inv.emit(2, "lot", part.Lot.Number, "qty", part.Quantity, "cost", money(part.Cost))
		}
		inv.emit(2, "revenue", money(order.Revenue), "cogs", money(order.COGS),
			"profit", money(order.Revenue-order.COGS))

	case "TRACE":
		lot, err := inv.lot(a[0])
		if err != nil {
			return err
		}
		inv.emit(0, "TRACE", "lot", lot.Number, lot.Item, lot.Kind, lot.Warehouse,
			"day", lot.Day, "qty", lot.InitialQuantity, "cost", money(lot.InitialCost))
		for _, warehouse := range sortedNames(inv.Stock) {
			if stock := inv.holdings(warehouse, lot.Item)[lot.Number]; stock != nil {
				inv.emit(2, "held", warehouse, "qty", stock.Quantity, "cost", money(stock.Cost))
			}
		}
		for _, order := range inv.Orders {
			var quantity int64
			for _, part := range order.Issues {
				if part.Lot.Number == lot.Number {
					quantity += part.Quantity
				}
			}
			if quantity > 0 {
				inv.emit(2, "order", order.Number, "qty", quantity)
			}
		}
		if lot.Removed > 0 {
			inv.emit(2, "removed", "qty", lot.Removed)
		}

	case "CARD":
		item, err := inv.item(a[0])
		if err != nil {
			return err
		}
		inv.emit(0, "CARD", item.Code, item.Name)
		var quantity, value int64
		for _, entry := range item.Card {
			quantity += entry.Quantity
			value += entry.Value
			inv.emit(2, "day", entry.Day, entry.Kind, entry.Warehouse,
				signedQuantity(entry.Quantity), signedMoney(entry.Value),
				"balance", quantity, money(value))
		}
		if len(item.Card) == 0 {
			inv.emit(2, "(none)")
		}

	case "STATUS":
		inv.emit(0, "STATUS")
		for _, warehouse := range sortedNames(inv.Stock) {
			var stocks []*StockLot
			skus := 0
			for _, holdings := range inv.Stock[warehouse] {
				if len(holdings) > 0 {
					skus++
				}
				for _, stock := range holdings {
					stocks = append(stocks, stock)
				}
			}
			var backorder int64
			for _, order := range inv.Orders {
				if order.Warehouse == warehouse {
					backorder += order.Backorder
				}
			}
			inv.emit(2, warehouse, "skus", skus, "qty", sumQuantity(stocks),
				"value", money(sumValue(stocks)), "backorder", backorder)
		}
		if len(inv.Stock) == 0 {
			inv.emit(2, "(none)")
		}

	case "SUMMARY":
		inv.emit(0, "SUMMARY")
		for _, category := range categories {
			total := inv.Totals[category]
			inv.emit(2, category, "qty", total.Quantity, "value", money(total.Value))
		}
		stocks := inv.allStocks()
		inv.emit(2, "on-hand", "qty", sumQuantity(stocks), "value", money(sumValue(stocks)))
		open := 0
		var backorder int64
		for _, order := range inv.Orders {
			if order.Backorder > 0 {
				open++
			}
			backorder += order.Backorder
		}
		inv.emit(2, "orders", len(inv.Orders), "open", open, "backorder", backorder)
	}
	return nil
}

func (inv *Inventory) execute(line string) {
	tokens := strings.Fields(line)
	if len(tokens) == 0 {
		return
	}
	if err := inv.command(tokens[0], tokens[1:]); err != nil {
		inv.emit(0, "ERROR", err.Error())
	}
}

func main() {
	reader := bufio.NewScanner(os.Stdin)
	reader.Buffer(make([]byte, 4096), 1024*1024)
	if !reader.Scan() {
		return
	}
	count, _ := strconv.Atoi(reader.Text())
	inventory := newInventory()
	for i := 0; i < count && reader.Scan(); i++ {
		inventory.execute(reader.Text())
	}
	fmt.Println(strings.Join(inventory.Output, "\n"))
}
