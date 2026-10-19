package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Cents int64
type AccountType string
type Category string

const (
	asset       AccountType = "ASSET"
	liability   AccountType = "LIABILITY"
	equity      AccountType = "EQUITY"
	revenue     AccountType = "REVENUE"
	expense     AccountType = "EXPENSE"
	contraAsset AccountType = "CONTRA_ASSET"
	journal      Category = "journal"
	recurring    Category = "recurring"
	reversal     Category = "reversal"
	closing      Category = "closing"
	reopen       Category = "reopen"
	depreciation Category = "depreciation"
	interest     Category = "interest"
	writeoff     Category = "writeoff"
	lastDay = 36524
)

func (kind AccountType) class() AccountType {
	if kind == contraAsset { return asset }
	return kind
}

func (kind AccountType) sign() Cents {
	if kind == asset || kind == expense { return 1 }
	return -1
}

func (kind AccountType) temporary() bool { return kind == revenue || kind == expense }

func integer(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func parseMoney(text string) Cents {
	parts := strings.Split(text, ".")
	return Cents(integer(parts[0]))*100 + Cents(integer(parts[1]))
}

func money(value Cents) string {
	sign := ""
	if value < 0 { sign, value = "-", -value }
	return fmt.Sprintf("%s%d.%02d", sign, value/100, value%100)
}

func leap(year int) bool { return year%4 == 0 && (year%100 != 0 || year%400 == 0) }

func monthLength(year, month int) int {
	lengths := [...]int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	if month == 2 && leap(year) { return 29 }
	return lengths[month-1]
}

func yearLength(year int) int {
	if leap(year) { return 366 }
	return 365
}

func dayNumber(year, month, day int) int {
	number := day - 1
	for y := 2000; y < year; y++ { number += yearLength(y) }
	for m := 1; m < month; m++ { number += monthLength(year, m) }
	return number
}

func calendar(number int) (int, int, int) {
	year, month := 2000, 1
	for number >= yearLength(year) { number -= yearLength(year); year++ }
	for number >= monthLength(year, month) { number -= monthLength(year, month); month++ }
	return year, month, number + 1
}

func dateText(number int) string {
	year, month, day := calendar(number)
	return fmt.Sprintf("%04d-%02d-%02d", year, month, day)
}

func parseDate(text string) (int, error) {
	year, month, day := integer(text[:4]), integer(text[5:7]), integer(text[8:])
	if year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > monthLength(year, month) {
		return 0, fmt.Errorf("invalid date %s", text)
	}
	return dayNumber(year, month, day), nil
}

func dateRange(first, last string) (int, int, error) {
	start, err := parseDate(first)
	if err != nil { return 0, 0, err }
	end, err := parseDate(last)
	if err != nil { return 0, 0, err }
	if start > end { return 0, 0, fmt.Errorf("invalid range %s %s", first, last) }
	return start, end, nil
}

func monthsAfter(number, offset int) int {
	year, month, day := calendar(number)
	total := month - 1 + offset
	year, month = year + total/12, total%12 + 1
	return dayNumber(year, month, min(day, monthLength(year, month)))
}

func sortedKeys[V any](values map[string]V) []string {
	keys := make([]string, 0, len(values))
	for key := range values { keys = append(keys, key) }
	sort.Strings(keys)
	return keys
}

type Account struct {
	code, name string
	kind AccountType
	active bool
}

type Totals struct { debit, credit Cents }

func (totals Totals) difference() Cents { return totals.debit - totals.credit }

func (totals *Totals) add(debit bool, amount Cents) {
	if debit { totals.debit += amount } else { totals.credit += amount }
}

func (totals *Totals) merge(other Totals) {
	totals.debit += other.debit
	totals.credit += other.credit
}

type Line struct {
	debit bool
	account *Account
	amount Cents
	partner *string
}

func (line Line) difference() Cents {
	if line.debit { return line.amount }
	return -line.amount
}

func (line Line) side() string {
	if line.debit { return "DR" }
	return "CR"
}

type Lines struct {
	items []Line
	amount Cents
	accounts map[*Account]Totals
}

func newLines(items []Line) *Lines {
	lines := &Lines{items: items, accounts: make(map[*Account]Totals)}
	for _, line := range items {
		totals := lines.accounts[line.account]
		totals.add(line.debit, line.amount)
		lines.accounts[line.account] = totals
		if line.debit { lines.amount += line.amount }
	}
	return lines
}

type DraftLine struct {
	debit bool
	code string
	amount Cents
	partner *string
}

type Draft struct {
	journal bool
	key, date, memo string
	lines []DraftLine
}

func (draft *Draft) totals() Totals {
	var totals Totals
	for _, line := range draft.lines { totals.add(line.debit, line.amount) }
	return totals
}

type Entry struct {
	id, memo string
	day, sequence int
	category Category
	lines *Lines
	reverses, reversedBy *Entry
}

type Template struct {
	memo string
	lines *Lines
	uses int
}

type CloseRecord struct {
	day int
	entry *Entry
}

type OpenItem struct {
	entry *Entry
	original, remaining Cents
}

type Settlement struct {
	items []OpenItem
	unapplied Cents
}

type Book struct {
	accounts map[string]*Account
	entries []*Entry
	entryIDs map[string]*Entry
	templates map[string]*Template
	draft *Draft
	closes []CloseRecord
	closeCount, depreciationCount, interestCount, writeoffCount int
	output *bufio.Writer
}

func newBook(output *bufio.Writer) *Book {
	return &Book{accounts: make(map[string]*Account), entryIDs: make(map[string]*Entry),
		templates: make(map[string]*Template), output: output}
}

func (book *Book) emit(format string, args ...any) { fmt.Fprintf(book.output, format+"\n", args...) }

func (book *Book) account(code string) (*Account, error) {
	account, ok := book.accounts[code]
	if !ok { return nil, fmt.Errorf("unknown account %s", code) }
	return account, nil
}

func (book *Book) requireType(code string, kind AccountType) (*Account, error) {
	account, err := book.account(code)
	if err != nil { return nil, err }
	if account.kind != kind { return nil, fmt.Errorf("wrong type %s %s", code, kind) }
	return account, nil
}

func checkActive(accounts ...*Account) error {
	for _, account := range accounts {
		if !account.active { return fmt.Errorf("inactive account %s", account.code) }
	}
	return nil
}

func activeLines(lines *Lines) error {
	for _, line := range lines.items {
		if err := checkActive(line.account); err != nil { return err }
	}
	return nil
}

func (book *Book) checkOpen(day int) error {
	if len(book.closes) > 0 && day <= book.closes[len(book.closes)-1].day {
		return fmt.Errorf("period closed %s", dateText(day))
	}
	return nil
}

func (book *Book) closedText() string {
	if len(book.closes) == 0 { return "none" }
	return dateText(book.closes[len(book.closes)-1].day)
}

func (book *Book) parent(code string) string {
	for length := len(code)-1; length > 0; length-- {
		if _, ok := book.accounts[code[:length]]; ok { return code[:length] }
	}
	return "none"
}

func (book *Book) top(code string) string {
	for length := 1; length < len(code); length++ {
		if _, ok := book.accounts[code[:length]]; ok { return code[:length] }
	}
	return code
}

func (book *Book) ordered() []*Entry {
	entries := append([]*Entry(nil), book.entries...)
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].day != entries[j].day { return entries[i].day < entries[j].day }
		return entries[i].sequence < entries[j].sequence
	})
	return entries
}

