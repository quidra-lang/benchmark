mod dataset;
mod logistic;
mod optimizers;
mod softmax;
mod metrics;
use std::{
    fs, io
};
use dataset::{
    Example, Settings, Statistics, read_examples, expansion_tuples, expanded_values, statistics, standardize
};
use logistic::{
    score, probability, loss, average_loss, objective, gradient, hessian
};
use optimizers::{
    Minstd, Checkpoints, cholesky, solve, newton, newton_direction, gd, sgd
};
use metrics::{
    Confusion, auc, roc, fixed, ratio, fraction
};
fn f4(v: f64) -> String {
    fixed(v, 4)
}
fn f6(v: f64) -> String {
    fixed(v, 6)
}
fn frac(p: (i64, i64)) -> String {
    fraction(p.0, p.1)
}
fn sum(xs: impl IntoIterator<Item = f64>) -> f64 {
    xs.into_iter().fold(0.0, |s, x|s+x)
}
fn length(xs: impl IntoIterator<Item = f64>) -> f64 {
    sum(xs.into_iter().map(|x|x*x)).sqrt()
}
fn predict(p: &[f64], threshold: f64) -> Vec<usize> {
    p.iter().map(|&p|usize::from(p >= threshold)).collect()
}
fn equal(a: &[usize], b: &[usize]) -> i64 {
    a.iter().zip(b).filter(|(a, b)|a == b).count()as i64
}
fn probabilities(w: &[f64], x: &[Vec<f64>]) -> Vec<f64> {
    x.iter().map(|v|probability(score(w, v))).collect()
}
fn inverse(a: &[Vec<f64>]) -> Vec<Vec<f64>> {
    let l = cholesky(a);
    let n = a.len();
    let mut out = vec![vec![0.0; n]; n];
    for k in 0..n {
        let mut unit = vec![0.0; n];
        unit[k] = 1.0;
        let x = solve(&l, &unit);
        for j in 0..n {
            out[j][k] = x[j]
        }
    }
    out
}
fn original(w: &[f64], s: &Statistics) -> Vec<f64> {
    let scaled = w[1..].iter().enumerate().map(|(j, w)|w/s.sd[j]).collect::<Vec<_>>();
    let mut out = vec![w[0]-sum(scaled.iter().zip(&s.means).map(|(a, b)|a*b))];
    out.extend(scaled);
    out
}
struct Data {
    names: Vec<String>,
    train: Vec<Example>,
    test: Vec<Example>,
    settings: Settings,
    tuples: Vec<Vec<usize>>,
    feature_names: Vec<String>,
    overall: Statistics,
    expanded: Vec<Vec<f64>>,
    test_expanded: Vec<Vec<f64>>,
    x: Vec<Vec<f64>>,
    z: Vec<Vec<f64>>,
    y: Vec<usize>,
    ty: Vec<usize>,
    labels: Vec<usize>,
    test_labels: Vec<usize>,
    classes: usize
}
impl Data {
    fn read() -> io::Result<Self> {
        let(names, train) = read_examples("train")?;
        let(_, test) = read_examples("test")?;
        let settings = Settings::read()?;
        let tuples = expansion_tuples(names.len(), settings.int("DEGREE", 0));
        let feature_names = tuples.iter().map(|t|t.iter().map(|&i|names[i].clone()).collect::<Vec<_>>().join("*")).collect();
        let expanded = train.iter().map(|r|expanded_values(&tuples, &r.values)).collect::<Vec<_>>();
        let test_expanded = test.iter().map(|r|expanded_values(&tuples, &r.values)).collect::<Vec<_>>();
        let overall = statistics(&expanded, tuples.len());
        let x = expanded.iter().map(|v|standardize(v, &overall, tuples.len())).collect();
        let z = test_expanded.iter().map(|v|standardize(v, &overall, tuples.len())).collect();
        let labels = train.iter().map(|r|r.label).collect::<Vec<_>>();
        let test_labels = test.iter().map(|r|r.label).collect::<Vec<_>>();
        let classes = labels.iter().max().unwrap()+1;
        let c = settings.int("POSITIVE", 0);
        let y = labels.iter().map(|&k|usize::from(k == c)).collect();
        let ty = test_labels.iter().map(|&k|usize::from(k == c)).collect();
        Ok(Self {
            names,
            train,
            test,
            settings,
            tuples,
            feature_names,
            overall,
            expanded,
            test_expanded,
            x,
            z,
            y,
            ty,
            labels,
            test_labels,
            classes
        })
    }
    fn vector(&self, values: &[f64]) -> Vec<f64> {
        standardize(&expanded_values(&self.tuples, values), &self.overall, self.tuples.len())
    }
    fn means(&self) -> Vec<f64> {
        self.overall.means[..self.names.len()].to_vec()
    }
    fn threshold(&self) -> f64 {
        self.settings.real("THRESHOLD", 0)
    }
}
struct Evaluation {
    p: Vec<f64>,
    pred: Vec<usize>,
    loss: f64,
    correct: i64,
    auc: (i64, i64)
}
impl Evaluation {
    fn new(w: &[f64], x: &[Vec<f64>], y: &[usize], threshold: f64) -> Self {
        let p = probabilities(w, x);
        let pred = predict(&p, threshold);
        let correct = equal(&pred, y);
        let auc = auc(&p, y);
        Self {
            p,
            pred,
            correct,
            auc,
            loss: average_loss(w, x, y)
        }
    }
}
struct Model {
    name: &'static str,
    checkpoints: Checkpoints,
    w: Vec<f64>,
    train: Evaluation,
    test: Evaluation
}
impl Model {
    fn new(name: &'static str, checkpoints: Checkpoints, d: &Data) -> Self {
        let w = checkpoints.last().unwrap().1.clone();
        let train = Evaluation::new(&w, &d.x, &d.y, d.threshold());
        let test = Evaluation::new(&w, &d.z, &d.ty, d.threshold());
        Self {
            name,
            checkpoints,
            w,
            train,
            test
        }
    }
}
struct Influence {
    matrix: Vec<Vec<f64>>,
    p: Vec<f64>,
    h: Vec<f64>,
    residual: Vec<f64>,
    cooks: Vec<f64>,
    edf: f64,
    dev: f64,
    aic: f64,
    bic: f64
}
impl Influence {
    fn new(w: &[f64], x: &[Vec<f64>], y: &[usize], lam: f64) -> Self {
        let matrix = inverse(&hessian(w, x, lam));
        let(mut p, mut h, mut residual, mut cooks) = (vec![], vec![], vec![], vec![]);
        let n = x.len()as f64;
        for(v, &y)in x.iter().zip(y) {
            let pi = probability(score(w, v));
            let variance = pi*(1.0-pi);
            let mut quadratic = 0.0;
            for j in 0..w.len() {
                for k in 0..w.len() {
                    quadratic += v[j]*matrix[j][k]*v[k]
                }
            }
            let leverage = variance*quadratic/n;
            let pearson = (y as f64-pi)/variance.sqrt();
            p.push(pi);
            h.push(leverage);
            residual.push(pearson/(1.0-leverage).sqrt());
            cooks.push(pearson*pearson*leverage/(w.len()as f64*((1.0-leverage)*(1.0-leverage))));
        }
        let edf = sum(h.iter().copied());
        let dev = 2.0*n*average_loss(w, x, y);
        Self {
            matrix,
            p,
            h,
            residual,
            cooks,
            edf,
            dev,
            aic: dev+2.0*edf,
            bic: dev+n.ln()*edf
        }
    }
}
struct Cv {
    lam: f64,
    folds: Vec<f64>,
    loss: f64,
    p: Vec<f64>,
    errors: usize
}
fn cross_validate(d: &Data, lam: f64, q: usize) -> Cv {
    let n = d.train.len();
    let mut losses = vec![0.0; n];
    let mut p = vec![0.0; n];
    let mut folds = vec![];
    let mut errors = 0;
    for f in 0..5 {
        let fit = (0..n).filter(|&i|i%5 != f).collect::<Vec<_>>();
        let check = (0..n).filter(|&i|i%5 == f).collect::<Vec<_>>();
        let rows = fit.iter().map(|&i|d.expanded[i].clone()).collect::<Vec<_>>();
        let s = statistics(&rows, q);
        let x = rows.iter().map(|v|standardize(v, &s, q)).collect::<Vec<_>>();
        let y = fit.iter().map(|&i|d.y[i]).collect::<Vec<_>>();
        let w = newton(&x, &y, lam).last().unwrap().1.clone();
        let mut total = 0.0;
        for &i in &check {
            let u = score(&w, &standardize(&d.expanded[i], &s, q));
            losses[i] = loss(u, d.y[i]);
            p[i] = probability(u);
            total += losses[i];
            if usize::from(p[i] >= d.threshold()) != d.y[i] {
                errors += 1
            }
        }
        folds.push(total/check.len()as f64);
    }
    Cv {
        lam,
        folds,
        loss: sum(losses)/n as f64,
        p,
        errors
    }
}
#[derive(Clone, Default)]
struct Bin {
    count: i64,
    total: f64,
    hits: i64
}
fn bins(p: &[f64], hits: &[usize]) -> Vec<Bin> {
    let mut out = vec![Bin::default(); 10];
    for(&p, &hit)in p.iter().zip(hits) {
        let k = (p*10.0).floor().min(9.0)as usize;
        out[k].count += 1;
        out[k].total += p;
        out[k].hits += hit as i64;
    }
    out
}
fn bin_lines(b: &[Bin], mean_label: &str, rate_label: &str) -> Vec<String> {
    b.iter().enumerate().map(|(i, b)|format!("bin {}-{} count {} {mean_label} {} {rate_label} {}", fixed(i as f64/10.0, 1), fixed((i+1)as f64/10.0, 1), b.count, if b.count == 0 {
        "-".into()
    }else {
        f4(b.total/b.count as f64)
    }, ratio(b.hits, b.count))).collect()
}
fn ece(b: &[Bin], n: usize) -> f64 {
    sum(b.iter().filter(|b|b.count>0).map(|b|(b.total-b.hits as f64).abs()))/n as f64
}
fn terms(d: &Data, w: &[f64]) -> Vec<String> {
    let orig = original(w, &d.overall);
    std::iter::once("intercept".to_owned()).chain(d.feature_names.clone()).enumerate().map(|(j, name)|format!("term {name} standardized {} original {}", f4(w[j]), f4(orig[j]))).collect()
}
fn weights_report(d: &Data, models: &[Model], sm: &[Vec<f64>], inf: &Influence, lam: f64) -> Vec<Vec<String>> {
    let p = d.tuples.len();
    let n = d.train.len();
    let r = (1..=p).map(|j|(1..=p).map(|k|sum(d.x.iter().map(|v|v[j]*v[k]))/(n-1)as f64).collect::<Vec<_>>()).collect::<Vec<_>>();
    let vif = inverse(&r);
    let mut features = vec![format!("features {} degree {} expanded {p}", d.names.len(), d.settings.int("DEGREE", 0)), "standardization".into()];
    for j in 0..p {
        features.push(format!("{} mean {} sd {} vif {}", d.feature_names[j], f6(d.overall.means[j]), f6(d.overall.sd[j]), f4(vif[j][j])))
    }
    features.push("correlation".into());
    features.extend(r.iter().map(|r|r.iter().map(|&v|f4(v)).collect::<Vec<_>>().join(" ")));
    let mut parts = vec![features];
    let w = &models[2].w;
    for m in models {
        let mut lines = vec![format!("model {} lambda {}", m.name, f4(lam))];
        lines.extend(terms(d, &m.w));
        lines.push(format!("norm {}", f4(length(m.w[1..].iter().copied()))));
        if m.name != "newton" {
            lines.push(format!("distance_to_newton {}", f6(length(m.w.iter().zip(w).map(|(a, b)|a-b)))))
        }
        parts.push(lines)
    }
    let mut coeff = vec![format!("coefficients newton lambda {}", f4(lam))];
    for(j, name)in std::iter::once("intercept".to_owned()).chain(d.feature_names.clone()).enumerate() {
        let se = (inf.matrix[j][j]/n as f64).sqrt();
        coeff.push(format!("{name} weight {} se {} z {} lower {} upper {} odds_ratio {}", f4(w[j]), f4(se), f4(w[j]/se), f4(w[j]-1.96*se), f4(w[j]+1.96*se), f4(w[j].exp())))
    }
    parts.push(coeff);
    let mut lines = vec![format!("model softmax lambda {}", f4(d.settings.real("SOFTMAX", 2)))];
    for(k, w)in sm.iter().enumerate() {
        lines.push(format!("class {k}"));
        lines.extend(terms(d, w));
    }
    parts.push(lines);
    parts
}
fn binary_report(d: &Data, m: &Model, lam: f64) -> Vec<String> {
    let n = d.train.len()as i64;
    let size = d.test.len()as i64;
    let pos = d.ty.iter().sum::<usize>()as i64;
    let neg = size-pos;
    let c = Confusion::new(&m.test.pred, &d.ty);
    let(tp, fp, tn, fn_) = (c.tp, c.fp, c.tn, c.fn_);
    let points = roc(&m.test.p, &d.ty);
    let(mut yd, mut bf, mut cheap) = (0, 0, 0);
    let cost = |i: usize|d.settings.int("COST", 0)as i64*points[i].fp+d.settings.int("COST", 1)as i64*(pos-points[i].tp);
    for i in 1..points.len() {
        let a = &points[i];
        let b = &points[yd];
        if a.tp*neg-a.fp*pos>b.tp*neg-b.fp*pos {
            yd = i
        }
        let b = &points[bf];
        if a.tp*(pos+b.tp+b.fp)>b.tp*(pos+a.tp+a.fp) {
            bf = i
        }
        if cost(i)<cost(cheap) {
            cheap = i
        }
    }
    let mut ap = 0.0;
    let mut prev = 0;
    for p in &points {
        ap += ((p.tp-prev)*p.tp)as f64/(p.tp+p.fp)as f64;
        prev = p.tp;
    }
    ap /= pos as f64;
    let y = &points[yd];
    let b = &points[bf];
    let cheapest = &points[cheap];
    let brier = sum(m.test.p.iter().zip(&d.ty).map(|(p, &y)|(p-y as f64)*(p-y as f64)))/size as f64;
    let mut lines = vec![format!("model {} lambda {}", m.name, f4(lam)), format!("train correct {}/{n} accuracy {}", m.train.correct, ratio(m.train.correct, n)), format!("test tp {tp} fp {fp} tn {tn} fn {fn_}"), format!("test accuracy {} precision {} recall {} specificity {} f1 {}", ratio(tp+tn, size), ratio(tp, tp+fp), ratio(tp, tp+fn_), ratio(tn, tn+fp), ratio(2*tp, 2*tp+fp+fn_)), format!("log_loss {} brier {}", f6(m.test.loss), f6(brier)), format!("auc {} average_precision {}", frac(m.test.auc), f4(ap)), format!("youden threshold {} tpr {} fpr {} j {}", f6(y.threshold), ratio(y.tp, pos), ratio(y.fp, neg), ratio(y.tp*neg-y.fp*pos, pos*neg)), format!("best_f1 threshold {} precision {} recall {} f1 {}", f6(b.threshold), ratio(b.tp, b.tp+b.fp), ratio(b.tp, pos), ratio(2*b.tp, pos+b.tp+b.fp)), format!("min_cost threshold {} cost {} fp {} fn {}", f6(cheapest.threshold), cost(cheap), cheapest.fp, pos-cheapest.tp), "calibration".into()];
    let bins = bins(&m.test.p, &d.ty);
    lines.extend(bin_lines(&bins, "mean_probability", "positive_rate"));
    let filled = bins.iter().filter(|b|b.count>0).collect::<Vec<_>>();
    let mce = filled.iter().fold(0.0f64, |s, b|s.max((b.total/b.count as f64-b.hits as f64/b.count as f64).abs()));
    let hl = sum(filled.iter().map(|b|(b.hits as f64-b.total)*(b.hits as f64-b.total)/(b.total*(1.0-b.total/b.count as f64))));
    lines.push(format!("ece {} mce {} hosmer_lemeshow {} groups {}", f4(ece(&bins, d.test.len())), f4(mce), f4(hl), filled.len()));
    lines.push("gains".into());
    let mut order = (0..d.test.len()).collect::<Vec<_>>();
    order.sort_by(|&a, &b|m.test.p[b].total_cmp(&m.test.p[a]).then(a.cmp(&b)));
    for g in 1..=10 {
        let rows = g*d.test.len()/10;
        let hits = order[..rows].iter().map(|&i|d.ty[i]).sum::<usize>()as i64;
        lines.push(format!("decile {g} rows {rows} positives {hits} gain {} lift {}", ratio(hits, pos), ratio(hits*size, rows as i64*pos)))
    }
    lines
}
fn slope(d: &Data, orig: &[f64], values: &[f64], base: usize) -> f64 {
    let mut total = 0.0;
    for(j, t)in d.tuples.iter().enumerate() {
        let occurrences = t.iter().filter(| && i|i == base).count();
        if occurrences == 0 {
            continue
        }
        let mut removed = false;
        let mut product = 1.0;
        for &i in t {
            if i == base && !removed {
                removed = true
            }else {
                product *= values[i]
            }
        }
        total += orig[j+1]*(occurrences as f64*product);
    }
    total
}
fn diagnostics(d: &Data, m: &Model, inf: &Influence, lam: f64) -> Vec<String> {
    let n = d.train.len();
    let size = d.test.len();
    let rate = d.y.iter().sum::<usize>()as f64/n as f64;
    let null = -(rate*rate.ln()+(1.0-rate)*(1.0-rate).ln());
    let mut lines = vec![format!("diagnostics newton lambda {}", f4(lam)), format!("fit null_loss {} train_loss {} mcfadden_r2 {} deviance {} edf {} aic {} bic {}", f6(null), f6(m.train.loss), f4(1.0-m.train.loss/null), f4(inf.dev), f4(inf.edf), f4(inf.aic), f4(inf.bic))];
    let mut order = (0..n).collect::<Vec<_>>();
    order.sort_by(|&a, &b|inf.p[a].total_cmp(&inf.p[b]).then(a.cmp(&b)));
    let mut groups = vec![];
    let mut hl = 0.0;
    for g in 1..=10 {
        let ids = &order[(g-1)*n/10..g*n/10];
        let observed = ids.iter().map(|&i|d.y[i]).sum::<usize>();
        let expected = sum(ids.iter().map(|&i|inf.p[i]));
        let diff = observed as f64-expected;
        hl += diff*diff/(expected*(1.0-expected/ids.len()as f64));
        groups.push(format!("group {g} rows {} observed {observed} expected {}", ids.len(), f4(expected)));
    }
    lines.push(format!("hosmer_lemeshow_train groups 10 statistic {}", f4(hl)));
    lines.extend(groups);
    lines.push("newton_iterations".into());
    for t in 1..=10 {
        let w = &m.checkpoints[t-1].1;
        let(g, step) = newton_direction(w, &d.x, &d.y, lam);
        lines.push(format!("iteration {t} objective {} gradient_norm {} step_norm {} predicted_decrease {}", f6(objective(w, &d.x, &d.y, lam)), f6(length(g.iter().copied())), f6(length(step.iter().copied())), f6(sum(g.iter().zip(&step).map(|(g, s)|g*s))/2.0)));
    }
    let orig = original(&m.w, &d.overall);
    let means = d.means();
    let centre = probability(score(&m.w, &d.vector(&means)));
    for k in 0..d.names.len() {
        let average = sum(d.train.iter().zip(&inf.p).map(|(r, &p)|p*(1.0-p)*slope(d, &orig, &r.values, k)))/n as f64;
        let at_mean = centre*(1.0-centre)*slope(d, &orig, &means, k);
        lines.push(format!("marginal {} average {} at_mean {}", d.names[k], f4(average), f4(at_mean)));
    }
    for k in 1..10 {
        let c = Confusion::new(&predict(&m.test.p, k as f64/10.0), &d.ty);
        lines.push(format!("cut 0.{k} positive {} tp {} fp {} precision {} recall {} accuracy {}", c.tp+c.fp, c.tp, c.fp, ratio(c.tp, c.tp+c.fp), ratio(c.tp, c.tp+c.fn_), ratio(c.tp+c.tn, size as i64)));
    }
    let mut wrong = (0..size).filter(|&i|m.test.pred[i] != d.ty[i]).collect::<Vec<_>>();
    wrong.sort_by(|&a, &b|(m.test.p[b]-d.threshold()).abs().total_cmp(&(m.test.p[a]-d.threshold()).abs()).then(a.cmp(&b)));
    for &i in wrong.iter().take(5) {
        lines.push(format!("error {} actual {} probability {}", d.test[i].id, d.ty[i], f6(m.test.p[i])))
    }
    let count = d.settings.int("BOOTSTRAP", 0);
    let seed = d.settings.int("BOOTSTRAP", 1);
    let mut rng = Minstd {
        state: seed as i64
    };
    let mut samples = vec![];
    for _ in 0..count {
        let picks = (0..size).map(|_|rng.draw()%size).collect::<Vec<_>>();
        samples.push(auc(&picks.iter().map(|&i|m.test.p[i]).collect::<Vec<_>>(), &picks.iter().map(|&i|d.ty[i]).collect::<Vec<_>>()));
    }
    let values = samples.iter().map(|&(a, b)|a as f64/b as f64).collect::<Vec<_>>();
    let mean = sum(values.iter().copied())/count as f64;
    let sd = (sum(values.iter().map(|v|(v-mean)*(v-mean)))/(count-1)as f64).sqrt();
    samples.sort_by(|&(a, b), &(c, d)|(a as f64/b as f64).total_cmp(&(c as f64/d as f64)));
    let tail = count/40;
    lines.push(format!("bootstrap resamples {count} seed {seed} auc_mean {} auc_sd {} lower {} upper {}", f4(mean), f4(sd), frac(samples[tail]), frac(samples[count-tail-1])));
    lines.push(format!("influence effective_parameters {} large_residuals {}", f4(inf.edf), inf.residual.iter().filter(|r|r.abs()>2.0).count()));
    let mut order = (0..n).collect::<Vec<_>>();
    order.sort_by(|&a, &b|inf.cooks[b].total_cmp(&inf.cooks[a]).then(a.cmp(&b)));
    for &i in order.iter().take(5) {
        lines.push(format!("cook {} actual {} probability {} leverage {} residual {} distance {}", d.train[i].id, d.y[i], f4(inf.p[i]), f4(inf.h[i]), f4(inf.residual[i]), f4(inf.cooks[i])))
    }
    lines
}
fn softmax_report(d: &Data, w: &[Vec<f64>], sp: &[Vec<f64>], pred: &[usize], newton: &Model) -> Vec<String> {
    let k = d.classes;
    let n = d.test.len()as i64;
    let mut table = vec![vec![0i64; k]; k];
    for(&label, &p)in d.test_labels.iter().zip(pred) {
        table[label][p] += 1
    }
    let rows = table.iter().map(|r|r.iter().sum::<i64>()).collect::<Vec<_>>();
    let cols = (0..k).map(|j|table.iter().map(|r|r[j]).sum::<i64>()).collect::<Vec<_>>();
    let mut lines = vec![format!("softmax classes {k} lambda {} iterations {}", f4(d.settings.real("SOFTMAX", 2)), d.settings.int("SOFTMAX", 1)), "confusion".into()];
    lines.extend(table.iter().map(|r|r.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")));
    for c in 0..k {
        let y = d.test_labels.iter().map(|&y|usize::from(y == c)).collect::<Vec<_>>();
        let scores = sp.iter().map(|p|p[c]).collect::<Vec<_>>();
        lines.push(format!("class {c} precision {} recall {} f1 {} auc {}", ratio(table[c][c], cols[c]), ratio(table[c][c], rows[c]), ratio(2*table[c][c], cols[c]+rows[c]), frac(auc(&scores, &y))));
    }
    let diagonal = (0..k).map(|c|table[c][c]).sum::<i64>();
    let chance = (0..k).map(|c|rows[c]*cols[c]).sum::<i64>();
    lines.push(format!("accuracy {} kappa {}", ratio(diagonal, n), ratio(n*diagonal-chance, n*n-chance)));
    let brier = sum(sp.iter().zip(&d.test_labels).map(|(p, &y)|sum(p.iter().enumerate().map(|(k, &p)| {
        let e = p-if k == y {
            1.0
        }else {
            0.0
        }; e*e
    }))))/n as f64;
    lines.push(format!("log_loss {} brier {}", f6(softmax::average_loss(w, &d.z, &d.test_labels)), f6(brier)));
    let scores = sp.iter().map(|p|p[d.settings.int("POSITIVE", 0)]).collect::<Vec<_>>();
    let predicted = predict(&scores, d.threshold());
    let ll = sum(scores.iter().zip(&d.ty).map(|(&p, &y)|-(if y == 1 {
        p
    }else {
        1.0-p
    }).ln()))/n as f64;
    lines.push(format!("binary_view positive_class {} auc {} log_loss {} accuracy {} agreement_with_newton {}/{n}", d.settings.int("POSITIVE", 0), frac(auc(&scores, &d.ty)), f6(ll), ratio(equal(&predicted, &d.ty), n), equal(&predicted, &newton.test.pred)));
    let confidence = sp.iter().zip(pred).map(|(p, &k)|p[k]).collect::<Vec<_>>();
    let hits = pred.iter().zip(&d.test_labels).map(|(a, b)|usize::from(a == b)).collect::<Vec<_>>();
    let b = bins(&confidence, &hits);
    lines.push("confidence".into());
    lines.extend(bin_lines(&b, "mean_confidence", "accuracy"));
    lines.push(format!("ece {}", f4(ece(&b, d.test.len()))));
    lines
}
fn write_lines(name: &str, lines: &[String]) -> io::Result<()> {
    fs::write(format!("output/{name}"), lines.join("\n")+"\n")
}
fn write_parts(name: &str, parts: Vec<Vec<String>>) -> io::Result<()> {
    let text = parts.iter().map(|p|p.join("\n")).collect::<Vec<_>>().join("\n\n")+"\n";
    fs::write(format!("output/{name}"), text)
}
fn main() -> io::Result<()> {
    let d = Data::read()?;
    let s = &d.settings;
    let n = d.train.len();
    let m = d.test.len();
    let p = d.tuples.len();
    let lambdas = s.values["LAMBDAS"].iter().map(|v|v.parse::<f64>().unwrap()).collect::<Vec<_>>();
    let cvs = lambdas.iter().map(|&lam|cross_validate(&d, lam, p)).collect::<Vec<_>>();
    let mut selected = 0;
    for i in 1..cvs.len() {
        if cvs[i].loss <= cvs[selected].loss {
            selected = i
        }
    }
    let best = &cvs[selected];
    let lam = best.lam;
    let mean = sum(best.folds.iter().copied())/5.0;
    let se = (sum(best.folds.iter().map(|v|(v-mean)*(v-mean)))/4.0).sqrt()/5f64.sqrt();
    let one_se = cvs.iter().filter(|c|c.loss <= best.loss+se).last().unwrap().lam;
    let models = vec![Model::new("gd", gd(&d.x, &d.y, lam, s.real("GD", 0), s.int("GD", 1)), &d), Model::new("sgd", sgd(&d.x, &d.y, lam, s.real("SGD", 0), s.int("SGD", 1), s.int("SGD", 2), s.int("SGD", 3)as i64), &d), Model::new("newton", newton(&d.x, &d.y, lam), &d)];
    let newton = &models[2];
    let sm_trace = softmax::train(&d.x, &d.labels, d.classes, s.real("SOFTMAX", 2), s.real("SOFTMAX", 0), s.int("SOFTMAX", 1));
    let sm = &sm_trace.last().unwrap().1;
    let sm_p = d.z.iter().map(|v|softmax::probabilities(sm, v)).collect::<Vec<_>>();
    let sm_pred = sm_p.iter().map(|p|softmax::predicted(p)).collect::<Vec<_>>();
    let inf = Influence::new(&newton.w, &d.x, &d.y, lam);
    let mut trace = vec!["optimizer,iteration,loss,gradient_norm,test_loss".into()];
    let mut predictions = vec!["id,model,probability,predicted,actual".into()];
    let mut roc_lines = vec!["model,threshold,tpr,fpr,precision".into()];
    let pos = d.ty.iter().sum::<usize>()as i64;
    let neg = m as i64-pos;
    for model in &models {
        for(t, w)in &model.checkpoints {
            trace.push(format!("{},{t},{},{},{}", model.name, f6(objective(w, &d.x, &d.y, lam)), f6(length(gradient(w, &d.x, &d.y, lam))), f6(average_loss(w, &d.z, &d.ty))));
        }
        for j in 0..m {
            predictions.push(format!("{},{},{},{},{}", d.test[j].id, model.name, f6(model.test.p[j]), model.test.pred[j], d.ty[j]));
        }
        roc_lines.push(format!("{},inf,0.0000,0.0000,-", model.name));
        for point in roc(&model.test.p, &d.ty) {
            roc_lines.push(format!("{},{},{},{},{}", model.name, f6(point.threshold), ratio(point.tp, pos), ratio(point.fp, neg), ratio(point.tp, point.tp+point.fp)));
        }
    }
    for(t, w)in &sm_trace {
        let g = softmax::gradient(w, &d.x, &d.labels, s.real("SOFTMAX", 2));
        trace.push(format!("softmax,{t},{},{},{}", f6(softmax::objective(w, &d.x, &d.labels, s.real("SOFTMAX", 2))), f6(length(g.into_iter().flatten())), f6(softmax::average_loss(w, &d.z, &d.test_labels))));
    }
    for j in 0..m {
        predictions.push(format!("{},softmax,{},{},{}", d.test[j].id, f6(sm_p[j][sm_pred[j]]), sm_pred[j], d.test_labels[j]));
    }
    let counts = |labels: &[usize]|(0..d.classes).map(|k|labels.iter().filter(| && c|c == k).count().to_string()).collect::<Vec<_>>().join(" ");
    let mut parts = vec![vec![format!("data train {n} test {m} base_features {} degree {} features {p}", d.names.len(), s.int("DEGREE", 0)), format!("binary positive_class {} train {}/{n} test {pos}/{m}", s.int("POSITIVE", 0), d.y.iter().sum::<usize>()), format!("classes {} train {} test {}", d.classes, counts(&d.labels), counts(&d.test_labels))]];
    let mut cv = vec!["cross_validation folds 5 newton_iterations 10".into()];
    for c in &cvs {
        cv.push(format!("lambda {} fold_loss {} cv_loss {} errors {}/{n}", f4(c.lam), c.folds.iter().map(|&v|f6(v)).collect::<Vec<_>>().join(" "), f6(c.loss), c.errors));
    }
    cv.push(format!("selected lambda {} cv_loss {} se {} lambda_1se {}", f4(lam), f6(best.loss), f6(se), f4(one_se)));
    let c = Confusion::new(&predict(&best.p, d.threshold()), &d.y);
    cv.push(format!("out_of_fold tp {} fp {} tn {} fn {} accuracy {} auc {}", c.tp, c.fp, c.tn, c.fn_, ratio(c.tp+c.tn, n as i64), frac(auc(&best.p, &d.y))));
    parts.push(cv);
    let mut path = vec!["lambda_path".into()];
    for &a in &lambdas {
        let w = newton_weights(&d.x, &d.y, a);
        let tr = Evaluation::new(&w, &d.x, &d.y, d.threshold());
        let te = Evaluation::new(&w, &d.z, &d.ty, d.threshold());
        path.push(format!("lambda {} objective {} train_loss {} test_loss {} train_accuracy {} test_accuracy {} norm {}", f4(a), f6(objective(&w, &d.x, &d.y, a)), f6(tr.loss), f6(te.loss), ratio(tr.correct, n as i64), ratio(te.correct, m as i64), f4(length(w[1..].iter().copied()))));
    }
    parts.push(path);
    let mut degrees = vec![format!("degrees lambda {}", f4(lam))];
    for degree in 1..=s.int("DEGREE", 0) {
        let q = d.tuples.iter().filter(|t|t.len() <= degree).count();
        let x = d.x.iter().map(|v|v[..=q].to_vec()).collect::<Vec<_>>();
        let z = d.z.iter().map(|v|v[..=q].to_vec()).collect::<Vec<_>>();
        let w = newton_weights(&x, &d.y, lam);
        let tr = Evaluation::new(&w, &x, &d.y, d.threshold());
        let te = Evaluation::new(&w, &z, &d.ty, d.threshold());
        let inf = Influence::new(&w, &x, &d.y, lam);
        degrees.push(format!("degree {degree} features {q} cv_loss {} train_loss {} test_loss {} test_accuracy {} auc {} edf {} aic {} bic {}", f6(cross_validate(&d, lam, q).loss), f6(tr.loss), f6(te.loss), ratio(te.correct, m as i64), frac(te.auc), f4(inf.edf), f4(inf.aic), f4(inf.bic)));
    }
    parts.push(degrees);
    let mut learning = vec![format!("learning_curve lambda {}", f4(lam))];
    for k in 1..=4 {
        let size = k*n/4;
        let rows = d.expanded[..size].to_vec();
        let stats = statistics(&rows, p);
        let x = rows.iter().map(|v|standardize(v, &stats, p)).collect::<Vec<_>>();
        let z = d.test_expanded.iter().map(|v|standardize(v, &stats, p)).collect::<Vec<_>>();
        let w = newton_weights(&x, &d.y[..size], lam);
        let tr = Evaluation::new(&w, &x, &d.y[..size], d.threshold());
        let te = Evaluation::new(&w, &z, &d.ty, d.threshold());
        learning.push(format!("size {size} train_loss {} test_loss {} test_accuracy {} auc {}", f6(tr.loss), f6(te.loss), ratio(te.correct, m as i64), frac(te.auc)));
    }
    parts.push(learning);
    for model in &models {
        parts.push(binary_report(&d, model, lam));
    }
    let mut comparison = vec![];
    for(a, b)in [(0, 1), (0, 2), (1, 2)] {
        let first = &models[a];
        let second = &models[b];
        let mut only_first = 0i64;
        let mut only_second = 0i64;
        for j in 0..m {
            let(a, b, y) = (first.test.pred[j], second.test.pred[j], d.ty[j]);
            if a == y && b != y {
                only_first += 1
            }else if b == y && a != y {
                only_second += 1
            }
        }
        let gap = (only_first-only_second).abs()-1;
        comparison.push(format!("agreement {} {} same {}/{m} only_first {only_first} only_second {only_second} mcnemar {}", first.name, second.name, equal(&first.test.pred, &second.test.pred), ratio(gap*gap, only_first+only_second)));
    }
    parts.push(comparison);
    parts.push(diagnostics(&d, newton, &inf, lam));
    let repeats = s.int("PERMUTATION", 0);
    let mut rng = Minstd {
        state: s.int("PERMUTATION", 1)as i64
    };
    let mut importance = vec![format!("importance repeats {repeats} seed {}", s.int("PERMUTATION", 1)), format!("baseline log_loss {} auc {} softmax_accuracy {}", f6(newton.test.loss), frac(newton.test.auc), ratio(equal(&sm_pred, &d.test_labels), m as i64))];
    for k in 0..d.names.len() {
        let mut losses = vec![];
        let(mut auc_total, mut correct) = (0, 0);
        for _ in 0..repeats {
            let mut order = (0..m).collect::<Vec<_>>();
            rng.shuffle(&mut order);
            let vectors = d.test.iter().enumerate().map(|(j, r)| {
                let mut v = r.values.clone(); v[k] = d.test[order[j]].values[k]; d.vector(&v)
            }).collect::<Vec<_>>();
            losses.push(average_loss(&newton.w, &vectors, &d.ty));
            auc_total += auc(&probabilities(&newton.w, &vectors), &d.ty).0;
            let pred = vectors.iter().map(|v|softmax::predicted(&softmax::probabilities(sm, v))).collect::<Vec<_>>();
            correct += equal(&pred, &d.test_labels);
        }
        importance.push(format!("feature {} log_loss_increase {} auc {} softmax_accuracy {}", d.names[k], f6(sum(losses)/repeats as f64-newton.test.loss), fraction(auc_total, repeats as i64*newton.test.auc.1), ratio(correct, (repeats*m)as i64)));
    }
    parts.push(importance);
    let mut profiles = vec!["profiles".into()];
    for k in 0..d.names.len() {
        let low = d.train.iter().map(|r|r.values[k]).fold(f64::INFINITY, f64::min);
        let high = d.train.iter().map(|r|r.values[k]).fold(f64::NEG_INFINITY, f64::max);
        for g in 0..=4 {
            let mut v = d.means();
            v[k] = low+(high-low)*g as f64/4.0;
            let x = d.vector(&v);
            let ps = softmax::probabilities(sm, &x);
            profiles.push(format!("profile {} value {} newton {} softmax {}", d.names[k], f4(v[k]), f4(probability(score(&newton.w, &x))), ps.iter().map(|&p|f4(p)).collect::<Vec<_>>().join(" ")));
        }
    }
    parts.push(profiles);
    parts.push(softmax_report(&d, sm, &sm_p, &sm_pred, newton));
    let lm = s.real("SOFTMAX", 2);
    let mut ovr = vec![format!("one_vs_rest lambda {} newton_iterations 10", f4(lm))];
    let mut class_prob = vec![];
    for k in 0..d.classes {
        let y = d.labels.iter().map(|&y|usize::from(y == k)).collect::<Vec<_>>();
        let ty = d.test_labels.iter().map(|&y|usize::from(y == k)).collect::<Vec<_>>();
        let w = newton_weights(&d.x, &y, lm);
        let ps = probabilities(&w, &d.z);
        ovr.push(format!("class {k} objective {} auc {}", f6(objective(&w, &d.x, &y, lm)), frac(auc(&ps, &ty))));
        class_prob.push(ps);
    }
    let pred = (0..m).map(|j|softmax::predicted(&class_prob.iter().map(|p|p[j]).collect::<Vec<_>>())).collect::<Vec<_>>();
    ovr.push(format!("accuracy {} agreement_with_softmax {}/{m}", ratio(equal(&pred, &d.test_labels), m as i64), equal(&pred, &sm_pred)));
    parts.push(ovr);
    let w = s.int("MAP", 0);
    let h = s.int("MAP", 1);
    let low = (0..2).map(|k|d.train.iter().map(|r|r.values[k]).fold(f64::INFINITY, f64::min)).collect::<Vec<_>>();
    let high = (0..2).map(|k|d.train.iter().map(|r|r.values[k]).fold(f64::NEG_INFINITY, f64::max)).collect::<Vec<_>>();
    let mut cells = vec![0; d.classes];
    let mut class_rows = vec![];
    let mut probability_rows = vec![];
    for r in 0..h {
        let mut class_row = String::new();
        let mut probability_row = String::new();
        for c in 0..w {
            let mut v = d.means();
            v[0] = low[0]+(c as f64+0.5)*(high[0]-low[0])/w as f64;
            v[1] = high[1]-(r as f64+0.5)*(high[1]-low[1])/h as f64;
            let x = d.vector(&v);
            let pred = softmax::predicted(&softmax::probabilities(sm, &x));
            cells[pred] += 1;
            class_row.push(char::from(b'0'+pred as u8));
            probability_row.push(char::from(b'0'+(probability(score(&newton.w, &x))*10.0).floor().min(9.0)as u8));
        }
        class_rows.push(class_row);
        probability_rows.push(probability_row);
    }
    let mut map = vec![format!("map {} {} width {w} height {h}", d.names[0], d.names[1]), "softmax_classes".into()];
    map.extend(class_rows);
    map.push(format!("cells {}", cells.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")));
    map.push("newton_probability".into());
    map.extend(probability_rows);
    parts.push(map);
    fs::create_dir_all("output")?;
    write_parts("weights.txt", weights_report(&d, &models, sm, &inf, lam))?;
    write_lines("loss_trace.csv", &trace)?;
    write_lines("predictions.csv", &predictions)?;
    write_parts("evaluation.txt", parts)?;
    write_lines("roc.csv", &roc_lines)
}
fn newton_weights(x: &[Vec<f64>], y: &[usize], lam: f64) -> Vec<f64> {
    newton(x, y, lam).pop().unwrap().1
}
