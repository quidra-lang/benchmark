package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

var ratingModels = []string{"elo", "colley", "massey", "bt", "od", "winpct"}
var comparisonModels = []string{"standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"}
var linkModels = []string{"colley", "massey", "od", "winpct"}
var predictionModels = []string{"base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble"}

const standingsHeader = "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck"
const ratingsHeader = "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank"
const historyHeader = "round,team,elo,change,elo_rank,points,position"
const projectionHeader = "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position"

func sequentialSum(values []float64) float64 {
	total := 0.0
	for _, value := range values {
		total += value
	}
	return total
}
func mean(values []float64) float64 { return sequentialSum(values) / float64(len(values)) }
func csv(fields ...any) string {
	words := make([]string, len(fields))
	for i, field := range fields {
		words[i] = fmt.Sprint(field)
	}
	return strings.Join(words, ",")
}
func joinParts(parts ...[]string) []string {
	lines := []string{}
	for _, part := range parts {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, part...)
	}
	return lines
}
func indices(count int) []int {
	result := make([]int, count)
	for i := range result {
		result[i] = i
	}
	return result
}
func competitionRanks(values []Fraction) []int {
	ranks := make([]int, len(values))
	for i, value := range values {
		ranks[i] = 1
		for _, other := range values {
			if other.Cmp(value) > 0 {
				ranks[i]++
			}
		}
	}
	return ranks
}
func roundedValues(values []float64, places int) []Fraction {
	result := make([]Fraction, len(values))
	for i, value := range values {
		result[i] = fraction(decimalValue(value, places), 1)
	}
	return result
}
func integerValues(values []int, negative bool) []Fraction {
	result := make([]Fraction, len(values))
	for i, value := range values {
		if negative {
			value = -value
		}
		result[i] = fraction(int64(value), 1)
	}
	return result
}
func resultLetter(scored, conceded int) string {
	if scored > conceded {
		return "W"
	}
	if scored == conceded {
		return "D"
	}
	return "L"
}
func resultCode(result2 int) string {
	if result2 == 2 {
		return "H"
	}
	if result2 == 0 {
		return "A"
	}
	return "D"
}

type Appearance struct {
	Match                      Match
	Home                       bool
	Opponent, Scored, Conceded int
	Letter                     string
}

func appearancesOf(team int, matches []Match) []Appearance {
	result := []Appearance{}
	for _, match := range matches {
		if match.Home != team && match.Away != team {
			continue
		}
		home := match.Home == team
		opponent, scored, conceded := match.Home, match.AwayScore, match.HomeScore
		if home {
			opponent, scored, conceded = match.Away, match.HomeScore, match.AwayScore
		}
		result = append(result, Appearance{match, home, opponent, scored, conceded, resultLetter(scored, conceded)})
	}
	return result
}
func recordText(appearances []Appearance) string {
	w, d, l := 0, 0, 0
	for _, appearance := range appearances {
		switch appearance.Letter {
		case "W":
			w++
		case "D":
			d++
		default:
			l++
		}
	}
	return fmt.Sprintf("%d-%d-%d", w, d, l)
}

type Record struct{ Played, Won, Drawn, Lost, Scored, Conceded, Points int }

func (r *Record) add(scored, conceded int, settings Settings) {
	r.Played++
	r.Scored += scored
	r.Conceded += conceded
	if scored > conceded {
		r.Won++
		r.Points += settings.WinPoints
	} else if scored == conceded {
		r.Drawn++
		r.Points += settings.DrawPoints
	} else {
		r.Lost++
	}
}
func (r Record) difference() int      { return r.Scored - r.Conceded }
func (r Record) percentage() Fraction { return fraction(int64(2*r.Won+r.Drawn), int64(2*r.Played)) }
func teamRecords(count int, matches []Match, settings Settings) []Record {
	records := make([]Record, count)
	for _, match := range matches {
		records[match.Home].add(match.HomeScore, match.AwayScore, settings)
		records[match.Away].add(match.AwayScore, match.HomeScore, settings)
	}
	return records
}

type Standings struct {
	Records                                    []Record
	H2HPoints, H2HDifference, Order, Positions []int
}