func (book *Book) totals(first, last int, operating bool) map[*Account]Totals {
	totals := make(map[*Account]Totals)
	for _, entry := range book.entries {
		if entry.day < first || entry.day > last || operating && (entry.category == closing || entry.category == reopen) { continue }
		for account, amount := range entry.lines.accounts {
			current := totals[account]
			current.merge(amount)
			totals[account] = current
		}
	}
	return totals
}

func (book *Book) accountTotals(account *Account, first, last int) Totals {
	var totals Totals
	for _, entry := range book.entries {
		if first <= entry.day && entry.day <= last { totals.merge(entry.lines.accounts[account]) }
	}
	return totals
}

func (book *Book) balance(account *Account, day int) Cents {
	return account.kind.sign() * book.accountTotals(account, 0, day).difference()
}

func (book *Book) dailySum(account *Account, first, last int) Cents {
	changes := make([]Cents, last-first+1)
	var running, sum Cents
	for _, entry := range book.entries {
		if entry.day > last { continue }
		value := account.kind.sign() * entry.lines.accounts[account].difference()
		if entry.day < first { running += value } else { changes[entry.day-first] += value }
	}
	for _, change := range changes { running += change; sum += running }
	return sum
}

func (book *Book) post(id string, day int, category Category, memo string, lines *Lines) *Entry {
	entry := &Entry{id: id, day: day, category: category, memo: memo, lines: lines, sequence: len(book.entries)+1}
	book.entries = append(book.entries, entry)
	book.entryIDs[id] = entry
	return entry
}

