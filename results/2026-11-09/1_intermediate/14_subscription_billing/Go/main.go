package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var periodLengths = map[string]int{"WEEKLY": 7, "MONTHLY": 30, "YEARLY": 360}

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func cents(text string) int {
	pieces := strings.Split(text, ".")
	return number(pieces[0])*100 + number(pieces[1])
}

func money(value int) string {
	sign := ""
	if value < 0 {
		sign = "-"
		value = -value
	}
	return fmt.Sprintf("%s%d.%02d", sign, value/100, value%100)
}

func signedMoney(value int) string {
	if value > 0 {
		return "+" + money(value)
	}
	return money(value)
}

func percentage(basisPoints int) string {
	return money(basisPoints) + "%"
}

func among(value string, permitted ...string) bool {
	for _, candidate := range permitted {
		if value == candidate {
			return true
		}
	}
	return false
}

func smaller(a, b int) int {
	if a < b {
		return a
	}
	return b
}

type Tier struct {
	upper *int
	unit  int
	flat  int
}

type Plan struct {
	name    string
	price   int
	cycle   string
	length  int
	trial   int
	setup   int
	perSeat bool
	mode    string
	tiers   []Tier
}

func (plan *Plan) fee(seats int) int {
	if plan.perSeat {
		return plan.price * seats
	}
	return plan.price
}

func (plan *Plan) usageCharge(units int) int {
	lower, total := 0, 0
	for i, tier := range plan.tiers {
		last := i == len(plan.tiers)-1
		if plan.mode == "VOLUME" {
			if last || tier.upper == nil || units <= *tier.upper {
				return units*tier.unit + tier.flat
			}
		} else {
			if units <= lower {
				break
			}
			end := units
			if !last && tier.upper != nil {
				end = smaller(units, *tier.upper)
			}
			total += (end-lower)*tier.unit + tier.flat
			if last || tier.upper == nil {
				break
			}
			lower = *tier.upper
		}
	}
	return total
}

type BalanceEntry struct {
	day         int
	description string
	change      int
	balance     int
}

type Customer struct {
	name          string
	region        string
	method        string
	balance       int
	log           []BalanceEntry
	subscriptions []*Subscription
	invoices      []*Invoice
}

type Coupon struct {
	name         string
	kind         string
	value        int
	applications *int
	maximum      *int
	redemptions  int
}

type Subscription struct {
	number     int
	customer   *Customer
	plan       *Plan
	seats      int
	state      string
	start      int
	end        int
	trialEnd   int
	pauseStart int
	pending    *PendingChange
	cancelEnd  bool
	cancelOn   int
	canceledOn int
	coupon     *Coupon
	remaining  *int
	usage      int
	invoices   []*Invoice
}

func (subscription *Subscription) fee() int {
	return subscription.plan.fee(subscription.seats)
}

func (subscription *Subscription) period() string {
	return fmt.Sprintf("%d-%d", subscription.start, subscription.end)
}

type PendingChange struct {
	plan  *Plan
	seats int
}

type Item struct {
	description string
	amount      int
}

type Totals struct {
	subtotal int
	discount int
	tax      int
	total    int
	credit   int
	due      int
}

type Invoice struct {
	number       int
	subscription *Subscription
	customer     *Customer
	day          int
	kind         string
	items        []Item
	Totals
	paid        int
	refunded    int
	outstanding int
	attempts    int
	retries     []int
}

func (invoice *Invoice) state() string {
	if invoice.outstanding == 0 {
		return "PAID"
	}
	return "OPEN"
}

type Event struct {
	day    int
	number int
	old    string
	new    string
}

type Service struct {
	day           int
	plans         map[string]*Plan
	taxes         map[string]int
	customers     map[string]*Customer
	coupons       map[string]*Coupon
	subscriptions []*Subscription
	invoices      []*Invoice
	events        []Event
	output        []string
}

func newService() *Service {
	return &Service{
		day:       1,
		plans:     make(map[string]*Plan),
		taxes:     make(map[string]int),
		customers: make(map[string]*Customer),
		coupons:   make(map[string]*Coupon),
	}
}

func (service *Service) emit(parts ...any) {
	fields := make([]string, len(parts))
	for i, part := range parts {
		fields[i] = fmt.Sprint(part)
	}
	service.output = append(service.output, strings.Join(fields, " "))
}

func (service *Service) indented(parts ...any) {
	fields := make([]string, len(parts))
	for i, part := range parts {
		fields[i] = fmt.Sprint(part)
	}
	service.output = append(service.output, "  "+strings.Join(fields, " "))
}

func (service *Service) notice(parts ...any) {
	values := append([]any{"day", service.day}, parts...)
	service.indented(values...)
}

func (service *Service) requirePlan(name string) (*Plan, error) {
	if plan := service.plans[name]; plan != nil {
		return plan, nil
	}
	return nil, fmt.Errorf("unknown plan %s", name)
}