func makeStandings(teams []Team, matches []Match, settings Settings) Standings {
	count := len(teams)
	table := Standings{Records: teamRecords(count, matches, settings), H2HPoints: make([]int, count), H2HDifference: make([]int, count), Order: indices(count), Positions: make([]int, count)}
	for _, match := range matches {
		i, j := match.Home, match.Away
		if table.Records[i].Points != table.Records[j].Points {
			continue
		}
		table.H2HDifference[i] += match.Margin
		table.H2HDifference[j] -= match.Margin
		if match.Margin > 0 {
			table.H2HPoints[i] += settings.WinPoints
		} else if match.Margin < 0 {
			table.H2HPoints[j] += settings.WinPoints
		} else {
			table.H2HPoints[i] += settings.DrawPoints
			table.H2HPoints[j] += settings.DrawPoints
		}
	}
	sort.Slice(table.Order, func(i, j int) bool {
		a, b := table.Order[i], table.Order[j]
		ra, rb := table.Records[a], table.Records[b]
		ak := []int{ra.Points, table.H2HPoints[a], table.H2HDifference[a], ra.difference(), ra.Scored}
		bk := []int{rb.Points, table.H2HPoints[b], table.H2HDifference[b], rb.difference(), rb.Scored}
		for k := range ak {
			if ak[k] != bk[k] {
				return ak[k] > bk[k]
			}
		}
		return teams[a].Code < teams[b].Code
	})
	for i, team := range table.Order {
		table.Positions[team] = i + 1
	}
	return table
}
func (s Standings) tiedGroups() [][]int {
	groups := [][]int{}
	for _, team := range s.Order {
		if len(groups) > 0 && s.Records[groups[len(groups)-1][0]].Points == s.Records[team].Points {
			groups[len(groups)-1] = append(groups[len(groups)-1], team)
		} else {
			groups = append(groups, []int{team})
		}
	}
	result := [][]int{}
	for _, group := range groups {
		if len(group) > 1 {
			result = append(result, group)
		}
	}
	return result
}

type Streak struct{ Length, First, Last int }

func longestStreak(appearances []Appearance, unbeaten bool) Streak {
	best := Streak{}
	start, length := 0, 0
	for i, appearance := range appearances {
		if appearance.Letter != "W" && !(unbeaten && appearance.Letter == "D") {
			length = 0
			continue
		}
		if length == 0 {
			start = i
		}
		length++
		if length > best.Length {
			best = Streak{length, appearances[start].Match.Round, appearance.Match.Round}
		}
	}
	return best
}
func currentStreak(appearances []Appearance) string {
	last := appearances[len(appearances)-1].Letter
	count := 0
	for i := len(appearances) - 1; i >= 0 && appearances[i].Letter == last; i-- {
		count++
	}
	return last + strconv.Itoa(count)
}

type ModelFit struct {
	Elo                                             EloRun
	Colley, Massey, Strengths, Offense, Defense, OD []float64
	HomeAdvantage, HomeFactor                       float64
	WinPercentages                                  []Fraction
}

func fitModels(count int, matches []Match, settings Settings) ModelFit {
	fit := ModelFit{Elo: runElo(count, matches, settings.EloK, settings.EloHome, settings.EloInitial), Colley: colleyRatings(count, matches)}
	fit.Massey, fit.HomeAdvantage = masseyRatings(count, matches)
	fit.Strengths, fit.HomeFactor = bradleyTerry(count, matches, settings.BTIterations)
	fit.Offense, fit.Defense, fit.OD = offenseDefense(count, matches, settings.ODIterations)
	for _, record := range teamRecords(count, matches, settings) {
		fit.WinPercentages = append(fit.WinPercentages, record.percentage())
	}
	return fit
}
func (f ModelFit) feature(model string, match Match) float64 {
	i, j := match.Home, match.Away
	switch model {
	case "colley":
		return f.Colley[i] - f.Colley[j]
	case "massey":
		return f.Massey[i] - f.Massey[j]
	case "od":
		return math.Log(f.OD[i]) - math.Log(f.OD[j])
	default:
		return f.WinPercentages[i].Real() - f.WinPercentages[j].Real()
	}
}
func (f ModelFit) btProbability(match Match) float64 {
	home := f.HomeFactor * f.Strengths[match.Home]
	return home / (home + f.Strengths[match.Away])
}

type Prediction struct {
	Match                         Match
	Probabilities, Losses, Briers [8]float64
	Scores2                       [8]int
	MarginError                   float64
}

func makePrediction(match Match, probabilities [8]float64, error float64) Prediction {
	prediction := Prediction{Match: match, Probabilities: probabilities, MarginError: error}
	for i, p := range probabilities {
		prediction.Losses[i] = logLoss(p, match.Result2)
		prediction.Briers[i] = brierScore(p, match.Y())
		prediction.Scores2[i] = correctness2(p, match.Result2)
	}
	return prediction
}

type ValidationRound struct {
	Number      int
	Training    []Match
	Fit         ModelFit
	Base        float64
	Links       map[string][2]float64
	Predictions []Prediction
}