func (book *Book) reverse(original *Entry, day int, category Category, memo string) *Entry {
	items := append([]Line(nil), original.lines.items...)
	for i := range items { items[i].debit = !items[i].debit }
	entry := book.post(original.id+"-R", day, category, memo, newLines(items))
	original.reversedBy, entry.reverses = entry, original
	return entry
}

func (book *Book) settlements(account *Account, day int) map[string]*Settlement {
	result := make(map[string]*Settlement)
	for _, entry := range book.ordered() {
		if entry.day > day { continue }
		for _, line := range entry.lines.items {
			if line.account != account || line.partner == nil { continue }
			partner := *line.partner
			settled := result[partner]
			if settled == nil { settled = &Settlement{}; result[partner] = settled }
			value := account.kind.sign() * line.difference()
			if value > 0 {
				applied := min(value, settled.unapplied)
				settled.unapplied -= applied
				if value > applied { settled.items = append(settled.items, OpenItem{entry, value, value-applied}) }
			} else {
				payment := -value
				for payment > 0 && len(settled.items) > 0 {
					item := &settled.items[0]
					applied := min(payment, item.remaining)
					payment -= applied
					item.remaining -= applied
					if item.remaining == 0 { settled.items = settled.items[1:] }
				}
				settled.unapplied += payment
				if len(settled.items) == 0 { settled.items = nil }
			}
		}
	}
	return result
}

func (book *Book) postDraft() error {
	if book.draft == nil { return fmt.Errorf("no open entry") }
	draft := book.draft
	book.draft = nil
	day := 0
	if draft.journal {
		if _, ok := book.entryIDs[draft.key]; ok { return fmt.Errorf("duplicate entry %s", draft.key) }
		var err error
		day, err = parseDate(draft.date)
		if err != nil { return err }
		if err := book.checkOpen(day); err != nil { return err }
	} else if _, ok := book.templates[draft.key]; ok { return fmt.Errorf("duplicate template %s", draft.key) }
	if len(draft.lines) < 2 { return fmt.Errorf("too few lines %s", draft.key) }
	items := make([]Line, 0, len(draft.lines))
	for _, line := range draft.lines {
		account, err := book.account(line.code)
		if err != nil { return err }
		if draft.journal { if err := checkActive(account); err != nil { return err } }
		if line.amount == 0 { return fmt.Errorf("zero amount %s", line.code) }
		items = append(items, Line{line.debit, account, line.amount, line.partner})
	}
	totals := draft.totals()
	if totals.debit != totals.credit {
		return fmt.Errorf("unbalanced %s debit %s credit %s", draft.key, money(totals.debit), money(totals.credit))
	}
	lines := newLines(items)
	if draft.journal {
		book.post(draft.key, day, journal, draft.memo, lines)
		book.emit("POST %s %s lines %d amount %s", draft.key, dateText(day), len(items), money(lines.amount))
	} else {
		book.templates[draft.key] = &Template{memo: draft.memo, lines: lines}
		book.emit("TEMPLATE %s lines %d amount %s", draft.key, len(items), money(lines.amount))
	}
	return nil
}

type Displayed struct { account *Account; amount Cents }

