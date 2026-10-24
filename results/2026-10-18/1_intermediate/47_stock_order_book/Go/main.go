package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Order struct {
	id, trader, kind, side, condition, status string
	price, trigger, peak, quantity, remaining, visible, filled, value, priority int
	history []string
}

type Trader struct {
	bought, sold, cash, fees, limit int
	limited bool
}

type Trade struct {
	price, quantity int
	buy, sell, taker *Order
	bf, sf int
}

type Level struct {
	price, quantity, count int
}

type Engine struct {
	orders []*Order
	ids map[string]*Order
	traders map[string]*Trader
	trades []Trade
	priority, maker, taker, band, tick, lot int
	halted bool
	out *bufio.Writer
}

func num(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func dec(n int) string {
	return fmt.Sprintf("%d.%02d", n/100, n%100)
}

func (e *Engine) emit(a ...any) {
	fmt.Fprintln(e.out, a...)
}

func active(o *Order) bool {
	return o.status == "PENDING" || resting(o)
}

func resting(o *Order) bool {
	return o.status == "OPEN" || o.status == "PARTIAL"
}

func matches(o *Order, p int) bool {
	return o.price == 0 || o.side == "BUY" && p <= o.price || o.side == "SELL" && p >= o.price
}

func triggered(o *Order, p int) bool {
	return o.side == "BUY" && p >= o.trigger || o.side == "SELL" && p <= o.trigger
}

func (e *Engine) last() int {
	if len(e.trades) == 0 {
		return 0
	}
	return e.trades[len(e.trades)-1].price
}

func (e *Engine) register(t string) *Trader {
	if e.traders[t] == nil {
		e.traders[t] = &Trader{}
	}
	return e.traders[t]
}

func (e *Engine) exposure(t, s string, exclude *Order) int {
	v := 0
	if x := e.traders[t]; x != nil {
		v = x.bought-x.sold
	}
	if s == "SELL" {
		v = -v
	}
	for _, o := range e.orders {
		if o != exclude && o.trader == t && o.side == s && active(o) {
			v += o.remaining
		}
	}
	return v
}

func (e *Engine) risk(t, s string, q int, exclude *Order) bool {
	x := e.traders[t]
	return x != nil && x.limited && e.exposure(t, s, exclude)+q > x.limit
}

func (e *Engine) outside(p int) bool {
	d := p-e.last()
	if d < 0 {
		d = -d
	}
	return e.band > 0 && len(e.trades) > 0 && d > e.band
}

func (e *Engine) best(s string) *Order {
	var b *Order
	for _, o := range e.orders {
		if !resting(o) || o.side != s {
			continue
		}
		if b == nil || s == "BUY" && o.price > b.price || s == "SELL" && o.price < b.price || o.price == b.price && o.priority < b.priority {
			b = o
		}
	}
	return b
}

func (e *Engine) orderLine(o *Order) {
	e.emit("ORDER", o.id, o.status, fmt.Sprintf("%d/%d", o.filled, o.quantity))
}

func details(o *Order) string {
	p, a := "-", "-"
	if o.price > 0 {
		p = strconv.Itoa(o.price)
	}
	if o.filled > 0 {
		a = dec(o.value*100/o.filled)
	}
	s := fmt.Sprintf("%s %s %s %s %s %s %d/%d avg %s", o.id, o.trader, o.kind, o.side, p, o.status, o.filled, o.quantity, a)
	if o.trigger > 0 {
		s += fmt.Sprintf(" trigger %d", o.trigger)
	}
	return s
}

func (e *Engine) position(t string) {
	x := e.traders[t]
	n := x.bought-x.sold
	e.emit("POSITION", t, "bought", x.bought, "sold", x.sold, "net", n, "cash", x.cash, "fees", x.fees, "pnl", x.cash+n*e.last())
}

func (e *Engine) tradeLine(i int) {
	x := e.trades[i]
	e.emit("TRADE", i+1, x.price, x.quantity, x.buy.id, x.buy.trader, x.sell.id, x.sell.trader)
}

func (e *Engine) execute(o *Order) {
	op := "BUY"
	if o.side == "BUY" {
		op = "SELL"
	}
	for o.remaining > 0 {
		y := e.best(op)
		if y == nil || !matches(o, y.price) {
			break
		}
		if y.trader == o.trader {
			e.emit("STP", y.id, y.remaining)
			y.history = append(y.history, fmt.Sprintf("STP %d", y.remaining))
			y.remaining = 0
			y.status = "CANCELLED"
			continue
		}
		q := min(o.remaining, y.visible)
		p := y.price
		tf, mf := q*e.taker, q*e.maker
		b, s := o, y
		bf, sf := tf, mf
		if o.side == "SELL" {
			b, s = y, o
			bf, sf = mf, tf
		}
		e.trades = append(e.trades, Trade{p, q, b, s, o, bf, sf})
		for _, x := range []*Order{o, y} {
			x.remaining -= q
			x.filled += q
			x.value += q*p
			x.history = append(x.history, fmt.Sprintf("FILL %d %d %d", len(e.trades), p, q))
		}
		y.visible -= q
		bt, st := e.traders[b.trader], e.traders[s.trader]
		bt.bought += q
		bt.cash -= q*p+bf
		bt.fees += bf
		st.sold += q
		st.cash += q*p-sf
		st.fees += sf
		e.tradeLine(len(e.trades)-1)
		if y.remaining == 0 {
			y.status = "FILLED"
		} else {
			y.status = "PARTIAL"
			if y.visible == 0 {
				e.priority++
				y.priority = e.priority
				y.visible = min(y.peak, y.remaining)
				h := y.remaining-y.visible
				y.history = append(y.history, fmt.Sprintf("REFRESH %d %d", y.visible, h))
				e.emit("REFRESH", y.id, y.visible, h)
			}
		}
	}
}

func (e *Engine) post(o *Order, force bool) {
	if o.remaining == 0 {
		o.status = "FILLED"
	} else if force || o.kind == "LIMIT" && o.condition != "IOC" || o.kind == "ICEBERG" || o.kind == "STOPLIMIT" {
		e.priority++
		o.priority = e.priority
		o.visible = o.remaining
		if o.peak > 0 {
			o.visible = min(o.peak, o.remaining)
		}
		o.status = "OPEN"
		if o.filled > 0 {
			o.status = "PARTIAL"
		}
		o.history = append(o.history, fmt.Sprintf("REST %d %d", o.price, o.visible))
	} else {
		o.history = append(o.history, fmt.Sprintf("EXPIRE %d", o.remaining))
		o.remaining = 0
		o.status = "CANCELLED"
	}
	e.orderLine(o)
}

func (e *Engine) stops() {
	for len(e.trades) > 0 {
		selected := []*Order{}
		p := e.last()
		for _, o := range e.orders {
			if o.status == "PENDING" && triggered(o, p) {
				selected = append(selected, o)
			}
		}
		if len(selected) == 0 {
			return
		}
		for _, o := range selected {
			o.status = "TRIGGERING"
		}
		for _, o := range selected {
			e.emit("TRIGGER", o.id)
			o.history = append(o.history, "TRIGGER")
			e.execute(o)
			e.post(o, false)
		}
	}
}

func (e *Engine) cancel(o *Order) {
	o.history = append(o.history, fmt.Sprintf("CANCEL %d", o.remaining))
	o.remaining = 0
	o.status = "CANCELLED"
	e.orderLine(o)
}

func (e *Engine) levels(s string) []Level {
	m := map[int]Level{}
	for _, o := range e.orders {
		if resting(o) && o.side == s {
			x := m[o.price]
			x.price = o.price
			x.quantity += o.visible
			x.count++
			m[o.price] = x
		}
	}
	r := []Level{}
	for _, x := range m {
		r = append(r, x)
	}
	sort.Slice(r, func(i, j int) bool {
		if s == "BUY" {
			return r[i].price > r[j].price
		}
		return r[i].price < r[j].price
	})
	return r
}

func (e *Engine) command(w []string) {
	c := w[0]
	reject := func(reason string) {
		if c == "LIMIT" || c == "MARKET" || c == "STOP" || c == "STOPLIMIT" || c == "ICEBERG" || c == "CANCEL" || c == "REPLACE" {
			e.emit("REJECT", w[1], reason)
		} else {
			e.emit("ERROR", reason)
		}
	}
	if c == "LIMIT" || c == "MARKET" || c == "STOP" || c == "STOPLIMIT" || c == "ICEBERG" {
		o := &Order{id: w[1], trader: w[2], side: w[3], kind: c, status:"ARRIVING", history: []string{"ACCEPT"}}
		prices := []int{}
		switch c {
		case "MARKET":
			o.quantity = num(w[4])
		case "STOP":
			o.trigger = num(w[4])
			o.quantity = num(w[5])
			prices = []int{o.trigger}
		case "STOPLIMIT":
			o.trigger = num(w[4])
			o.price = num(w[5])
			o.quantity = num(w[6])
			prices = []int{o.trigger, o.price}
		default:
			o.price = num(w[4])
			o.quantity = num(w[5])
			prices = []int{o.price}
			if c == "ICEBERG" {
				o.peak = num(w[6])
			} else if len(w) > 6 {
				o.condition = w[6]
			}
		}
		o.remaining = o.quantity
		reason := ""
		if e.halted {
			reason = "halted"
		} else if e.ids[o.id] != nil {
			reason = "duplicate id"
		} else {
			for _, p := range prices {
				if p == 0 {
					reason = "invalid price"
				}
			}
			if reason == "" && o.quantity == 0 {
				reason = "invalid quantity"
			}
			if reason == "" {
				for _, p := range prices {
					if p%e.tick != 0 {
						reason = "invalid tick"
					}
				}
			}
			if reason == "" && o.quantity%e.lot != 0 {
				reason = "invalid lot"
			}
		}
		if reason == "" && (c == "STOP" || c == "STOPLIMIT") && len(e.trades) > 0 && triggered(o, e.last()) {
			reason = "invalid trigger"
		}
		if reason == "" && c == "ICEBERG" && (o.peak == 0 || o.peak > o.quantity || o.peak%e.lot != 0) {
			reason = "invalid peak"
		}
		if reason == "" && o.price > 0 && e.outside(o.price) {
			reason = "outside band"
		}
		if reason == "" && e.risk(o.trader, o.side, o.quantity, nil) {
			reason = "risk limit"
		}
		op := "BUY"
		if o.side == "BUY" {
			op = "SELL"
		}
		b := e.best(op)
		if reason == "" && o.condition == "POSTONLY" && b != nil && matches(o, b.price) {
			reason = "would cross"
		}
		if reason == "" && o.condition == "FOK" {
			v := 0
			for _, x := range e.orders {
				if resting(x) && x.side == op && x.trader != o.trader && matches(o, x.price) {
					v += x.remaining
				}
			}
			if v < o.quantity {
				reason = "unfillable"
			}
		}
		if reason != "" {
			reject(reason)
			return
		}
		e.register(o.trader)
		e.ids[o.id] = o
		e.orders = append(e.orders, o)
		if c == "STOP" || c == "STOPLIMIT" {
			o.status = "PENDING"
			e.orderLine(o)
		} else {
			if o.condition != "POSTONLY" {
				e.execute(o)
			}
			e.post(o, false)
			e.stops()
		}
		return
	}
	if c == "CANCEL" || c == "REPLACE" || c == "STATUS" || c == "HISTORY" {
		o := e.ids[w[1]]
		if c == "REPLACE" && e.halted {
			reject("halted")
			return
		}
		if o == nil {
			reject("unknown order")
			return
		}
		switch c {
		case "STATUS":
			e.emit("STATUS", details(o))
		case "HISTORY":
			e.emit("HISTORY", o.id, len(o.history))
			for _, h := range o.history {
				e.emit(h)
			}
		case "CANCEL":
			if !active(o) {
				reject("not open")
				return
			}
			e.cancel(o)
		case "REPLACE":
			p, q := num(w[2]), num(w[3])
			moved := p != o.price
			reason := ""
			switch {
			case !resting(o):
				reason = "not open"
			case p == 0:
				reason = "invalid price"
			case q == 0:
				reason = "invalid quantity"
			case moved && p%e.tick != 0:
				reason = "invalid tick"
			case q%e.lot != 0:
				reason = "invalid lot"
			case !moved && q == o.remaining:
				reason = "no change"
			case moved && e.outside(p):
				reason = "outside band"
			case q > o.remaining && e.risk(o.trader, o.side, q, o):
				reason = "risk limit"
			}
			if reason != "" {
				reject(reason)
				return
			}
			o.quantity = o.filled+q
			kept := !moved && q < o.remaining
			mode := "lost"
			if kept {
				mode = "kept"
			}
			o.history = append(o.history, fmt.Sprintf("REPLACE %d %d %s", p, q, mode))
			e.emit("REPLACE", o.id, mode)
			o.price = p
			o.remaining = q
			if kept {
				o.visible = min(o.visible, q)
				e.orderLine(o)
			} else {
				o.status = "ARRIVING"
				e.execute(o)
				e.post(o, true)
				e.stops()
			}
		}
		return
	}
	if c == "CANCELALL" || c == "ORDERS" || c == "POSITION" || c == "FILLS" {
		t := w[1]
		if e.traders[t] == nil {
			reject("unknown trader")
			return
		}
		switch c {
		case "CANCELALL", "ORDERS":
			a := []*Order{}
			for _, o := range e.orders {
				if active(o) && o.trader == t {
					a = append(a, o)
				}
			}
			e.emit(c, t, len(a))
			for _, o := range a {
				if c == "ORDERS" {
					e.emit(details(o))
				} else {
					e.cancel(o)
				}
			}
		case "POSITION":
			e.position(t)
		case "FILLS":
			count := 0
			for _, x := range e.trades {
				if x.buy.trader == t || x.sell.trader == t {
					count++
				}
			}
			e.emit("FILLS", t, count)
			net := 0
			for i, x := range e.trades {
				var o *Order
				side := "BUY"
				fee := x.bf
				if x.buy.trader == t {
					o = x.buy
					net += x.quantity
				} else if x.sell.trader == t {
					o = x.sell
					side = "SELL"
					fee = x.sf
					net -= x.quantity
				} else {
					continue
				}
				role := "MAKER"
				if x.taker == o {
					role = "TAKER"
				}
				e.emit(i+1, side, x.price, x.quantity, o.id, role, "fee", fee, "net", net)
			}
		}
		return
	}
	switch c {
	case "HALT":
		if e.halted {
			reject("already halted")
		} else {
			e.halted = true
			e.emit(c)
		}
	case "RESUME":
		if !e.halted {
			reject("not halted")
		} else {
			e.halted = false
			e.emit(c)
		}
	case "RISK":
		t, m := w[1], num(w[2])
		x := e.register(t)
		x.limit = m
		x.limited = true
		e.emit(c, t, m, "exposure buy", e.exposure(t, "BUY", nil), "sell", e.exposure(t, "SELL", nil))
	case "FEE":
		a, b := num(w[1]), num(w[2])
		if a+b < 0 {
			reject("invalid fee")
		} else {
			e.maker = a
			e.taker = b
			e.emit(c, "maker", a, "taker", b)
		}
	case "BAND":
		e.band = num(w[1])
		e.emit(c, e.band)
	case "TICK", "LOT":
		u := num(w[1])
		if u == 0 {
			reject("invalid size")
			return
		}
		if c == "TICK" {
			e.tick = u
		} else {
			e.lot = u
		}
		e.emit(c, u)
	case "BOOK":
		n := num(w[1])
		if n == 0 {
			reject("invalid depth")
			return
		}
		b, a := e.levels("BUY"), e.levels("SELL")
		e.emit("BOOK bids", len(b), "asks", len(a))
		for i := min(n, len(a))-1; i >= 0; i-- {
			x := a[i]
			e.emit("ASK", x.price, x.quantity, x.count)
		}
		for _, x := range b[:min(n, len(b))] {
			e.emit("BID", x.price, x.quantity, x.count)
		}
	case "LAST":
		if len(e.trades) == 0 {
			e.emit("LAST none")
		} else {
			x := e.trades[len(e.trades)-1]
			e.emit(c, x.price, x.quantity)
		}
	case "VWAP":
		v, a := 0, 0
		for _, x := range e.trades {
			v += x.quantity
			a += x.price*x.quantity
		}
		if v == 0 {
			e.emit("VWAP none")
		} else {
			e.emit(c, dec(a*100/v), "volume", v, "trades", len(e.trades))
		}
	case "SPREAD":
		b, a := e.best("BUY"), e.best("SELL")
		if b == nil || a == nil {
			bt, at := "none", "none"
			if b != nil {
				bt = strconv.Itoa(b.price)
			}
			if a != nil {
				at = strconv.Itoa(a.price)
			}
			e.emit(c, "bid", bt, "ask", at)
		} else {
			s := a.price+b.price
			e.emit(c, "bid", b.price, "ask", a.price, "spread", a.price-b.price, "mid", fmt.Sprintf("%d.%d", s/2, s%2*5))
		}
	case "IMPACT":
		s, q := w[1], num(w[2])
		if q == 0 {
			reject("invalid quantity")
			return
		}
		op := "BUY"
		if s == "BUY" {
			op = "SELL"
		}
		r, cost, worst, used, total := q, 0, 0, 0, 0
		for _, x := range e.levels(op) {
			total += x.quantity
			if r > 0 {
				u := min(r, x.quantity)
				r -= u
				cost += u*x.price
				worst = x.price
				used++
			}
		}
		if r > 0 {
			e.emit(c, s, q, "insufficient", total)
		} else {
			e.emit(c, s, q, "avg", dec(cost*100/q), "worst", worst, "levels", used)
		}
	case "TRADES", "BARS":
		k := num(w[1])
		if k == 0 {
			reject("invalid count")
			return
		}
		if c == "TRADES" {
			m := min(k, len(e.trades))
			e.emit(c, m, "of", len(e.trades))
			for i := len(e.trades)-m; i < len(e.trades); i++ {
				e.tradeLine(i)
			}
		} else {
			e.emit(c, (len(e.trades)+k-1)/k)
			for i := 0; i < len(e.trades); i += k {
				g := e.trades[i: min(i+k, len(e.trades))]
				hi, lo, v := g[0].price, g[0].price, 0
				for _, x := range g {
					hi = max(hi, x.price)
					lo = min(lo, x.price)
					v += x.quantity
				}
				e.emit(i/k+1, "open", g[0].price, "high", hi, "low", lo, "close", g[len(g)-1].price, "volume", v)
			}
		}
	case "RANK":
		names := []string{}
		for t := range e.traders {
			names = append(names, t)
		}
		pnl := func(t string) int {
			x := e.traders[t]
			return x.cash+(x.bought-x.sold)*e.last()
		}
		sort.Slice(names, func(i, j int) bool {
			a, b := names[i], names[j]
			if pnl(a) != pnl(b) {
				return pnl(a) > pnl(b)
			}
			x, y := e.traders[a], e.traders[b]
			if x.bought+x.sold != y.bought+y.sold {
				return x.bought+x.sold > y.bought+y.sold
			}
			return a < b
		})
		e.emit(c, len(names))
		for i, t := range names {
			x := e.traders[t]
			e.emit(i+1, t, "pnl", pnl(t), "volume", x.bought+x.sold)
		}
	case "FLOW":
		b, s := 0, 0
		for _, x := range e.trades {
			if x.taker.side == "BUY" {
				b += x.quantity
			} else {
				s += x.quantity
			}
		}
		e.emit(c, "buy", b, "sell", s, "net", b-s)
	case "SUMMARY":
		if len(e.trades) == 0 {
			e.emit("SUMMARY trades 0")
		} else {
			hi, lo, v, f := e.trades[0].price, e.trades[0].price, 0, 0
			for _, x := range e.trades {
				hi = max(hi, x.price)
				lo = min(lo, x.price)
				v += x.quantity
				f += x.bf+x.sf
			}
			e.emit(c, "trades", len(e.trades), "volume", v, "open", e.trades[0].price, "high", hi, "low", lo, "close", e.last(), "fees", f)
		}
		names := []string{}
		for t := range e.traders {
			names = append(names, t)
		}
		sort.Strings(names)
		for _, t := range names {
			e.position(t)
		}
	}
}

func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 4096), 1024*1024)
	in.Scan()
	n := num(in.Text())
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	e := Engine{ids: map[string]*Order{}, traders: map[string]*Trader{}, tick: 1, lot: 1, out: out}
	for i := 0; i < n && in.Scan(); i++ {
		e.command(strings.Fields(in.Text()))
	}
}