func makeValidation(number, count int, matches []Match, settings Settings) ValidationRound {
	training := matchesBefore(matches, number)
	fit := fitModels(count, training, settings)
	round := ValidationRound{Number: number, Training: training, Fit: fit, Links: map[string][2]float64{}}
	y2 := 0
	results := make([]float64, len(training))
	for i, match := range training {
		y2 += match.Result2
		results[i] = match.Y()
	}
	round.Base = float64(y2) / float64(2*len(training))
	for _, model := range linkModels {
		features := make([]float64, len(training))
		for i, match := range training {
			features[i] = fit.feature(model, match)
		}
		round.Links[model] = fitLink(features, results, settings.LinkIterations)
	}
	for _, match := range matches {
		if match.Round != number {
			continue
		}
		probabilities := [8]float64{}
		probabilities[0] = round.Base
		probabilities[1] = expectedScore(fit.Elo.Ratings[match.Home], fit.Elo.Ratings[match.Away], settings.EloHome)
		probabilities[4] = fit.btProbability(match)
		for _, model := range linkModels {
			k := 0
			for i, name := range predictionModels {
				if name == model {
					k = i
				}
			}
			link := round.Links[model]
			probabilities[k] = sigma(link[0] + link[1]*fit.feature(model, match))
		}
		total := 0.0
		for _, k := range []int{1, 2, 3, 4, 5, 6} {
			total += probabilities[k]
		}
		probabilities[7] = total / 6
		margin := fit.Massey[match.Home] - fit.Massey[match.Away] + fit.HomeAdvantage
		round.Predictions = append(round.Predictions, makePrediction(match, probabilities, float64(match.Margin)-margin))
	}
	return round
}

type ModelScores struct {
	Losses, Briers, Skills                     [8]float64
	Accuracies                                 [8]Fraction
	LossRanking, BrierRanking, AccuracyRanking []int
}

func scoreModels(predictions []Prediction) ModelScores {
	scores := ModelScores{LossRanking: indices(8), BrierRanking: indices(8), AccuracyRanking: indices(8)}
	for k := 0; k < 8; k++ {
		loss, brier := 0.0, 0.0
		score2 := int64(0)
		for _, prediction := range predictions {
			loss += prediction.Losses[k]
			brier += prediction.Briers[k]
			score2 += int64(prediction.Scores2[k])
		}
		scores.Losses[k] = loss / float64(len(predictions))
		scores.Briers[k] = brier / float64(len(predictions))
		scores.Accuracies[k] = fraction(score2, int64(2*len(predictions)))
	}
	for k := 0; k < 8; k++ {
		scores.Skills[k] = 1 - scores.Briers[k]/scores.Briers[0]
	}
	sort.SliceStable(scores.LossRanking, func(i, j int) bool {
		return decimalValue(scores.Losses[scores.LossRanking[i]], 4) < decimalValue(scores.Losses[scores.LossRanking[j]], 4)
	})
	sort.SliceStable(scores.BrierRanking, func(i, j int) bool {
		return decimalValue(scores.Briers[scores.BrierRanking[i]], 4) < decimalValue(scores.Briers[scores.BrierRanking[j]], 4)
	})
	sort.SliceStable(scores.AccuracyRanking, func(i, j int) bool {
		return scores.Accuracies[scores.AccuracyRanking[i]].Cmp(scores.Accuracies[scores.AccuracyRanking[j]]) > 0
	})
	return scores
}

type Projection struct {
	Current                             Standings
	Ratings                             []float64
	Remaining                           []Match
	TotalPoints                         []int64
	Titles, Tops, Bottoms, Order, Ranks []int
}

func makeProjection(teams []Team, matches []Match, settings Settings) Projection {
	count := len(teams)
	current := matchesBefore(matches, settings.Holdout)
	projection := Projection{Current: makeStandings(teams, current, settings), Ratings: runElo(count, current, settings.EloK, settings.EloHome, settings.EloInitial).Ratings, TotalPoints: make([]int64, count), Titles: make([]int, count), Tops: make([]int, count), Bottoms: make([]int, count), Ranks: make([]int, count)}
	for _, match := range matches {
		if match.Round >= settings.Holdout {
			projection.Remaining = append(projection.Remaining, match)
		}
	}
	probabilities := make([]float64, len(projection.Remaining))
	for i, match := range projection.Remaining {
		probabilities[i] = expectedScore(projection.Ratings[match.Home], projection.Ratings[match.Away], settings.EloHome)
	}
	rankOrder := func(points []int64) []int {
		order := indices(count)
		sort.Slice(order, func(i, j int) bool {
			a, b := order[i], order[j]
			if points[a] != points[b] {
				return points[a] > points[b]
			}
			return projection.Current.Positions[a] < projection.Current.Positions[b]
		})
		return order
	}
	state := settings.Seed
	for simulation := 0; simulation < settings.Simulations; simulation++ {
		points := make([]int64, count)
		for i, record := range projection.Current.Records {
			points[i] = int64(record.Points)
		}
		for i, match := range projection.Remaining {
			state = 48271 * state % 2147483647
			if float64(state)/2147483647 < probabilities[i] {
				points[match.Home] += int64(settings.WinPoints)
			} else {
				points[match.Away] += int64(settings.WinPoints)
			}
		}
		for place, team := range rankOrder(points) {
			projection.TotalPoints[team] += points[team]
			if place == 0 {
				projection.Titles[team]++
			}
			if place < settings.Top {
				projection.Tops[team]++
			}
			if place >= count-settings.Bottom {
				projection.Bottoms[team]++
			}
		}
	}
	projection.Order = rankOrder(projection.TotalPoints)
	for i, team := range projection.Order {
		projection.Ranks[team] = i + 1
	}
	return projection
}
func (p Projection) opponentStrength(team int) float64 {
	values := []float64{}
	for _, match := range p.Remaining {
		if match.Home == team {
			values = append(values, p.Ratings[match.Away])
		} else if match.Away == team {
			values = append(values, p.Ratings[match.Home])
		}
	}
	return mean(values)
}

