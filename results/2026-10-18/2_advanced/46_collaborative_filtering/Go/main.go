package main

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

var methods = []string{"GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"}
var rankings = []string{"POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"}

type Prediction struct {
	Value      float64
	Fallback   bool
	Neighbors  int
	Similarity float64
	Top        int
}
type Metric struct {
	RMSE, MAE         float64
	Clipped, Fallback int
}
type Recommender struct {
	Data               *Ratings
	Neighborhood       Neighborhood
	UserBias, ItemBias []float64
	Popularity         []int
	Popular            []bool
	Head               int
	SVD, ALS           FactorModel
	Log                []TrainingRecord
	TrainErrors        map[int]float64
	Predictions        [][]Prediction
	Clipped, Errors    [][]float64
	Metrics            []Metric
	Relevant           map[int]map[int]bool
	Evaluated          []int
	Rankings           map[int][][]int
	RankingPredictions map[int][]map[int]Prediction
}

func newRecommender(d *Ratings) *Recommender {
	r := &Recommender{Data: d, Neighborhood: newNeighborhood(d, d.Params.Shrinkage), UserBias: make([]float64,
		len(d.Users)), ItemBias: make([]float64, len(d.Items)), Popular: make([]bool, len(d.Items)),
		Head: len(d.Items) / 5, TrainErrors: map[int]float64{}, Predictions: make([][]Prediction,
			7), Clipped: make([][]float64, 7), Errors: make([][]float64, 7), Metrics: make([]Metric,
			7), Relevant: map[int]map[int]bool{}, Rankings: map[int][][]int{}, RankingPredictions: map[int][]map[int]Prediction{}}
	for i := range d.Items {
		r.Popularity = append(r.Popularity, i)
	}
	sort.Slice(r.Popularity, func(a, b int) bool {
		i, j := r.Popularity[a], r.Popularity[b]
		if d.ItemCounts[i] != d.ItemCounts[j] {
			return d.ItemCounts[i] > d.ItemCounts[j]
		}
		if d.ItemMeans[i] != d.ItemMeans[j] {
			return d.ItemMeans[i] > d.ItemMeans[j]
		}
		return i < j
	})
	for _, i := range r.Popularity[:r.Head] {
		r.Popular[i] = true
	}
	return r
}
func (r *Recommender) baseline(u, i int) float64 {
	return (r.Data.Mean + r.UserBias[u]) + r.ItemBias[i]
}
func (r *Recommender) train() {
	d, p := r.Data, r.Data.Params
	r.TrainErrors[0] = trainingRMSE(d.Training, func(u, i int) float64 { return d.Mean })
	for sweep := 1; sweep <= 10; sweep++ {
		for i, rows := range d.ByItem {
			total := 0.0
			for _, v := range rows {
				total += float64(v.Value) - d.Mean - r.UserBias[v.Other]
			}
			r.ItemBias[i] = total / (p.ItemReg + float64(len(rows)))
		}
		for u, rows := range d.ByUser {
			total := 0.0
			for _, v := range rows {
				total += float64(v.Value) - d.Mean - r.ItemBias[v.Other]
			}
			r.UserBias[u] = total / (p.UserReg + float64(len(rows)))
		}
		r.Log = append(r.Log, TrainingRecord{"BASELINE", sweep, trainingRMSE(d.Training, r.baseline)})
	}
	r.TrainErrors[1] = r.Log[len(r.Log)-1].RMSE
	model, log := trainSVD(d)
	r.SVD = model
	r.Log = append(r.Log, log...)
	r.TrainErrors[5] = log[len(log)-1].RMSE
	model, log = trainALS(d, r.UserBias, r.ItemBias)
	r.ALS = model
	r.Log = append(r.Log, log...)
	r.TrainErrors[6] = log[len(log)-1].RMSE
}
func (r *Recommender) knnPrediction(user, item, size int, byUser bool) Prediction {
	d := r.Data
	candidates := []Neighbor{}
	if byUser {
		for _, v := range d.ByItem[item] {
			s := r.Neighborhood.Users[user][v.Other]
			if s.Defined && s.Value > d.Params.MinSimilarity {
				candidates = append(candidates, Neighbor{v.Other, s.Value})
			}
		}
	} else {
		for _, v := range d.ByUser[user] {
			s := r.Neighborhood.Items[item][v.Other]
			if s.Defined && s.Value > d.Params.MinSimilarity {
				candidates = append(candidates, Neighbor{v.Other, s.Value})
			}
		}
	}
	selected := largestNeighbors(candidates, size)
	if len(selected) == 0 {
		return Prediction{Value: r.baseline(user, item), Fallback: true}
	}
	numerator, denominator := 0.0, 0.0
	for _, v := range selected {
		rating, mean := 0.0, 0.0
		if byUser {
			rating = float64(d.Values[v.Index][item])
			mean = d.UserMeans[v.Index]
		} else {
			rating = float64(d.Values[user][v.Index])
			mean = d.ItemMeans[v.Index]
		}
		numerator += v.Similarity * (rating - mean)
		denominator += v.Similarity
	}
	mean, top := d.ItemMeans[item], 0
	if byUser {
		mean = d.UserMeans[user]
		top = d.Users[selected[0].Index]
	} else {
		top = d.Items[selected[0].Index]
	}
	return Prediction{mean + numerator/denominator, false, len(selected), denominator / float64(len(selected)), top}
}
func (r *Recommender) slopePrediction(u, i int) Prediction {
	numerator := 0.0
	denominator := 0
	for _, v := range r.Data.ByUser[u] {
		count := r.Neighborhood.Counts[i][v.Other]
		if count > 0 {
			numerator += (r.Neighborhood.deviation(i, v.Other) + float64(v.Value)) * float64(count)
			denominator += count
		}
	}
	if denominator == 0 {
		return Prediction{Value: r.baseline(u, i), Fallback: true}
	}
	return Prediction{Value: numerator / float64(denominator)}
}
func (r *Recommender) predict(method, u, i, size int) Prediction {
	switch method {
	case 0:
		return Prediction{Value: r.Data.Mean}
	case 1:
		return Prediction{Value: r.baseline(u, i)}
	case 2:
		return r.knnPrediction(u, i, size, true)
	case 3:
		return r.knnPrediction(u, i, size, false)
	case 4:
		return r.slopePrediction(u, i)
	case 5:
		return Prediction{Value: r.SVD.predict(u, i)}
	case 6:
		return Prediction{Value: r.ALS.predict(u, i)}
	}
	panic("unknown method")
}
func (r *Recommender) predictTests() []string {
	lines := []string{"user,item,actual," + strings.Join(methods, ",")}
	d := r.Data
	for _, row := range d.Test {
		fields := []string{fmt.Sprint(d.Users[row.User]), fmt.Sprint(d.Items[row.Item]), fmt.Sprint(row.Value)}
		for m := range methods {
			p := r.predict(m, row.User, row.Item, d.Params.Neighbors)
			q := clip(p.Value)
			r.Predictions[m] = append(r.Predictions[m], p)
			r.Clipped[m] = append(r.Clipped[m], q)
			r.Errors[m] = append(r.Errors[m], q-float64(row.Value))
			fields = append(fields, real(q))
		}
		lines = append(lines, strings.Join(fields, ","))
	}
	for m := range methods {
		metric := Metric{RMSE: rmse(r.Errors[m]), MAE: mae(r.Errors[m])}
		for _, p := range r.Predictions[m] {
			if p.Value < 1 || p.Value > 5 {
				metric.Clipped++
			}
			if p.Fallback {
				metric.Fallback++
			}
		}
		r.Metrics[m] = metric
	}
	return lines
}
func (r *Recommender) prepareRankings() {
	d := r.Data
	selected := map[int]bool{}
	for _, t := range d.Test {
		if t.Value >= 4 {
			if r.Relevant[t.User] == nil {
				r.Relevant[t.User] = map[int]bool{}
			}
			r.Relevant[t.User][t.Item] = true
			selected[t.User] = true
		}
	}
	for u := range d.Users {
		if len(r.Relevant[u]) > 0 {
			r.Evaluated = append(r.Evaluated, u)
		}
	}
	for _, id := range d.Params.RecommendUsers {
		if u, ok := d.UserIndex[id]; ok {
			selected[u] = true
		}
	}
	for u := range d.Users {
		if !selected[u] {
			continue
		}
		candidates := []int{}
		for i := range d.Items {
			if d.Values[u][i] == 0 {
				candidates = append(candidates, i)
			}
		}
		lists := make([][]int, 7)
		for _, i := range r.Popularity {
			if d.Values[u][i] == 0 {
				lists[0] = append(lists[0], i)
			}
		}
		predictions := make([]map[int]Prediction, 7)
		for m := 1; m < 7; m++ {
			values := map[int]Prediction{}
			for _, i := range candidates {
				values[i] = r.predict(m, u, i, d.Params.Neighbors)
			}
			predictions[m] = values
			order := append([]int{}, candidates...)
			sort.Slice(order, func(a, b int) bool {
				i, j := order[a], order[b]
				if values[i].Value != values[j].Value {
					return values[i].Value > values[j].Value
				}
				return i < j
			})
			lists[m] = order
		}
		r.Rankings[u] = lists
		r.RankingPredictions[u] = predictions
	}
}
func contains(values []string, s string) bool {
	for _, v := range values {
		if v == s {
			return true
		}
	}
	return false
}
func sortedStrings(set map[string]bool) []string {
	out := []string{}
	for s := range set {
		out = append(out, s)
	}
	sort.Strings(out)
	return out
}
func countSummary(counts []int) string {
	ordered := append([]int{}, counts...)
	sort.Ints(ordered)
	n := len(ordered)
	median := float64(ordered[n/2])
	if n%2 == 0 {
		median = float64(ordered[n/2-1]+ordered[n/2]) / 2
	}
	return fmt.Sprintf("min %d median %s max %d", ordered[0], real(median), ordered[n-1])
}
func (r *Recommender) timeRange() (int64, int64) {
	first, last := r.Data.Training[0].Time, r.Data.Training[0].Time
	for _, t := range r.Data.Training[1:] {
		first = min(first, t.Time)
		last = max(last, t.Time)
	}
	return first, last
}
func (r *Recommender) dataSummary() []string {
	d := r.Data
	hist := make([]int, 5)
	for _, t := range d.Training {
		hist[t.Value-1]++
	}
	first, last := r.timeRange()
	up, uu, ip, iu, sp := 0, 0, 0, 0, 0
	for i := range d.Users {
		for j := i + 1; j < len(d.Users); j++ {
			s := r.Neighborhood.Users[i][j]
			if s.Defined {
				up++
				if s.Value > d.Params.MinSimilarity {
					uu++
				}
			}
		}
	}
	for i := range d.Items {
		for j := i + 1; j < len(d.Items); j++ {
			s := r.Neighborhood.Items[i][j]
			if s.Defined {
				ip++
				if s.Value > d.Params.MinSimilarity {
					iu++
				}
			}
			if r.Neighborhood.Counts[i][j] > 0 {
				sp++
			}
		}
	}
	return []string{fmt.Sprintf("data users %d items %d catalog %d ratings %d test %d", len(d.Users),
		len(d.Items), len(d.Catalog), len(d.Training), len(d.Test)), fmt.Sprintf("density %s global_mean %s",
		real(float64(len(d.Training))/float64(len(d.Users)*len(d.Items))), real(d.Mean)), "histogram " + ints(hist),
		"user_ratings " + countSummary(d.UserCounts), "item_ratings " + countSummary(d.ItemCounts),
		fmt.Sprintf("timestamps first %d last %d", first, last), fmt.Sprintf("cold_items %d", len(d.Catalog)-len(d.Items)),
		fmt.Sprintf("similarities user_pairs %d usable %d item_pairs %d usable %d slope_pairs %d",
			up, uu, ip, iu, sp)}
}
func (r *Recommender) genreSummary() []string {
	d := r.Data
	set := map[string]bool{}
	for _, id := range d.Items {
		for _, g := range d.Catalog[id].Genres {
			set[g] = true
		}
	}
	lines := []string{"genre_stats"}
	for _, g := range sortedStrings(set) {
		items, ratings, high := 0, 0, 0
		for i, id := range d.Items {
			if contains(d.Catalog[id].Genres, g) {
				items++
				ratings += d.ItemCounts[i]
				for _, v := range d.ByItem[i] {
					if v.Value >= 4 {
						high++
					}
				}
			}
		}
		lines = append(lines, fmt.Sprintf("genre %s items %d ratings %d high %d", g, items, ratings, high))
	}
	return lines
}
func (r *Recommender) timeSummary() []string {
	d := r.Data
	buckets := d.Params.Buckets
	counts, totals := make([]int, buckets), make([]int, buckets)
	users := make([]map[int]bool, buckets)
	for b := range users {
		users[b] = map[int]bool{}
	}
	first, last := r.timeRange()
	for _, t := range d.Training {
		b := int((t.Time - first) * int64(buckets) / (last - first + 1))
		counts[b]++
		totals[b] += t.Value
		users[b][t.User] = true
	}
	lines := []string{fmt.Sprintf("time_buckets %d", buckets)}
	for b := 0; b < buckets; b++ {
		mean := math.NaN()
		if counts[b] > 0 {
			mean = float64(totals[b]) / float64(counts[b])
		}
		lines = append(lines, fmt.Sprintf("bucket %d ratings %d users %d mean %s", b+1, counts[b], len(users[b]), real(mean)))
	}
	return lines
}
func (r *Recommender) ratingMetrics() []string {
	lines := []string{"rating_metrics"}
	for m, name := range methods {
		v := r.Metrics[m]
		lines = append(lines, fmt.Sprintf("%s rmse %s mae %s clipped %d fallback %d", name, real(v.RMSE), real(v.MAE), v.Clipped, v.Fallback))
	}
	return lines
}
func (r *Recommender) generalization() []string {
	lines := []string{"generalization"}
	for _, m := range []int{0, 1, 5, 6} {
		train, test := r.TrainErrors[m], r.Metrics[m].RMSE
		lines = append(lines, fmt.Sprintf("%s train %s test %s gap %s", methods[m], real(train), real(test), real(test-train)))
	}
	return lines
}
func (r *Recommender) neighborhoodUsage() []string {
	lines := []string{fmt.Sprintf("neighborhoods k %d", r.Data.Params.Neighbors)}
	for _, m := range []int{2, 3} {
		count, neighbors := 0, 0
		similarity := 0.0
		for _, p := range r.Predictions[m] {
			if !p.Fallback {
				count++
				neighbors += p.Neighbors
				similarity += p.Similarity
			}
		}
		mean, sim := math.NaN(), math.NaN()
		if count > 0 {
			mean = float64(neighbors) / float64(count)
			sim = similarity / float64(count)
		}
		lines = append(lines, fmt.Sprintf("%s predictions %d with_neighbors %d mean_neighbors %s mean_similarity %s",
			methods[m], len(r.Data.Test), count, real(mean), real(sim)))
	}
	return lines
}
func sum(values []float64) float64 {
	total := 0.0
	for _, x := range values {
		total += x
	}
	return total
}
func (r *Recommender) predictionStatistics() []string {
	n := len(r.Data.Test)
	total := 0
	for _, t := range r.Data.Test {
		total += t.Value
	}
	mean := float64(total) / float64(n)
	variation := 0.0
	lo, hi := r.Data.Test[0].Value, r.Data.Test[0].Value
	for _, t := range r.Data.Test {
		x := float64(t.Value) - mean
		variation += x * x
		lo = min(lo, t.Value)
		hi = max(hi, t.Value)
	}
	lines := []string{fmt.Sprintf("prediction_stats actual mean %s std %s", real(mean), real(math.Sqrt(variation/float64(n))))}
	for m, name := range methods {
		q := r.Clipped[m]
		mq := sum(q) / float64(n)
		vq, cov := 0.0, 0.0
		ql, qh := q[0], q[0]
		for i, x := range q {
			vq += (x - mq) * (x - mq)
			cov += (x - mq) * (float64(r.Data.Test[i].Value) - mean)
			ql = math.Min(ql, x)
			qh = math.Max(qh, x)
		}
		correlation := math.NaN()
		if ql != qh && lo != hi {
			correlation = cov / math.Sqrt(vq*variation)
		}
		lines = append(lines, fmt.Sprintf("%s mean %s std %s correlation %s", name, real(mq), real(math.Sqrt(vq/float64(n))), real(correlation)))
	}
	return lines
}
func (r *Recommender) errorBins() []string {
	lines := []string{"error_bins edges 0.5 1.0 1.5 2.0"}
	for m, name := range methods {
		bins := make([]int, 5)
		for _, e := range r.Errors[m] {
			b := 0
			for _, edge := range []float64{0.5, 1, 1.5, 2} {
				if math.Abs(e) >= edge {
					b++
				}
			}
			bins[b]++
		}
		lines = append(lines, name+" "+ints(bins))
	}
	return lines
}
func (r *Recommender) comparison() []string {
	lines := []string{"comparison"}
	for a := 0; a < 7; a++ {
		for b := a + 1; b < 7; b++ {
			wins, ties, losses := 0, 0, 0
			for i, x := range r.Errors[a] {
				left, right := math.Abs(x), math.Abs(r.Errors[b][i])
				if left < right {
					wins++
				} else if left == right {
					ties++
				} else {
					losses++
				}
			}
			lines = append(lines, fmt.Sprintf("%s %s wins %d ties %d losses %d", methods[a], methods[b], wins, ties, losses))
		}
	}
	return lines
}
func groupIndex(count int, bounds []int) int {
	g := 0
	for _, b := range bounds {
		if count >= b {
			g++
		}
	}
	return g
}
func (r *Recommender) errorsFor(indices []int, absolute bool) string {
	fields := []string{}
	for m, name := range methods {
		errors := make([]float64, len(indices))
		for j, i := range indices {
			errors[j] = r.Errors[m][i]
		}
		metric := rmse(errors)
		if absolute {
			metric = mae(errors)
		}
		fields = append(fields, name+" "+real(metric))
	}
	return strings.Join(fields, " ")
}
func (r *Recommender) groupErrors(user bool) []string {
	d := r.Data
	kind, bounds := "item", d.Params.ItemGroups
	if user {
		kind, bounds = "user", d.Params.UserGroups
	}
	groups := make([][]int, len(bounds)+1)
	for i, t := range d.Test {
		count := d.ItemCounts[t.Item]
		if user {
			count = d.UserCounts[t.User]
		}
		g := groupIndex(count, bounds)
		groups[g] = append(groups[g], i)
	}
	lines := []string{kind + "_groups bounds " + ints(bounds)}
	for g, indices := range groups {
		lower := 1
		if g > 0 {
			lower = bounds[g-1]
		}
		upper := "-"
		if g < len(bounds) {
			upper = fmt.Sprint(bounds[g] - 1)
		}
		lines = append(lines, fmt.Sprintf("group %d from %d to %s pairs %d %s", g+1, lower, upper, len(indices), r.errorsFor(indices, false)))
	}
	return lines
}
func (r *Recommender) ratingErrors() []string {
	lines := []string{"by_rating"}
	for v := 1; v <= 5; v++ {
		indices := []int{}
		for i, t := range r.Data.Test {
			if t.Value == v {
				indices = append(indices, i)
			}
		}
		lines = append(lines, fmt.Sprintf("rating %d pairs %d %s", v, len(indices), r.errorsFor(indices, true)))
	}
	return lines
}
func (r *Recommender) genreErrors() []string {
	set := map[string]bool{}
	for _, t := range r.Data.Test {
		for _, g := range r.Data.Catalog[r.Data.Items[t.Item]].Genres {
			set[g] = true
		}
	}
	lines := []string{"genres"}
	for _, g := range sortedStrings(set) {
		indices := []int{}
		for i, t := range r.Data.Test {
			if contains(r.Data.Catalog[r.Data.Items[t.Item]].Genres, g) {
				indices = append(indices, i)
			}
		}
		lines = append(lines, fmt.Sprintf("genre %s pairs %d %s", g, len(indices), r.errorsFor(indices, false)))
	}
	return lines
}
func (r *Recommender) userRankingMetrics(m, u, cutoff int) RankingMetrics {
	return rankingMetrics(r.Rankings[u][m], r.Relevant[u], cutoff)
}
func (r *Recommender) rankingEvaluation() []string {
	count := len(r.Evaluated)
	relevant := 0
	for _, u := range r.Evaluated {
		relevant += len(r.Relevant[u])
	}
	lines := []string{fmt.Sprintf("ranking users %d relevant %d", count, relevant)}
	for _, cutoff := range r.Data.Params.Cutoffs {
		lines = append(lines, fmt.Sprintf("cutoff %d", cutoff))
		for m, name := range rankings {
			hits, hitUsers := 0, 0
			recall, ndcg, ap, rr := 0.0, 0.0, 0.0, 0.0
			for _, u := range r.Evaluated {
				v := r.userRankingMetrics(m, u, cutoff)
				hits += v.Hits
				if v.Hits >= 1 {
					hitUsers++
				}
				recall += v.Recall
				ndcg += v.NDCG
				ap += v.AP
				rr += v.RR
			}
			den := float64(count)
			lines = append(lines, fmt.Sprintf("  %s precision %s recall %s ndcg %s map %s mrr %s hit_rate %s",
				name, real(float64(hits)/float64(cutoff*count)), real(recall/den), real(ndcg/den),
				real(ap/den), real(rr/den), real(float64(hitUsers)/den)))
		}
	}
	return lines
}
func (r *Recommender) beyondAccuracy() []string {
	d := r.Data
	size, count := d.Params.TopN, len(r.Evaluated)
	pairs := size * (size - 1) / 2
	lines := []string{fmt.Sprintf("beyond_accuracy top_n %d head %d", size, r.Head)}
	for m, name := range rankings {
		distinct := map[int]bool{}
		diversity, popularity, longTail := 0, 0, 0
		novelty, similarity := 0.0, 0.0
		for _, u := range r.Evaluated {
			ranked := r.Rankings[u][m][:size]
			genres := map[string]bool{}
			nov := 0.0
			for _, i := range ranked {
				distinct[i] = true
				for _, g := range d.Catalog[d.Items[i]].Genres {
					genres[g] = true
				}
				nov += math.Log2(float64(len(d.Users)) / float64(d.ItemCounts[i]))
				popularity += d.ItemCounts[i]
				if !r.Popular[i] {
					longTail++
				}
			}
			diversity += len(genres)
			novelty += nov / float64(size)
			pairSum := 0.0
			for a, i := range ranked {
				for _, j := range ranked[a+1:] {
					s := r.Neighborhood.Items[i][j]
					if s.Defined {
						pairSum += s.Value
					}
				}
			}
			similarity += pairSum / float64(pairs)
		}
		den := float64(count)
		lines = append(lines, fmt.Sprintf("%s coverage %s diversity %s novelty %s popularity %s long_tail %s similarity %s",
			name, real(float64(len(distinct))/float64(len(d.Items))), real(float64(diversity)/den),
			real(novelty/den), real(float64(popularity)/float64(size*count)), real(float64(longTail)/float64(size*count)),
			real(similarity/den)))
	}
	return lines
}
func (r *Recommender) rankingGroups() []string {
	bounds := r.Data.Params.UserGroups
	size := r.Data.Params.TopN
	groups := make([][]int, len(bounds)+1)
	for _, u := range r.Evaluated {
		g := groupIndex(r.Data.UserCounts[u], bounds)
		groups[g] = append(groups[g], u)
	}
	lines := []string{fmt.Sprintf("ranking_groups top_n %d bounds %s", size, ints(bounds))}
	for g, users := range groups {
		line := fmt.Sprintf("group %d users %d", g+1, len(users))
		for m, name := range rankings {
			mean := math.NaN()
			if len(users) > 0 {
				total := 0.0
				for _, u := range users {
					total += r.userRankingMetrics(m, u, size).NDCG
				}
				mean = total / float64(len(users))
			}
			line += " " + name + " " + real(mean)
		}
		lines = append(lines, line)
	}
	return lines
}
func (r *Recommender) agreement() []string {
	size := r.Data.Params.TopN
	lines := []string{fmt.Sprintf("agreement top_n %d", size)}
	for a := 0; a < 7; a++ {
		for b := a + 1; b < 7; b++ {
			total := 0.0
			for _, u := range r.Evaluated {
				left := map[int]bool{}
				for _, i := range r.Rankings[u][a][:size] {
					left[i] = true
				}
				intersection := 0
				for _, i := range r.Rankings[u][b][:size] {
					if left[i] {
						intersection++
					}
				}
				total += float64(intersection) / float64(2*size-intersection)
			}
			lines = append(lines, fmt.Sprintf("%s %s jaccard %s", rankings[a], rankings[b], real(total/float64(len(r.Evaluated)))))
		}
	}
	return lines
}
func (r *Recommender) neighborGrid() []string {
	lines := []string{"neighbor_grid"}
	best := [2]int{}
	values := [2]float64{math.Inf(1), math.Inf(1)}
	for _, size := range r.Data.Params.NeighborGrid {
		line := fmt.Sprintf("k %d", size)
		for j, m := range []int{2, 3} {
			errors := []float64{}
			for _, t := range r.Data.Test {
				p := r.predict(m, t.User, t.Item, size)
				errors = append(errors, clip(p.Value)-float64(t.Value))
			}
			error := rmse(errors)
			line += " " + methods[m] + " " + real(error)
			if error < values[j] {
				values[j] = error
				best[j] = size
			}
		}
		lines = append(lines, line)
	}
	return append(lines, fmt.Sprintf("best USER_KNN %d ITEM_KNN %d", best[0], best[1]))
}
func (r *Recommender) biasLists() []string {
	d := r.Data
	lines := []string{"biases"}
	for _, item := range []bool{true, false} {
		biases, counts, means, ids := r.UserBias, d.UserCounts, d.UserMeans, d.Users
		kind := "user"
		if item {
			biases, counts, means, ids = r.ItemBias, d.ItemCounts, d.ItemMeans, d.Items
			kind = "item"
		}
		for _, high := range []bool{true, false} {
			order := make([]int, len(ids))
			for i := range order {
				order[i] = i
			}
			sort.SliceStable(order, func(a, b int) bool {
				if high {
					return biases[order[a]] > biases[order[b]]
				}
				return biases[order[a]] < biases[order[b]]
			})
			label := "low"
			if high {
				label = "high"
			}
			for _, i := range order[:d.Params.ListSize] {
				line := fmt.Sprintf("%s_%s %d bias %s count %d mean %s", kind, label, ids[i], real(biases[i]), counts[i], real(means[i]))
				if item {
					line += " " + d.Catalog[ids[i]].Title
				}
				lines = append(lines, line)
			}
		}
	}
	return lines
}
func (r *Recommender) evaluationReport() []string {
	return separateSections([][]string{r.dataSummary(), r.genreSummary(), r.timeSummary(), r.ratingMetrics(),
		r.generalization(), r.neighborhoodUsage(), r.predictionStatistics(), r.errorBins(), r.comparison(),
		r.groupErrors(true), r.groupErrors(false), r.ratingErrors(), r.genreErrors(), r.rankingEvaluation(),
		r.beyondAccuracy(), r.rankingGroups(), r.agreement(), r.neighborGrid(), r.biasLists()})
}

