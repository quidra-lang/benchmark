package main

import (
	"fmt"
	"math/bits"
	"os"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
)

type Bidder struct {
	Name, Language  string
	Valid, Eligible []*Bid
}
type Rejection struct {
	Number        int
	Name, Message string
}
type Auction struct {
	Name            string
	Offered         int
	Bidders         []Bidder
	Valid, Eligible []*Bid
	Rejected        []Rejection
	Total           int
}

var bidForm = regexp.MustCompile(`^[a-z]+(?:\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})$`)
var ctrForm = regexp.MustCompile(`^[1-9][0-9]*/[1-9][0-9]*$`)

func reserve(items []Item, mask int) int64 {
	sum := int64(0)
	for i, item := range items {
		if mask&(1<<i) != 0 {
			sum += item.Reserve
		}
	}
	return sum
}
func validate(in Input, raw RawAuction) Auction {
	a := Auction{Name: raw.Name}
	indices := map[string]int{}
	for i, item := range in.Items {
		indices[item.Name] = i
	}
	for _, name := range raw.Offered {
		a.Offered |= 1 << indices[name]
	}
	seen := map[string]bool{}
	for _, line := range raw.Lines {
		lineError := ""
		if seen[line.Name] {
			lineError = "duplicate bidder"
		} else if line.Language != "XOR" && line.Language != "OR" {
			lineError = "bad language " + line.Language
		}
		seen[line.Name] = true
		if lineError != "" {
			for range line.Raw {
				a.Total++
				a.Rejected = append(a.Rejected, Rejection{a.Total, line.Name, lineError})
			}
			continue
		}
		k := len(a.Bidders)
		a.Bidders = append(a.Bidders, Bidder{Name: line.Name, Language: line.Language})
		bundles := map[int]int{}
		for _, text := range line.Raw {
			a.Total++
			message := ""
			mask := 0
			amount := int64(0)
			size := 0
			if !bidForm.MatchString(text) {
				message = "malformed bid"
			} else {
				v := strings.Split(text, ":")
				amount = integer(v[1])
				names := strings.Split(v[0], "+")
				size = len(names)
				for _, name := range names {
					i, ok := indices[name]
					if !ok {
						message = "unknown item " + name
						break
					}
					if a.Offered&(1<<i) == 0 {
						message = "item not offered " + name
						break
					}
					if mask&(1<<i) != 0 {
						message = "duplicate item " + name
						break
					}
					mask |= 1 << i
				}
				if message == "" {
					switch {
					case int64(size) > in.Parameters["max_bundle_size"]:
						message = "bundle too large"
					case amount == 0:
						message = "zero value"
					case bundles[mask] > 0:
						message = fmt.Sprintf("duplicate bundle %d", bundles[mask])
					case int64(len(a.Bidders[k].Valid)) >= in.Parameters["max_bids_per_bidder"]:
						message = "too many bids"
					}
				}
			}
			if message != "" {
				a.Rejected = append(a.Rejected, Rejection{a.Total, line.Name, message})
				continue
			}
			b := &Bid{a.Total, k, mask, size, amount, reserve(in.Items, mask), line.Language == "XOR"}
			bundles[mask] = b.Number
			a.Valid = append(a.Valid, b)
			a.Bidders[k].Valid = append(a.Bidders[k].Valid, b)
			if amount >= b.Reserve {
				a.Eligible = append(a.Eligible, b)
				a.Bidders[k].Eligible = append(a.Bidders[k].Eligible, b)
			}
		}
	}
	return a
}
func allocation(items []Item, offered int, bids []*Bid) (int64, int64, int) {
	accepted, used := int64(0), 0
	for _, b := range bids {
		accepted += b.Amount
		used |= b.Mask
	}
	unsold := offered &^ used
	return accepted, reserve(items, unsold), unsold
}
func sortedBids(bids []*Bid) []*Bid {
	out := slices.Clone(bids)
	sort.Slice(out, func(i, j int) bool { return out[i].Number < out[j].Number })
	return out
}
func unsoldText(items []Item, mask int) string {
	return strings.ReplaceAll(bundle(items, mask), "+", " ")
}
func wdpLines(in Input, a Auction, r *SearchResult, order, greedy []*Bid, critical map[int]Critical) []string {
	out := []string{fmt.Sprintf("AUCTION %s items %d bidders %d bids %d valid %d eligible %d", a.Name, bits.OnesCount(uint(a.Offered)), len(a.Bidders), a.Total, len(a.Valid), len(a.Eligible))}
	for _, b := range a.Bidders {
		out = append(out, fmt.Sprintf("BIDDER %s %s valid %d eligible %d", b.Name, b.Language, len(b.Valid), len(b.Eligible)))
	}
	for _, e := range a.Rejected {
		out = append(out, fmt.Sprintf("REJECT %d %s %s", e.Number, e.Name, e.Message))
	}
	for _, b := range a.Valid {
		if b.Amount < b.Reserve {
			out = append(out, fmt.Sprintf("BELOW_RESERVE %d %s value %d reserve %d", b.Number, a.Bidders[b.Bidder].Name, b.Amount, b.Reserve))
		}
	}
	for i, item := range in.Items {
		if a.Offered&(1<<i) == 0 {
			continue
		}
		source := "reserve"
		if r.Sources[i] > 0 {
			source = fmt.Sprintf("bid %d", r.Sources[i])
		}
		out = append(out, fmt.Sprintf("SHARE %s %s %s", item.Name, r.Shares[i], source))
	}
	out = append(out, "ROOT_BOUND "+r.Bound.String())
	for _, record := range r.Records {
		out = append(out, fmt.Sprintf("IMPROVE %d welfare %d bids %s", record.Node, record.Welfare, numberList(record.Bids)))
	}
	accepted, retained, unsold := allocation(in.Items, a.Offered, r.Bids)
	out = append(out, fmt.Sprintf("OPTIMAL welfare %d accepted %d retained %d winners %d", r.Welfare, accepted, retained, len(r.Bids)))
	for _, b := range r.Bids {
		out = append(out, fmt.Sprintf("WIN %d %s %s %d", b.Number, a.Bidders[b.Bidder].Name, bundle(in.Items, b.Mask), b.Amount))
	}
	out = append(out, "UNSOLD "+unsoldText(in.Items, unsold), fmt.Sprintf("SEARCH nodes %d pruned %d leaves %d improvements %d", r.Nodes, r.Pruned, r.Leaves, r.Improvements))
	orderText := "-"
	if len(order) > 0 {
		names := []string{}
		for _, b := range order {
			names = append(names, strconv.Itoa(b.Number))
		}
		orderText = strings.Join(names, " ")
	}
	out = append(out, "GREEDY_ORDER "+orderText)
	ga, gr, gu := allocation(in.Items, a.Offered, greedy)
	out = append(out, fmt.Sprintf("GREEDY welfare %d accepted %d retained %d winners %d efficiency %s", ga+gr, ga, gr, len(greedy), fraction(ga+gr, r.Welfare)))
	for _, b := range sortedBids(greedy) {
		c := critical[b.Number]
		against := "-"
		if c.Rival > 0 {
			against = strconv.Itoa(c.Rival)
		}
		out = append(out, fmt.Sprintf("GWIN %d %s %s %d critical %d against %s", b.Number, a.Bidders[b.Bidder].Name, bundle(in.Items, b.Mask), b.Amount, c.Payment, against))
	}
	out = append(out, "GUNSOLD "+unsoldText(in.Items, gu))
	for i, item := range in.Items {
		if a.Offered&(1<<i) == 0 {
			continue
		}
		demand := 0
		optimalName, greedyName := "-", "-"
		for _, b := range a.Eligible {
			if b.Mask&(1<<i) != 0 {
				demand++
			}
		}
		for _, b := range r.Bids {
			if b.Mask&(1<<i) != 0 {
				optimalName = a.Bidders[b.Bidder].Name
			}
		}
		for _, b := range greedy {
			if b.Mask&(1<<i) != 0 {
				greedyName = a.Bidders[b.Bidder].Name
			}
		}
		out = append(out, fmt.Sprintf("ITEM %s reserve %d demand %d optimal %s greedy %s", item.Name, item.Reserve, demand, optimalName, greedyName))
	}
	return out
}