func (service *Service) requireCustomer(name string) (*Customer, error) {
	if customer := service.customers[name]; customer != nil {
		return customer, nil
	}
	return nil, fmt.Errorf("unknown customer %s", name)
}

func (service *Service) redeemableCoupon(name string) (*Coupon, error) {
	coupon := service.coupons[name]
	if coupon == nil {
		return nil, fmt.Errorf("unknown coupon %s", name)
	}
	if coupon.maximum != nil && coupon.redemptions == *coupon.maximum {
		return nil, fmt.Errorf("coupon exhausted %s", name)
	}
	return coupon, nil
}

func (service *Service) requireSubscription(text string, permitted ...string) (*Subscription, error) {
	id := number(text)
	if id < 1 || id > len(service.subscriptions) {
		return nil, fmt.Errorf("unknown sub %s", text)
	}
	subscription := service.subscriptions[id-1]
	if len(permitted) > 0 && !among(subscription.state, permitted...) {
		return nil, fmt.Errorf("invalid state %s %s", text, subscription.state)
	}
	return subscription, nil
}

func (service *Service) requireInvoice(text string) (*Invoice, error) {
	id := number(text)
	if id < 1 || id > len(service.invoices) {
		return nil, fmt.Errorf("unknown invoice %s", text)
	}
	return service.invoices[id-1], nil
}

func (service *Service) balanceChange(customer *Customer, change int, description string) {
	if change == 0 {
		return
	}
	customer.balance += change
	customer.log = append(customer.log, BalanceEntry{
		day: service.day, description: description, change: change, balance: customer.balance,
	})
}

func (service *Service) changeState(subscription *Subscription, state string) {
	old := subscription.state
	if old == "PAST_DUE" {
		for _, invoice := range subscription.invoices {
			invoice.retries = nil
		}
	}
	subscription.state = state
	service.notice("sub", subscription.number, old, "->", state)
	service.events = append(service.events, Event{service.day, subscription.number, old, state})
}

func periodItem(plan *Plan, seats, start int) Item {
	return Item{
		description: fmt.Sprintf("charge %s seats %d %d-%d",
			plan.name, seats, start, start+plan.length),
		amount: plan.fee(seats),
	}
}

func openingItems(subscription *Subscription, start int) []Item {
	plan := subscription.plan
	items := []Item{periodItem(plan, subscription.seats, start)}
	if plan.setup != 0 {
		items = append(items, Item{description: "setup " + plan.name, amount: plan.setup})
	}
	return items
}

func usageItems(subscription *Subscription, close bool) []Item {
	if subscription.plan.mode == "" || subscription.usage == 0 {
		return nil
	}
	units := subscription.usage
	item := Item{
		description: fmt.Sprintf("usage %s %d units", subscription.plan.name, units),
		amount:      subscription.plan.usageCharge(units),
	}
	if close {
		subscription.usage = 0
	}
	return []Item{item}
}

func couponUsable(subscription *Subscription, subtotal int) bool {
	return subtotal > 0 && subscription.coupon != nil &&
		(subscription.remaining == nil || *subscription.remaining > 0)
}

func (service *Service) invoiceTotals(subscription *Subscription, items []Item) Totals {
	var totals Totals
	for _, item := range items {
		totals.subtotal += item.amount
	}
	if couponUsable(subscription, totals.subtotal) {
		coupon := subscription.coupon
		if coupon.kind == "PERCENT" {
			totals.discount = totals.subtotal * coupon.value / 10000
		} else {
			totals.discount = smaller(totals.subtotal, coupon.value)
		}
	}
	totals.tax = (totals.subtotal - totals.discount) * service.taxes[subscription.customer.region] / 10000
	totals.total = totals.subtotal - totals.discount + totals.tax
	totals.credit = smaller(subscription.customer.balance, totals.total)
	totals.due = totals.total - totals.credit
	return totals
}

func (service *Service) issue(subscription *Subscription, kind string, items []Item) {
	totals := service.invoiceTotals(subscription, items)
	invoice := &Invoice{
		number:       len(service.invoices) + 1,
		subscription: subscription,
		customer:     subscription.customer,
		day:          service.day,
		kind:         kind,
		items:        items,
		Totals:       totals,
		outstanding:  totals.due,
	}
	if couponUsable(subscription, invoice.subtotal) && subscription.remaining != nil {
		*subscription.remaining--
	}
	service.invoices = append(service.invoices, invoice)
	subscription.invoices = append(subscription.invoices, invoice)
	subscription.customer.invoices = append(subscription.customer.invoices, invoice)
	service.balanceChange(subscription.customer, -invoice.credit, fmt.Sprintf("applied invoice %d", invoice.number))
	result := "PAID"
	if invoice.due == 0 {
		result = "PAID"
	} else if subscription.state == "UNPAID" {
		result = "OPEN"
	} else {
		invoice.attempts = 1
		if subscription.customer.method == "OK" {
			invoice.paid = invoice.due
			invoice.outstanding = 0
			result = "PAID"
		} else {
			result = "FAILED"
		}
	}
	service.notice("invoice", invoice.number, "sub", subscription.number, kind,
		"total", money(invoice.total), "credit", money(invoice.credit),
		"due", money(invoice.due), result)
	if result == "FAILED" {
		if subscription.state == "ACTIVE" {
			service.changeState(subscription, "PAST_DUE")
		}
		if subscription.state == "PAST_DUE" {
			invoice.retries = []int{service.day + 3, service.day + 5, service.day + 7}
		}
	}
}

