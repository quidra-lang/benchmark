import Foundation
func f4(_ v: Double) -> String {
    fixed(v, 4)
}
func f6(_ v: Double) -> String {
    fixed(v, 6)
}
func frac(_ p: (Int, Int)) -> String {
    fraction(p.0, p.1)
}
func length(_ xs: [Double]) -> Double {
    sqrt(xs.reduce(0.0) {
        $0+$1*$1
    })
}
func predict(_ p: [Double], _ threshold: Double) -> [Int] {
    p.map {
        $0 >= threshold ? 1 : 0
    }
}
func equal(_ a: [Int], _ b: [Int]) -> Int {
    zip(a, b).filter {
        $0.0 == $0.1
    }.count
}
func probabilities(_ w: [Double], _ x: [[Double]]) -> [Double] {
    x.map {
        probability(score(w, $0))
    }
}
func inverse(_ a: [[Double]]) -> [[Double]] {
    let l = cholesky(a), n = a.count;
    var out = Array(repeating: Array(repeating: 0.0, count: n), count: n);
    for k in 0..<n {
        var unit = Array(repeating: 0.0, count: n);
        unit[k] = 1;
        let x = solve(l, unit);
        for j in 0..<n {
            out[j][k] = x[j]
        }
    };
    return out
}
func original(_ w: [Double], _ s: Statistics) -> [Double] {
    let scaled = w.indices.dropFirst().map {
        w[$0]/s.sd[$0-1]
    }, shift = zip(scaled, s.means).reduce(0.0) {
        $0+$1.0*$1.1
    };
    return[w[0]-shift]+scaled
}
struct Data {
    let names: [String],
    train: [Example],
    test: [Example],
    settings: Settings,
    tuples: [[Int]],
    featureNames: [String],
    overall: Statistics,
    expanded: [[Double]],
    testExpanded: [[Double]],
    x: [[Double]],
    z: [[Double]],
    y: [Int],
    ty: [Int],
    labels: [Int],
    testLabels: [Int],
    classes: Int
    init() throws {
        let(names, train) = try readExamples("train"), (_, test) = try readExamples("test"), settings = try Settings(), tuples = expansionTuples(names.count, settings.int("DEGREE"))
        let featureNames = tuples.map {
            $0.map {
                names[$0]
            }.joined(separator: "*")
        }, expanded = train.map {
            expandedValues(tuples, $0.values)
        }, testExpanded = test.map {
            expandedValues(tuples, $0.values)
        }, overall = statistics(expanded, tuples.count), x = expanded.map {
            standardize($0, overall, tuples.count)
        }, z = testExpanded.map {
            standardize($0, overall, tuples.count)
        }, labels = train.map(\.label), testLabels = test.map(\.label), c = settings.int("POSITIVE")
        self.names = names;
        self.train = train;
        self.test = test;
        self.settings = settings;
        self.tuples = tuples;
        self.featureNames = featureNames;
        self.overall = overall;
        self.expanded = expanded;
        self.testExpanded = testExpanded;
        self.x = x;
        self.z = z;
        self.labels = labels;
        self.testLabels = testLabels;
        classes = labels.max()!+1;
        y = labels.map {
            $0 == c ? 1 : 0
        };
        ty = testLabels.map {
            $0 == c ? 1 : 0
        }
    }
    func vector(_ values: [Double]) -> [Double] {
        standardize(expandedValues(tuples, values), overall, tuples.count)
    }
    var means: [Double] {
        Array(overall.means.prefix(names.count))
    }
    var threshold: Double {
        settings.real("THRESHOLD")
    }
}
struct Evaluation {
    let p: [Double],
    pred: [Int],
    loss: Double,
    correct: Int,
    aucValue: (Int, Int)
    init(_ w: [Double], _ x: [[Double]], _ y: [Int], _ threshold: Double) {
        let p = probabilities(w, x), pred = predict(p, threshold);
        self.p = p;
        self.pred = pred;
        loss = averageLoss(w, x, y);
        correct = equal(pred, y);
        aucValue = auc(p, y)
    }
}
struct Model {
    let name: String,
    checkpoints: Checkpoints,
    w: [Double],
    train: Evaluation,
    test: Evaluation
    init(_ name: String, _ checkpoints: Checkpoints, _ d: Data) {
        let w = checkpoints.last!.1;
        self.name = name;
        self.checkpoints = checkpoints;
        self.w = w;
        train = Evaluation(w, d.x, d.y, d.threshold);
        test = Evaluation(w, d.z, d.ty, d.threshold)
    }
}
struct Influence {
    let matrix: [[Double]],
    p: [Double],
    h: [Double],
    residual: [Double],
    cooks: [Double],
    edf: Double,
    dev: Double,
    aic: Double,
    bic: Double
    init(_ w: [Double], _ x: [[Double]], _ y: [Int], _ lam: Double) {
        let matrix = inverse(hessian(w, x, lam)), n = Double(x.count);
        var ps = [Double](), hs = [Double](), residuals = [Double](), cooks = [Double]()
        for(v, y)in zip(x, y) {
            let p = probability(score(w, v)), variance = p*(1-p);
            var quadratic = 0.0;
            for j in w.indices {
                for k in w.indices {
                    quadratic += v[j]*matrix[j][k]*v[k]
                }
            };
            let h = variance*quadratic/n, pearson = (Double(y)-p)/sqrt(variance);
            ps.append(p);
            hs.append(h);
            residuals.append(pearson/sqrt(1-h));
            cooks.append(pearson*pearson*h/(Double(w.count)*((1-h)*(1-h))))
        }
        let edf = hs.reduce(0, +), dev = 2*n*averageLoss(w, x, y);
        self.matrix = matrix;
        p = ps;
        h = hs;
        residual = residuals;
        self.cooks = cooks;
        self.edf = edf;
        self.dev = dev;
        aic = dev+2*edf;
        bic = dev+log(n)*edf
    }
}
struct Cv {
    let lam: Double,
    folds: [Double],
    loss: Double,
    p: [Double],
    errors: Int
}
func crossValidate(_ d: Data, _ lam: Double, _ q: Int) -> Cv {
    let n = d.train.count;
    var losses = Array(repeating: 0.0, count: n), p = losses, folds = [Double](), errors = 0
    for fold in 0..<5 {
        let fit = (0..<n).filter {
            $0%5 != fold
        }, check = (0..<n).filter {
            $0%5 == fold
        }, rows = fit.map {
            d.expanded[$0]
        }, s = statistics(rows, q), x = rows.map {
            standardize($0, s, q)
        }, y = fit.map {
            d.y[$0]
        }, w = newton(x, y, lam).last!.1;
        var total = 0.0
        for i in check {
            let u = score(w, standardize(d.expanded[i], s, q));
            losses[i] = loss(u, d.y[i]);
            p[i] = probability(u);
            total += losses[i];
            if (p[i] >= d.threshold ? 1 : 0) != d.y[i] {
                errors += 1
            }
        };
        folds.append(total/Double(check.count))
    };
    return Cv(lam: lam, folds: folds, loss: losses.reduce(0, +)/Double(n), p: p, errors: errors)
}
struct Bin {
    var count = 0,
    total = 0.0,
    hits = 0
}
func bins(_ p: [Double], _ hits: [Int]) -> [Bin] {
    var out = Array(repeating: Bin(), count: 10);
    for(p, hit)in zip(p, hits) {
        let k = min(9, Int(floor(p*10)));
        out[k].count += 1;
        out[k].total += p;
        out[k].hits += hit
    };
    return out
}
func binLines(_ bins: [Bin], _ meanLabel: String, _ rateLabel: String) -> [String] {
    bins.enumerated().map {
        i, b in let mean = b.count == 0 ? "-" : f4(b.total/Double(b.count));
        return "bin \(fixed(Double(i)/10,1))-\(fixed(Double(i+1)/10,1)) count \(b.count) \(meanLabel) \(mean) \(rateLabel) \(ratio(b.hits,b.count))"
    }
}
func ece(_ b: [Bin], _ n: Int) -> Double {
    b.filter {
        $0.count>0
    }.reduce(0.0) {
        $0+abs($1.total-Double($1.hits))
    }
    /Double(n)
}
func terms(_ d: Data, _ w: [Double]) -> [String] {
    let orig = original(w, d.overall);
    return(["intercept"]+d.featureNames).enumerated().map {
        j, name in "term \(name) standardized \(f4(w[j])) original \(f4(orig[j]))"
    }
}
func weightsReport(_ d: Data, _ models: [Model], _ sm: [[Double]], _ inf: Influence, _ lam: Double) -> [[String]] {
    let p = d.tuples.count, n = d.train.count, r = (1...p).map {
        j in (1...p).map {
            k in d.x.reduce(0.0) {
                $0+$1[j]*$1[k]
            }
            /Double(n-1)
        }
    }, vif = inverse(r)
    var features = ["features \(d.names.count) degree \(d.settings.int("DEGREE")) expanded \(p)", "standardization"]
    for j in 0..<p {
        features.append("\(d.featureNames[j]) mean \(f6(d.overall.means[j])) sd \(f6(d.overall.sd[j])) vif \(f4(vif[j][j]))")
    };
    features.append("correlation");
    features += r.map {
        $0.map(f4).joined(separator: " ")
    }
    var parts = [features];
    let w = models[2].w
    for m in models {
        var lines = ["model \(m.name) lambda \(f4(lam))"]+terms(d, m.w);
        lines.append("norm \(f4(length(Array(m.w.dropFirst()))))");
        if m.name != "newton" {
            lines.append("distance_to_newton \(f6(length(zip(m.w,w).map{$0.0-$0.1})))")
        };
        parts.append(lines)
    }
    var coeff = ["coefficients newton lambda \(f4(lam))"]
    for(j, name)in (["intercept"]+d.featureNames).enumerated() {
        let se = sqrt(inf.matrix[j][j]/Double(n));
        coeff.append("\(name) weight \(f4(w[j])) se \(f4(se)) z \(f4(w[j]/se)) lower \(f4(w[j]-1.96*se)) upper \(f4(w[j]+1.96*se)) odds_ratio \(f4(exp(w[j])))")
    };
    parts.append(coeff)
    var lines = ["model softmax lambda \(f4(d.settings.real("SOFTMAX",2)))"];
    for(k, w)in sm.enumerated() {
        lines.append("class \(k)");
        lines += terms(d, w)
    };
    parts.append(lines);
    return parts
}
func binaryReport(_ d: Data, _ m: Model, _ lam: Double) -> [String] {
    let n = d.train.count, size = d.test.count, pos = d.ty.reduce(0, +), neg = size-pos, c = Confusion(m.test.pred, d.ty), tp = c.tp, fp = c.fp, tn = c.tn, fn = c.fn, points = roc(m.test.p, d.ty)
    var yd = 0, bf = 0, cheap = 0;
    func cost(_ i: Int) -> Int {
        d.settings.int("COST")*points[i].fp+d.settings.int("COST", 1)*(pos-points[i].tp)
    }
    for i in points.indices.dropFirst() {
        let a = points[i], y = points[yd], b = points[bf];
        if a.tp*neg-a.fp*pos>y.tp*neg-y.fp*pos {
            yd = i
        };
        if a.tp*(pos+b.tp+b.fp)>b.tp*(pos+a.tp+a.fp) {
            bf = i
        };
        if cost(i)<cost(cheap) {
            cheap = i
        }
    }
    var ap = 0.0, previous = 0;
    for p in points {
        ap += Double((p.tp-previous)*p.tp)/Double(p.tp+p.fp);
        previous = p.tp
    };
    ap /= Double(pos)
    let y = points[yd], b = points[bf], cheapest = points[cheap], brier = zip(m.test.p, d.ty).reduce(0.0) {
        $0+($1.0-Double($1.1))*($1.0-Double($1.1))
    }
    /Double(size)
    var lines = ["model \(m.name) lambda \(f4(lam))", "train correct \(m.train.correct)/\(n) accuracy \(ratio(m.train.correct,n))", "test tp \(tp) fp \(fp) tn \(tn) fn \(fn)", "test accuracy \(ratio(tp+tn,size)) precision \(ratio(tp,tp+fp)) recall \(ratio(tp,tp+fn)) specificity \(ratio(tn,tn+fp)) f1 \(ratio(2*tp,2*tp+fp+fn))", "log_loss \(f6(m.test.loss)) brier \(f6(brier))", "auc \(frac(m.test.aucValue)) average_precision \(f4(ap))", "youden threshold \(f6(y.threshold)) tpr \(ratio(y.tp,pos)) fpr \(ratio(y.fp,neg)) j \(ratio(y.tp*neg-y.fp*pos,pos*neg))", "best_f1 threshold \(f6(b.threshold)) precision \(ratio(b.tp,b.tp+b.fp)) recall \(ratio(b.tp,pos)) f1 \(ratio(2*b.tp,pos+b.tp+b.fp))", "min_cost threshold \(f6(cheapest.threshold)) cost \(cost(cheap)) fp \(cheapest.fp) fn \(pos-cheapest.tp)", "calibration"]
    let binned = bins(m.test.p, d.ty), filled = binned.filter {
        $0.count>0
    };
    lines += binLines(binned, "mean_probability", "positive_rate")
    let mce = filled.reduce(0.0) {
        max($0, abs($1.total/Double($1.count)-Double($1.hits)/Double($1.count)))
    }, hl = filled.reduce(0.0) {
        $0+(Double($1.hits)-$1.total)*(Double($1.hits)-$1.total)/($1.total*(1-$1.total/Double($1.count)))
    }
    lines.append("ece \(f4(ece(binned,size))) mce \(f4(mce)) hosmer_lemeshow \(f4(hl)) groups \(filled.count)");
    lines.append("gains")
    let order = (0..<size).sorted {
        m.test.p[$0] != m.test.p[$1] ? m.test.p[$0]>m.test.p[$1] : $0<$1
    }
    for g in 1...10 {
        let rows = g*size/10, hits = order.prefix(rows).reduce(0) {
            $0+d.ty[$1]
        };
        lines.append("decile \(g) rows \(rows) positives \(hits) gain \(ratio(hits,pos)) lift \(ratio(hits*size,rows*pos))")
    };
    return lines
}
func slope(_ d: Data, _ orig: [Double], _ values: [Double], _ base: Int) -> Double {
    var total = 0.0;
    for(j, t)in d.tuples.enumerated() {
        let count = t.filter {
            $0 == base
        }.count;
        if count == 0 {
            continue
        };
        var removed = false, product = 1.0;
        for i in t {
            if i == base && !removed {
                removed = true
            }else {
                product *= values[i]
            }
        };
        total += orig[j+1]*(Double(count)*product)
    };
    return total
}
func diagnostics(_ d: Data, _ m: Model, _ inf: Influence, _ lam: Double) -> [String] {
    let n = d.train.count, size = d.test.count, rate = Double(d.y.reduce(0, +))/Double(n), null = -(rate*log(rate)+(1-rate)*log(1-rate))
    var lines = ["diagnostics newton lambda \(f4(lam))", "fit null_loss \(f6(null)) train_loss \(f6(m.train.loss)) mcfadden_r2 \(f4(1-m.train.loss/null)) deviance \(f4(inf.dev)) edf \(f4(inf.edf)) aic \(f4(inf.aic)) bic \(f4(inf.bic))"]
    let order = (0..<n).sorted {
        inf.p[$0] != inf.p[$1] ? inf.p[$0]<inf.p[$1] : $0<$1
    };
    var groups = [String](), hl = 0.0
    for g in 1...10 {
        let ids = order[((g-1)*n/10)..<(g*n/10)], observed = ids.reduce(0) {
            $0+d.y[$1]
        }, expected = ids.reduce(0.0) {
            $0+inf.p[$1]
        }, diff = Double(observed)-expected;
        hl += diff*diff/(expected*(1-expected/Double(ids.count)));
        groups.append("group \(g) rows \(ids.count) observed \(observed) expected \(f4(expected))")
    }
    lines.append("hosmer_lemeshow_train groups 10 statistic \(f4(hl))");
    lines += groups;
    lines.append("newton_iterations")
    for t in 1...10 {
        let w = m.checkpoints[t-1].1, (g, step) = newtonDirection(w, d.x, d.y, lam), decrease = zip(g, step).reduce(0.0) {
            $0+$1.0*$1.1
        }
        /2;
        lines.append("iteration \(t) objective \(f6(objective(w,d.x,d.y,lam))) gradient_norm \(f6(length(g))) step_norm \(f6(length(step))) predicted_decrease \(f6(decrease))")
    }
    let orig = original(m.w, d.overall), means = d.means, centre = probability(score(m.w, d.vector(means)))
    for k in d.names.indices {
        let average = zip(d.train, inf.p).reduce(0.0) {
            $0+$1.1*(1-$1.1)*slope(d, orig, $1.0.values, k)
        }
        /Double(n), atMean = centre*(1-centre)*slope(d, orig, means, k);
        lines.append("marginal \(d.names[k]) average \(f4(average)) at_mean \(f4(atMean))")
    }
    for k in 1..<10 {
        let c = Confusion(predict(m.test.p, Double(k)/10), d.ty);
        lines.append("cut 0.\(k) positive \(c.tp+c.fp) tp \(c.tp) fp \(c.fp) precision \(ratio(c.tp,c.tp+c.fp)) recall \(ratio(c.tp,c.tp+c.fn)) accuracy \(ratio(c.tp+c.tn,size))")
    }
    let wrong = (0..<size).filter {
        m.test.pred[$0] != d.ty[$0]
    }.sorted {
        a, b in let x = abs(m.test.p[a]-d.threshold), y = abs(m.test.p[b]-d.threshold);
        return x != y ? x>y : a<b
    }
    for i in wrong.prefix(5) {
        lines.append("error \(d.test[i].id) actual \(d.ty[i]) probability \(f6(m.test.p[i]))")
    }
    let count = d.settings.int("BOOTSTRAP"), seed = d.settings.int("BOOTSTRAP", 1);
    var rng = Minstd(state: seed), samples = [(Int, Int)]()
    for _ in 0..<count {
        let picks = (0..<size).map {
            _ in rng.draw()%size
        };
        samples.append(auc(picks.map {
            m.test.p[$0]
        }, picks.map {
            d.ty[$0]
        }))
    }
    let values = samples.map {
        Double($0.0)/Double($0.1)
    }, mean = values.reduce(0, +)/Double(count), sd = sqrt(values.reduce(0.0) {
        $0+($1-mean)*($1-mean)
    }
    /Double(count-1)), tail = count/40
    samples.sort {
        Double($0.0)/Double($0.1)<Double($1.0)/Double($1.1)
    }
    lines.append("bootstrap resamples \(count) seed \(seed) auc_mean \(f4(mean)) auc_sd \(f4(sd)) lower \(frac(samples[tail])) upper \(frac(samples[count-tail-1]))")
    lines.append("influence effective_parameters \(f4(inf.edf)) large_residuals \(inf.residual.filter{abs($0)>2}.count)")
    let cooks = (0..<n).sorted {
        inf.cooks[$0] != inf.cooks[$1] ? inf.cooks[$0]>inf.cooks[$1] : $0<$1
    }
    for i in cooks.prefix(5) {
        lines.append("cook \(d.train[i].id) actual \(d.y[i]) probability \(f4(inf.p[i])) leverage \(f4(inf.h[i])) residual \(f4(inf.residual[i])) distance \(f4(inf.cooks[i]))")
    };
    return lines
}
func softmaxReport(_ d: Data, _ w: [[Double]], _ sp: [[Double]], _ pred: [Int], _ newtonModel: Model) -> [String] {
    let classes = d.classes, n = d.test.count;
    var table = Array(repeating: Array(repeating: 0, count: classes), count: classes)
    for(label, p)in zip(d.testLabels, pred) {
        table[label][p] += 1
    }
    let rows = table.map {
        $0.reduce(0, +)
    }, cols = (0..<classes).map {
        k in table.reduce(0) {
            $0+$1[k]
        }
    }
    var lines = ["softmax classes \(classes) lambda \(f4(d.settings.real("SOFTMAX",2))) iterations \(d.settings.int("SOFTMAX",1))", "confusion"]+table.map {
        $0.map(String.init).joined(separator: " ")
    }
    for k in 0..<classes {
        let y = d.testLabels.map {
            $0 == k ? 1 : 0
        }, scores = sp.map {
            $0[k]
        }, hits = table[k][k];
        lines.append("class \(k) precision \(ratio(hits,cols[k])) recall \(ratio(hits,rows[k])) f1 \(ratio(2*hits,cols[k]+rows[k])) auc \(frac(auc(scores,y)))")
    }
    let diagonal = (0..<classes).reduce(0) {
        $0+table[$1][$1]
    }, chance = (0..<classes).reduce(0) {
        $0+rows[$1]*cols[$1]
    }
    lines.append("accuracy \(ratio(diagonal,n)) kappa \(ratio(n*diagonal-chance,n*n-chance))")
    var squares = 0.0;
    for(p, y)in zip(sp, d.testLabels) {
        var total = 0.0;
        for(k, value)in p.enumerated() {
            let e = value-(k == y ? 1.0 : 0.0);
            total += e*e
        };
        squares += total
    }
    lines.append("log_loss \(f6(softmaxLoss(w,d.z,d.testLabels))) brier \(f6(squares/Double(n)))")
    let scores = sp.map {
        $0[d.settings.int("POSITIVE")]
    }, predicted = predict(scores, d.threshold), ll = zip(scores, d.ty).reduce(0.0) {
        $0-log($1.1 == 1 ? $1.0 : 1-$1.0)
    }
    /Double(n)
    lines.append("binary_view positive_class \(d.settings.int("POSITIVE")) auc \(frac(auc(scores,d.ty))) log_loss \(f6(ll)) accuracy \(ratio(equal(predicted,d.ty),n)) agreement_with_newton \(equal(predicted,newtonModel.test.pred))/\(n)")
    let confidence = zip(sp, pred).map {
        $0.0[$0.1]
    }, hits = zip(pred, d.testLabels).map {
        $0.0 == $0.1 ? 1 : 0
    }, b = bins(confidence, hits);
    lines.append("confidence");
    lines += binLines(b, "mean_confidence", "accuracy");
    lines.append("ece \(f4(ece(b,n)))");
    return lines
}
func writeLines(_ name: String, _ lines: [String]) throws {
    try(lines.joined(separator: "\n")+"\n").write(toFile: "output/"+name, atomically: true, encoding: .utf8)
}
func writeParts(_ name: String, _ parts: [[String]]) throws {
    try(parts.map {
        $0.joined(separator: "\n")
    }.joined(separator: "\n\n")+"\n").write(toFile: "output/"+name, atomically: true, encoding: .utf8)
}
func newtonWeights(_ x: [[Double]], _ y: [Int], _ lam: Double) -> [Double] {
    newton(x, y, lam).last!.1
}
let d = try Data(), s = d.settings, n = d.train.count, m = d.test.count, p = d.tuples.count, lambdas = s.values["LAMBDAS"]!.map {
    Double($0)!
}, cvs = lambdas.map {
    crossValidate(d, $0, p)
}
var selected = 0
for i in cvs.indices.dropFirst() {
    if cvs[i].loss <= cvs[selected].loss {
        selected = i
    }
}
let best = cvs[selected], lam = best.lam, foldMean = best.folds.reduce(0, +)/5, se = sqrt(best.folds.reduce(0.0) {
    $0+($1-foldMean)*($1-foldMean)
}
/4)/sqrt(5.0), oneSE = cvs.last {
    $0.loss <= best.loss+se
}!.lam
let models = [Model("gd", gradientDescent(d.x, d.y, lam, s.real("GD"), s.int("GD", 1)), d), Model("sgd", stochasticDescent(d.x, d.y, lam, s.real("SGD"), s.int("SGD", 1), s.int("SGD", 2), s.int("SGD", 3)), d), Model("newton", newton(d.x, d.y, lam), d)]
let newtonModel = models[2], smTrace = trainSoftmax(d.x, d.labels, d.classes, s.real("SOFTMAX", 2), s.real("SOFTMAX"), s.int("SOFTMAX", 1)), sm = smTrace.last!.1, smP = d.z.map {
    softmaxProbabilities(sm, $0)
}, smPred = smP.map(predictedClass), inf = Influence(newtonModel.w, d.x, d.y, lam)
var trace = ["optimizer,iteration,loss,gradient_norm,test_loss"], predictions = ["id,model,probability,predicted,actual"], rocLines = ["model,threshold,tpr,fpr,precision"]
let pos = d.ty.reduce(0, +), neg = m-pos
for model in models {
    for(t, w)in model.checkpoints {
        trace.append("\(model.name),\(t),\(f6(objective(w,d.x,d.y,lam))),\(f6(length(gradient(w,d.x,d.y,lam)))),\(f6(averageLoss(w,d.z,d.ty)))")
    }
    for j in 0..<m {
        predictions.append("\(d.test[j].id),\(model.name),\(f6(model.test.p[j])),\(model.test.pred[j]),\(d.ty[j])")
    }
    rocLines.append("\(model.name),inf,0.0000,0.0000,-")
    for point in roc(model.test.p, d.ty) {
        rocLines.append("\(model.name),\(f6(point.threshold)),\(ratio(point.tp,pos)),\(ratio(point.fp,neg)),\(ratio(point.tp,point.tp+point.fp))")
    }
}
for(t, w)in smTrace {
    let g = softmaxGradient(w, d.x, d.labels, s.real("SOFTMAX", 2));
    trace.append("softmax,\(t),\(f6(softmaxObjective(w,d.x,d.labels,s.real("SOFTMAX",2)))),\(f6(length(g.flatMap{$0}))),\(f6(softmaxLoss(w,d.z,d.testLabels)))")
}
for j in 0..<m {
    predictions.append("\(d.test[j].id),softmax,\(f6(smP[j][smPred[j]])),\(smPred[j]),\(d.testLabels[j])")
}
func classCounts(_ labels: [Int]) -> String {
    (0..<d.classes).map {
        k in String(labels.filter {
            $0 == k
        }.count)
    }.joined(separator: " ")
}
var parts = [["data train \(n) test \(m) base_features \(d.names.count) degree \(s.int("DEGREE")) features \(p)", "binary positive_class \(s.int("POSITIVE")) train \(d.y.reduce(0,+))/\(n) test \(pos)/\(m)", "classes \(d.classes) train \(classCounts(d.labels)) test \(classCounts(d.testLabels))"]]
var cv = ["cross_validation folds 5 newton_iterations 10"]
for c in cvs {
    cv.append("lambda \(f4(c.lam)) fold_loss \(c.folds.map(f6).joined(separator:" ")) cv_loss \(f6(c.loss)) errors \(c.errors)/\(n)")
}
cv.append("selected lambda \(f4(lam)) cv_loss \(f6(best.loss)) se \(f6(se)) lambda_1se \(f4(oneSE))")
let outOfFold = Confusion(predict(best.p, d.threshold), d.y)
cv.append("out_of_fold tp \(outOfFold.tp) fp \(outOfFold.fp) tn \(outOfFold.tn) fn \(outOfFold.fn) accuracy \(ratio(outOfFold.tp+outOfFold.tn,n)) auc \(frac(auc(best.p,d.y)))")
parts.append(cv)
var path = ["lambda_path"]
for a in lambdas {
    let w = newtonWeights(d.x, d.y, a), tr = Evaluation(w, d.x, d.y, d.threshold), te = Evaluation(w, d.z, d.ty, d.threshold);
    path.append("lambda \(f4(a)) objective \(f6(objective(w,d.x,d.y,a))) train_loss \(f6(tr.loss)) test_loss \(f6(te.loss)) train_accuracy \(ratio(tr.correct,n)) test_accuracy \(ratio(te.correct,m)) norm \(f4(length(Array(w.dropFirst()))))")
}
parts.append(path)
var degrees = ["degrees lambda \(f4(lam))"]
for degree in 1...s.int("DEGREE") {
    let q = d.tuples.filter {
        $0.count <= degree
    }.count, x = d.x.map {
        Array($0.prefix(q+1))
    }, z = d.z.map {
        Array($0.prefix(q+1))
    }, w = newtonWeights(x, d.y, lam), tr = Evaluation(w, x, d.y, d.threshold), te = Evaluation(w, z, d.ty, d.threshold), influence = Influence(w, x, d.y, lam);
    degrees.append("degree \(degree) features \(q) cv_loss \(f6(crossValidate(d,lam,q).loss)) train_loss \(f6(tr.loss)) test_loss \(f6(te.loss)) test_accuracy \(ratio(te.correct,m)) auc \(frac(te.aucValue)) edf \(f4(influence.edf)) aic \(f4(influence.aic)) bic \(f4(influence.bic))")
}
parts.append(degrees)
var learning = ["learning_curve lambda \(f4(lam))"]
for k in 1...4 {
    let size = k*n/4, rows = Array(d.expanded.prefix(size)), stats = statistics(rows, p), x = rows.map {
        standardize($0, stats, p)
    }, z = d.testExpanded.map {
        standardize($0, stats, p)
    }, y = Array(d.y.prefix(size)), w = newtonWeights(x, y, lam), tr = Evaluation(w, x, y, d.threshold), te = Evaluation(w, z, d.ty, d.threshold);
    learning.append("size \(size) train_loss \(f6(tr.loss)) test_loss \(f6(te.loss)) test_accuracy \(ratio(te.correct,m)) auc \(frac(te.aucValue))")
}
parts.append(learning)
for model in models {
    parts.append(binaryReport(d, model, lam))
}
var comparison = [String]()
for(a, b)in [(0, 1), (0, 2), (1, 2)] {
    let first = models[a], second = models[b];
    var onlyFirst = 0, onlySecond = 0;
    for j in 0..<m {
        let a = first.test.pred[j], b = second.test.pred[j], y = d.ty[j];
        if a == y && b != y {
            onlyFirst += 1
        }else if b == y && a != y {
            onlySecond += 1
        }
    };
    let gap = abs(onlyFirst-onlySecond)-1;
    comparison.append("agreement \(first.name) \(second.name) same \(equal(first.test.pred,second.test.pred))/\(m) only_first \(onlyFirst) only_second \(onlySecond) mcnemar \(ratio(gap*gap,onlyFirst+onlySecond))")
}
parts.append(comparison)
parts.append(diagnostics(d, newtonModel, inf, lam))
let repeats = s.int("PERMUTATION")
var rng = Minstd(state: s.int("PERMUTATION", 1)), importance = ["importance repeats \(repeats) seed \(s.int("PERMUTATION",1))", "baseline log_loss \(f6(newtonModel.test.loss)) auc \(frac(newtonModel.test.aucValue)) softmax_accuracy \(ratio(equal(smPred,d.testLabels),m))"]
for k in d.names.indices {
    var losses = [Double](), aucTotal = 0, correct = 0
    for _ in 0..<repeats {
        var order = Array(0..<m);
        rng.shuffle(&order);
        let vectors = d.test.enumerated().map {
            j, r in var v = r.values;
            v[k] = d.test[order[j]].values[k];
            return d.vector(v)
        };
        losses.append(averageLoss(newtonModel.w, vectors, d.ty));
        aucTotal += auc(probabilities(newtonModel.w, vectors), d.ty).0;
        let pred = vectors.map {
            predictedClass(softmaxProbabilities(sm, $0))
        };
        correct += equal(pred, d.testLabels)
    }
    importance.append("feature \(d.names[k]) log_loss_increase \(f6(losses.reduce(0,+)/Double(repeats)-newtonModel.test.loss)) auc \(fraction(aucTotal,repeats*newtonModel.test.aucValue.1)) softmax_accuracy \(ratio(correct,repeats*m))")
}
parts.append(importance)
var profiles = ["profiles"]
for k in d.names.indices {
    let low = d.train.map {
        $0.values[k]
    }.min()!, high = d.train.map {
        $0.values[k]
    }.max()!;
    for g in 0...4 {
        var v = d.means;
        v[k] = low+(high-low)*Double(g)/4;
        let x = d.vector(v), ps = softmaxProbabilities(sm, x);
        profiles.append("profile \(d.names[k]) value \(f4(v[k])) newton \(f4(probability(score(newtonModel.w,x)))) softmax \(ps.map(f4).joined(separator:" "))")
    }
}
parts.append(profiles)
parts.append(softmaxReport(d, sm, smP, smPred, newtonModel))
let lm = s.real("SOFTMAX", 2)
var ovr = ["one_vs_rest lambda \(f4(lm)) newton_iterations 10"], classProb = [[Double]]()
for k in 0..<d.classes {
    let y = d.labels.map {
        $0 == k ? 1 : 0
    }, ty = d.testLabels.map {
        $0 == k ? 1 : 0
    }, w = newtonWeights(d.x, y, lm), ps = probabilities(w, d.z);
    ovr.append("class \(k) objective \(f6(objective(w,d.x,y,lm))) auc \(frac(auc(ps,ty)))");
    classProb.append(ps)
}
let ovrPred = (0..<m).map {
    j in predictedClass(classProb.map {
        $0[j]
    })
}
ovr.append("accuracy \(ratio(equal(ovrPred,d.testLabels),m)) agreement_with_softmax \(equal(ovrPred,smPred))/\(m)")
parts.append(ovr)
let width = s.int("MAP"), height = s.int("MAP", 1), low = (0..<2).map {
    k in d.train.map {
        $0.values[k]
    }.min()!
}, high = (0..<2).map {
    k in d.train.map {
        $0.values[k]
    }.max()!
}
var cells = Array(repeating: 0, count: d.classes), classRows = [String](), probabilityRows = [String]()
for r in 0..<height {
    var classRow = "", probabilityRow = "";
    for c in 0..<width {
        var v = d.means;
        v[0] = low[0]+(Double(c)+0.5)*(high[0]-low[0])/Double(width);
        v[1] = high[1]-(Double(r)+0.5)*(high[1]-low[1])/Double(height);
        let x = d.vector(v), pred = predictedClass(softmaxProbabilities(sm, x));
        cells[pred] += 1;
        classRow += String(pred);
        probabilityRow += String(min(9, Int(floor(probability(score(newtonModel.w, x))*10))))
    };
    classRows.append(classRow);
    probabilityRows.append(probabilityRow)
}
parts.append(["map \(d.names[0]) \(d.names[1]) width \(width) height \(height)", "softmax_classes"]+classRows+["cells "+cells.map(String.init).joined(separator: " "), "newton_probability"]+probabilityRows)
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
try writeParts("weights.txt", weightsReport(d, models, sm, inf, lam))
try writeLines("loss_trace.csv", trace)
try writeLines("predictions.csv", predictions)
try writeParts("evaluation.txt", parts)
try writeLines("roc.csv", rocLines)