type AscendingResult struct {
	Lines                                []string
	Payment, Value, Utility              []int64
	Revenue, Welfare, Retained, Exposure int64
	Exposed, Rounds                      int
	Reason                               string
}

func ascending(in Input, a Auction, optimum int64) *AscendingResult {
	n, m := len(a.Bidders), len(in.Items)
	result := &AscendingResult{Payment: make([]int64, n), Value: make([]int64, n), Utility: make([]int64, n)}
	candidatesByBidder := make([][]Candidate, n)
	eligibility := make([]int, n)
	prices := make([]int64, m)
	holder := make([]int, m)
	bidCounts, roundCounts, lastRound := make([]int, m), make([]int, m), make([]int, m)
	for j, item := range in.Items {
		prices[j] = item.Reserve
		holder[j] = -1
	}
	for k, b := range a.Bidders {
		candidatesByBidder[k] = candidates(b.Valid, b.Language == "XOR")
		for _, c := range candidatesByBidder[k] {
			eligibility[k] = max(eligibility[k], bits.OnesCount(uint(c.Mask)))
		}
	}
	increment := in.Parameters["saa_increment"]
	state := in.Parameters["seed"]
	result.Lines = append(result.Lines, fmt.Sprintf("AUCTION %s increment %d", a.Name, increment))
	for round := 1; ; round++ {
		newBids := make([]int, n)
		activity := make([]int, n)
		demand := 0
		for k := range a.Bidders {
			held := 0
			for j, h := range holder {
				if h == k {
					held |= 1 << j
				}
			}
			chosen := 0
			best := int64(0)
			for _, c := range candidatesByBidder[k] {
				if bits.OnesCount(uint(c.Mask|held)) > eligibility[k] {
					continue
				}
				cost := int64(0)
				for j := range in.Items {
					if c.Mask&(1<<j) != 0 {
						cost += prices[j]
						if holder[j] >= 0 && holder[j] != k {
							cost += increment
						}
					}
				}
				surplus := c.Value - cost
				if surplus > best {
					best = surplus
					chosen = c.Mask
				}
			}
			activity[k] = bits.OnesCount(uint(chosen | held))
			newBids[k] = chosen &^ held
			demand += bits.OnesCount(uint(newBids[k]))
		}
		if demand == 0 {
			result.Lines = append(result.Lines, fmt.Sprintf("ROUND %d none", round))
		} else {
			line := fmt.Sprintf("ROUND %d demand %d", round, demand)
			for k, mask := range newBids {
				if mask != 0 {
					line += " " + a.Bidders[k].Name + ":" + bundle(in.Items, mask)
				}
			}
			result.Lines = append(result.Lines, line)
			for j := range in.Items {
				if a.Offered&(1<<j) == 0 {
					continue
				}
				bidders := []int{}
				for k, mask := range newBids {
					if mask&(1<<j) != 0 {
						bidders = append(bidders, k)
					}
				}
				if len(bidders) == 0 {
					continue
				}
				bidCounts[j] += len(bidders)
				roundCounts[j]++
				lastRound[j] = round
				q := 0
				if len(bidders) > 1 {
					state = 48271 * state % 2147483647
					q = int(state % int64(len(bidders)))
				}
				if holder[j] >= 0 {
					prices[j] += increment
				}
				holder[j] = bidders[q]
			}
			line = "STANDING"
			for j, item := range in.Items {
				if a.Offered&(1<<j) == 0 {
					continue
				}
				name := "-"
				if holder[j] >= 0 {
					name = a.Bidders[holder[j]].Name
				}
				line += fmt.Sprintf(" %s=%d@%s", item.Name, prices[j], name)
			}
			result.Lines = append(result.Lines, line)
		}
		changes := ""
		for k := range a.Bidders {
			if activity[k] < eligibility[k] {
				eligibility[k] = activity[k]
				changes += fmt.Sprintf(" %s=%d", a.Bidders[k].Name, eligibility[k])
			}
		}
		if changes != "" {
			result.Lines = append(result.Lines, "ELIGIBILITY"+changes)
		}
		if demand == 0 || int64(round) == in.Parameters["round_cap"] {
			result.Rounds = round
			result.Reason = "cap"
			if demand == 0 {
				result.Reason = "quiet"
			}
			break
		}
	}
	result.Lines = append(result.Lines, fmt.Sprintf("END rounds %d %s", result.Rounds, result.Reason))
	won := make([]int, n)
	for j, item := range in.Items {
		if a.Offered&(1<<j) == 0 {
			continue
		}
		if holder[j] < 0 {
			result.Retained += item.Reserve
			result.Lines = append(result.Lines, fmt.Sprintf("ITEM %s unsold reserve %d", item.Name, item.Reserve))
		} else {
			k := holder[j]
			won[k] |= 1 << j
			result.Payment[k] += prices[j]
			result.Revenue += prices[j]
			result.Lines = append(result.Lines, fmt.Sprintf("ITEM %s price %d holder %s bids %d rounds %d last %d", item.Name, prices[j], a.Bidders[k].Name, bidCounts[j], roundCounts[j], lastRound[j]))
		}
	}
	result.Welfare = result.Retained
	for k, b := range a.Bidders {
		result.Value[k] = candidateValue(candidatesByBidder[k], won[k])
		result.Utility[k] = result.Value[k] - result.Payment[k]
		result.Welfare += result.Value[k]
		text := fmt.Sprintf("BIDDER %s won %s paid %d value %d utility %d eligibility %d", b.Name, bundle(in.Items, won[k]), result.Payment[k], result.Value[k], result.Utility[k], eligibility[k])
		if result.Utility[k] < 0 {
			result.Exposed++
			result.Exposure -= result.Utility[k]
			text += " exposed"
		}
		result.Lines = append(result.Lines, text)
	}
	result.Lines = append(result.Lines, fmt.Sprintf("TOTAL revenue %d welfare %d efficiency %s exposure %d exposed %d", result.Revenue, result.Welfare, fraction(result.Welfare, optimum), result.Exposure, result.Exposed))
	return result
}