func (service *Service) paymentComplete(invoice *Invoice) {
	invoice.retries = nil
	subscription := invoice.subscription
	if !among(subscription.state, "PAST_DUE", "UNPAID") {
		return
	}
	for _, other := range subscription.invoices {
		if other.outstanding != 0 {
			return
		}
	}
	subscription.cancelOn = 0
	service.changeState(subscription, "ACTIVE")
}

func (service *Service) cancelSubscription(subscription *Subscription) {
	service.changeState(subscription, "CANCELED")
	subscription.canceledOn = service.day
	subscription.pending = nil
	subscription.cancelEnd = false
	subscription.cancelOn = 0
	items := usageItems(subscription, true)
	if len(items) > 0 {
		service.issue(subscription, "final", items)
	}
}

func (service *Service) retry(invoice *Invoice) {
	invoice.retries = invoice.retries[1:]
	invoice.attempts++
	attempt := invoice.attempts - 1
	if invoice.customer.method == "OK" {
		invoice.paid += invoice.outstanding
		invoice.outstanding = 0
		service.notice("retry", attempt, "invoice", invoice.number, "PAID")
		service.paymentComplete(invoice)
	} else {
		service.notice("retry", attempt, "invoice", invoice.number, "FAILED")
		if len(invoice.retries) == 0 {
			service.changeState(invoice.subscription, "UNPAID")
			invoice.subscription.cancelOn = service.day + 14
		}
	}
}

func (service *Service) advanceSubscription(subscription *Subscription) {
	if among(subscription.state, "PAUSED", "CANCELED") {
		return
	}
	for _, invoice := range subscription.invoices {
		if len(invoice.retries) > 0 && invoice.retries[0] == service.day {
			service.retry(invoice)
		}
	}
	if subscription.state == "UNPAID" && subscription.cancelOn == service.day {
		service.cancelSubscription(subscription)
	}
	if subscription.state == "TRIALING" && subscription.trialEnd == service.day {
		if subscription.cancelEnd {
			service.cancelSubscription(subscription)
		} else {
			service.changeState(subscription, "ACTIVE")
			subscription.start = service.day
			subscription.end = service.day + subscription.plan.length
			service.issue(subscription, "first", openingItems(subscription, service.day))
		}
	}
	if among(subscription.state, "ACTIVE", "PAST_DUE", "UNPAID") &&
		subscription.end == service.day {
		if subscription.cancelEnd {
			service.cancelSubscription(subscription)
		} else {
			items := usageItems(subscription, true)
			if subscription.pending != nil {
				change := subscription.pending
				service.notice("sub", subscription.number, subscription.plan.name,
					"seats", subscription.seats, "->", change.plan.name, "seats", change.seats)
				subscription.plan = change.plan
				subscription.seats = change.seats
				subscription.pending = nil
			}
			subscription.start = service.day
			subscription.end = service.day + subscription.plan.length
			items = append(items, periodItem(subscription.plan, subscription.seats, service.day))
			service.issue(subscription, "renewal", items)
		}
	}
}

func (service *Service) cmdPlan(args []string) error {
	name, amount, cycle := args[0], args[1], args[2]
	if service.plans[name] != nil {
		return fmt.Errorf("duplicate plan %s", name)
	}
	plan := &Plan{name: name, price: cents(amount), cycle: cycle, length: periodLengths[cycle]}
	for i := 3; i < len(args); {
		switch args[i] {
		case "TRIAL":
			plan.trial = number(args[i+1])
			i += 2
		case "SETUP":
			plan.setup = cents(args[i+1])
			i += 2
		case "PERSEAT":
			plan.perSeat = true
			i++
		default:
			plan.mode = args[i]
			i++
		}
	}
	service.plans[name] = plan
	parts := []any{"PLAN", name, cycle, amount}
	if plan.trial > 0 {
		parts = append(parts, "trial", plan.trial)
	}
	if plan.setup > 0 {
		parts = append(parts, "setup", money(plan.setup))
	}
	if plan.perSeat {
		parts = append(parts, "perseat")
	}
	if plan.mode != "" {
		parts = append(parts, strings.ToLower(plan.mode))
	}
	service.emit(parts...)
	return nil
}

