package main

import (
	"math"
	"sort"
)

var featureNames = []string{"recency", "frequency", "monetary", "basket", "categories", "tenure"}
var sqrtFeatures = []bool{false, true, true, true, false, false}

type Customer struct {
	id                                     string
	recency, frequency, categories, tenure int
	spend                                  int64
	monetary, basket                       float64
	categorySpend                          map[string]int64
	orders                                 []*Order
}

func (c *Customer) values() []float64 {
	return []float64{float64(c.recency), float64(c.frequency), c.monetary, c.basket, float64(c.categories), float64(c.tenure)}
}
func (c *Customer) transformed() []float64 {
	values := c.values()
	for i, root := range sqrtFeatures {
		if root {
			values[i] = math.Sqrt(values[i])
		}
	}
	return values
}
func eligibleCustomers(orders []*Order, day int) []*Customer {
	valid := []*Order{}
	for _, order := range orders {
		if order.net > 0 {
			valid = append(valid, order)
		}
	}
	groups := ordersByCustomer(valid)
	ids := []string{}
	for id := range groups {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	customers := []*Customer{}
	for _, id := range ids {
		purchases := groups[id]
		first, last := purchases[0].day, purchases[0].day
		c := &Customer{id: id, frequency: len(purchases), orders: purchases, categorySpend: map[string]int64{}}
		for _, order := range purchases {
			first = min(first, order.day)
			last = max(last, order.day)
			c.spend += order.net
			for _, row := range order.rows {
				c.categorySpend[row.category] += row.amount
			}
		}
		c.recency = day - last
		c.tenure = day - first
		c.monetary = float64(c.spend) / 100
		c.basket = c.monetary / float64(c.frequency)
		for _, spend := range c.categorySpend {
			if spend > 0 {
				c.categories++
			}
		}
		customers = append(customers, c)
	}
	return customers
}
func orderedSum(values []float64) float64 {
	total := 0.0
	for _, value := range values {
		total += value
	}
	return total
}
func mean(values []float64) float64 { return orderedSum(values) / float64(len(values)) }
func sampleSD(values []float64) float64 {
	average := mean(values)
	total := 0.0
	for _, value := range values {
		d := value - average
		total += d * d
	}
	return math.Sqrt(total / float64(len(values)-1))
}
func standardization(rows [][]float64) ([]float64, []float64) {
	means, sds := make([]float64, len(featureNames)), make([]float64, len(featureNames))
	for f := range featureNames {
		column := []float64{}
		for _, row := range rows {
			column = append(column, row[f])
		}
		means[f] = mean(column)
		sds[f] = sampleSD(column)
	}
	return means, sds
}
func standardize(values, means, sds []float64) []float64 {
	point := make([]float64, len(values))
	for i, value := range values {
		if sds[i] != 0 {
			point[i] = (value - means[i]) / sds[i]
		}
	}
	return point
}
func correlation(points [][]float64, first, second int) float64 {
	total := 0.0
	for _, point := range points {
		total += point[first] * point[second]
	}
	return total / float64(len(points)-1)
}