type Laboratory struct {
	Input                                                                           Input
	WDP, VCG, Core, Ascending, Single, Summary                                      []string
	BidTotal, ValidTotal, EligibleTotal, NodeTotal, GreedyOptimal, Checked, Skipped int
	CoreCounts                                                                      [4]int
	RevenueTotals                                                                   [5]int64
	RoundTotal, Capped, Exposed                                                     int
	Exposure                                                                        int64
	Lots, SlotGroups, Errors, EnvyFree, Nash, Equilibria                            int
}

func (l *Laboratory) SummaryRow(name, format string, revenue, welfare, efficiency Fraction) {
	l.Summary = append(l.Summary, fmt.Sprintf("%s/%s,%s,%s,%s", name, format, revenue, welfare, efficiency))
}
func coalitionName(a Auction, c Coalition) string {
	names := []string{}
	for _, k := range c.Members {
		names = append(names, a.Bidders[k].Name)
	}
	if len(names) == 0 {
		return "-"
	}
	return strings.Join(names, "+")
}
func int64Texts(a []int64) string {
	out := make([]string, len(a))
	for i, n := range a {
		out[i] = strconv.FormatInt(n, 10)
	}
	return strings.Join(out, " ")
}
func (l *Laboratory) ProcessAuction(a Auction) {
	in := l.Input
	opt := solveWDP(in.Items, a.Offered, a.Eligible)
	order := greedyOrder(a.Eligible)
	greedy := greedySelect(order, 0)
	critical := criticalPayments(order, greedy)
	vcg := vcgPayments(in.Items, a.Offered, len(a.Bidders), a.Eligible, opt.Bids, opt.Welfare)
	saa := ascending(in, a, opt.Welfare)
	accepted, retained, _ := allocation(in.Items, a.Offered, opt.Bids)
	ga, gr, _ := allocation(in.Items, a.Offered, greedy)
	gw := ga + gr
	n := len(a.Bidders)
	vcgPay, vcgUtility, greedyPay, critPay, critUtility := make([]int64, n), make([]int64, n), make([]int64, n), make([]int64, n), make([]int64, n)
	vcgRevenue, critRevenue, utilitySum := int64(0), int64(0), int64(0)
	for k, v := range vcg {
		vcgPay[k] = v.Payment
		vcgUtility[k] = v.Utility
		vcgRevenue += v.Payment
		utilitySum += v.Utility
	}
	for _, b := range greedy {
		greedyPay[b.Bidder] += b.Amount
		critPay[b.Bidder] += critical[b.Number].Payment
		critUtility[b.Bidder] += b.Amount - critical[b.Number].Payment
		critRevenue += critical[b.Number].Payment
	}
	l.WDP = append(l.WDP, wdpLines(in, a, opt, order, greedy, critical)...)
	l.BidTotal += a.Total
	l.ValidTotal += len(a.Valid)
	l.EligibleTotal += len(a.Eligible)
	l.NodeTotal += opt.Nodes
	if gw == opt.Welfare {
		l.GreedyOptimal++
	}
	l.VCG = append(l.VCG, fmt.Sprintf("AUCTION %s welfare %d", a.Name, opt.Welfare))
	for k, b := range a.Bidders {
		v := vcg[k]
		if len(v.Won) == 0 {
			l.VCG = append(l.VCG, "BIDDER "+b.Name+" lost")
		} else {
			l.VCG = append(l.VCG, fmt.Sprintf("BIDDER %s won %s value %d without %d alternative %s payment %d utility %d", b.Name, numberList(v.Won), v.Value, v.Without, numberList(v.Alternative), v.Payment, v.Utility))
		}
	}
	l.VCG = append(l.VCG, fmt.Sprintf("TOTAL revenue %d pay_as_bid %d retained %d seller %d bidders %d", vcgRevenue, accepted, retained, vcgRevenue+retained, utilitySum))
	for k, b := range a.Bidders {
		l.VCG = append(l.VCG, fmt.Sprintf("PAYMENTS %s vcg %d pay_as_bid %d greedy %d critical %d saa %d", b.Name, vcgPay[k], vcg[k].Value, greedyPay[k], critPay[k], saa.Payment[k]))
	}
	for k, b := range a.Bidders {
		l.VCG = append(l.VCG, fmt.Sprintf("UTILITIES %s vcg %d critical %d saa %d", b.Name, vcgUtility[k], critUtility[k], saa.Utility[k]))
	}
	l.Core = append(l.Core, fmt.Sprintf("AUCTION %s bidders %d", a.Name, n))
	if int64(n) > in.Parameters["core_max_bidders"] {
		l.Skipped++
		l.Core = append(l.Core, "SKIPPED")
	} else {
		l.Checked++
		cs := coalitions(in.Items, a.Offered, n, a.Eligible)
		l.Core = append(l.Core, fmt.Sprintf("COALITIONS %d", len(cs)))
		names := []string{"vcg", "greedy", "critical", "saa"}
		sellers := []int64{vcgRevenue + retained, gw, critRevenue + gr, saa.Revenue + saa.Retained}
		utilities := [][]int64{vcgUtility, make([]int64, n), critUtility, saa.Utility}
		for i, name := range names {
			l.Core = append(l.Core, fmt.Sprintf("OUTCOME %s seller %d utilities %s", name, sellers[i], int64Texts(utilities[i])))
			blocked := blockers(cs, sellers[i], utilities[i])
			minimal := 0
			for _, b := range blocked {
				if b.Minimal {
					minimal++
					l.Core = append(l.Core, fmt.Sprintf("BLOCK %s welfare %d payoff %d deficit %d bids %s", coalitionName(a, b.Coalition), b.Coalition.Welfare, b.Payoff, b.Deficit, numberList(b.Coalition.Bids)))
				}
			}
			if len(blocked) == 0 {
				l.CoreCounts[i]++
				l.Core = append(l.Core, "RESULT core")
			} else {
				best := blocked[0]
				for _, b := range blocked[1:] {
					if b.Deficit > best.Deficit {
						best = b
					}
				}
				l.Core = append(l.Core, fmt.Sprintf("RESULT blocked %d minimal %d max_deficit %d by %s", len(blocked), minimal, best.Deficit, coalitionName(a, best.Coalition)))
			}
		}
	}
	l.Ascending = append(l.Ascending, saa.Lines...)
	l.RoundTotal += saa.Rounds
	if saa.Reason == "cap" {
		l.Capped++
	}
	l.Exposed += saa.Exposed
	l.Exposure += saa.Exposure
	revenues := []int64{vcgRevenue, accepted, ga, critRevenue, saa.Revenue}
	welfares := []int64{opt.Welfare, opt.Welfare, gw, gw, saa.Welfare}
	for i, name := range []string{"vcg", "pay_as_bid", "greedy", "critical", "saa"} {
		l.RevenueTotals[i] += revenues[i]
		l.SummaryRow(a.Name, name, whole(revenues[i]), whole(welfares[i]), fraction(welfares[i], opt.Welfare))
	}
}