func (service *Service) cmdTier(args []string) error {
	name, limit, unit, flat := args[0], args[1], args[2], args[3]
	plan, err := service.requirePlan(name)
	if err != nil {
		return err
	}
	if plan.mode == "" {
		return fmt.Errorf("not metered %s", name)
	}
	var upper *int
	if limit != "INF" {
		value := number(limit)
		upper = &value
	}
	if len(plan.tiers) > 0 {
		previous := plan.tiers[len(plan.tiers)-1].upper
		if previous == nil || (upper != nil && *upper <= *previous) {
			return fmt.Errorf("tier order %s", name)
		}
	}
	plan.tiers = append(plan.tiers, Tier{upper: upper, unit: cents(unit), flat: cents(flat)})
	service.emit("TIER", name, len(plan.tiers), "upto", limit, "unit", unit, "flat", flat)
	return nil
}

func (service *Service) cmdTax(args []string) error {
	region, bp := args[0], number(args[1])
	service.taxes[region] = bp
	service.emit("TAX", region, percentage(bp))
	return nil
}

func (service *Service) cmdCustomer(args []string) error {
	name, region := args[0], args[1]
	if service.customers[name] != nil {
		return fmt.Errorf("duplicate customer %s", name)
	}
	service.customers[name] = &Customer{name: name, region: region, method: "OK"}
	service.emit("CUSTOMER", name, "region", region)
	return nil
}

func (service *Service) cmdCoupon(args []string) error {
	name, kind, value, application := args[0], args[1], args[2], args[3]
	if service.coupons[name] != nil {
		return fmt.Errorf("duplicate coupon %s", name)
	}
	var applications, maximum *int
	if application == "ONCE" {
		count := 1
		applications = &count
	}
	index := 4
	if application == "REPEATING" {
		count := number(args[4])
		applications = &count
		index = 5
	}
	if index < len(args) {
		count := number(args[index+1])
		maximum = &count
	}
	numeric := number(value)
	if kind == "AMOUNT" {
		numeric = cents(value)
	}
	coupon := &Coupon{
		name: name, kind: kind, value: numeric,
		applications: applications, maximum: maximum,
	}
	service.coupons[name] = coupon
	shown := money(numeric)
	if kind == "PERCENT" {
		shown = percentage(numeric)
	}
	parts := []any{"COUPON", name, strings.ToLower(kind), shown, strings.ToLower(application)}
	if application == "REPEATING" {
		parts = append(parts, *applications)
	}
	if maximum != nil {
		parts = append(parts, "max", *maximum)
	}
	service.emit(parts...)
	return nil
}

func (service *Service) cmdPaymethod(args []string) error {
	customer, err := service.requireCustomer(args[0])
	if err != nil {
		return err
	}
	customer.method = args[1]
	service.emit("PAYMETHOD", args[0], args[1])
	return nil
}

func (service *Service) cmdCredit(args []string) error {
	customer, err := service.requireCustomer(args[0])
	if err != nil {
		return err
	}
	value := cents(args[1])
	if value == 0 {
		return fmt.Errorf("invalid amount")
	}
	service.balanceChange(customer, value, "grant")
	service.emit("CREDIT", args[0], "amount", args[1], "balance", money(customer.balance))
	return nil
}

func (service *Service) cmdDay(args []string) error {
	target := number(args[0])
	if target <= service.day {
		return fmt.Errorf("invalid day %s", args[0])
	}
	service.emit("DAY", target)
	for day := service.day + 1; day <= target; day++ {
		service.day = day
		for _, subscription := range service.subscriptions {
			service.advanceSubscription(subscription)
		}
	}
	return nil
}

func (service *Service) cmdSubscribe(args []string) error {
	name, planName := args[0], args[1]
	customer, err := service.requireCustomer(name)
	if err != nil {
		return err
	}
	plan, err := service.requirePlan(planName)
	if err != nil {
		return err
	}
	seats, hasSeats, couponName := 1, false, ""
	for i := 2; i < len(args); i += 2 {
		if args[i] == "SEATS" {
			seats = number(args[i+1])
			hasSeats = true
		} else {
			couponName = args[i+1]
		}
	}
	if hasSeats && !plan.perSeat {
		return fmt.Errorf("not per-seat %s", planName)
	}
	if seats == 0 {
		return fmt.Errorf("invalid seats")
	}
	var coupon *Coupon
	if couponName != "" {
		coupon, err = service.redeemableCoupon(couponName)
		if err != nil {
			return err
		}
	}
	subscription := &Subscription{
		number: len(service.subscriptions) + 1, customer: customer,
		plan: plan, seats: seats, state: "NONE", coupon: coupon,
	}
	if coupon != nil {
		coupon.redemptions++
		if coupon.applications != nil {
			remaining := *coupon.applications
			subscription.remaining = &remaining
		}
	}
	service.subscriptions = append(service.subscriptions, subscription)
	customer.subscriptions = append(customer.subscriptions, subscription)
	parts := []any{"SUBSCRIBE", "sub", subscription.number, name, planName, "seats", seats}
	if coupon != nil {
		parts = append(parts, "coupon", coupon.name)
	}
	service.emit(parts...)
	if plan.trial > 0 {
		subscription.trialEnd = service.day + plan.trial
		service.changeState(subscription, "TRIALING")
	} else {
		service.changeState(subscription, "ACTIVE")
		subscription.start = service.day
		subscription.end = service.day + plan.length
		service.issue(subscription, "first", openingItems(subscription, service.day))
	}
	return nil
}

