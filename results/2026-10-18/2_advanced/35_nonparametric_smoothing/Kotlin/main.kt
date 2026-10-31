import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt
import kotlin.math.floor
data class Block(val start: Int, val end: Int, val sum: Int, val count: Int) {
    fun value() = sum.toDouble() / (100 * count)
}
fun pava(data: Dataset.Series, direction: String): List<Block> {
    val blocks = mutableListOf<Block>();
    for (i in 0 until data.n) {
        blocks.add(Block(i,i,data.hundredths[i],1));
        while (blocks.size >= 2) {
            val a = blocks[blocks.size - 2];
            val b = blocks.last();
            val violates = if (direction == "increasing") a.sum * b.count > b.sum * a.count else a.sum * b.count < b.sum * a.count;
            if (!violates) break;
            blocks.removeAt(blocks.lastIndex);
            blocks.removeAt(blocks.lastIndex);
            blocks.add(Block(a.start,b.end,a.sum + b.sum,a.count + b.count))
        }
    };
    return blocks
}
fun blockValues(data: Dataset.Series, blocks: List<Block>): DoubleArray {
    val values = DoubleArray(data.n);
    for (block in blocks) for (i in block.start..block.end) values[i] = block.value();
    return values
}
class Fit(val data: Dataset.Series, val name: String, val parameter: String, robustIterations: Int, diagnostics: Boolean) {
    var fitted = DoubleArray(data.n);
    var leverage: DoubleArray? = null;
    var edf = Double.NaN;
    var intercept = 0.0;
    var slope = 0.0;
    var xbar = 0.0;
    var sxx = 0.0;
    var loess: Loess? = null;
    var spline: Spline? = null;
    var blocks = listOf<Block>()
    init {
        val n = data.n
        when {
            name == "linear" -> {
                xbar = Selection.sum(data.x) / n;
                val ybar = Selection.sum(data.y) / n;
                var sxy = 0.0;
                for (i in 0 until n) {
                    val d = data.x[i] - xbar;
                    sxx += d * d;
                    sxy += d * (data.y[i] - ybar)
                };
                slope = sxy / sxx;
                intercept = ybar - slope * xbar;
                edf = 2.0;
                val diagonal = DoubleArray(n);
                for (i in 0 until n) {
                    fitted[i] = intercept + slope * data.x[i];
                    val d = data.x[i] - xbar;
                    diagonal[i] = 1.0 / n + d * d / sxx
                };
                leverage = diagonal
            }
            name.startsWith("running_") -> {
                val k = (parameter.toInt() - 1) / 2;
                val diagonal = if (name == "running_mean") DoubleArray(n) else null;
                if (diagonal != null) edf = 0.0;
                for (i in 0 until n) {
                    val r = minOf(k,i,n - 1 - i);
                    val count = 2 * r + 1;
                    val values = IntArray(count) {
                        data.hundredths[i - r + it]
                    };
                    if (diagonal != null) {
                        fitted[i] = values.sum().toDouble() / (100 * count);
                        diagonal[i] = 1.0 / count;
                        edf += diagonal[i]
                    } else {
                        values.sort();
                        fitted[i] = values[r] / 100.0
                    }
                };
                leverage = diagonal
            }
            name == "isotonic" -> {
                blocks = pava(data,parameter);
                fitted = blockValues(data,blocks);
                edf = blocks.size.toDouble()
            }
            name.startsWith("loess") -> {
                val local = Loess(data,name.substring(5).toInt(),Dataset.hundredths(parameter),robustIterations,diagnostics);
                loess = local;
                fitted = local.fitted;
                leverage = if (diagnostics) local.leverage else null;
                edf = local.edf
            }
            name == "spline" -> {
                val local = Spline(data,parameter.toDouble(),diagnostics);
                spline = local;
                fitted = local.fit.fitted;
                leverage = local.leverage;
                edf = local.edf
            }
            diagnostics -> {
                val diagonal = DoubleArray(n);
                edf = 0.0;
                for (i in 0 until n) {
                    val result = estimate(data.positions[i]);
                    fitted[i] = result.value;
                    diagonal[i] = result.weights[i];
                    edf += diagonal[i]
                };
                if (fitted.any {
                    it.isNaN()
                }) {
                    edf = Double.NaN;
                    leverage = null
                } else leverage = diagonal
            }
        }
    }
    fun estimate(position: Int): Kernels.Result {
        val n = data.n;
        val weights = DoubleArray(n)
        if (name == "linear") {
            val x0 = position / 100.0;
            for (j in 0 until n) weights[j] = 1.0 / n + (x0 - xbar) * (data.x[j] - xbar) / sxx;
            return Kernels.Result(intercept + slope * x0,weights,Double.NaN)
        }
        if (name.startsWith("running_")) {
            var nearest = 0;
            for (j in 1 until n) if (abs(data.positions[j] - position) < abs(data.positions[nearest] - position)) nearest = j;
            if (name == "running_mean") {
                val r = minOf((parameter.toInt() - 1) / 2,nearest,n - 1 - nearest);
                for (j in nearest - r..nearest + r) weights[j] = 1.0 / (2 * r + 1)
            };
            return Kernels.Result(fitted[nearest],weights,Double.NaN)
        }
        if (name == "isotonic") {
            var i = 0;
            while (i + 1 < n && data.positions[i + 1] <= position) i++;
            return Kernels.Result(fitted[i],weights,Double.NaN)
        }
        loess?.let {
            return it.estimate(position)
        };
        spline?.let {
            return it.estimate(position)
        }
        return Kernels.estimate(data,position,Dataset.hundredths(parameter),name.substring(3),name.startsWith("ll_"))
    }
}
fun cv(data: Dataset.Series, name: String, parameter: String, folds: Int): Double {
    val predicted = DoubleArray(data.n);
    if (folds == 0) for (i in 0 until data.n) predicted[i] = Fit(data.subset(i,0),name,parameter,
        0,false).estimate(data.positions[i]).value else for (group in 0 until folds) {
        val fit = Fit(data.subset(group,folds),name,parameter,0,false);
        for (i in group until data.n step folds) predicted[i] = fit.estimate(data.positions[i]).value
    };
    return Selection.score(data.y,predicted)
}
data class Candidate(val parameter: String, val score: Double, val edf: Double)
class Method(val name: String, var parameter: String) {
    lateinit var fit: Fit;
    var loo = 0.0;
    var kfold = 0.0;
    var score = Double.NaN;
    var rss = 0.0;
    var df = 0.0;
    var rse = 0.0;
    var r2 = 0.0;
    var nonlinear = Double.NaN;
    var errors = doubleArrayOf();
    var grid = doubleArrayOf();
    val acf = DoubleArray(5);
    val quantiles = DoubleArray(5);
    var dw = 0.0;
    var z = 0.0;
    var runs = 0;
    var positive = 0;
    var negative = 0;
    var maximum = 0;
    var turning = 0;
    val candidates = mutableListOf<Candidate>();
    var selected = 0
}
class Analysis(val data: Dataset.Series, val mode: String) {
    var direction = "";
    var increasing = 0.0;
    var decreasing = 0.0;
    val methods = mutableListOf<Method>();
    var grid = intArrayOf();
    var ranking = listOf<Int>();
    lateinit var best: Method;
    lateinit var outlier: Method;
    var standardized = doubleArrayOf();
    var cook = doubleArrayOf();
    val named = mutableMapOf<String,Method>()
}
fun real(value: Double): String {
    if (value.isNaN()) return "NA";
    val text = String.format(Locale.ROOT,"%.4f",value);
    return if (text == "-0.0000") "0.0000" else text
}
fun decimal(value: Int) = String.format(Locale.ROOT,"%.2f",value / 100.0)
fun rss(observed: DoubleArray, fitted: DoubleArray): Double {
    var total = 0.0;
    for (i in observed.indices) {
        val e = observed[i] - fitted[i];
        total += e * e
    };
    return total
}
fun methods(dataset: Dataset) = listOf("linear","running_mean","running_median") + dataset.values("KERNELS").map {
    "nw_$it"
}
+ dataset.values("KERNELS").map {
    "ll_$it"
}
+ dataset.values("LOESS_DEGREES").map {
    "loess$it"
}
+ listOf("spline","isotonic")
fun candidates(settings: Dataset, name: String) = settings.values(when {
    name.startsWith("running_") -> "WINDOWS";
    name.startsWith("nw_") || name.startsWith("ll_") -> "BANDWIDTHS";
    name.startsWith("loess") -> "SPANS";
    else -> "LAMBDAS"
})
fun analyze(dataset: Dataset, data: Dataset.Series, index: Int, names: List<String>): Analysis {
    val result = Analysis(data,dataset.values("ISOTONIC")[index]);
    result.increasing = rss(data.y,blockValues(data,pava(data,"increasing")));
    result.decreasing = rss(data.y,blockValues(data,pava(data,"decreasing")));
    result.direction = if (result.mode == "auto") {
        if (result.increasing <= result.decreasing) "increasing" else "decreasing"
    } else result.mode
    val count = dataset.integer("GRID_POINTS");
    result.grid = IntArray(count) {
        data.positions[0] + it * (data.positions[data.n - 1] - data.positions[0]) / (count - 1)
    }
    for (name in names) {
        val method = Method(name,if (name == "linear") "-" else result.direction)
        if (name !in listOf("linear","isotonic")) {
            val parameters = candidates(dataset,name);
            val scores = DoubleArray(parameters.size);
            for (i in parameters.indices) {
                val candidate = Fit(data,name,parameters[i],0,true);
                val score = if (name == "spline") Selection.generalized(data.y,candidate.fitted,candidate.edf) else cv(data,name,parameters[i],0);
                scores[i] = score;
                method.candidates.add(Candidate(parameters[i],score,candidate.edf))
            };
            method.selected = Selection.choose(scores);
            method.parameter = parameters[method.selected];
            method.score = scores[method.selected]
        }
        method.fit = Fit(data,name,method.parameter,dataset.integer("ROBUST_ITERATIONS"),true);
        method.loo = if (name in listOf("linear","spline","isotonic")) cv(data,name,method.parameter,0) else method.score;
        method.kfold = cv(data,name,method.parameter,dataset.integer("CV_FOLDS"));
        method.grid = DoubleArray(count) {
            method.fit.estimate(result.grid[it]).value
        };
        diagnostics(method,data,result.methods.firstOrNull()?.rss ?: Double.NaN);
        result.methods.add(method);
        result.named[name] = method
    }
    result.ranking = names.indices.sortedWith(compareBy<Int> {
        result.methods[it].loo
    }.thenBy {
        it
    });
    result.best = result.methods[result.ranking[0]];
    result.outlier = result.methods[result.ranking.first {
        result.methods[it].fit.leverage != null
    }];
    result.standardized = DoubleArray(data.n) {
        Double.NaN
    };
    result.cook = DoubleArray(data.n) {
        Double.NaN
    }
    for (i in 0 until data.n) {
        val leverage = result.outlier.fit.leverage!![i];
        if (leverage < 1) {
            val t = result.outlier.errors[i] / (result.outlier.rse * sqrt(1 - leverage));
            result.standardized[i] = t;
            result.cook[i] = t * t * leverage / ((1 - leverage) * result.outlier.fit.edf)
        }
    }
    return result
}
fun diagnostics(m: Method, data: Dataset.Series, linearRss: Double) {
    val n = data.n;
    m.errors = DoubleArray(n) {
        data.y[it] - m.fit.fitted[it]
    };
    m.rss = rss(data.y,m.fit.fitted);
    val mean = Selection.sum(data.y) / n;
    var tss = 0.0;
    for (y in data.y) tss += (y - mean) * (y - mean);
    m.r2 = 1 - m.rss / tss;
    m.df = n - m.fit.edf;
    m.rse = sqrt(m.rss / m.df);
    m.nonlinear = if (m.name != "linear" && m.fit.edf > 2) ((linearRss - m.rss) / (m.fit.edf - 2)) / (m.rss / m.df) else Double.NaN
    val errorMean = Selection.sum(m.errors) / n;
    var denominator = 0.0;
    var dw = 0.0;
    var previous = 0
    for (i in 0 until n) {
        val e = m.errors[i];
        denominator += (e - errorMean) * (e - errorMean);
        if (i > 0) dw += (e - m.errors[i - 1]) * (e - m.errors[i - 1]);
        if (abs(e) > abs(m.errors[m.maximum])) m.maximum = i;
        if (e != 0.0) {
            val sign = if (e > 0) 1 else -1;
            if (sign > 0) m.positive++ else m.negative++;
            if (sign != previous) m.runs++;
            previous = sign
        }
    }
    for (k in 1..5) {
        var total = 0.0;
        for (i in 0 until n - k) total += (m.errors[i] - errorMean) * (m.errors[i + k] - errorMean);
        m.acf[k - 1] = total / denominator
    };
    m.dw = dw / m.rss
    val plus = m.positive.toLong();
    val minus = m.negative.toLong();
    val total = plus + minus;
    val mu = 1 + (2 * plus * minus).toDouble() / total;
    val variance = (2 * plus * minus * (2 * plus * minus - total)).toDouble() / (total * total * (total - 1));
    m.z = (m.runs - mu) / sqrt(variance)
    val sorted = m.errors.sortedArray();
    for (k in 0..4) {
        val j = (n - 1) * k / 4;
        val remainder = (n - 1) * k - 4 * j;
        m.quantiles[k] = if (remainder == 0) sorted[j] else sorted[j] + remainder / 4.0 * (sorted[j + 1] - sorted[j])
    }
    var hasPrevious = false;
    var last = 0.0;
    var lastSign = 0;
    for (value in m.grid) if (!value.isNaN()) {
        if (hasPrevious) {
            val delta = value - last;
            if (delta != 0.0) {
                val sign = if (delta > 0) 1 else -1;
                if (lastSign != 0 && sign != lastSign) m.turning++;
                lastSign = sign
            }
        };
        hasPrevious = true;
        last = value
    }
}
fun se(method: Method, position: Int): Double {
    val weights = method.fit.estimate(position).weights;
    var total = 0.0;
    for (weight in weights) total += weight * weight;
    return method.rse * sqrt(total)
}
fun sortedDefined(values: DoubleArray, absolute: Boolean) = values.indices.filter {
    !values[it].isNaN()
}.sortedWith(compareByDescending<Int> {
    if (absolute) abs(values[it]) else values[it]
}.thenBy {
    it
})
fun diagnosticLines(a: Analysis, settings: Dataset): List<String> {
    val data = a.data;
    val n = data.n;
    val output = mutableListOf("series ${data.name} n $n x ${decimal(data.positions[0])} ${decimal(data.positions[n - 1])} y ${decimal(data.hundredths.min())} ${decimal(data.hundredths.max())}")
    for (m in a.methods) {
        output.add("method ${m.name} parameter ${m.parameter} loo ${real(m.loo)}" + if (m.name == "spline") " gcv ${real(m.score)}" else "")
        output.add("  rss ${real(m.rss)} edf ${real(m.fit.edf)} df ${real(m.df)} rse ${real(m.rse)} r2 ${real(m.r2)} f_nonlinear ${real(m.nonlinear)}")
        output.add("  acf" + m.acf.joinToString("") {
            " ${real(it)}"
        }
        + " dw ${real(m.dw)}");
        output.add("  runs ${m.runs} positive ${m.positive} negative ${m.negative} z ${real(m.z)}");
        output.add("  max_residual ${real(m.errors[m.maximum])} at ${decimal(data.positions[m.maximum])} turning ${m.turning}");
        output.add("  quantiles" + m.quantiles.joinToString("") {
            " ${real(it)}"
        })
        m.fit.loess?.let {
            local -> for (i in local.rounds.indices) {
                val r = local.rounds[i];
                output.add("  robust ${i + 1} scale ${real(r.scale)} zero_weight ${r.zeros} max_change ${real(r.change)}")
            };
            val zero = (0 until n).filter {
                local.rho[it] == 0.0
            }.map {
                decimal(data.positions[it])
            };
            output.add("  zero_weight_points " + if (zero.isEmpty()) "none" else zero.joinToString(" "))
        }
    }
    output.add("ranking");
    for (i in a.ranking.indices) {
        val m = a.methods[a.ranking[i]];
        output.add("  ${i + 1} ${m.name} ${real(m.loo)} kfold ${real(m.kfold)}")
    };
    output.add("agreement with ${a.best.name}")
    for (m in a.methods) if (m !== a.best) {
        var count = 0;
        var at = -1;
        var squares = 0.0;
        var largest = -1.0;
        for (k in a.grid.indices) if (!m.grid[k].isNaN() && !a.best.grid[k].isNaN()) {
            val delta = abs(m.grid[k] - a.best.grid[k]);
            count++;
            squares += delta * delta;
            if (delta > largest) {
                largest = delta;
                at = k
            }
        };
        output.add("  ${m.name} points $count rms ${real(sqrt(squares / count))} max ${real(largest)} at ${decimal(a.grid[at])}")
    }
    val spline = a.named.getValue("spline");
    var largest = -Double.MAX_VALUE;
    var smallest = Double.MAX_VALUE;
    var atMaximum = -1;
    var atMinimum = -1;
    for (k in 1 until a.grid.size - 1) {
        val slope = (spline.grid[k + 1] - spline.grid[k - 1]) / ((a.grid[k + 1] - a.grid[k - 1]) / 100.0);
        if (slope > largest) {
            largest = slope;
            atMaximum = k
        };
        if (slope < smallest) {
            smallest = slope;
            atMinimum = k
        }
    };
    output.add("slope spline max ${real(largest)} at ${decimal(a.grid[atMaximum])} min ${real(smallest)} at ${decimal(a.grid[atMinimum])}")
    val threshold = settings.number("OUTLIER_THRESHOLD");
    output.add("outliers method ${a.outlier.name} threshold ${decimal(Dataset.hundredths(settings.values("OUTLIER_THRESHOLD")[0]))}");
    var outliers = 0;
    for (i in sortedDefined(a.standardized,true)) if (abs(a.standardized[i]) > threshold) {
        outliers++;
        output.add("  x ${decimal(data.positions[i])} y ${decimal(data.hundredths[i])} fit ${real(a.outlier.fit.fitted[i])} residual ${real(a.outlier.errors[i])} standardized ${real(a.standardized[i])}")
    };
    if (outliers == 0) output.add("  none")
    output.add("influence method ${a.outlier.name}");
    for (i in sortedDefined(a.cook,false).take(3)) output.add("  x ${decimal(data.positions[i])} lev ${real(a.outlier.fit.leverage!![i])} cook ${real(a.cook[i])}")
    output.add("bands");
    val z = settings.number("BAND_Z");
    for (name in settings.values("BAND_METHODS")) {
        val m = a.named.getValue(name);
        var total = 0.0;
        var count = 0;
        var coverage = 0;
        for (k in a.grid.indices) if (!m.grid[k].isNaN()) {
            total += se(m,a.grid[k]);
            count++
        };
        for (i in 0 until n) {
            val error = se(m,data.positions[i]);
            if (abs(m.errors[i]) <= z * sqrt(m.rse * m.rse + error * error)) coverage++
        };
        output.add("  $name mean_se ${real(total / count)} coverage $coverage of $n")
    }
    return output
}
class Rng(var state: Long) {
    fun draw(): Long {
        state = state * 48271 % 2147483647;
        return state
    }
}
fun bandLines(a: Analysis, settings: Dataset, rng: Rng): List<String> {
    val output = mutableListOf<String>();
    val z = settings.number("BAND_Z")
    for (name in settings.values("BAND_METHODS")) {
        val m = a.named.getValue(name);
        for (k in a.grid.indices) {
            val fitted = m.grid[k];
            val error = if (fitted.isNaN()) Double.NaN else se(m,a.grid[k]);
            output.add("${a.data.name},$name,${decimal(a.grid[k])},${real(fitted)},${real(error)},${real(fitted - z * error)},${real(fitted + z * error)}")
        }
    }
    val spline = a.named.getValue("spline");
    val count = settings.values("BOOTSTRAP")[0].toInt();
    val trim = settings.values("BOOTSTRAP")[1].toInt();
    val mean = Selection.sum(spline.errors) / a.data.n;
    val centered = DoubleArray(a.data.n) {
        spline.errors[it] - mean
    };
    val estimates = Array(a.grid.size) {
        DoubleArray(count)
    };
    val model = spline.fit.spline!!
    for (b in 0 until count) {
        val values = DoubleArray(a.data.n) {
            spline.fit.fitted[it] + centered[(rng.draw() % a.data.n).toInt()]
        };
        val fit = model.fitValues(values);
        for (k in a.grid.indices) estimates[k][b] = model.evaluate(fit,a.grid[k])
    }
    for (k in a.grid.indices) {
        val average = Selection.sum(estimates[k]) / count;
        var total = 0.0;
        for (value in estimates[k]) total += (value - average) * (value - average);
        val error = sqrt(total / (count - 1));
        val sorted = estimates[k].sortedArray();
        output.add("${a.data.name},spline_bootstrap,${decimal(a.grid[k])},${real(spline.grid[k])},${real(error)},${real(sorted[trim])},${real(sorted[count - trim - 1])}")
    }
    return output
}
fun isotonicLines(a: Analysis): List<String> {
    val m = a.named.getValue("isotonic");
    val output = mutableListOf("series ${a.data.name} direction ${a.direction} mode ${a.mode}" + if (a.mode == "auto") " rss_increasing ${real(a.increasing)} rss_decreasing ${real(a.decreasing)}" else "",
        "blocks ${m.fit.blocks.size} rss ${real(m.rss)} loo ${real(m.loo)}");
    for (i in m.fit.blocks.indices) {
        val b = m.fit.blocks[i];
        output.add("block ${i + 1} x ${decimal(a.data.positions[b.start])} ${decimal(a.data.positions[b.end])} count ${b.count} value ${real(b.value())}")
    };
    return output
}
fun frame(cells: Array<CharArray>): List<String> {
    val border = "+" + "-".repeat(cells[0].size) + "+";
    return listOf(border) + cells.map {
        "|" + String(it) + "|"
    }
    + border
}
fun clamp(row: Double, height: Int) = if (row < 0) 0 else if (row >= height) height - 1 else floor(row).toInt()
fun plotLines(a: Analysis, settings: Dataset): List<String> {
    val data = a.data;
    val width = settings.values("PLOT_SIZE")[0].toInt();
    val height = settings.values("PLOT_SIZE")[1].toInt();
    val xa = data.positions[0];
    val xb = data.positions[data.n - 1];
    val ya = data.hundredths.min();
    val yb = data.hundredths.max();
    val ymin = ya / 100.0;
    val ymax = yb / 100.0;
    val cells = Array(height) {
        CharArray(width) {
            ' '
        }
    };
    val columns = IntArray(data.n)
    for (i in 0 until data.n) {
        val column = minOf(width - 1,width * (data.positions[i] - xa) / (xb - xa));
        val row = minOf(height - 1,height * (yb - data.hundredths[i]) / (yb - ya));
        columns[i] = column;
        cells[row][column] = '.'
    }
    val plotted = settings.values("PLOT_METHODS");
    var legend = "legend . data"
    for (i in plotted.indices) {
        legend += " ${i + 1} ${plotted[i]}";
        val m = a.named.getValue(plotted[i]);
        val digit = '1' + i;
        for (c in 0 until width) {
            val position = xa + (2 * c + 1) * (xb - xa) / (2 * width);
            val value = m.fit.estimate(position).value;
            if (value.isNaN()) continue;
            val r = clamp(height * (ymax - value) / (ymax - ymin),height);
            val old = cells[r][c];
            cells[r][c] = if (old == ' ' || old == '.' || old == digit) digit else '*'
        }
    }
    val output = mutableListOf("plot ${data.name} size ${width}x$height x ${decimal(xa)} ${decimal(xb)} y ${decimal(ya)} ${decimal(yb)}",legend);
    output.addAll(frame(cells));
    var points = 0;
    var curves = 0;
    var overlap = 0;
    for (row in cells) for (c in row) {
        if (c == '.') points++ else if (c == '*') overlap++ else if (c in '1'..'9') curves++
    };
    output.add("cells data $points curve $curves overlap $overlap");
    output.add("")
    var limit = 0.0;
    for (error in a.best.errors) limit = maxOf(limit,abs(error));
    output.add("residuals ${data.name} method ${a.best.name} limit ${real(limit)}");
    for (row in cells) row.fill(' ');
    cells[height / 2].fill('-');
    for (i in 0 until data.n) cells[clamp(height * ((limit - a.best.errors[i]) / (2 * limit)),height)][columns[i]] = 'o';
    output.addAll(frame(cells));
    output.add("");
    output.add("histogram ${data.name} method ${a.outlier.name}");
    val bins = IntArray(14)
    for (t in a.standardized) if (!t.isNaN()) {
        val k = if (t < -3) 0 else if (t >= 3) 13 else 1 + floor((t + 3) / 0.5).toInt();
        bins[k]++
    }
    for (k in bins.indices) output.add("${if (k == 0) "-inf" else decimal(-300 + 50 * (k - 1))} ${if (k == 13) "inf" else decimal(-300 + 50 * k)} ${bins[k]} |${"#".repeat(bins[k])}")
    return output
}
fun part(output: MutableList<String>, lines: List<String>) {
    if (output.isNotEmpty()) output.add("");
    output.addAll(lines)
}
fun write(name: String, lines: List<String>) {
    Files.writeString(Path.of("output",name),lines.joinToString("\n") + "\n",StandardCharsets.US_ASCII)
}
fun main() {
    val dataset = Dataset();
    val names = methods(dataset);
    val header = "series,x," + names.joinToString(",");
    val selections = mutableListOf("series,method,parameter,score,edf,selected");
    val fits = mutableListOf(header);
    val predictions = mutableListOf(header);
    val bands = mutableListOf("series,method,x,fit,se,lower,upper");
    val diagnostics = mutableListOf<String>();
    val isotonic = mutableListOf<String>();
    val plots = mutableListOf<String>();
    val analyzed = mutableMapOf<String,Analysis>();
    val rng = Rng(dataset.values("BOOTSTRAP")[2].toLong())
    for (index in dataset.series.indices) {
        val data = dataset.series[index];
        val a = analyze(dataset,data,index,names);
        analyzed[data.name] = a;
        for (m in a.methods) for (i in m.candidates.indices) {
            val c = m.candidates[i];
            selections.add("${data.name},${m.name},${c.parameter},${real(c.score)},${real(c.edf)},${if (i == m.selected) 1 else 0}")
        };
        for (k in a.grid.indices) fits.add("${data.name},${decimal(a.grid[k])}" + a.methods.joinToString("") {
            ",${real(it.grid[k])}"
        });
        bands.addAll(bandLines(a,dataset,rng));
        part(diagnostics,diagnosticLines(a,dataset));
        part(isotonic,isotonicLines(a))
    }
    for (test in dataset.tests) {
        val a = analyzed.getValue(test.name);
        predictions.add("${test.name},${decimal(test.position)}" + a.methods.joinToString("") {
            ",${real(it.fit.estimate(test.position).value)}"
        })
    }
    for (name in dataset.values("PLOT_SERIES")) part(plots,plotLines(analyzed.getValue(name),dataset));
    Files.createDirectories(Path.of("output"));
    write("selection.csv",selections);
    write("fits.csv",fits);
    write("predictions.csv",predictions);
    write("bands.csv",bands);
    write("diagnostics.txt",diagnostics);
    write("isotonic.txt",isotonic);
    write("plots.txt",plots)
}