type GenreCount struct {
	Genre string
	Count int
}

func (r *Recommender) preferredGenres(u int, liked bool) []GenreCount {
	counts := map[string]int{}
	for _, v := range r.Data.ByUser[u] {
		qualifies := v.Value <= 2
		if liked {
			qualifies = v.Value >= 4
		}
		if qualifies {
			for _, g := range r.Data.Catalog[r.Data.Items[v.Other]].Genres {
				counts[g]++
			}
		}
	}
	out := []GenreCount{}
	for g, c := range counts {
		out = append(out, GenreCount{g, c})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Count != out[j].Count {
			return out[i].Count > out[j].Count
		}
		return out[i].Genre < out[j].Genre
	})
	return out[:min(3, len(out))]
}
func (r *Recommender) popularityLine(rank, item int) string {
	d := r.Data
	return fmt.Sprintf("  %d %d count %d mean %s %s", rank, d.Items[item], d.ItemCounts[item], real(d.ItemMeans[item]), d.Catalog[d.Items[item]].Title)
}
func (r *Recommender) recommendationLine(u, m, rank, item int) string {
	if m == 0 {
		return r.popularityLine(rank, item)
	}
	p := r.RankingPredictions[u][m][item]
	line := fmt.Sprintf("  %d %d %s", rank, r.Data.Items[item], real(p.Value))
	if m == 2 || m == 3 {
		line += " via " + optional(p.Top)
	}
	return line + " " + r.Data.Catalog[r.Data.Items[item]].Title
}
func (r *Recommender) knownUserRecommendations(u int) []string {
	d := r.Data
	lines := []string{fmt.Sprintf("user %d ratings %d mean %s bias %s", d.Users[u], d.UserCounts[u], real(d.UserMeans[u]), real(r.UserBias[u]))}
	liked, disliked := r.preferredGenres(u, true), r.preferredGenres(u, false)
	for i, list := range [][]GenreCount{liked, disliked} {
		label := []string{"liked_genres", "disliked_genres"}[i]
		fields := []string{}
		for _, g := range list {
			fields = append(fields, fmt.Sprintf("%s %d", g.Genre, g.Count))
		}
		value := "-"
		if len(fields) > 0 {
			value = strings.Join(fields, " ")
		}
		lines = append(lines, label+" "+value)
	}
	recent := []Rating{}
	for _, t := range d.Training {
		if t.User == u {
			recent = append(recent, t)
		}
	}
	sort.Slice(recent, func(i, j int) bool {
		if recent[i].Time != recent[j].Time {
			return recent[i].Time > recent[j].Time
		}
		return recent[i].Item < recent[j].Item
	})
	line := "recent"
	for _, t := range recent[:min(3, len(recent))] {
		line += fmt.Sprintf(" %d %d", d.Items[t.Item], t.Value)
	}
	lines = append(lines, line)
	candidates := []Neighbor{}
	for v := range d.Users {
		s := r.Neighborhood.Users[u][v]
		if s.Defined && s.Value > d.Params.MinSimilarity {
			candidates = append(candidates, Neighbor{v, s.Value})
		}
	}
	for _, n := range largestNeighbors(candidates, d.Params.ListSize) {
		lines = append(lines, fmt.Sprintf("neighbor %d similarity %s common %d", d.Users[n.Index], real(n.Similarity), r.Neighborhood.Users[u][n.Index].Common))
	}
	for j, t := range d.Test {
		if t.User == u {
			line := fmt.Sprintf("heldout %d actual %d", d.Items[t.Item], t.Value)
			for m := range methods {
				line += " " + real(r.Clipped[m][j])
			}
			lines = append(lines, line)
		}
	}
	likedNames := map[string]bool{}
	for _, g := range liked {
		likedNames[g.Genre] = true
	}
	for m, name := range rankings {
		ranked := r.Rankings[u][m][:d.Params.TopN]
		matched := 0
		for _, i := range ranked {
			for _, g := range d.Catalog[d.Items[i]].Genres {
				if likedNames[g] {
					matched++
					break
				}
			}
		}
		lines = append(lines, fmt.Sprintf("list %s genre_match %d", name, matched))
		for rank, i := range ranked {
			lines = append(lines, r.recommendationLine(u, m, rank+1, i))
		}
	}
	return lines
}
func (r *Recommender) recommendations() []string {
	sections := [][]string{}
	for _, id := range r.Data.Params.RecommendUsers {
		if u, ok := r.Data.UserIndex[id]; ok {
			sections = append(sections, r.knownUserRecommendations(u))
		} else {
			lines := []string{fmt.Sprintf("user %d unknown", id), "list POPULAR"}
			for rank, i := range r.Popularity[:r.Data.Params.TopN] {
				lines = append(lines, r.popularityLine(rank+1, i))
			}
			sections = append(sections, lines)
		}
	}
	return separateSections(sections)
}
func (r *Recommender) similarItems() []string {
	d := r.Data
	size := d.Params.ListSize
	norms := make([]float64, len(d.Items))
	for i, v := range r.SVD.Items {
		norms[i] = dot(v, v)
	}
	sections := [][]string{}
	for _, id := range d.Params.SimilarItems {
		i := d.ItemIndex[id]
		info := d.Catalog[id]
		lines := []string{fmt.Sprintf("item %d ratings %d mean %s bias %s genres %s title %s", id, d.ItemCounts[i],
			real(d.ItemMeans[i]), real(r.ItemBias[i]), info.GenreText, info.Title), "cosine"}
		candidates := []Neighbor{}
		for j := range d.Items {
			s := r.Neighborhood.Items[i][j]
			if s.Defined {
				candidates = append(candidates, Neighbor{j, s.Value})
			}
		}
		for rank, n := range largestNeighbors(candidates, size) {
			lines = append(lines, fmt.Sprintf("  %d %d similarity %s common %d %s", rank+1, d.Items[n.Index],
				real(n.Similarity), r.Neighborhood.Items[i][n.Index].Common, d.Catalog[d.Items[n.Index]].Title))
		}
		candidates = []Neighbor{}
		for j := range d.Items {
			if i != j {
				value := dot(r.SVD.Items[i], r.SVD.Items[j]) / math.Sqrt(norms[i]*norms[j])
				candidates = append(candidates, Neighbor{j, value})
			}
		}
		lines = append(lines, "factors")
		for rank, n := range largestNeighbors(candidates, size) {
			lines = append(lines, fmt.Sprintf("  %d %d similarity %s %s", rank+1, d.Items[n.Index], real(n.Similarity), d.Catalog[d.Items[n.Index]].Title))
		}
		common := []int{}
		for j := range d.Items {
			if r.Neighborhood.Counts[i][j] >= 1 {
				common = append(common, j)
			}
		}
		sort.Slice(common, func(a, b int) bool {
			j, k := common[a], common[b]
			if r.Neighborhood.Counts[i][j] != r.Neighborhood.Counts[i][k] {
				return r.Neighborhood.Counts[i][j] > r.Neighborhood.Counts[i][k]
			}
			return j < k
		})
		lines = append(lines, "co_rated")
		for rank, j := range common[:min(size, len(common))] {
			lines = append(lines, fmt.Sprintf("  %d %d common %d %s", rank+1, d.Items[j], r.Neighborhood.Counts[i][j], d.Catalog[d.Items[j]].Title))
		}
		sort.Slice(common, func(a, b int) bool {
			j, k := common[a], common[b]
			x, y := r.Neighborhood.deviation(j, i), r.Neighborhood.deviation(k, i)
			if x != y {
				return x > y
			}
			if r.Neighborhood.Counts[j][i] != r.Neighborhood.Counts[k][i] {
				return r.Neighborhood.Counts[j][i] > r.Neighborhood.Counts[k][i]
			}
			return j < k
		})
		lines = append(lines, "slope_one")
		for rank, j := range common[:min(size, len(common))] {
			lines = append(lines, fmt.Sprintf("  %d %d difference %d common %d %s", rank+1, d.Items[j], r.Neighborhood.Differences[j][i],
				r.Neighborhood.Counts[j][i], d.Catalog[d.Items[j]].Title))
		}
		sections = append(sections, lines)
	}
	return separateSections(sections)
}
func (r *Recommender) trainingLog() []string {
	lines := []string{"method,epoch,train_rmse"}
	for _, t := range r.Log {
		lines = append(lines, fmt.Sprintf("%s,%d,%s", t.Method, t.Epoch, real(t.RMSE)))
	}
	return lines
}
func main() {
	r := newRecommender(readInputs())
	r.train()
	predictions := r.predictTests()
	r.prepareRankings()
	writeLines("predictions.csv", predictions)
	writeLines("evaluation.txt", r.evaluationReport())
	writeLines("recommendations.txt", r.recommendations())
	writeLines("similar_items.txt", r.similarItems())
	writeLines("training_log.csv", r.trainingLog())
}