func (service *Service) cmdChange(args []string) error {
	text, kind, value := args[0], args[1], args[2]
	subscription, err := service.requireSubscription(text, "ACTIVE", "TRIALING")
	if err != nil {
		return err
	}
	oldPlan, oldSeats := subscription.plan, subscription.seats
	var plan *Plan
	var seats int
	if kind == "PLAN" {
		plan, err = service.requirePlan(value)
		if err != nil {
			return err
		}
		seats = 1
		if plan.perSeat {
			seats = oldSeats
		}
	} else {
		plan = oldPlan
		if !plan.perSeat {
			return fmt.Errorf("not per-seat %s", plan.name)
		}
		seats = number(value)
		if seats == 0 {
			return fmt.Errorf("invalid seats")
		}
	}
	if plan == oldPlan && seats == oldSeats {
		return fmt.Errorf("no change %s", text)
	}
	head := []any{"CHANGE", "sub", subscription.number, oldPlan.name, "seats", oldSeats,
		"->", plan.name, "seats", seats}
	subscription.pending = nil
	upgrade := plan.fee(seats)*oldPlan.length > oldPlan.fee(oldSeats)*plan.length
	if subscription.state == "TRIALING" {
		subscription.plan = plan
		subscription.seats = seats
		service.emit(append(head, "now")...)
	} else if upgrade {
		service.emit(append(head, "now")...)
		days := subscription.end - service.day
		items := usageItems(subscription, true)
		items = append(items, Item{
			description: fmt.Sprintf("unused %s seats %d %d days", oldPlan.name, oldSeats, days),
			amount:      -(oldPlan.fee(oldSeats) * days / oldPlan.length),
		})
		items = append(items, Item{
			description: fmt.Sprintf("remaining %s seats %d %d days", plan.name, seats, days),
			amount:      plan.fee(seats) * days / plan.length,
		})
		subscription.plan = plan
		subscription.seats = seats
		service.issue(subscription, "upgrade", items)
	} else {
		subscription.pending = &PendingChange{plan: plan, seats: seats}
		service.emit(append(head, "at", subscription.end)...)
	}
	return nil
}

func (service *Service) cmdPause(args []string) error {
	subscription, err := service.requireSubscription(args[0], "ACTIVE")
	if err != nil {
		return err
	}
	service.emit("PAUSE", "sub", subscription.number)
	subscription.pauseStart = service.day
	service.changeState(subscription, "PAUSED")
	return nil
}

func (service *Service) cmdResume(args []string) error {
	subscription, err := service.requireSubscription(args[0], "PAUSED")
	if err != nil {
		return err
	}
	elapsed := service.day - subscription.pauseStart
	subscription.end += elapsed
	subscription.pauseStart = 0
	service.emit("RESUME", "sub", subscription.number, "shift", elapsed, "period", subscription.period())
	service.changeState(subscription, "ACTIVE")
	return nil
}

func (service *Service) cmdCancel(args []string) error {
	text, when := args[0], args[1]
	subscription, err := service.requireSubscription(text)
	if err != nil {
		return err
	}
	if when == "END" {
		if !among(subscription.state, "ACTIVE", "TRIALING") {
			return fmt.Errorf("invalid state %s %s", text, subscription.state)
		}
		if subscription.cancelEnd {
			return fmt.Errorf("already canceling %s", text)
		}
		subscription.cancelEnd = true
		day := subscription.end
		if subscription.state == "TRIALING" {
			day = subscription.trialEnd
		}
		service.emit("CANCEL", "sub", subscription.number, "end", day)
	} else {
		if subscription.state == "CANCELED" {
			return fmt.Errorf("invalid state %s %s", text, subscription.state)
		}
		refund := 0
		if among(subscription.state, "ACTIVE", "PAUSED") {
			start := service.day
			if subscription.state == "PAUSED" {
				start = subscription.pauseStart
			}
			refund = subscription.fee() * (subscription.end - start) / subscription.plan.length
		}
		service.balanceChange(subscription.customer, refund, fmt.Sprintf("cancel sub %d", subscription.number))
		service.emit("CANCEL", "sub", subscription.number, "now", "credit", money(refund))
		service.cancelSubscription(subscription)
	}
	return nil
}