func (book *Book) section(heading string, kinds []AccountType, sign Cents, totals map[*Account]Totals, earnings *Cents) Cents {
	groups := make(map[string][]Displayed)
	var total Cents
	if earnings != nil { total = *earnings }
	for _, code := range sortedKeys(book.accounts) {
		account := book.accounts[code]
		selected := false
		for _, kind := range kinds { selected = selected || account.kind == kind }
		if !selected { continue }
		value := sign * totals[account].difference()
		root := book.top(code)
		groups[root] = append(groups[root], Displayed{account, value})
		total += value
	}
	book.emit("  %s %s", heading, money(total))
	for _, root := range sortedKeys(groups) {
		var subtotal Cents
		nonzero := false
		for _, item := range groups[root] { subtotal += item.amount; nonzero = nonzero || item.amount != 0 }
		if !nonzero { continue }
		book.emit("    %s %s %s", root, book.accounts[root].name, money(subtotal))
		for _, item := range groups[root] {
			if item.amount != 0 { book.emit("      %s %s %s", item.account.code, item.account.name, money(item.amount)) }
		}
	}
	if earnings != nil { book.emit("    current earnings %s", money(*earnings)) }
	return total
}

func (book *Book) agingRow(partner string, values [5]Cents) {
	balance := values[0]+values[1]+values[2]+values[3]-values[4]
	book.emit("  %s 0-30 %s 31-60 %s 61-90 %s 91+ %s unapplied %s balance %s", partner,
		money(values[0]), money(values[1]), money(values[2]), money(values[3]), money(values[4]), money(balance))
}