type LeagueAnalysis struct {
	Teams                       []Team
	Matches                     []Match
	Settings                    Settings
	Count, FinalRound           int
	Appearances                 [][]Appearance
	Final                       Standings
	Fit                         ModelFit
	RoundTables                 []Standings
	WinStreaks, UnbeatenStreaks []Streak
	SOS, SOS2, RPI              []Fraction
	Pythag, Luck                []float64
	Comparison                  map[string][]Fraction
	Ranks                       map[string][]int
	Rounds                      []ValidationRound
	Predictions                 []Prediction
	Scores                      ModelScores
	Projection                  Projection
}

func analyze(teams []Team, matches []Match, settings Settings) LeagueAnalysis {
	a := LeagueAnalysis{Teams: teams, Matches: matches, Settings: settings, Count: len(teams), FinalRound: matches[len(matches)-1].Round, Final: makeStandings(teams, matches, settings), Fit: fitModels(len(teams), matches, settings)}
	for team := range teams {
		appearances := appearancesOf(team, matches)
		a.Appearances = append(a.Appearances, appearances)
		a.WinStreaks = append(a.WinStreaks, longestStreak(appearances, false))
		a.UnbeatenStreaks = append(a.UnbeatenStreaks, longestStreak(appearances, true))
	}
	for round := 1; round <= a.FinalRound; round++ {
		a.RoundTables = append(a.RoundTables, makeStandings(teams, matchesBefore(matches, round+1), settings))
	}
	a.SOS = make([]Fraction, a.Count)
	a.SOS2 = make([]Fraction, a.Count)
	a.RPI = make([]Fraction, a.Count)
	a.Pythag = make([]float64, a.Count)
	a.Luck = make([]float64, a.Count)
	for team := range teams {
		a.SOS[team] = a.opponentAverage(team, a.Fit.WinPercentages)
	}
	for team := range teams {
		a.SOS2[team] = a.opponentAverage(team, a.SOS)
		a.RPI[team] = a.Fit.WinPercentages[team].Add(a.SOS[team].Mul(fraction(2, 1))).Add(a.SOS2[team]).Div(4)
		record := a.Final.Records[team]
		a.Pythag[team] = 1 / (1 + math.Pow(float64(record.Conceded)/float64(record.Scored), settings.Exponent))
		a.Luck[team] = a.Fit.WinPercentages[team].Real() - a.Pythag[team]
	}
	a.Comparison = map[string][]Fraction{"standings": integerValues(a.Final.Positions, true), "elo": roundedValues(a.Fit.Elo.Ratings, 2), "colley": roundedValues(a.Fit.Colley, 4), "massey": roundedValues(a.Fit.Massey, 4), "bt": roundedValues(a.Fit.Strengths, 4), "od": roundedValues(a.Fit.OD, 2), "winpct": a.Fit.WinPercentages, "rpi": a.RPI, "pythag": roundedValues(a.Pythag, 4)}
	a.Ranks = map[string][]int{}
	for _, model := range ratingModels {
		a.Ranks[model] = competitionRanks(a.Comparison[model])
	}
	for round := settings.Holdout; round <= a.FinalRound; round++ {
		validation := makeValidation(round, a.Count, matches, settings)
		a.Rounds = append(a.Rounds, validation)
		a.Predictions = append(a.Predictions, validation.Predictions...)
	}
	a.Scores = scoreModels(a.Predictions)
	a.Projection = makeProjection(teams, matches, settings)
	return a
}
func (a LeagueAnalysis) opponentAverage(team int, values []Fraction) Fraction {
	total := fraction(0, 1)
	for _, appearance := range a.Appearances[team] {
		total = total.Add(values[appearance.Opponent])
	}
	return total.Div(int64(len(a.Appearances[team])))
}
func (a LeagueAnalysis) code(team int) string { return a.Teams[team].Code }
func (a LeagueAnalysis) standingsLines() []string {
	lines := []string{standingsHeader}
	for position, team := range a.Final.Order {
		record := a.Final.Records[team]
		appearances := a.Appearances[team]
		home, away, close := []Appearance{}, []Appearance{}, []Appearance{}
		form := ""
		for i, item := range appearances {
			if item.Home {
				home = append(home, item)
			} else {
				away = append(away, item)
			}
			if math.Abs(float64(item.Scored-item.Conceded)) <= float64(a.Settings.CloseMargin) {
				close = append(close, item)
			}
			if i >= len(appearances)-a.Settings.FormLength {
				form += item.Letter
			}
		}
		lines = append(lines, csv(position+1, a.code(team), a.Teams[team].Name, record.Played, record.Won, record.Drawn, record.Lost, record.Scored, record.Conceded, record.difference(), record.Points, recordText(home), recordText(away), form, currentStreak(appearances), recordText(close), a.WinStreaks[team].Length, a.UnbeatenStreaks[team].Length, fractionText(a.Fit.WinPercentages[team]), fixedFraction(a.SOS[team], 4), fixedFraction(a.SOS2[team], 4), fixedFraction(a.RPI[team], 4), fixed(a.Pythag[team], 4), fixed(a.Luck[team], 4)))
	}
	return lines
}
func (a LeagueAnalysis) ratingsLines() []string {
	totals := make([]int, a.Count)
	for team := range totals {
		for _, model := range ratingModels {
			totals[team] += a.Ranks[model][team]
		}
	}
	order := indices(a.Count)
	sort.Slice(order, func(i, j int) bool {
		if totals[order[i]] != totals[order[j]] {
			return totals[order[i]] < totals[order[j]]
		}
		return a.code(order[i]) < a.code(order[j])
	})
	lines := []string{ratingsHeader}
	f := a.Fit
	for _, team := range order {
		best, worst := a.Count, 0
		for _, model := range ratingModels {
			rank := a.Ranks[model][team]
			if rank < best {
				best = rank
			}
			if rank > worst {
				worst = rank
			}
		}
		lines = append(lines, csv(a.code(team), fixed(f.Elo.Ratings[team], 2), a.Ranks["elo"][team], fixed(f.Colley[team], 4), a.Ranks["colley"][team], fixed(f.Massey[team], 4), a.Ranks["massey"][team], fixed(f.Strengths[team], 4), a.Ranks["bt"][team], fixed(f.Offense[team], 2), fixed(f.Defense[team], 4), fixed(f.OD[team], 2), a.Ranks["od"][team], fixedFraction(f.WinPercentages[team], 4), a.Ranks["winpct"][team], totals[team], best, worst))
	}
	return lines
}
func (a LeagueAnalysis) historyLines() []string {
	lines := []string{historyHeader}
	previous := make([]float64, a.Count)
	for i := range previous {
		previous[i] = a.Settings.EloInitial
	}
	for round, table := range a.RoundTables {
		ratings := a.Fit.Elo.Rounds[round]
		ranks := competitionRanks(roundedValues(ratings, 2))
		for team := range a.Teams {
			lines = append(lines, csv(round+1, a.code(team), fixed(ratings[team], 2), fixed(ratings[team]-previous[team], 2), ranks[team], table.Records[team].Points, table.Positions[team]))
		}
		previous = ratings
	}
	return lines
}
func (a LeagueAnalysis) summaryLines() []string {
	won, drawn, lost, y2 := 0, 0, 0, int64(0)
	for _, match := range a.Matches {
		y2 += int64(match.Result2)
		if match.Result2 == 2 {
			won++
		} else if match.Result2 == 1 {
			drawn++
		} else {
			lost++
		}
	}
	return []string{fmt.Sprintf("season teams %d matches %d rounds %d", a.Count, len(a.Matches), a.FinalRound), fmt.Sprintf("home won %d drawn %d lost %d rate %s", won, drawn, lost, fractionWithReal(fraction(y2, int64(2*len(a.Matches))))), "massey_home_advantage " + fixed(a.Fit.HomeAdvantage, 4), "bt_home_factor " + fixed(a.Fit.HomeFactor, 4)}
}
func (a LeagueAnalysis) upsetLines() []string {
	type candidate struct {
		Index          int
		Expected, Gain float64
	}
	candidates := []candidate{}
	for i, match := range a.Matches {
		if match.Margin == 0 {
			continue
		}
		expected := a.Fit.Elo.Expected[i]
		if match.Margin < 0 {
			expected = 1 - expected
		}
		candidates = append(candidates, candidate{i, expected, math.Abs(a.Fit.Elo.Changes[i])})
	}
	sort.SliceStable(candidates, func(i, j int) bool {
		return decimalValue(candidates[i].Expected, 4) < decimalValue(candidates[j].Expected, 4)
	})
	lines := []string{fmt.Sprintf("upsets top %d", a.Settings.Upsets)}
	for i, item := range candidates {
		if i >= a.Settings.Upsets {
			break
		}
		match := a.Matches[item.Index]
		winner, loser, scored, conceded, side := match.Home, match.Away, match.HomeScore, match.AwayScore, "home"
		if match.Margin < 0 {
			winner, loser, scored, conceded, side = match.Away, match.Home, match.AwayScore, match.HomeScore, "away"
		}
		lines = append(lines, fmt.Sprintf("round %d %s beat %s %d-%d %s expected %s gain %s", match.Round, a.code(winner), a.code(loser), scored, conceded, side, fixed(item.Expected, 4), fixed(item.Gain, 2)))
	}
	return lines
}
func (a LeagueAnalysis) tiebreakLines() []string {
	lines := []string{"tiebreaks"}
	for _, group := range a.Final.tiedGroups() {
		codes, points, differences := []string{}, []string{}, []string{}
		for _, team := range group {
			codes = append(codes, a.code(team))
			points = append(points, strconv.Itoa(a.Final.H2HPoints[team]))
			differences = append(differences, strconv.Itoa(a.Final.H2HDifference[team]))
		}
		lines = append(lines, fmt.Sprintf("points %d order %s h2h_points %s h2h_diff %s", a.Final.Records[group[0]].Points, strings.Join(codes, " "), strings.Join(points, " "), strings.Join(differences, " ")))
	}
	if len(lines) == 1 {
		lines = append(lines, "none")
	}
	return lines
}
func (a LeagueAnalysis) leaderLines() []string {
	lines := []string{"leaders"}
	previous, recorded := -1, 0
	for round, table := range a.RoundTables {
		leader := table.Order[0]
		if leader != previous {
			lines = append(lines, fmt.Sprintf("round %d %s points %d", round+1, a.code(leader), table.Records[leader].Points))
			recorded++
		}
		previous = leader
	}
	return append(lines, fmt.Sprintf("lead_changes %d", recorded-1))
}
func (a LeagueAnalysis) streakLines() []string {
	lines := []string{}
	for k, streaks := range [][]Streak{a.WinStreaks, a.UnbeatenStreaks} {
		longest := 0
		for _, streak := range streaks {
			if streak.Length > longest {
				longest = streak.Length
			}
		}
		label := []string{"longest_win_streak", "longest_unbeaten_streak"}[k]
		for team, streak := range streaks {
			if streak.Length == longest {
				lines = append(lines, fmt.Sprintf("%s %s length %d rounds %d-%d", label, a.code(team), streak.Length, streak.First, streak.Last))
			}
		}
	}
	return lines
}
func (a LeagueAnalysis) crosstableLines() []string {
	top := a.Final.Order[:a.Settings.Top]
	codes := []string{}
	for _, team := range top {
		codes = append(codes, a.code(team))
	}
	lines := []string{fmt.Sprintf("crosstable top %d", a.Settings.Top), "team " + strings.Join(codes, " ")}
	for _, first := range top {
		entries := []string{}
		for _, second := range top {
			if first == second {
				entries = append(entries, "-")
				continue
			}
			meetings := []Appearance{}
			for _, appearance := range a.Appearances[first] {
				if appearance.Opponent == second {
					meetings = append(meetings, appearance)
				}
			}
			entries = append(entries, recordText(meetings))
		}
		lines = append(lines, a.code(first)+" "+strings.Join(entries, " "))
	}
	return lines
}
func (a LeagueAnalysis) trajectoryLines() []string {
	lines := []string{"trajectories"}
	for team := range a.Teams {
		peak, low, best, worst := 0, 0, 0, 0
		for round := 1; round < a.FinalRound; round++ {
			ratings := a.Fit.Elo.Rounds
			if decimalValue(ratings[round][team], 2) > decimalValue(ratings[peak][team], 2) {
				peak = round
			}
			if decimalValue(ratings[round][team], 2) < decimalValue(ratings[low][team], 2) {
				low = round
			}
			if a.RoundTables[round].Positions[team] < a.RoundTables[best].Positions[team] {
				best = round
			}
			if a.RoundTables[round].Positions[team] > a.RoundTables[worst].Positions[team] {
				worst = round
			}
		}
		lines = append(lines, fmt.Sprintf("%s elo_peak %s round %d elo_low %s round %d best_position %d round %d worst_position %d round %d", a.code(team), fixed(a.Fit.Elo.Rounds[peak][team], 2), peak+1, fixed(a.Fit.Elo.Rounds[low][team], 2), low+1, a.RoundTables[best].Positions[team], best+1, a.RoundTables[worst].Positions[team], worst+1))
	}
	return lines
}
func (a LeagueAnalysis) correlationLines(title string, measure func([]Fraction, []Fraction) Fraction) []string {
	lines := []string{title, "model " + strings.Join(comparisonModels, " ")}
	for _, first := range comparisonModels {
		values := []string{}
		for _, second := range comparisonModels {
			values = append(values, fractionText(measure(a.Comparison[first], a.Comparison[second])))
		}
		lines = append(lines, first+" "+strings.Join(values, " "))
	}
	return lines
}
func (a LeagueAnalysis) similarityLines() []string {
	mostFirst, mostSecond, leastFirst, leastSecond := "", "", "", ""
	most, least := fraction(0, 1), fraction(0, 1)
	firstPair := true
	for i, first := range comparisonModels {
		for _, second := range comparisonModels[i+1:] {
			tau := kendallTau(a.Comparison[first], a.Comparison[second])
			if firstPair || tau.Cmp(most) > 0 {
				mostFirst, mostSecond, most = first, second, tau
			}
			if firstPair || tau.Cmp(least) < 0 {
				leastFirst, leastSecond, least = first, second, tau
			}
			firstPair = false
		}
	}
	return []string{"most_similar " + mostFirst + " " + mostSecond + " tau " + fractionWithReal(most), "least_similar " + leastFirst + " " + leastSecond + " tau " + fractionWithReal(least)}
}
func (a LeagueAnalysis) seasonLines() []string {
	return joinParts(a.summaryLines(), a.upsetLines(), a.tiebreakLines(), a.leaderLines(), a.streakLines(), a.crosstableLines(), a.trajectoryLines(), a.correlationLines("kendall", kendallTau), a.correlationLines("spearman", spearmanRho), a.similarityLines())
}
func (a LeagueAnalysis) predictionLines() []string {
	lines := []string{"round,home,away,home_score,away_score,result," + strings.Join(predictionModels, ",")}
	for _, prediction := range a.Predictions {
		match := prediction.Match
		fields := []any{match.Round, a.code(match.Home), a.code(match.Away), match.HomeScore, match.AwayScore, resultCode(match.Result2)}
		for _, probability := range prediction.Probabilities {
			fields = append(fields, fixed(probability, 4))
		}
		lines = append(lines, csv(fields...))
	}
	return lines
}
func (a LeagueAnalysis) linkLines() []string {
	lines := []string{"links"}
	for _, round := range a.Rounds {
		line := fmt.Sprintf("round %d train %d base %s bt_home %s", round.Number, len(round.Training), fixed(round.Base, 4), fixed(round.Fit.HomeFactor, 4))
		for _, model := range linkModels {
			link := round.Links[model]
			line += " " + model + " " + fixed(link[0], 4) + " " + fixed(link[1], 4)
		}
		lines = append(lines, line)
	}
	return lines
}
func (a LeagueAnalysis) scoreLines() []string {
	scores := a.Scores
	lines := []string{"scores", "model log_loss brier skill accuracy"}
	for i, model := range predictionModels {
		lines = append(lines, model+" "+fixed(scores.Losses[i], 4)+" "+fixed(scores.Briers[i], 4)+" "+fixed(scores.Skills[i], 4)+" "+fractionWithReal(scores.Accuracies[i]))
	}
	for i, ranking := range [][]int{scores.LossRanking, scores.BrierRanking, scores.AccuracyRanking} {
		names := []string{}
		for _, k := range ranking {
			names = append(names, predictionModels[k])
		}
		lines = append(lines, []string{"ranking_log_loss", "ranking_brier", "ranking_accuracy"}[i]+" "+strings.Join(names, " "))
	}
	return lines
}
func (a LeagueAnalysis) pairedLines() []string {
	reference := a.Scores.LossRanking[0]
	count := len(a.Predictions)
	lines := []string{"paired_log_loss reference " + predictionModels[reference]}
	for i, model := range predictionModels {
		if i == reference {
			continue
		}
		deltas := make([]float64, count)
		for k, item := range a.Predictions {
			deltas[k] = item.Losses[i] - item.Losses[reference]
		}
		average := mean(deltas)
		squares := 0.0
		for _, delta := range deltas {
			squares += (delta - average) * (delta - average)
		}
		spread := math.Sqrt(squares / float64(count-1))
		t := average / (spread / math.Sqrt(float64(count)))
		lines = append(lines, model+" mean_diff "+fixed(average, 4)+" sd "+fixed(spread, 4)+" t "+fixed(t, 2))
	}
	return lines
}
func (a LeagueAnalysis) marginLines() []string {
	absolute, squared, bias := 0.0, 0.0, 0.0
	for _, prediction := range a.Predictions {
		error := prediction.MarginError
		absolute += math.Abs(error)
		squared += error * error
		bias += error
	}
	count := float64(len(a.Predictions))
	return []string{"massey_margin mae " + fixed(absolute/count, 4) + " rmse " + fixed(math.Sqrt(squared/count), 4) + " bias " + fixed(bias/count, 4)}
}
func (a LeagueAnalysis) roundLossLines() []string {
	lines := []string{"round_log_loss", "round " + strings.Join(predictionModels, " ")}
	for _, round := range a.Rounds {
		fields := []string{strconv.Itoa(round.Number)}
		for k := 0; k < 8; k++ {
			total := 0.0
			for _, item := range round.Predictions {
				total += item.Losses[k]
			}
			fields = append(fields, fixed(total/float64(len(round.Predictions)), 4))
		}
		lines = append(lines, strings.Join(fields, " "))
	}
	return lines
}
func (a LeagueAnalysis) calibrationLines() []string {
	bins := a.Settings.Bins
	lines := []string{fmt.Sprintf("calibration bins %d", bins)}
	for k, model := range predictionModels {
		members := make([][]Prediction, bins)
		for _, prediction := range a.Predictions {
			bin := int(math.Floor(float64(bins) * prediction.Probabilities[k]))
			if bin >= bins {
				bin = bins - 1
			}
			members[bin] = append(members[bin], prediction)
		}
		for number, group := range members {
			prefix := fmt.Sprintf("%s bin %d count %d predicted ", model, number+1, len(group))
			if len(group) == 0 {
				lines = append(lines, prefix+"- observed -")
				continue
			}
			predicted, y2 := 0.0, int64(0)
			for _, item := range group {
				predicted += item.Probabilities[k]
				y2 += int64(item.Match.Result2)
			}
			lines = append(lines, prefix+fixed(predicted/float64(len(group)), 4)+" observed "+fractionText(fraction(y2, int64(2*len(group)))))
		}
	}
	return lines
}
func (a LeagueAnalysis) gridLines() []string {
	head := []string{"k"}
	for _, home := range a.Settings.GridHome {
		head = append(head, "h"+strconv.Itoa(home))
	}
	lines := []string{"elo_grid", strings.Join(head, " ")}
	bestK, bestHome := 0, 0
	bestLoss := 0.0
	for _, k := range a.Settings.GridK {
		fields := []string{strconv.Itoa(k)}
		for _, home := range a.Settings.GridHome {
			run := runElo(a.Count, a.Matches, float64(k), float64(home), a.Settings.EloInitial)
			losses := []float64{}
			for i, match := range a.Matches {
				if match.Round >= a.Settings.Holdout {
					losses = append(losses, logLoss(run.Expected[i], match.Result2))
				}
			}
			loss := mean(losses)
			fields = append(fields, fixed(loss, 4))
			if bestK == 0 || decimalValue(loss, 4) < decimalValue(bestLoss, 4) {
				bestK, bestHome, bestLoss = k, home, loss
			}
		}
		lines = append(lines, strings.Join(fields, " "))
	}
	return append(lines, fmt.Sprintf("best k %d home %d log_loss %s", bestK, bestHome, fixed(bestLoss, 4)))
}
func (a LeagueAnalysis) projectionTau() Fraction {
	return kendallTau(integerValues(a.Projection.Ranks, true), integerValues(a.Final.Positions, true))
}
func (a LeagueAnalysis) evaluationLines() []string {
	return joinParts([]string{fmt.Sprintf("holdout rounds %d-%d matches %d", a.Settings.Holdout, a.FinalRound, len(a.Predictions))}, a.linkLines(), a.scoreLines(), a.pairedLines(), a.marginLines(), a.roundLossLines(), a.calibrationLines(), a.gridLines(), []string{fmt.Sprintf("projection simulations %d kendall %s", a.Settings.Simulations, fractionWithReal(a.projectionTau()))})
}
func (a LeagueAnalysis) projectionLines() []string {
	p := a.Projection
	simulations := int64(a.Settings.Simulations)
	lines := []string{projectionHeader}
	for rank, team := range p.Order {
		lines = append(lines, csv(rank+1, a.code(team), p.Current.Records[team].Points, p.Current.Positions[team], fixed(p.opponentStrength(team), 2), fixedFraction(fraction(p.TotalPoints[team], simulations), 4), fixedFraction(fraction(int64(p.Titles[team]), simulations), 4), fixedFraction(fraction(int64(p.Tops[team]), simulations), 4), fixedFraction(fraction(int64(p.Bottoms[team]), simulations), 4), a.Final.Records[team].Points, a.Final.Positions[team]))
	}
	return lines
}
func main() {
	teams, matches, settings := loadSeason()
	analysis := analyze(teams, matches, settings)
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	files := []struct {
		Name  string
		Lines []string
	}{{"standings.csv", analysis.standingsLines()}, {"ratings.csv", analysis.ratingsLines()}, {"history.csv", analysis.historyLines()}, {"season.txt", analysis.seasonLines()}, {"predictions.csv", analysis.predictionLines()}, {"evaluation.txt", analysis.evaluationLines()}, {"projection.csv", analysis.projectionLines()}}
	for _, file := range files {
		writeLines(file.Name, file.Lines)
	}
}