func (service *Service) cmdUsage(args []string) error {
	subscription, err := service.requireSubscription(args[0], "ACTIVE", "PAST_DUE")
	if err != nil {
		return err
	}
	if subscription.plan.mode == "" {
		return fmt.Errorf("not metered %s", subscription.plan.name)
	}
	quantity := number(args[1])
	if quantity == 0 {
		return fmt.Errorf("invalid units")
	}
	subscription.usage += quantity
	service.emit("USAGE", "sub", subscription.number, "units", quantity, "total", subscription.usage)
	return nil
}

func (service *Service) cmdApply(args []string) error {
	text, name := args[0], args[1]
	subscription, err := service.requireSubscription(text)
	if err != nil {
		return err
	}
	if subscription.state == "CANCELED" {
		return fmt.Errorf("invalid state %s %s", text, subscription.state)
	}
	coupon, err := service.redeemableCoupon(name)
	if err != nil {
		return err
	}
	coupon.redemptions++
	subscription.coupon = coupon
	subscription.remaining = nil
	if coupon.applications != nil {
		remaining := *coupon.applications
		subscription.remaining = &remaining
	}
	service.emit("APPLY", "sub", subscription.number, "coupon", name)
	return nil
}

func (service *Service) cmdPay(args []string) error {
	text := args[0]
	invoice, err := service.requireInvoice(text)
	if err != nil {
		return err
	}
	if invoice.outstanding == 0 {
		return fmt.Errorf("already paid %s", text)
	}
	service.emit("PAY", "invoice", invoice.number, "amount", money(invoice.outstanding))
	invoice.paid += invoice.outstanding
	invoice.outstanding = 0
	service.paymentComplete(invoice)
	return nil
}

func (service *Service) cmdRefund(args []string) error {
	text, amount := args[0], args[1]
	invoice, err := service.requireInvoice(text)
	if err != nil {
		return err
	}
	value := cents(amount)
	if value == 0 {
		return fmt.Errorf("invalid amount")
	}
	maximum := invoice.total - invoice.refunded
	if value > maximum {
		return fmt.Errorf("refund exceeds %s %s", text, money(maximum))
	}
	applied := smaller(value, invoice.outstanding)
	invoice.refunded += value
	invoice.outstanding -= applied
	service.balanceChange(invoice.customer, value-applied, fmt.Sprintf("refund invoice %d", invoice.number))
	service.emit("REFUND", "invoice", invoice.number, "amount", amount,
		"applied", money(applied), "balance", money(invoice.customer.balance))
	if applied > 0 && invoice.outstanding == 0 {
		service.paymentComplete(invoice)
	}
	return nil
}

func (service *Service) emitItems(items []Item) {
	for _, item := range items {
		service.indented(item.description, money(item.amount))
	}
}

func (service *Service) emitTotals(totals Totals) {
	service.indented("subtotal", money(totals.subtotal), "discount", money(totals.discount),
		"tax", money(totals.tax), "total", money(totals.total))
}

func (service *Service) cmdInvoice(args []string) error {
	invoice, err := service.requireInvoice(args[0])
	if err != nil {
		return err
	}
	service.emit("INVOICE", invoice.number, "sub", invoice.subscription.number,
		invoice.customer.name, "day", invoice.day, invoice.kind, invoice.state())
	service.emitItems(invoice.items)
	service.emitTotals(invoice.Totals)
	service.indented("credit", money(invoice.credit), "due", money(invoice.due),
		"paid", money(invoice.paid), "refunded", money(invoice.refunded),
		"outstanding", money(invoice.outstanding))
	return nil
}

func (service *Service) cmdSub(args []string) error {
	subscription, err := service.requireSubscription(args[0])
	if err != nil {
		return err
	}
	state := subscription.state
	service.emit("SUB", subscription.number, subscription.customer.name, subscription.plan.name,
		"seats", subscription.seats, state)
	if state == "TRIALING" {
		service.indented("trial until", subscription.trialEnd)
	}
	if among(state, "ACTIVE", "PAST_DUE", "UNPAID", "PAUSED") {
		service.indented("period", subscription.period())
	}
	if state == "PAUSED" {
		service.indented("paused since", subscription.pauseStart)
	}
	if subscription.pending != nil {
		service.indented("pending", subscription.pending.plan.name, "seats", subscription.pending.seats)
	}
	if subscription.cancelEnd {
		service.indented("cancel at end")
	}
	if subscription.cancelOn != 0 {
		service.indented("cancel on", subscription.cancelOn)
	}
	if state == "CANCELED" {
		service.indented("canceled on", subscription.canceledOn)
	}
	if subscription.coupon != nil {
		if subscription.remaining == nil {
			service.indented("coupon", subscription.coupon.name, "forever")
		} else if *subscription.remaining > 0 {
			service.indented("coupon", subscription.coupon.name, "left", *subscription.remaining)
		}
	}
	if subscription.plan.mode != "" && state != "CANCELED" {
		service.indented("usage", subscription.usage)
	}
	open := []any{"open"}
	for _, invoice := range subscription.invoices {
		if invoice.outstanding != 0 {
			open = append(open, invoice.number)
		}
	}
	if len(open) > 1 {
		service.indented(open...)
	}
	return nil
}