func (book *Book) execute(words []string) error {
	switch words[0] {
	case "ACCOUNT":
		code, kind := words[1], AccountType(words[2])
		if _, ok := book.accounts[code]; ok { return fmt.Errorf("duplicate account %s", code) }
		for _, other := range sortedKeys(book.accounts) {
			if (strings.HasPrefix(code, other) || strings.HasPrefix(other, code)) && kind.class() != book.accounts[other].kind.class() {
				return fmt.Errorf("class mismatch %s %s", code, other)
			}
		}
		book.accounts[code] = &Account{code, words[3], kind, true}
		book.emit("ACCOUNT %s %s %s parent %s", code, kind, words[3], book.parent(code))
	case "DEACTIVATE":
		account, err := book.account(words[1])
		if err != nil { return err }
		if !account.active { return fmt.Errorf("already inactive %s", account.code) }
		balance := book.balance(account, lastDay)
		if balance != 0 { return fmt.Errorf("nonzero balance %s %s", account.code, money(balance)) }
		account.active = false
		book.emit("DEACTIVATE %s %s", account.code, account.name)
	case "JOURNAL", "TEMPLATE":
		if book.draft != nil { book.emit("DISCARD %s lines %d", book.draft.key, len(book.draft.lines)) }
		draft := &Draft{journal: words[0] == "JOURNAL", key: words[1]}
		if draft.journal { draft.date, draft.memo = words[2], words[3] } else { draft.memo = words[2] }
		book.draft = draft
	case "DR", "CR":
		if book.draft == nil { return fmt.Errorf("no open entry") }
		var partner *string
		if len(words) == 4 { name := words[3]; partner = &name }
		book.draft.lines = append(book.draft.lines, DraftLine{words[0] == "DR", words[1], parseMoney(words[2]), partner})
	case "POST":
		return book.postDraft()
	case "DRAFT":
		if book.draft == nil { return fmt.Errorf("no open entry") }
		kind := "template"
		if book.draft.journal { kind = "journal" }
		totals := book.draft.totals()
		book.emit("DRAFT %s %s lines %d debit %s credit %s difference %s", kind, book.draft.key, len(book.draft.lines),
			money(totals.debit), money(totals.credit), money(totals.difference()))
	case "REVERSE":
		original, ok := book.entryIDs[words[1]]
		if !ok { return fmt.Errorf("unknown entry %s", words[1]) }
		if original.category == reversal || original.category == closing || original.category == reopen { return fmt.Errorf("cannot reverse %s", original.id) }
		if original.reversedBy != nil { return fmt.Errorf("already reversed %s", original.id) }
		day, err := parseDate(words[2])
		if err != nil { return err }
		if day < original.day { return fmt.Errorf("reverse before entry %s %s", original.id, dateText(original.day)) }
		if err := book.checkOpen(day); err != nil { return err }
		if err := activeLines(original.lines); err != nil { return err }
		entry := book.reverse(original, day, reversal, original.memo)
		book.emit("REVERSE %s entry %s %s amount %s", original.id, entry.id, dateText(day), money(entry.lines.amount))
	case "RECUR":
		model, ok := book.templates[words[1]]
		if !ok { return fmt.Errorf("unknown template %s", words[1]) }
		day, err := parseDate(words[2])
		if err != nil { return err }
		count := integer(words[3])
		if count == 0 { return fmt.Errorf("invalid count") }
		if err := book.checkOpen(day); err != nil { return err }
		if err := activeLines(model.lines); err != nil { return err }
		book.emit("RECUR %s count %d", words[1], count)
		for offset := 0; offset < count; offset++ {
			model.uses++
			entry := book.post(words[1]+"-"+strconv.Itoa(model.uses), monthsAfter(day, offset), recurring, model.memo, model.lines)
			book.emit("  POST %s %s lines %d amount %s", entry.id, dateText(entry.day), len(entry.lines.items), money(entry.lines.amount))
		}
	case "DEPRECIATE":
		day, err := parseDate(words[1])
		if err != nil { return err }
		if err := book.checkOpen(day); err != nil { return err }
		acquisition, err := book.requireType(words[2], asset)
		if err != nil { return err }
		contra, err := book.requireType(words[3], contraAsset)
		if err != nil { return err }
		costAccount, err := book.requireType(words[4], expense)
		if err != nil { return err }
		if err := checkActive(contra, costAccount); err != nil { return err }
		cost, accumulated := book.balance(acquisition, day), book.balance(contra, day)
		var amount Cents
		if cost > 0 { amount = min(cost/Cents(integer(words[5])), cost-accumulated) }
		if amount <= 0 { return fmt.Errorf("nothing to depreciate %s", acquisition.code) }
		book.depreciationCount++
		entry := book.post("DEP-"+strconv.Itoa(book.depreciationCount), day, depreciation, "depreciation",
			newLines([]Line{{true, costAccount, amount, nil}, {false, contra, amount, nil}}))
		book.emit("DEPRECIATE %s entry %s %s amount %s accumulated %s book %s", acquisition.code, entry.id, dateText(day),
			money(amount), money(accumulated+amount), money(cost-accumulated-amount))
	case "INTEREST":
		account, err := book.account(words[1])
		if err != nil { return err }
		if account.kind != asset && account.kind != liability { return fmt.Errorf("not interest bearing %s", account.code) }
		offsetType := revenue
		if account.kind == liability { offsetType = expense }
		offset, err := book.requireType(words[2], offsetType)
		if err != nil { return err }
		first, last, err := dateRange(words[3], words[4])
		if err != nil { return err }
		if err := book.checkOpen(last); err != nil { return err }
		if err := checkActive(account, offset); err != nil { return err }
		sum := book.dailySum(account, first, last)
		amount := sum * Cents(integer(words[5])) / 3650000
		if amount <= 0 { return fmt.Errorf("no interest %s", account.code) }
		debit, credit := account, offset
		if account.kind == liability { debit, credit = offset, account }
		book.interestCount++
		entry := book.post("INT-"+strconv.Itoa(book.interestCount), last, interest, "interest",
			newLines([]Line{{true, debit, amount, nil}, {false, credit, amount, nil}}))
		days := last-first+1
		book.emit("INTEREST %s entry %s %s days %d average %s amount %s", account.code, entry.id, dateText(last), days,
			money(sum/Cents(days)), money(amount))
	case "WRITEOFF":
		day, err := parseDate(words[1])
		if err != nil { return err }
		if err := book.checkOpen(day); err != nil { return err }
		account, err := book.requireType(words[2], asset)
		if err != nil { return err }
		cost, err := book.requireType(words[3], expense)
		if err != nil { return err }
		if err := checkActive(account, cost); err != nil { return err }
		age := integer(words[4])
		settlements := book.settlements(account, day)
		targets := make(map[string]Cents)
		var total Cents
		for _, partner := range sortedKeys(settlements) {
			var amount Cents
			for _, item := range settlements[partner].items { if day-item.entry.day > age { amount += item.remaining } }
			if amount > 0 { targets[partner] = amount; total += amount }
		}
		if total == 0 { return fmt.Errorf("nothing to write off %s", account.code) }
		items := []Line{{true, cost, total, nil}}
		for _, partner := range sortedKeys(targets) {
			name := partner
			items = append(items, Line{false, account, targets[partner], &name})
		}
		book.writeoffCount++
		entry := book.post("WO-"+strconv.Itoa(book.writeoffCount), day, writeoff, "writeoff", newLines(items))
		book.emit("WRITEOFF %s entry %s %s partners %d amount %s", account.code, entry.id, dateText(day), len(targets), money(total))
		for _, partner := range sortedKeys(targets) { book.emit("  %s %s", partner, money(targets[partner])) }
	case "CLOSE":
		day, err := parseDate(words[1])
		if err != nil { return err }
		if err := book.checkOpen(day); err != nil { return err }
		capital, err := book.requireType(words[2], equity)
		if err != nil { return err }
		if err := checkActive(capital); err != nil { return err }
		totals := book.totals(0, day, false)
		var targets []*Account
		for _, code := range sortedKeys(book.accounts) {
			account := book.accounts[code]
			if account.kind.temporary() && totals[account].difference() != 0 { targets = append(targets, account) }
		}
		if err := checkActive(targets...); err != nil { return err }
		var items []Line
		var income Cents
		for _, account := range targets {
			value := totals[account].difference()
			amount := value
			if amount < 0 { amount = -amount }
			items = append(items, Line{value < 0, account, amount, nil})
			income -= value
		}
		if income != 0 {
			amount := income
			if amount < 0 { amount = -amount }
			items = append(items, Line{income < 0, capital, amount, nil})
		}
		book.closeCount++
		var entry *Entry
		if len(items) > 0 { entry = book.post("CLOSE-"+strconv.Itoa(book.closeCount), day, closing, "closing", newLines(items)) }
		book.closes = append(book.closes, CloseRecord{day, entry})
		if entry == nil { book.emit("CLOSE %s no entry", dateText(day)) } else {
			book.emit("CLOSE %s entry %s lines %d net income %s", dateText(day), entry.id, len(items), money(income))
		}
	case "REOPEN":
		if len(book.closes) == 0 { return fmt.Errorf("nothing to reopen") }
		record := book.closes[len(book.closes)-1]
		detail := "no entry"
		if record.entry != nil {
			if err := activeLines(record.entry.lines); err != nil { return err }
			detail = "entry " + book.reverse(record.entry, record.day, reopen, "reopen").id
		}
		book.closes = book.closes[:len(book.closes)-1]
		book.emit("REOPEN %s %s closed %s", dateText(record.day), detail, book.closedText())
	case "LEDGER":
		account, err := book.account(words[1])
		if err != nil { return err }
		first, last, err := dateRange(words[2], words[3])
		if err != nil { return err }
		running := book.balance(account, first-1)
		var totals Totals
		book.emit("LEDGER %s %s %s %s", account.code, account.name, words[2], words[3])
		book.emit("  opening %s", money(running))
		for _, entry := range book.ordered() {
			if entry.day < first || entry.day > last { continue }
			for _, line := range entry.lines.items {
				if line.account != account { continue }
				totals.add(line.debit, line.amount)
				running += account.kind.sign()*line.difference()
				book.emit("  %s %s %s %s balance %s %s", dateText(entry.day), entry.id, line.side(), money(line.amount), money(running), entry.memo)
			}
		}
		days := last-first+1
		book.emit("  ending %s debits %s credits %s days %d average %s", money(running), money(totals.debit), money(totals.credit),
			days, money(book.dailySum(account, first, last)/Cents(days)))
	case "ACTIVITY":
		account, err := book.account(words[1])
		if err != nil { return err }
		year := integer(words[2])
		var totals Totals
		book.emit("ACTIVITY %s %s %d", account.code, account.name, year)
		for month := 1; month <= 12; month++ {
			first, last := dayNumber(year, month, 1), dayNumber(year, month, monthLength(year, month))
			current := book.accountTotals(account, first, last)
			totals.merge(current)
			book.emit("  %04d-%02d debit %s credit %s balance %s", year, month, money(current.debit), money(current.credit), money(book.balance(account, last)))
		}
		book.emit("  total debit %s credit %s", money(totals.debit), money(totals.credit))
	case "TRIAL":
		day, err := parseDate(words[1])
		if err != nil { return err }
		totals := book.totals(0, day, false)
		var grand Totals
		book.emit("TRIAL %s", words[1])
		for _, code := range sortedKeys(book.accounts) {
			value := totals[book.accounts[code]].difference()
			if value == 0 { continue }
			side, amount := "debit", value
			if value > 0 { grand.debit += value } else { side, amount = "credit", -value; grand.credit -= value }
			book.emit("  %s %s %s %s", code, book.accounts[code].name, side, money(amount))
		}
		book.emit("  total debit %s credit %s", money(grand.debit), money(grand.credit))
	case "INCOME":
		first, last, err := dateRange(words[1], words[2])
		if err != nil { return err }
		totals := book.totals(first, last, true)
		book.emit("INCOME %s %s", words[1], words[2])
		sales := book.section("REVENUE", []AccountType{revenue}, -1, totals, nil)
		cost := book.section("EXPENSE", []AccountType{expense}, 1, totals, nil)
		book.emit("  NET INCOME %s", money(sales-cost))
	case "BALANCE":
		day, err := parseDate(words[1])
		if err != nil { return err }
		totals := book.totals(0, day, false)
		var earnings Cents
		for _, code := range sortedKeys(book.accounts) {
			account := book.accounts[code]
			if account.kind.temporary() { earnings -= totals[account].difference() }
		}
		book.emit("BALANCE %s", words[1])
		assets := book.section("ASSETS", []AccountType{asset, contraAsset}, 1, totals, nil)
		liabilities := book.section("LIABILITIES", []AccountType{liability}, -1, totals, nil)
		capital := book.section("EQUITY", []AccountType{equity}, -1, totals, &earnings)
		if assets == liabilities+capital { book.emit("  check ok") } else { book.emit("  check mismatch %s", money(assets-liabilities-capital)) }
	case "ROLLUP":
		day, err := parseDate(words[2])
		if err != nil { return err }
		var targets []string
		for _, code := range sortedKeys(book.accounts) { if strings.HasPrefix(code, words[1]) { targets = append(targets, code) } }
		book.emit("ROLLUP %s %s", words[1], words[2])
		if len(targets) == 0 { book.emit("  (none)"); return nil }
		totals := book.totals(0, day, false)
		var postings Totals
		for _, code := range targets {
			account := book.accounts[code]
			depth := 0
			var subtotal Cents
			for _, other := range targets {
				if other != code && strings.HasPrefix(code, other) { depth++ }
				if strings.HasPrefix(other, code) { subtotal += totals[book.accounts[other]].difference() }
			}
			own := totals[account]
			book.emit("%s%s %s own %s total %s", strings.Repeat(" ", 2*(1+depth)), code, account.name,
				money(account.kind.sign()*own.difference()), money(account.kind.sign()*subtotal))
			postings.merge(own)
		}
		book.emit("  postings debit %s credit %s", money(postings.debit), money(postings.credit))
	case "AGING", "ITEMS":
		account, err := book.account(words[1])
		if err != nil { return err }
		aging := words[0] == "AGING"
		dateIndex := 3
		if aging { dateIndex = 2 }
		day, err := parseDate(words[dateIndex])
		if err != nil { return err }
		settlements := book.settlements(account, day)
		if aging {
			book.emit("AGING %s %s %s", account.code, account.name, words[2])
			var totals [5]Cents
			for _, partner := range sortedKeys(settlements) {
				settled := settlements[partner]
				if len(settled.items) == 0 && settled.unapplied == 0 { continue }
				values := [5]Cents{0, 0, 0, 0, settled.unapplied}
				for _, item := range settled.items {
					age, bucket := day-item.entry.day, 3
					if age <= 30 { bucket = 0 } else if age <= 60 { bucket = 1 } else if age <= 90 { bucket = 2 }
					values[bucket] += item.remaining
				}
				book.agingRow(partner, values)
				for i, amount := range values { totals[i] += amount }
			}
			book.agingRow("total", totals)
		} else {
			settled := settlements[words[2]]
			if settled == nil { settled = &Settlement{} }
			book.emit("ITEMS %s %s %s %s", account.code, account.name, words[2], words[3])
			var remaining Cents
			for _, item := range settled.items {
				book.emit("  %s %s amount %s open %s age %d", dateText(item.entry.day), item.entry.id,
					money(item.original), money(item.remaining), day-item.entry.day)
				remaining += item.remaining
			}
			book.emit("  unapplied %s balance %s", money(settled.unapplied), money(remaining-settled.unapplied))
		}
	case "ENTRY":
		entry, ok := book.entryIDs[words[1]]
		if !ok { return fmt.Errorf("unknown entry %s", words[1]) }
		book.emit("ENTRY %s %s %s %s", entry.id, dateText(entry.day), entry.category, entry.memo)
		for _, line := range entry.lines.items {
			partner := ""
			if line.partner != nil { partner = " " + *line.partner }
			book.emit("  %s %s %s %s%s", line.side(), line.account.code, line.account.name, money(line.amount), partner)
		}
		book.emit("  total %s", money(entry.lines.amount))
		if entry.reverses != nil { book.emit("  reverses %s", entry.reverses.id) }
		if entry.reversedBy != nil { book.emit("  reversed by %s", entry.reversedBy.id) }
	case "DAYBOOK":
		first, last, err := dateRange(words[1], words[2])
		if err != nil { return err }
		count := 0
		var total Cents
		book.emit("DAYBOOK %s %s", words[1], words[2])
		for _, entry := range book.ordered() {
			if entry.day < first || entry.day > last { continue }
			count++
			total += entry.lines.amount
			book.emit("  %s %s %s %s %s", dateText(entry.day), entry.id, entry.category, money(entry.lines.amount), entry.memo)
		}
		book.emit("  total entries %d amount %s", count, money(total))
	case "ACCOUNTS":
		totals := book.totals(0, lastDay, false)
		book.emit("ACCOUNTS")
		for _, code := range sortedKeys(book.accounts) {
			account := book.accounts[code]
			status := "inactive"
			if account.active { status = "active" }
			book.emit("  %s %s %s parent %s balance %s %s", code, account.kind, account.name, book.parent(code),
				money(account.kind.sign()*totals[account].difference()), status)
		}
		if len(book.accounts) == 0 { book.emit("  (none)") }
	case "TEMPLATES":
		book.emit("TEMPLATES")
		for _, name := range sortedKeys(book.templates) {
			model := book.templates[name]
			book.emit("  %s %s lines %d amount %s used %d", name, model.memo, len(model.lines.items), money(model.lines.amount), model.uses)
		}
		if len(book.templates) == 0 { book.emit("  (none)") }
	case "STATUS":
		inactive := 0
		for _, account := range book.accounts { if !account.active { inactive++ } }
		open := "none"
		if book.draft != nil { open = book.draft.key }
		book.emit("STATUS accounts %d inactive %d entries %d templates %d closed %s open %s", len(book.accounts), inactive,
			len(book.entries), len(book.templates), book.closedText(), open)
	}
	return nil
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	input.Scan()
	count := integer(input.Text())
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	book := newBook(output)
	for i := 0; i < count && input.Scan(); i++ {
		if err := book.execute(strings.Split(input.Text(), " ")); err != nil { book.emit("ERROR %s", err) }
	}
}
