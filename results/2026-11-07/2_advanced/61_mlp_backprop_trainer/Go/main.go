package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
)

type Evaluation struct {
	Loss    float64
	Correct int
	Results []Forward
}

func evaluate(n Network, theta []float64, data []Image) Evaluation {
	out := Evaluation{}
	for _, image := range data {
		f := n.forward(theta, image)
		out.Loss += f.Loss
		if f.Prediction == image.Label {
			out.Correct++
		}
		out.Results = append(out.Results, f)
	}
	out.Loss /= float64(len(data))
	return out
}

type Epoch struct {
	Eta, Gradient, TrainLoss, ValidationLoss float64
	TrainCorrect, ValidationCorrect          int
	Improved                                 bool
	Status                                   []bool
}
type Run struct {
	Config                          RunConfig
	Network                         Network
	Theta                           []float64
	Epochs                          []Epoch
	BestEpoch, BestCorrect, Updates int
	BestLoss                        float64
	Stop                            string
	Test                            Evaluation
	Matrix                          [][]int
}

func writeLines(name string, values []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(values, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
func indices(n int) []int {
	v := make([]int, n)
	for i := range v {
		v[i] = i
	}
	return v
}
func gradientCheck(networks []Network, data []Image, params Params) {
	out := []string{}
	for ni, n := range networks {
		if ni > 0 {
			out = append(out, "")
		}
		rng := RNG{int64(params.Seed)}
		order := indices(len(data))
		rng.shuffle(order)
		batch := order[:min(params.Batch, len(order))]
		theta := append([]float64(nil), n.Initial...)
		analytic, _ := n.meanGradient(theta, data, batch)
		counts := make([][2]int, len(n.Layers))
		checked := 0
		pass := true
		for p := 0; p < len(theta); p += params.Stride {
			original := theta[p]
			theta[p] = original + .00001
			_, plus := n.meanGradient(theta, data, batch)
			theta[p] = original - .00001
			_, minus := n.meanGradient(theta, data, batch)
			theta[p] = original
			numeric := (plus - minus) / (2 * .00001)
			error := math.Abs(analytic[p]-numeric) / math.Max(1, math.Abs(analytic[p])+math.Abs(numeric))
			if error >= .000001 {
				pass = false
			}
			checked++
			for l, layer := range n.Layers {
				if p >= layer.Weights && p < layer.Biases+layer.Units {
					kind := 0
					if p >= layer.Biases {
						kind = 1
					}
					counts[l][kind]++
					break
				}
			}
		}
		ids := []string{}
		for _, i := range batch {
			ids = append(ids, data[i].ID)
		}
		out = append(out, "network "+n.Name, fmt.Sprint("parameters ", len(theta)), "batch "+strings.Join(ids, " "))
		for l, count := range counts {
			out = append(out, fmt.Sprintf("layer %d weights %d biases %d", l+1, count[0], count[1]))
		}
		result := "PASS"
		if !pass {
			result = "FAIL"
		}
		out = append(out, fmt.Sprint("checked ", checked), "result "+result)
	}
	writeLines("gradient_check.txt", out)
}
func trainRun(network Network, config RunConfig, params Params, training, validation, test []Image) Run {
	out := Run{Config: config, Network: network, Stop: "max_epochs"}
	theta := append([]float64(nil), network.Initial...)
	order := indices(len(training))
	rng := RNG{int64(params.Seed)}
	optimizer := newOptimizer(config, len(theta))
	wait := 0
	for epoch := 1; epoch <= params.Epochs; epoch++ {
		eta := learningRate(config, params, epoch)
		rng.shuffle(order)
		magnitude := 0.0
		batches := 0
		for start := 0; start < len(order); start += params.Batch {
			batch := order[start:min(len(order), start+params.Batch)]
			g, _ := network.meanGradient(theta, training, batch)
			for _, p := range network.WeightIndices {
				g[p] = g[p] + config.Lambda*theta[p]
			}
			sum := 0.0
			for _, v := range g {
				sum += v * v
			}
			magnitude += math.Sqrt(sum)
			batches++
			optimizer.update(theta, g, eta)
			out.Updates++
		}
		trainEval, valEval := evaluate(network, theta, training), evaluate(network, theta, validation)
		record := Epoch{Eta: eta, Gradient: magnitude / float64(batches), TrainLoss: trainEval.Loss, ValidationLoss: valEval.Loss,
			TrainCorrect: trainEval.Correct, ValidationCorrect: valEval.Correct, Status: make([]bool,
				len(training))}
		for i, f := range trainEval.Results {
			record.Status[i] = f.Prediction == training[i].Label
		}
		if epoch == 1 || valEval.Loss < out.BestLoss {
			record.Improved = true
			out.BestLoss, out.BestEpoch, out.BestCorrect = valEval.Loss, epoch, valEval.Correct
			out.Theta = append([]float64(nil), theta...)
			wait = 0
		} else {
			wait++
		}
		out.Epochs = append(out.Epochs, record)
		if wait >= params.Patience {
			out.Stop = "early"
			break
		}
		if epoch == params.Epochs {
			break
		}
	}
	out.Test = evaluate(network, out.Theta, test)
	out.Matrix = confusion(test, out.Test.Results, network.Layers[len(network.Layers)-1].Units)
	return out
}
func trainingOutputs(runs []Run, training, validation, test []Image) {
	log, weights, predictions := []string{"run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved"},
		[]string{}, []string{"run,id,label,predicted,confidence"}
	for ri, run := range runs {
		for e, record := range run.Epochs {
			log = append(log, fmt.Sprintf("%s,%d,%s,%s,%s,%s,%s,%s,%d", run.Config.Name, e+1, fixed(record.Eta,
				6), fixed(record.Gradient, 4), fixed(record.TrainLoss, 6), ratio(record.TrainCorrect,
				len(training)), fixed(record.ValidationLoss, 6), ratio(record.ValidationCorrect,
				len(validation)), boolInt(record.Improved)))
		}
		if ri > 0 {
			weights = append(weights, "")
		}
		weights = append(weights, fmt.Sprintf("RUN %s NETWORK %s EPOCH %d", run.Config.Name, run.Network.Name, run.BestEpoch))
		for l, layer := range run.Network.Layers {
			weights = append(weights, fmt.Sprintf("LAYER %d %d %d", l+1, layer.Units, layer.Inputs))
			for j := 0; j < layer.Units; j++ {
				row := []string{"W"}
				for i := 0; i < layer.Inputs; i++ {
					row = append(row, fixed(run.Theta[layer.Weights+j*layer.Inputs+i], 4))
				}
				weights = append(weights, strings.Join(row, " "))
			}
			row := []string{"B"}
			for j := 0; j < layer.Units; j++ {
				row = append(row, fixed(run.Theta[layer.Biases+j], 4))
			}
			weights = append(weights, strings.Join(row, " "))
		}
		for i, image := range test {
			f := run.Test.Results[i]
			predictions = append(predictions, fmt.Sprintf("%s,%s,%d,%d,%s", run.Config.Name, image.ID, image.Label, f.Prediction, fixed(f.Confidence, 4)))
		}
	}
	writeLines("training_log.csv", log)
	writeLines("final_weights.txt", weights)
	writeLines("predictions.csv", predictions)
}
func noisyImages(test []Image, rate, seed int) ([]Image, int) {
	rng := RNG{int64(seed)}
	out := make([]Image, len(test))
	flips := 0
	for j, image := range test {
		pixels := []byte(image.Pixels)
		input := append([]float64(nil), image.Input...)
		for i := range pixels {
			if rng.next()%100 < rate {
				flips++
				if pixels[i] == '1' {
					pixels[i] = '0'
					input[i] = 0
				} else {
					pixels[i] = '1'
					input[i] = 1
				}
			}
		}
		out[j] = Image{image.ID, image.Label, string(pixels), input}
	}
	return out, flips
}
func dataOutput(training, validation, test []Image, k, w, h int) []string {
	counts := make([][3]int, k)
	ink := make([]int, k)
	pixels := make([][]int, k)
	levels := make([][]int, k)
	for cl := 0; cl < k; cl++ {
		pixels[cl] = make([]int, w*h)
		levels[cl] = make([]int, w*h)
	}
	for which, data := range [][]Image{training, validation, test} {
		for _, image := range data {
			counts[image.Label][which]++
			if which == 0 {
				for i, p := range image.Pixels {
					if p == '1' {
						ink[image.Label]++
						pixels[image.Label][i]++
					}
				}
			}
		}
	}
	out := []string{"data", fmt.Sprintf("train %d validation %d test %d pixels %d", len(training), len(validation), len(test), w*h)}
	names := []string{"mean_images"}
	for cl := 0; cl < k; cl++ {
		out = append(out, fmt.Sprintf("class %d train %d validation %d test %d ink %s", cl, counts[cl][0],
			counts[cl][1], counts[cl][2], ratio(ink[cl], counts[cl][0])))
		names = append(names, fmt.Sprint(cl))
		if counts[cl][0] > 0 {
			for i, v := range pixels[cl] {
				levels[cl][i] = min(9, 10*v/counts[cl][0])
			}
		}
	}
	out = append(out, strings.Join(names, " "))
	return append(out, levelLines(levels, w, h)...)
}
func runOutput(run Run, params Params, training, validation, test []Image, noisy map[int][]Image) []string {
	n := run.Network
	k := n.Layers[len(n.Layers)-1].Units
	total := len(test)
	top2 := 0
	confidenceSum := [2]float64{}
	confidenceCount := [2]int{}
	wrong := []string{}
	for i, image := range test {
		f := run.Test.Results[i]
		right := f.Prediction == image.Label
		group := 0
		if !right {
			group = 1
			wrong = append(wrong, image.ID)
		}
		confidenceSum[group] += f.Confidence
		confidenceCount[group]++
		if right || second(f.Scores, f.Prediction) == image.Label {
			top2++
		}
	}
	mean := [2]string{"-", "-"}
	for g, count := range confidenceCount {
		if count > 0 {
			mean[g] = fixed(confidenceSum[g]/float64(count), 4)
		}
	}
	forgetting, forgotten, never := 0, 0, 0
	for i := range training {
		count := 0
		learned := false
		for e, epoch := range run.Epochs {
			if epoch.Status[i] {
				learned = true
			}
			if e > 0 && run.Epochs[e-1].Status[i] && !epoch.Status[i] {
				count++
			}
		}
		forgetting += count
		if count > 0 {
			forgotten++
		}
		if !learned {
			never++
		}
	}
	norms, changes := []string{}, []string{}
	for _, layer := range n.Layers {
		norm, change := 0.0, 0.0
		for p := layer.Weights; p < layer.Biases; p++ {
			norm += run.Theta[p] * run.Theta[p]
			d := run.Theta[p] - n.Initial[p]
			change += d * d
		}
		norms = append(norms, fixed(math.Sqrt(norm), 4))
		changes = append(changes, fixed(math.Sqrt(change), 4))
	}
	out := []string{fmt.Sprintf("run %s network %s optimizer %s", run.Config.Name, n.Name, run.Config.Optimizer),
		fmt.Sprintf("epochs %d best_epoch %d stop %s updates %d", len(run.Epochs), run.BestEpoch,
			run.Stop, run.Updates), fmt.Sprintf("best_val_loss %s best_val_acc %s correct %d/%d", fixed(run.BestLoss,
			6), ratio(run.BestCorrect, len(validation)), run.BestCorrect, len(validation)), fmt.Sprintf("test_loss %s test_acc %s correct %d/%d",
			fixed(run.Test.Loss, 6), ratio(run.Test.Correct, total), run.Test.Correct, total), fmt.Sprintf("top2_acc %s correct %d/%d",
			ratio(top2, total), top2, total), fmt.Sprintf("confidence correct %s wrong %s", mean[0],
			mean[1]), fmt.Sprintf("forgetting events %d rows %d never_learned %d", forgetting, forgotten,
			never), "weight_norms " + strings.Join(norms, " "), "weight_changes " + strings.Join(changes,
			" "), "curve"}
	lmax := 0.0
	for _, e := range run.Epochs {
		lmax = math.Max(lmax, math.Max(e.TrainLoss, e.ValidationLoss))
	}
	for e, record := range run.Epochs {
		row := []byte(strings.Repeat(" ", 40))
		ct, cv := int(math.Floor(39*record.TrainLoss/lmax+.5)), int(math.Floor(39*record.ValidationLoss/lmax+.5))
		row[ct] = 't'
		row[cv] = 'v'
		if ct == cv {
			row[ct] = '*'
		}
		line := fmt.Sprintf("%2d |%s|", e+1, string(row))
		if e+1 == run.BestEpoch {
			line += " best"
		}
		out = append(out, line)
	}
	out = append(out, "confusion")
	for cl, row := range run.Matrix {
		items := []string{}
		for _, v := range row {
			items = append(items, fmt.Sprint(v))
		}
		out = append(out, fmt.Sprint(cl, ": ", strings.Join(items, " ")))
	}
	for cl := 0; cl < k; cl++ {
		support, predicted, precision, recall, f1 := classMetrics(run.Matrix, cl)
		out = append(out, fmt.Sprintf("class %d support %d predicted %d precision %s recall %s f1 %s", cl, support, predicted, precision, recall, f1))
	}
	out = append(out, "calibration")
	binCounts, binCorrect := make([]int, params.Bins), make([]int, params.Bins)
	binSums := make([]float64, params.Bins)
	for i, f := range run.Test.Results {
		bin := min(params.Bins-1, int(math.Floor(f.Confidence*float64(params.Bins))))
		binCounts[bin]++
		binSums[bin] += f.Confidence
		if f.Prediction == test[i].Label {
			binCorrect[bin]++
		}
	}
	ece := 0.0
	for bin, count := range binCounts {
		confidence := "-"
		if count > 0 {
			value := binSums[bin] / float64(count)
			confidence = fixed(value, 4)
			ece += float64(count) / float64(total) * math.Abs(float64(binCorrect[bin])/float64(count)-value)
		}
		out = append(out, fmt.Sprintf("bin %d %s %s count %d accuracy %s confidence %s", bin+1, fixed(float64(bin)/float64(params.Bins),
			2), fixed(float64(bin+1)/float64(params.Bins), 2), count, ratio(binCorrect[bin], count),
			confidence))
	}
	out = append(out, "ece "+fixed(ece, 4))
	for l, layer := range n.Layers[:len(n.Layers)-1] {
		counts := make([]int, k)
		sums := make([][]float64, k)
		zeros := make([]int, layer.Units)
		for cl := range sums {
			sums[cl] = make([]float64, layer.Units)
		}
		for i, image := range test {
			counts[image.Label]++
			for j, v := range run.Test.Results[i].Activations[l+1] {
				sums[image.Label][j] += v
				if v == 0 {
					zeros[j]++
				}
			}
		}
		out = append(out, fmt.Sprintf("hidden %d %s units %d", l+1, layer.Activation, layer.Units))
		for cl, count := range counts {
			items := []string{}
			if count == 0 {
				items = append(items, "-")
			} else {
				for j := range sums[cl] {
					sums[cl][j] /= float64(count)
					items = append(items, fixed(sums[cl][j], 4))
				}
			}
			out = append(out, fmt.Sprintf("class %d mean %s", cl, strings.Join(items, " ")))
		}
		preferred := []string{"preferred"}
		for j := 0; j < layer.Units; j++ {
			best := -1
			for cl, count := range counts {
				if count > 0 && (best < 0 || sums[cl][j] > sums[best][j]) {
					best = cl
				}
			}
			preferred = append(preferred, fmt.Sprint(best))
		}
		out = append(out, strings.Join(preferred, " "))
		if layer.Activation == "RELU" {
			items := []string{"zero_counts"}
			for _, count := range zeros {
				items = append(items, fmt.Sprint(count))
			}
			out = append(out, strings.Join(items, " "))
		}
	}
	out = append(out, "pruning")
	ordered := append([]int(nil), n.WeightIndices...)
	sort.Slice(ordered, func(i, j int) bool {
		x, y := math.Abs(run.Theta[ordered[i]]), math.Abs(run.Theta[ordered[j]])
		if x != y {
			return x < y
		}
		return ordered[i] < ordered[j]
	})
	for _, fraction := range params.Prune {
		theta := append([]float64(nil), run.Theta...)
		removed := fraction * len(ordered) / 100
		for _, p := range ordered[:removed] {
			theta[p] = 0
		}
		evaluation := evaluate(n, theta, test)
		out = append(out, fmt.Sprintf("prune %d removed %d correct %d test_acc %s test_loss %s", fraction,
			removed, evaluation.Correct, ratio(evaluation.Correct, total), fixed(evaluation.Loss,
				6)))
	}
	out = append(out, "noise")
	for _, rate := range params.Noise {
		evaluation := evaluate(n, run.Theta, noisy[rate])
		out = append(out, fmt.Sprintf("noise %d correct %d test_acc %s", rate, evaluation.Correct, ratio(evaluation.Correct, total)))
	}
	line := fmt.Sprint("misclassified ", len(wrong))
	if len(wrong) > 0 {
		line += " " + strings.Join(wrong, " ")
	}
	out = append(out, line)
	return out
}
func comparisonOutput(runs []Run, params Params, all, training, test []Image, w, h, k int, flips map[int]int) []string {
	order := indices(len(runs))
	sort.Slice(order, func(i, j int) bool {
		x, y := runs[order[i]], runs[order[j]]
		if x.Test.Correct != y.Test.Correct {
			return x.Test.Correct > y.Test.Correct
		}
		if x.BestLoss != y.BestLoss {
			return x.BestLoss < y.BestLoss
		}
		return order[i] < order[j]
	})
	top := runs[order[0]]
	total := len(test)
	out := []string{"comparison"}
	for rank, index := range order {
		r := runs[index]
		out = append(out, fmt.Sprintf("rank %d %s correct %d test_acc %s best_val_loss %s test_loss %s best_epoch %d epochs %d updates %d",
			rank+1, r.Config.Name, r.Test.Correct, ratio(r.Test.Correct, total), fixed(r.BestLoss,
				6), fixed(r.Test.Loss, 6), r.BestEpoch, len(r.Epochs), r.Updates))
	}
	out = append(out, "agreement")
	for _, a := range runs {
		line := []string{a.Config.Name}
		for _, b := range runs {
			count := 0
			for i, f := range a.Test.Results {
				if f.Prediction == b.Test.Results[i].Prediction {
					count++
				}
			}
			line = append(line, fmt.Sprint(count))
		}
		out = append(out, strings.Join(line, " "))
	}
	out = append(out, "mcnemar "+top.Config.Name)
	for _, index := range order[1:] {
		r := runs[index]
		b, c := 0, 0
		for i, image := range test {
			x, y := top.Test.Results[i].Prediction == image.Label, r.Test.Results[i].Prediction == image.Label
			if x && !y {
				b++
			}
			if y && !x {
				c++
			}
		}
		difference := b - c
		if difference < 0 {
			difference = -difference
		}
		difference = max(0, difference-1)
		numerator, denominator := difference*difference, b+c
		chi := "0.0000"
		if denominator > 0 {
			chi = ratio(numerator, denominator)
		}
		significant := "no"
		if numerator*1000 > 3841*denominator {
			significant = "yes"
		}
		out = append(out, fmt.Sprintf("vs %s b %d c %d chi2 %s significant %s", r.Config.Name, b, c, chi, significant))
	}
	ensemble := make([]int, total)
	ensembleCorrect, fixedCount, broken := 0, 0, 0
	for i, image := range test {
		votes := make([]int, k)
		maximum := 0
		for _, r := range runs {
			cl := r.Test.Results[i].Prediction
			votes[cl]++
			maximum = max(maximum, votes[cl])
		}
		chosen := 0
		for _, index := range order {
			cl := runs[index].Test.Results[i].Prediction
			if votes[cl] == maximum {
				chosen = cl
				break
			}
		}
		ensemble[i] = chosen
		right, topRight := chosen == image.Label, top.Test.Results[i].Prediction == image.Label
		if right {
			ensembleCorrect++
		}
		if right && !topRight {
			fixedCount++
		}
		if !right && topRight {
			broken++
		}
	}
	out = append(out, fmt.Sprintf("ensemble correct %d/%d test_acc %s fixed %d broken %d", ensembleCorrect,
		total, ratio(ensembleCorrect, total), fixedCount, broken))
	soft := []int{}
	for i, r := range runs {
		if r.Network.Layers[len(r.Network.Layers)-1].Activation == "SOFTMAX" {
			soft = append(soft, i)
		}
	}
	if len(soft) == 0 {
		out = append(out, "soft_ensemble none")
	} else {
		correct := 0
		for i, image := range test {
			means := make([]float64, k)
			for _, index := range soft {
				for cl, v := range runs[index].Test.Results[i].Scores {
					means[cl] += v
				}
			}
			for cl := range means {
				means[cl] /= float64(len(soft))
			}
			if prediction(means) == image.Label {
				correct++
			}
		}
		out = append(out, fmt.Sprintf("soft_ensemble runs %d correct %d/%d test_acc %s", len(soft), correct, total, ratio(correct, total)))
	}
	for _, rate := range params.Noise {
		out = append(out, fmt.Sprintf("noise %d flipped %d", rate, flips[rate]))
	}
	type Pair struct{ Y, P, Count int }
	pairs := []Pair{}
	for y := 0; y < k; y++ {
		for p := 0; p < k; p++ {
			if y == p {
				continue
			}
			count := 0
			for _, r := range runs {
				count += r.Matrix[y][p]
			}
			if count > 0 {
				pairs = append(pairs, Pair{y, p, count})
			}
		}
	}
	sort.Slice(pairs, func(i, j int) bool {
		a, b := pairs[i], pairs[j]
		if a.Count != b.Count {
			return a.Count > b.Count
		}
		if a.Y != b.Y {
			return a.Y < b.Y
		}
		return a.P < b.P
	})
	out = append(out, "confused_pairs")
	for _, pair := range pairs[:min(5, len(pairs))] {
		out = append(out, fmt.Sprintf("%d as %d count %d", pair.Y, pair.P, pair.Count))
	}
	out = append(out, "", "saliency "+top.Config.Name)
	classes := []string{"classes"}
	for cl := 0; cl < k; cl++ {
		classes = append(classes, fmt.Sprint(cl))
	}
	out = append(out, strings.Join(classes, " "))
	counts := make([]int, k)
	sums := make([][]float64, k)
	levels := make([][]int, k)
	for cl := 0; cl < k; cl++ {
		sums[cl] = make([]float64, w*h)
		levels[cl] = make([]int, w*h)
	}
	for _, image := range test {
		_, input, _ := top.Network.gradient(top.Theta, image)
		counts[image.Label]++
		for i, v := range input {
			sums[image.Label][i] += math.Abs(v)
		}
	}
	for cl, count := range counts {
		if count == 0 {
			continue
		}
		maximum := 0.0
		for i := range sums[cl] {
			sums[cl][i] /= float64(count)
			maximum = math.Max(maximum, sums[cl][i])
		}
		if maximum > 0 {
			for i, v := range sums[cl] {
				levels[cl][i] = min(9, int(math.Floor(10*v/maximum)))
			}
		}
	}
	out = append(out, levelLines(levels, w, h)...)
	out = append(out, "", "hardest_training_examples "+top.Config.Name)
	trainingResults := evaluate(top.Network, top.Theta, training).Results
	hardest := indices(len(training))
	sort.Slice(hardest, func(i, j int) bool {
		a, b := trainingResults[hardest[i]].Loss, trainingResults[hardest[j]].Loss
		if a != b {
			return a > b
		}
		return hardest[i] < hardest[j]
	})
	for _, index := range hardest[:min(5, len(hardest))] {
		image, result := training[index], trainingResults[index]
		out = append(out, fmt.Sprintf("%s label %d predicted %d loss %s", image.ID, image.Label, result.Prediction, fixed(result.Loss, 6)))
	}
	out = append(out, "", "misclassified_examples "+top.Config.Name)
	for i, image := range test {
		result := top.Test.Results[i]
		if result.Prediction == image.Label {
			continue
		}
		predictions := []string{}
		for _, r := range runs {
			predictions = append(predictions, fmt.Sprint(r.Test.Results[i].Prediction))
		}
		out = append(out, fmt.Sprintf("%s label %d predicted %d confidence %s true_score %s runs %s ensemble %d",
			image.ID, image.Label, result.Prediction, fixed(result.Confidence, 4), fixed(result.Scores[image.Label],
				4), strings.Join(predictions, " "), ensemble[i]))
		nearest, distance := 0, len(image.Pixels)+1
		for index, candidate := range all {
			d := 0
			for p, c := range image.Pixels {
				if byte(c) != candidate.Pixels[p] {
					d++
				}
			}
			if d < distance {
				nearest, distance = index, d
			}
		}
		out = append(out, fmt.Sprintf("nearest %s label %d distance %d", all[nearest].ID, all[nearest].Label, distance))
		out = append(out, imageLines(image, w, h)...)
	}
	return out
}
func main() {
	all, test := readImages("input/train.csv"), readImages("input/test.csv")
	networks, w, h := readNetworks()
	params := readParams()
	m := len(all) - len(all)/5
	training, validation := all[:m], all[m:]
	gradientCheck(networks, training, params)
	byName := map[string]Network{}
	for _, n := range networks {
		byName[n.Name] = n
	}
	runs := []Run{}
	for _, config := range params.Runs {
		runs = append(runs, trainRun(byName[config.Network], config, params, training, validation, test))
	}
	trainingOutputs(runs, training, validation, test)
	noisy, flips := map[int][]Image{}, map[int]int{}
	for _, rate := range params.Noise {
		noisy[rate], flips[rate] = noisyImages(test, rate, params.Seed)
	}
	k := networks[0].Layers[len(networks[0].Layers)-1].Units
	out := dataOutput(training, validation, test, k, w, h)
	out = append(out, "")
	for _, run := range runs {
		out = append(out, runOutput(run, params, training, validation, test, noisy)...)
		out = append(out, "")
	}
	out = append(out, comparisonOutput(runs, params, all, training, test, w, h, k, flips)...)
	writeLines("evaluation.txt", out)
}