func (service *Service) cmdPreview(args []string) error {
	subscription, err := service.requireSubscription(
		args[0], "TRIALING", "ACTIVE", "PAST_DUE", "UNPAID")
	if err != nil {
		return err
	}
	day := subscription.end
	if subscription.state == "TRIALING" {
		day = subscription.trialEnd
	}
	var items []Item
	kind := "renewal"
	if subscription.cancelEnd {
		kind = "final"
		if subscription.state != "TRIALING" {
			items = usageItems(subscription, false)
		}
	} else if subscription.state == "TRIALING" {
		kind = "first"
		items = openingItems(subscription, day)
	} else {
		plan, seats := subscription.plan, subscription.seats
		if subscription.pending != nil {
			plan, seats = subscription.pending.plan, subscription.pending.seats
		}
		items = usageItems(subscription, false)
		items = append(items, periodItem(plan, seats, day))
	}
	service.emit("PREVIEW", "sub", subscription.number, "day", day, kind)
	if len(items) == 0 {
		service.indented("(none)")
		return nil
	}
	service.emitItems(items)
	totals := service.invoiceTotals(subscription, items)
	service.emitTotals(totals)
	service.indented("credit", money(totals.credit), "due", money(totals.due))
	return nil
}

func (service *Service) cmdStatement(args []string) error {
	customer, err := service.requireCustomer(args[0])
	if err != nil {
		return err
	}
	service.emit("STATEMENT", customer.name, "region", customer.region,
		"tax", percentage(service.taxes[customer.region]), "method", customer.method,
		"balance", money(customer.balance))
	for _, subscription := range customer.subscriptions {
		service.indented("sub", subscription.number, subscription.plan.name, subscription.state)
	}
	outstanding := 0
	for _, invoice := range customer.invoices {
		service.indented("invoice", invoice.number, "day", invoice.day, "sub",
			invoice.subscription.number, invoice.kind, "total", money(invoice.total),
			"outstanding", money(invoice.outstanding))
		outstanding += invoice.outstanding
	}
	service.indented("outstanding", money(outstanding))
	return nil
}

func (service *Service) cmdLedger(args []string) error {
	customer, err := service.requireCustomer(args[0])
	if err != nil {
		return err
	}
	service.emit("LEDGER", customer.name, "balance", money(customer.balance))
	if len(customer.log) == 0 {
		service.indented("(none)")
	}
	for _, entry := range customer.log {
		service.indented("day", entry.day, entry.description, signedMoney(entry.change),
			"balance", money(entry.balance))
	}
	return nil
}

func (service *Service) cmdMrr(_ []string) error {
	type Aggregate struct{ count, monthly int }
	byPlan := make(map[string]*Aggregate)
	for _, subscription := range service.subscriptions {
		if !among(subscription.state, "ACTIVE", "PAST_DUE") {
			continue
		}
		fee := subscription.fee()
		var monthly int
		switch subscription.plan.cycle {
		case "MONTHLY":
			monthly = fee
		case "YEARLY":
			monthly = fee / 12
		default:
			monthly = fee * 30 / 7
		}
		name := subscription.plan.name
		if byPlan[name] == nil {
			byPlan[name] = &Aggregate{}
		}
		byPlan[name].count++
		byPlan[name].monthly += monthly
	}
	keys := make([]string, 0, len(byPlan))
	for name := range byPlan {
		keys = append(keys, name)
	}
	sort.Strings(keys)
	service.emit("MRR")
	count, total := 0, 0
	for _, name := range keys {
		row := byPlan[name]
		service.indented(name, "subs", row.count, "mrr", money(row.monthly))
		count += row.count
		total += row.monthly
	}
	service.indented("total subs", count, "mrr", money(total))
	return nil
}

func agingParts(values [3]int) []any {
	return []any{"0-30", money(values[0]), "31-60", money(values[1]),
		"61+", money(values[2]), "sum", money(values[0]+values[1]+values[2])}
}