type LotResult struct {
	Winner, Steps           int
	Price, Revenue, Welfare int64
	Utilities               []int64
}

func lotError(g Group) string {
	if len(g.Participants) == 0 {
		return "no bidders"
	}
	seen := map[string]bool{}
	for _, p := range g.Participants {
		if seen[p.Name] {
			return "duplicate bidder " + p.Name
		}
		seen[p.Name] = true
	}
	for _, p := range g.Participants {
		if p.Bid > p.Value {
			return "bid above value " + p.Name
		}
	}
	return ""
}
func (l *Laboratory) ProcessLot(g Group) {
	l.Lots++
	if message := lotError(g); message != "" {
		l.Errors++
		l.Single = append(l.Single, "LOT "+g.Name+" ERROR "+message)
		return
	}
	participants := g.Participants
	n := len(participants)
	reserve := integer(g.Arguments[0])
	efficient := 0
	for i, p := range participants {
		if p.Value > participants[efficient].Value {
			efficient = i
		}
	}
	optimum := max(reserve, participants[efficient].Value)
	efficientName := "-"
	if participants[efficient].Value >= reserve {
		efficientName = participants[efficient].Name
	}
	l.Single = append(l.Single, fmt.Sprintf("LOT %s reserve %d bidders %d efficient %s optimum %d", g.Name, reserve, n, efficientName, optimum))
	first := -1
	for i, p := range participants {
		if p.Bid >= reserve && (first < 0 || p.Bid > participants[first].Bid) {
			first = i
		}
	}
	second := -1
	secondPrice := reserve
	if participants[efficient].Value >= reserve {
		second = efficient
		for i, p := range participants {
			if i != second && p.Value >= reserve {
				secondPrice = max(secondPrice, p.Value)
			}
		}
	}
	eng := english(participants, reserve, l.Input.Parameters["english_increment"])
	dut := dutch(participants, reserve, l.Input.Parameters["dutch_start"], l.Input.Parameters["dutch_decrement"])
	winner := []int{first, second, eng.Winner, dut.Winner, first}
	firstPrice := int64(0)
	if first >= 0 {
		firstPrice = participants[first].Bid
	}
	prices := []int64{firstPrice, secondPrice, eng.Price, dut.Price, firstPrice}
	results := make([]LotResult, 5)
	labels := []string{"FIRST_PRICE", "SECOND_PRICE", "ENGLISH", "DUTCH", "ALL_PAY"}
	formats := []string{"first_price", "second_price", "english", "dutch", "all_pay"}
	for j := 0; j < 5; j++ {
		r := LotResult{Winner: winner[j], Price: prices[j], Welfare: reserve, Utilities: make([]int64, n)}
		if j == 2 {
			r.Steps = eng.Steps
		}
		if j == 3 {
			r.Steps = dut.Steps
		}
		if r.Winner >= 0 {
			r.Revenue = r.Price
			r.Welfare = participants[r.Winner].Value
			r.Utilities[r.Winner] = r.Welfare - r.Price
		}
		if j == 4 {
			r.Revenue = 0
			for i, p := range participants {
				if p.Bid >= reserve {
					r.Revenue += p.Bid
					if i != r.Winner {
						r.Utilities[i] = -p.Bid
					}
				}
			}
		}
		text := labels[j]
		if r.Winner >= 0 {
			text += fmt.Sprintf(" winner %s price %d utility %d", participants[r.Winner].Name, r.Price, r.Utilities[r.Winner])
		} else {
			text += " unsold"
		}
		if j == 2 || j == 3 {
			text += fmt.Sprintf(" steps %d", r.Steps)
		}
		text += fmt.Sprintf(" revenue %d welfare %d efficiency %s", r.Revenue, r.Welfare, fraction(r.Welfare, optimum))
		l.Single = append(l.Single, text)
		if j == 2 {
			line := "ENGLISH_DROPS"
			for i, p := range participants {
				drop := "-"
				if eng.Drops[i] >= 0 {
					drop = strconv.FormatInt(eng.Drops[i], 10)
				}
				line += " " + p.Name + "=" + drop
			}
			l.Single = append(l.Single, line)
		}
		l.SummaryRow(g.Name, formats[j], whole(r.Revenue), whole(r.Welfare), fraction(r.Welfare, optimum))
		results[j] = r
	}
	for i, p := range participants {
		values := make([]int64, 5)
		for j, r := range results {
			values[j] = r.Utilities[i]
		}
		l.Single = append(l.Single, "UTILITY "+p.Name+" "+int64Texts(values))
	}
	ranking := []int{0, 1, 2, 3, 4}
	sort.Slice(ranking, func(i, j int) bool {
		a, b := ranking[i], ranking[j]
		if results[a].Revenue != results[b].Revenue {
			return results[a].Revenue > results[b].Revenue
		}
		return a < b
	})
	names := make([]string, 5)
	for i, j := range ranking {
		names[i] = formats[j]
	}
	l.Single = append(l.Single, "RANKING "+strings.Join(names, " "))
}