func (service *Service) cmdAging(_ []string) error {
	byCustomer := make(map[string]*[3]int)
	var totals [3]int
	for _, invoice := range service.invoices {
		if invoice.outstanding == 0 {
			continue
		}
		age := service.day - invoice.day
		bucket := 0
		if age > 60 {
			bucket = 2
		} else if age > 30 {
			bucket = 1
		}
		name := invoice.customer.name
		if byCustomer[name] == nil {
			byCustomer[name] = &[3]int{}
		}
		byCustomer[name][bucket] += invoice.outstanding
		totals[bucket] += invoice.outstanding
	}
	keys := make([]string, 0, len(byCustomer))
	for name := range byCustomer {
		keys = append(keys, name)
	}
	sort.Strings(keys)
	service.emit("AGING", "day", service.day)
	for _, name := range keys {
		service.indented(append([]any{name}, agingParts(*byCustomer[name])...)...)
	}
	service.indented(append([]any{"total"}, agingParts(totals)...)...)
	return nil
}

func (service *Service) cmdDunning(_ []string) error {
	service.emit("DUNNING")
	found := false
	for _, invoice := range service.invoices {
		if len(invoice.retries) > 0 {
			found = true
			service.indented("invoice", invoice.number, "sub", invoice.subscription.number,
				invoice.customer.name, "outstanding", money(invoice.outstanding),
				"attempts", invoice.attempts, "next", invoice.retries[0])
		}
	}
	if !found {
		service.indented("(none)")
	}
	return nil
}

func (service *Service) cmdRevenue(_ []string) error {
	var totals Totals
	counts := struct{ paid, refunded, outstanding, balances int }{}
	for _, invoice := range service.invoices {
		totals.subtotal += invoice.subtotal
		totals.discount += invoice.discount
		totals.tax += invoice.tax
		totals.total += invoice.total
		totals.credit += invoice.credit
		counts.paid += invoice.paid
		counts.refunded += invoice.refunded
		counts.outstanding += invoice.outstanding
	}
	for _, customer := range service.customers {
		counts.balances += customer.balance
	}
	service.emit("REVENUE")
	service.indented("invoices", len(service.invoices), "subtotal", money(totals.subtotal),
		"discount", money(totals.discount), "tax", money(totals.tax), "total", money(totals.total))
	service.indented("credit", money(totals.credit), "paid", money(counts.paid),
		"refunded", money(counts.refunded), "outstanding", money(counts.outstanding),
		"balances", money(counts.balances))
	return nil
}

func (service *Service) cmdEvents(args []string) error {
	selected := 0
	if len(args) > 0 {
		subscription, err := service.requireSubscription(args[0])
		if err != nil {
			return err
		}
		selected = subscription.number
	}
	if selected == 0 {
		service.emit("EVENTS")
	} else {
		service.emit("EVENTS", "sub", selected)
	}
	found := false
	for _, event := range service.events {
		if selected == 0 || event.number == selected {
			found = true
			service.indented("day", event.day, "sub", event.number, event.old, "->", event.new)
		}
	}
	if !found {
		service.indented("(none)")
	}
	return nil
}

func (service *Service) execute(line string) {
	tokens := strings.Fields(line)
	command, args := tokens[0], tokens[1:]
	var err error
	switch command {
	case "PLAN":
		err = service.cmdPlan(args)
	case "TIER":
		err = service.cmdTier(args)
	case "TAX":
		err = service.cmdTax(args)
	case "CUSTOMER":
		err = service.cmdCustomer(args)
	case "COUPON":
		err = service.cmdCoupon(args)
	case "PAYMETHOD":
		err = service.cmdPaymethod(args)
	case "CREDIT":
		err = service.cmdCredit(args)
	case "DAY":
		err = service.cmdDay(args)
	case "SUBSCRIBE":
		err = service.cmdSubscribe(args)
	case "CHANGE":
		err = service.cmdChange(args)
	case "PAUSE":
		err = service.cmdPause(args)
	case "RESUME":
		err = service.cmdResume(args)
	case "CANCEL":
		err = service.cmdCancel(args)
	case "USAGE":
		err = service.cmdUsage(args)
	case "APPLY":
		err = service.cmdApply(args)
	case "PAY":
		err = service.cmdPay(args)
	case "REFUND":
		err = service.cmdRefund(args)
	case "INVOICE":
		err = service.cmdInvoice(args)
	case "SUB":
		err = service.cmdSub(args)
	case "PREVIEW":
		err = service.cmdPreview(args)
	case "STATEMENT":
		err = service.cmdStatement(args)
	case "LEDGER":
		err = service.cmdLedger(args)
	case "MRR":
		err = service.cmdMrr(args)
	case "AGING":
		err = service.cmdAging(args)
	case "DUNNING":
		err = service.cmdDunning(args)
	case "REVENUE":
		err = service.cmdRevenue(args)
	case "EVENTS":
		err = service.cmdEvents(args)
	}
	if err != nil {
		service.emit("ERROR", err.Error())
	}
}

func main() {
	reader := bufio.NewScanner(os.Stdin)
	reader.Scan()
	count := number(reader.Text())
	service := newService()
	for i := 0; i < count && reader.Scan(); i++ {
		service.execute(reader.Text())
	}
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	for _, line := range service.output {
		fmt.Fprintln(writer, line)
	}
}