func slotValidation(g Group) ([]Fraction, string) {
	ctr := []Fraction{}
	for _, text := range g.Arguments {
		if !ctrForm.MatchString(text) {
			return nil, "bad ctr " + text
		}
		a := strings.Split(text, "/")
		value := fraction(integer(a[0]), integer(a[1]))
		if value.Cmp(whole(1)) > 0 || (len(ctr) > 0 && value.Cmp(ctr[len(ctr)-1]) >= 0) {
			return nil, "bad ctr " + text
		}
		ctr = append(ctr, value)
	}
	if len(g.Participants) == 0 {
		return nil, "no advertisers"
	}
	seen := map[string]bool{}
	for _, p := range g.Participants {
		if seen[p.Name] {
			return nil, "duplicate advertiser " + p.Name
		}
		seen[p.Name] = true
	}
	return ctr, ""
}
func (l *Laboratory) ProcessSlots(g Group) {
	l.SlotGroups++
	ctr, message := slotValidation(g)
	if message != "" {
		l.Errors++
		l.Single = append(l.Single, "SLOTS "+g.Name+" ERROR "+message)
		return
	}
	participants := g.Participants
	n, k := len(participants), len(ctr)
	gsp, vcg := make([]int, n), make([]int, n)
	for i := 0; i < n; i++ {
		gsp[i] = i
		vcg[i] = i
	}
	sort.Slice(gsp, func(i, j int) bool {
		a, b := gsp[i], gsp[j]
		if participants[a].Bid != participants[b].Bid {
			return participants[a].Bid > participants[b].Bid
		}
		return a < b
	})
	sort.Slice(vcg, func(i, j int) bool {
		a, b := vcg[i], vcg[j]
		if participants[a].Value != participants[b].Value {
			return participants[a].Value > participants[b].Value
		}
		return a < b
	})
	rate := func(rank int) Fraction {
		if rank >= k {
			return whole(0)
		}
		return ctr[rank]
	}
	bid := func(rank int) int64 {
		if rank >= n {
			return 0
		}
		return participants[gsp[rank]].Bid
	}
	l.Single = append(l.Single, fmt.Sprintf("SLOTS %s slots %d advertisers %d", g.Name, k, n))
	gspRevenue, gspWelfare, vcgRevenue, optimum := whole(0), whole(0), whole(0), whole(0)
	for s := 0; s < min(n, k); s++ {
		p := participants[gsp[s]]
		price := gspPrice(participants, gsp, s)
		payment := ctr[s].Mul(whole(price))
		utility := ctr[s].Mul(whole(p.Value - price))
		gspRevenue = gspRevenue.Add(payment)
		gspWelfare = gspWelfare.Add(ctr[s].Mul(whole(p.Value)))
		optimum = optimum.Add(ctr[s].Mul(whole(participants[vcg[s]].Value)))
		l.Single = append(l.Single, fmt.Sprintf("GSP %d %s ctr %s bid %d price %d payment %s utility %s", s+1, p.Name, ctr[s], p.Bid, price, payment, utility))
	}
	l.Single = append(l.Single, fmt.Sprintf("GSP_TOTAL revenue %s welfare %s efficiency %s", gspRevenue, gspWelfare, gspWelfare.Div(optimum)))
	for s := 0; s < min(n, k); s++ {
		p := participants[vcg[s]]
		payment := slotVCG(participants, vcg, ctr, s)
		utility := ctr[s].Mul(whole(p.Value)).Sub(payment)
		vcgRevenue = vcgRevenue.Add(payment)
		l.Single = append(l.Single, fmt.Sprintf("VCG %d %s ctr %s value %d payment %s price %s utility %s", s+1, p.Name, ctr[s], p.Value, payment, payment.Div(ctr[s]), utility))
	}
	l.Single = append(l.Single, fmt.Sprintf("VCG_TOTAL revenue %s welfare %s efficiency 1", vcgRevenue, optimum))
	violations := 0
	for s := 1; s < min(n, k+1); s++ {
		p := participants[gsp[s]]
		stay := rate(s).Mul(whole(p.Value - bid(s+1)))
		swap := rate(s - 1).Mul(whole(p.Value - bid(s)))
		judgment := "ok"
		if stay.Cmp(swap) < 0 {
			judgment = "violated"
			violations++
		}
		l.Single = append(l.Single, fmt.Sprintf("ENVY %d %s stay %s swap %s %s", s+1, p.Name, stay, swap, judgment))
	}
	if violations == 0 {
		l.EnvyFree++
		l.Single = append(l.Single, "ENVY_FREE yes")
	} else {
		l.Single = append(l.Single, fmt.Sprintf("ENVY_FREE no violations %d", violations))
	}
	deviations := 0
	for s := 0; s < n; s++ {
		p := participants[gsp[s]]
		current := rate(s).Mul(whole(p.Value - bid(s+1)))
		for t := 0; t < k; t++ {
			if t == s {
				continue
			}
			price := bid(t + 1)
			if t < s {
				price = bid(t)
			}
			payoff := rate(t).Mul(whole(p.Value - price))
			if payoff.Cmp(current) > 0 {
				deviations++
				l.Single = append(l.Single, fmt.Sprintf("DEVIATE %s from %d to %d gain %s", p.Name, s+1, t+1, payoff.Sub(current)))
			}
		}
	}
	if deviations == 0 {
		l.Nash++
		l.Single = append(l.Single, "NASH yes")
	} else {
		l.Single = append(l.Single, fmt.Sprintf("NASH no deviations %d", deviations))
	}
	if deviations == 0 && violations == 0 {
		l.Equilibria++
		l.Single = append(l.Single, "EQUILIBRIUM yes")
	} else {
		l.Single = append(l.Single, "EQUILIBRIUM no")
	}
	l.SummaryRow(g.Name, "gsp", gspRevenue, gspWelfare, gspWelfare.Div(optimum))
	l.SummaryRow(g.Name, "vcg", vcgRevenue, optimum, whole(1))
}
func main() {
	in := readInput()
	l := &Laboratory{Input: in, Summary: []string{"mechanism,revenue,welfare,efficiency"}}
	for _, name := range in.Runs {
		l.ProcessAuction(validate(in, in.Auctions[name]))
	}
	for _, g := range in.Groups {
		if g.Kind == "lot" {
			l.ProcessLot(g)
		} else {
			l.ProcessSlots(g)
		}
	}
	l.WDP = append(l.WDP, fmt.Sprintf("TOTAL auctions %d bids %d valid %d eligible %d nodes %d greedy_optimal %d", len(in.Runs), l.BidTotal, l.ValidTotal, l.EligibleTotal, l.NodeTotal, l.GreedyOptimal))
	l.VCG = append(l.VCG, fmt.Sprintf("OVERALL vcg %d pay_as_bid %d greedy %d critical %d saa %d", l.RevenueTotals[0], l.RevenueTotals[1], l.RevenueTotals[2], l.RevenueTotals[3], l.RevenueTotals[4]))
	l.Core = append(l.Core, fmt.Sprintf("SUMMARY checked %d skipped %d vcg %d greedy %d critical %d saa %d", l.Checked, l.Skipped, l.CoreCounts[0], l.CoreCounts[1], l.CoreCounts[2], l.CoreCounts[3]))
	l.Ascending = append(l.Ascending, fmt.Sprintf("SUMMARY auctions %d rounds %d capped %d exposed %d exposure %d", len(in.Runs), l.RoundTotal, l.Capped, l.Exposed, l.Exposure))
	l.Single = append(l.Single, fmt.Sprintf("SUMMARY lots %d slot_groups %d errors %d envy_free %d nash %d equilibria %d", l.Lots, l.SlotGroups, l.Errors, l.EnvyFree, l.Nash, l.Equilibria))
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("wdp.txt", l.WDP)
	writeLines("vcg.txt", l.VCG)
	writeLines("core_check.txt", l.Core)
	writeLines("ascending_log.txt", l.Ascending)
	writeLines("single_item.txt", l.Single)
	writeLines("summary.csv", l.Summary)
}
