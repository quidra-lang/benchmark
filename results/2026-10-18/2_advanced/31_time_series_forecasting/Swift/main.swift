import Foundation

let methods = [
    "naive", "snaive", "drift", "ses", "holt", "damped", "hw_add", "hw_mult",
    "decomp_add", "decomp_mult", "ar"
]
let modelNames = methods + ["combo"]

struct ArFit {
    let kind: Int
    let differenced: [Double]
    let offset: Int
    let average: Double
    let variances: [Double]
    let order: Int
    let sigma2: Double
    let aic: [Double]
    let coefficients: [Double]
    let correlations: [Double]
    let partial: [Double]
}

indirect enum ForecastFit {
    case naive
    case seasonalNaive
    case drift(Double)
    case smooth(SmoothingParameters, [SmoothingState])
    case decomposition(Double, Double, [Double])
    case ar(ArFit)
    case combo([ForecastModel])
}

struct ForecastModel {
    let name: String
    let values: [Double]
    let season: Int
    let residuals: [Double]
    let fit: ForecastFit
}

struct CrossValidation {
    let counts: [Int]
    let sigma: [Double]
    let mae: [Double]
    let rmse: Double
}

struct Interval {
    let forecast: Double
    let lo80: Double
    let hi80: Double
    let lo95: Double
    let hi95: Double

    func csv() -> String {
        [forecast, lo80, hi80, lo95, hi95].map(real).joined(separator: ",")
    }
}

struct Measures {
    let accuracy: Accuracy
    let cover80: Int
    let cover95: Int
    let winkler80: Double
    let winkler95: Double
}

struct Lift {
    let kind: String
    var times: [Int] = []
    var value = 0.0
}

struct Prepared {
    let values: [Double]
    let corrected: [Double]
    let components: Decomposition
    let past: [String?]
    let outliers: [Double?]
    let lifts: [Lift]
    let strengthTrend: Double
    let strengthSeasonal: Double
    let futurePeriods: [String]
}

struct Reports {
    var decomposition = [
        "series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag"
    ]
    var models: [String] = []
    var forecasts = ["series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95"]
    var accuracy = [
        "series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank"
    ]
    var cv = ["series,method,step,origins,mae,rmse"]
    var correlogram: [String] = []
    var chart: [String] = []
    var plan: [String] = []
}

func rmse(_ errors: [Double]) -> Double {
    sqrt(total(errors.map { $0 * $0 }) / Double(errors.count))
}

func prepare(_ record: Series, _ settings: Settings) -> Prepared {
    let count = record.raw.count
    var values = record.raw.map { Double($0 ?? 0) }
    var left = 0
    while left + 1 < count {
        var right = left + 1
        while record.raw[right] == nil {
            right += 1
        }
        for t in (left + 1)..<right {
            values[t] = Double(record.raw[left]!)
                + Double(record.raw[right]! - record.raw[left]!) * Double(t - left) / Double(right - left)
        }
        left = right
    }
    let components = decompose(values, settings.season)
    let residuals = components.defined.map { components.residualAdd[$0]! }
    let average = mean(residuals)
    let deviation = sqrt(sampleVariance(residuals))
    var past = [String?](repeating: nil, count: count)
    var lifts: [Lift] = []
    for t in 0..<count {
        if let kind = record.events[record.periods[t]] {
            past[t] = kind
            if let index = lifts.firstIndex(where: { $0.kind == kind }) {
                lifts[index].times.append(t)
            } else {
                lifts.append(Lift(kind: kind, times: [t]))
            }
        }
    }
    for i in lifts.indices {
        lifts[i].value = total(lifts[i].times.map { t in
            values[t] / (components.trend[t]! + components.additive[t % settings.season])
        }) / Double(lifts[i].times.count)
    }
    var outliers = [Double?](repeating: nil, count: count)
    for t in components.defined {
        let centered = components.residualAdd[t]! - average
        if record.raw[t] != nil && past[t] == nil && abs(centered) > settings.outlier * deviation {
            outliers[t] = centered / deviation
        }
    }
    let corrected = (0..<count).map { t in
        past[t] != nil || outliers[t] != nil
            ? components.trend[t]! + components.additive[t % settings.season] : values[t]
    }
    let trendResiduals = components.defined.map { components.trend[$0]! + components.residualAdd[$0]! }
    let seasonalResiduals = components.defined.map {
        components.additive[$0 % settings.season] + components.residualAdd[$0]!
    }
    let variance = sampleVariance(residuals)
    let strengthTrend = max(0, 1 - variance / sampleVariance(trendResiduals))
    let strengthSeasonal = max(0, 1 - variance / sampleVariance(seasonalResiduals))
    var period = record.periods.last!
    var futurePeriods: [String] = []
    for _ in 0..<settings.horizon {
        period = nextMonth(period)
        futurePeriods.append(period)
    }
    return Prepared(
        values: values, corrected: corrected, components: components, past: past, outliers: outliers,
        lifts: lifts, strengthTrend: strengthTrend, strengthSeasonal: strengthSeasonal, futurePeriods: futurePeriods
    )
}

func fitAR(_ values: [Double], _ settings: Settings) -> (ArFit, [Double]) {
    let candidates = (0..<4).map { kind -> ([Double], Int, Double, Double) in
        let (transformed, offset) = difference(values, settings.season, kind)
        let (average, variance, _) = autocorrelation(transformed, 0)
        return (transformed, offset, average, variance)
    }
    var kind = 0
    for i in 1..<4 {
        if candidates[i].3 < candidates[kind].3 {
            kind = i
        }
    }
    let (differenced, offset, average, variance) = candidates[kind]
    let (_, _, correlations) = autocorrelation(differenced, settings.maxLag)
    let recursion = durbinLevinson(correlations)
    let aic = (0...settings.maxAR).map {
        Double(differenced.count) * log(variance * recursion.variances[$0]) + 2 * Double($0)
    }
    let order = rankModels(aic)[0]
    let coefficients = recursion.coefficients[order]
    let fit = ArFit(
        kind: kind, differenced: differenced, offset: offset, average: average,
        variances: candidates.map { $0.3 }, order: order, sigma2: variance * recursion.variances[order],
        aic: aic, coefficients: coefficients, correlations: correlations, partial: recursion.partial
    )
    return (fit, arResiduals(differenced, average, coefficients))
}

func fitMethod(_ name: String, _ values: [Double], _ settings: Settings) -> ForecastModel {
    let count = values.count
    let season = settings.season
    let fit: ForecastFit
    let residuals: [Double]
    switch name {
    case "naive":
        fit = .naive
        residuals = (1..<count).map { values[$0] - values[$0 - 1] }
    case "snaive":
        fit = .seasonalNaive
        residuals = (season..<count).map { values[$0] - values[$0 - season] }
    case "drift":
        let slope = (values[count - 1] - values[0]) / Double(count - 1)
        fit = .drift(slope)
        residuals = (1..<count).map { values[$0] - values[$0 - 1] - slope }
    case "ses", "holt", "damped", "hw_add", "hw_mult":
        let betas = name == "ses" ? [0.0] : settings.beta
        let gammas = name == "hw_add" || name == "hw_mult" ? settings.gamma : [0.0]
        let phis = name == "damped" ? settings.phi : [1.0]
        var best: (Double, SmoothingParameters, [Double], [SmoothingState])?
        for alpha in settings.alpha {
            for beta in betas {
                for gamma in gammas {
                    for phi in phis {
                        let parameters = SmoothingParameters(alpha: alpha, beta: beta, gamma: gamma, phi: phi)
                        let (errors, states) = smoothingRecursion(name, values, season, parameters)
                        let score = total(errors.map { $0 * $0 })
                        if best == nil || score < best!.0 {
                            best = (score, parameters, errors, states)
                        }
                    }
                }
            }
        }
        residuals = best!.2
        fit = .smooth(best!.1, best!.3)
    case "decomp_add", "decomp_mult":
        let components = decompose(values, season)
        let seasonal = name == "decomp_add" ? components.additive : components.multiplicative
        let adjusted = values.indices.map { t in
            name == "decomp_add" ? values[t] - seasonal[t % season] : values[t] / seasonal[t % season]
        }
        let (intercept, slope) = leastSquaresLine(adjusted)
        residuals = values.indices.map { t in
            let base = intercept + slope * Double(t + 1)
            let predicted = name == "decomp_add" ? base + seasonal[t % season] : base * seasonal[t % season]
            return values[t] - predicted
        }
        fit = .decomposition(intercept, slope, seasonal)
    default:
        let (ar, errors) = fitAR(values, settings)
        fit = .ar(ar)
        residuals = errors
    }
    return ForecastModel(name: name, values: values, season: season, residuals: residuals, fit: fit)
}

func combination(_ members: [ForecastModel], _ values: [Double], _ season: Int) -> ForecastModel {
    ForecastModel(name: "combo", values: values, season: season, residuals: [], fit: .combo(members))
}

func forecast(_ model: ForecastModel, _ origin: Int, _ steps: Int) -> [Double] {
    let values = model.values
    switch model.fit {
    case .naive:
        return [Double](repeating: values[origin - 1], count: steps)
    case .seasonalNaive:
        return (0..<steps).map { values[origin - model.season + $0 % model.season] }
    case .drift:
        let slope = (values[origin - 1] - values[0]) / Double(origin - 1)
        return (1...steps).map { values[origin - 1] + Double($0) * slope }
    case let .smooth(parameters, states):
        return smoothingForecast(model.name, states[origin], parameters, origin, steps, model.season)
    case let .decomposition(intercept, slope, seasonal):
        return (0..<steps).map { i in
            let t = origin + i
            let base = intercept + slope * Double(t + 1)
            return model.name == "decomp_add" ? base + seasonal[t % model.season] : base * seasonal[t % model.season]
        }
    case let .ar(ar):
        return arForecast(
            values, ar.differenced, ar.offset, ar.kind, ar.average, ar.coefficients, origin, steps, model.season
        )
    case let .combo(members):
        let predictions = members.map { forecast($0, origin, steps) }
        return (0..<steps).map { i in total(predictions.map { $0[i] }) / Double(members.count) }
    }
}

func crossValidate(_ model: ForecastModel, _ settings: Settings) -> CrossValidation {
    var counts = [Int](repeating: 0, count: settings.horizon)
    var squared = [Double](repeating: 0, count: settings.horizon)
    var absolute = squared
    for origin in settings.cvStart..<model.values.count {
        let predictions = forecast(model, origin, min(settings.horizon, model.values.count - origin))
        for (i, prediction) in predictions.enumerated() {
            let error = model.values[origin + i] - prediction
            counts[i] += 1
            squared[i] += error * error
            absolute[i] += abs(error)
        }
    }
    let sigma = squared.indices.map { sqrt(squared[$0] / Double(counts[$0])) }
    let mae = absolute.indices.map { absolute[$0] / Double(counts[$0]) }
    let denominator = counts.prefix(settings.holdout).reduce(0, +)
    let rmse = sqrt(total(squared.prefix(settings.holdout)) / Double(denominator))
    return CrossValidation(counts: counts, sigma: sigma, mae: mae, rmse: rmse)
}

func intervals(
    _ predictions: [Double], _ sigma: [Double], _ coefficients: [Double], _ multipliers: [Double]
) -> [Interval] {
    predictions.enumerated().map { i, value in
        let multiplier = multipliers[i]
        return Interval(
            forecast: value * multiplier,
            lo80: (value - coefficients[0] * sigma[i]) * multiplier,
            hi80: (value + coefficients[0] * sigma[i]) * multiplier,
            lo95: (value - coefficients[1] * sigma[i]) * multiplier,
            hi95: (value + coefficients[1] * sigma[i]) * multiplier
        )
    }
}

func modelLines(_ model: ForecastModel) -> [String] {
    let name = model.name
    let common = "rmse \(real(rmse(model.residuals))) residuals \(model.residuals.count)"
    switch model.fit {
    case .naive, .seasonalNaive:
        return ["\(name) \(common)"]
    case let .drift(slope):
        return ["drift slope \(real(slope)) \(common)"]
    case let .smooth(parameters, states):
        var first = "\(name) alpha \(real(parameters.alpha))"
        if name != "ses" {
            first += " beta \(real(parameters.beta))"
        }
        if name == "damped" {
            first += " phi \(real(parameters.phi))"
        }
        if name == "hw_add" || name == "hw_mult" {
            first += " gamma \(real(parameters.gamma))"
        }
        let state = states.last!
        first += " \(common) level \(real(state.level))"
        if name != "ses" {
            first += " slope \(real(state.slope))"
        }
        var lines = [first]
        if !state.seasonal.isEmpty {
            let seasonal = (0..<model.season).map {
                real(state.seasonal[(model.values.count + $0) % model.season])
            }.joined(separator: " ")
            lines.append("\(name) seasonal \(seasonal)")
        }
        return lines
    case let .decomposition(intercept, slope, seasonal):
        return [
            "\(name) intercept \(real(intercept)) slope \(real(slope)) \(common)",
            "\(name) seasonal " + seasonal.map(real).joined(separator: " ")
        ]
    case let .ar(ar):
        let variances = differenceKinds.indices.map {
            "\(differenceKinds[$0]) \(real(ar.variances[$0]))"
        }.joined(separator: " ")
        let coefficients = ar.coefficients.isEmpty ? "none" : ar.coefficients.map(real).joined(separator: " ")
        return [
            "ar variance \(variances)",
            "ar difference \(differenceKinds[ar.kind]) n \(ar.differenced.count) mean \(real(ar.average)) "
                + "order \(ar.order) sigma2 \(real(ar.sigma2)) \(common)",
            "ar aic " + ar.aic.map(real).joined(separator: " "),
            "ar coefficients \(coefficients)"
        ]
    case .combo:
        return []
    }
}

func inventoryPlan(
    _ model: ForecastModel, _ demands: [Double], _ periods: [String], _ policy: Inventory,
    _ settings: Settings, _ lines: inout [String]
) {
    let protection = policy.leadTime + policy.review
    let errors = (settings.cvStart...(model.values.count - protection)).map { origin in
        let predictions = forecast(model, origin, protection)
        return total(predictions.indices.map { model.values[origin + $0] - predictions[$0] })
    }
    let safety = policy.service * rmse(errors)
    lines.append(
        "policy on_hand \(policy.onHand) lead_time \(policy.leadTime) review \(policy.review) "
            + "service \(real(policy.service)) safety_stock \(real(safety))"
    )
    let reviews = Array(stride(from: 1, through: demands.count - protection + 1, by: policy.review))
    let end = reviews.last! - 1 + protection
    var receipts = [Int](repeating: 0, count: end + policy.leadTime + 1)
    var onHand = Double(policy.onHand)
    var outstanding = 0
    var orders = 0
    var ordered = 0
    var shortPeriods = 0
    var stocks: [Double] = []
    for step in 1...end {
        let receipt = receipts[step]
        onHand += Double(receipt)
        outstanding -= receipt
        let period = periods[step - 1]
        if reviews.contains(step) {
            let position = onHand + Double(outstanding)
            let target = total(demands[(step - 1)..<(step - 1 + protection)]) + safety
            let quantity = max(0, Int(ceil(target - position)))
            lines.append("review \(period) position \(real(position)) target \(real(target)) order \(quantity)")
            if quantity > 0 {
                orders += 1
                ordered += quantity
                outstanding += quantity
                receipts[step + policy.leadTime] = quantity
            }
        }
        onHand -= demands[step - 1]
        let status = onHand < 0 ? "short" : onHand < safety ? "low" : "ok"
        if status == "short" {
            shortPeriods += 1
        }
        stocks.append(onHand)
        lines.append(
            "period \(period) demand \(real(demands[step - 1])) receipt \(receipt) "
                + "on_hand \(real(onHand)) status \(status)"
        )
    }
    lines.append(
        "summary orders \(orders) ordered \(ordered) short_periods \(shortPeriods) "
            + "lowest \(real(stocks.min()!)) average \(real(mean(stocks)))"
    )
}

struct YearTotal {
    var actualMonths = 0
    var actual = 0.0
    var forecastMonths = 0
    var forecast = 0.0
}

func yearlyTotals(_ record: Series, _ data: Prepared, _ demands: [Double], _ lines: inout [String]) {
    var years: [String: YearTotal] = [:]
    for (period, value) in zip(record.periods, data.values) {
        let year = String(period.prefix(4))
        years[year, default: YearTotal()].actualMonths += 1
        years[year, default: YearTotal()].actual += value
    }
    for (period, value) in zip(data.futurePeriods, demands) {
        let year = String(period.prefix(4))
        years[year, default: YearTotal()].forecastMonths += 1
        years[year, default: YearTotal()].forecast += value
    }
    var previous: (Bool, Double)?
    for year in years.keys.sorted() {
        let row = years[year]!
        let total = row.actual + row.forecast
        let complete = row.actualMonths + row.forecastMonths == 12
        var growth: Double?
        if let (wasComplete, old) = previous, complete && wasComplete {
            growth = 100 * (total - old) / old
        }
        lines.append(
            "year \(year) actual_months \(row.actualMonths) actual \(real(row.actual)) "
                + "forecast_months \(row.forecastMonths) forecast \(real(row.forecast)) "
                + "total \(real(total)) growth \(optionalReal(growth))"
        )
        previous = (complete, total)
    }
}

func centeredBar(_ value: Double, _ center: Int, _ width: Int, _ band: Double?) -> String {
    var cells = [Character](repeating: " ", count: center * 2 + 1)
    if let band {
        let threshold = Int(floor(band * Double(center) + 0.5))
        cells[center - threshold] = ":"
        cells[center + threshold] = ":"
    }
    cells[center] = "|"
    if value > 0 {
        for i in (center + 1)..<(center + 1 + width) {
            cells[i] = "#"
        }
    } else if value < 0 {
        for i in (center - width)..<center {
            cells[i] = "#"
        }
    }
    return String(cells)
}

func residualDiagnostics(_ model: ForecastModel, _ lags: [Int], _ lines: inout [String]) {
    let errors = model.residuals
    let count = errors.count
    let average = mean(errors)
    let centered = errors.map { $0 - average }
    let squared = total(centered.map { $0 * $0 })
    let m2 = squared / Double(count)
    let m3 = total(centered.map { $0 * $0 * $0 }) / Double(count)
    let m4 = total(centered.map { $0 * $0 * $0 * $0 }) / Double(count)
    let sd = sqrt(squared / Double(count - 1))
    let dw = total((1..<count).map { (errors[$0] - errors[$0 - 1]) * (errors[$0] - errors[$0 - 1]) })
        / total(errors.map { $0 * $0 })
    let skewness = m3 / (m2 * sqrt(m2))
    let kurtosis = m4 / (m2 * m2) - 3
    let jb = Double(count) / 6 * (skewness * skewness + kurtosis * kurtosis / 4)
    lines.append(
        "residuals \(model.name) n \(count) mean \(real(average)) sd \(real(sd)) dw \(real(dw)) "
            + "skewness \(real(skewness)) kurtosis \(real(kurtosis)) jb \(real(jb))"
    )
    let tests = ljungBox(errors, lags).map { lag, q, p in
        "lag \(lag) q \(real(q)) p \(real(p))"
    }.joined(separator: " ")
    lines.append("ljung_box \(model.name) \(tests)")
}

func forecastChart(_ row: Interval, _ actual: Double?, _ low: Double, _ high: Double) -> String {
    func column(_ value: Double) -> Int {
        Int(floor((value - low) / (high - low) * 60 + 0.5))
    }
    var cells = [Character](repeating: " ", count: 61)
    let ranges: [(Double, Double, Character)] = [(row.lo95, row.hi95, "-"), (row.lo80, row.hi80, "=")]
    for (start, stop, symbol) in ranges {
        let first = column(start)
        let last = column(stop)
        if first <= last {
            for i in first...last {
                cells[i] = symbol
            }
        }
    }
    cells[column(row.forecast)] = "o"
    if let actual {
        cells[column(actual)] = "*"
    }
    return String(cells)
}

func analyze(_ record: Series, _ settings: Settings, _ reports: inout Reports) {
    let data = prepare(record, settings)
    let count = data.values.count
    let trainingCount = count - settings.holdout
    let training = Array(data.corrected.prefix(trainingCount))
    let actual = Array(data.values.suffix(settings.holdout))
    var models = methods.map { fitMethod($0, training, settings) }
    var cvs = models.map { crossValidate($0, settings) }
    let selected = Array(rankModels(cvs.map { $0.rmse }).prefix(settings.combo))
    let members = methods.indices.filter { selected.contains($0) }
    let combo = combination(members.map { models[$0] }, training, settings.season)
    cvs.append(crossValidate(combo, settings))
    models.append(combo)
    let scale = seasonalScale(training, settings.season)
    var holdout: [[Interval]] = []
    var metrics: [Measures] = []
    for i in models.indices {
        let predicted = forecast(models[i], trainingCount, settings.holdout)
        let rows = intervals(
            predicted, cvs[i].sigma, settings.interval, [Double](repeating: 1, count: settings.holdout)
        )
        let accuracyValues = accuracy(actual, predicted, scale)
        let cover80 = actual.indices.filter { rows[$0].lo80 <= actual[$0] && actual[$0] <= rows[$0].hi80 }.count
        let cover95 = actual.indices.filter { rows[$0].lo95 <= actual[$0] && actual[$0] <= rows[$0].hi95 }.count
        let winkler80 = total(actual.indices.map {
            winkler(actual[$0], rows[$0].lo80, rows[$0].hi80, 10)
        }) / Double(actual.count)
        let winkler95 = total(actual.indices.map {
            winkler(actual[$0], rows[$0].lo95, rows[$0].hi95, 40)
        }) / Double(actual.count)
        metrics.append(Measures(
            accuracy: accuracyValues, cover80: cover80, cover95: cover95, winkler80: winkler80, winkler95: winkler95
        ))
        holdout.append(rows)
    }
    let ranking = rankModels(metrics.map { $0.accuracy.rmse })
    let best = ranking[0]
    let finalNames = best == 11 ? members : [best]
    let finalFits = finalNames.map { fitMethod(methods[$0], data.corrected, settings) }
    let finalModel = best == 11 ? combination(finalFits, data.corrected, settings.season) : finalFits[0]
    let finalCV = crossValidate(finalModel, settings)
    let multipliers = data.futurePeriods.map { period -> Double in
        guard let kind = record.events[period] else { return 1 }
        return data.lifts.first { $0.kind == kind }!.value
    }
    let future = intervals(
        forecast(finalModel, count, settings.horizon), finalCV.sigma, settings.interval, multipliers
    )
    let demands = future.map { $0.forecast }
    let name = record.name
    let components = data.components
    for t in 0..<count {
        let j = t % settings.season
        let flag = data.past[t] ?? (record.raw[t] == nil ? "missing" : data.outliers[t] != nil ? "outlier" : "ok")
        let fields = [
            name, record.periods[t], real(data.values[t]), real(data.corrected[t]),
            optionalReal(components.trend[t]), real(components.additive[j]), optionalReal(components.residualAdd[t]),
            real(components.multiplicative[j]), optionalReal(components.residualMult[t]), flag
        ]
        reports.decomposition.append(fields.joined(separator: ","))
    }
    reports.models.append("series \(name)")
    reports.models.append(
        "data observations \(count) train \(trainingCount) holdout \(settings.holdout) "
            + "missing \(record.raw.filter { $0 == nil }.count) outliers \(data.outliers.compactMap { $0 }.count) "
            + "events \(data.past.compactMap { $0 }.count)"
    )
    for lift in data.lifts {
        reports.models.append("event \(lift.kind) occurrences \(lift.times.count) lift \(real(lift.value))")
    }
    for t in data.outliers.indices {
        if let score = data.outliers[t] {
            reports.models.append(
                "outlier \(record.periods[t]) value \(real(data.values[t])) "
                    + "expected \(real(data.corrected[t])) score \(real(score))"
            )
        }
    }
    reports.models.append("strength trend \(real(data.strengthTrend)) seasonal \(real(data.strengthSeasonal))")
    for model in models.prefix(11) {
        reports.models += modelLines(model)
    }
    reports.models.append("combo members " + members.map { methods[$0] }.joined(separator: " "))
    reports.models.append("best \(modelNames[best]) rmse \(real(metrics[best].accuracy.rmse))")
    for model in finalFits {
        reports.models += modelLines(model).map { "final " + $0 }
    }
    for i in models.indices {
        for (t, row) in holdout[i].enumerated() {
            let prefix = "\(name),holdout,\(modelNames[i]),\(record.periods[trainingCount + t]),"
            reports.forecasts.append(prefix + "\(record.raw[trainingCount + t]!)," + row.csv())
        }
        let m = metrics[i]
        let a = m.accuracy
        let fva = 100 * (metrics[0].accuracy.mae - a.mae) / metrics[0].accuracy.mae
        let values = [a.me, a.mae, a.rmse, a.mape, a.smape, a.mase, fva, cvs[i].rmse]
        let rank = ranking.firstIndex(of: i)! + 1
        var fields = [name, modelNames[i]] + values.map(real)
        fields += [String(m.cover80), String(m.cover95), real(m.winkler80), real(m.winkler95), String(rank)]
        reports.accuracy.append(fields.joined(separator: ","))
        for k in 0..<settings.horizon {
            reports.cv.append(
                "\(name),\(modelNames[i]),\(k + 1),\(cvs[i].counts[k]),"
                    + "\(real(cvs[i].mae[k])),\(real(cvs[i].sigma[k]))"
            )
        }
    }
    for (period, row) in zip(data.futurePeriods, future) {
        reports.forecasts.append("\(name),future,\(modelNames[best]),\(period),NA," + row.csv())
    }
    if case let .ar(ar) = models[10].fit {
        let band = 2 / sqrt(Double(ar.differenced.count))
        reports.correlogram.append(
            "series \(name) difference \(differenceKinds[ar.kind]) n \(ar.differenced.count) band \(real(band))"
        )
        for (label, sequence) in [("acf", ar.correlations), ("pacf", ar.partial)] {
            for lag in 1..<sequence.count {
                let value = sequence[lag]
                let width = Int(floor(abs(value) * 20 + 0.5))
                let lagText = String(repeating: " ", count: max(0, 2 - String(lag).count)) + String(lag)
                let valueText = String(repeating: " ", count: max(0, 7 - real(value).count)) + real(value)
                let bar = centeredBar(value, 20, width, band)
                let marker = abs(value) > band ? " *" : ""
                reports.correlogram.append("\(label) \(lagText) \(valueText) [\(bar)]\(marker)")
            }
        }
    }
    for model in models.prefix(11) {
        residualDiagnostics(model, settings.ljungBox, &reports.correlogram)
    }
    var chartRows: [(String, Interval, Double?)] = holdout[best].enumerated().map { t, row in
        (record.periods[trainingCount + t], row, actual[t])
    }
    chartRows += zip(data.futurePeriods, future).map { ($0.0, $0.1, nil) }
    let low = chartRows.map { min($0.1.lo95, $0.2 ?? $0.1.lo95) }.min()!
    let high = chartRows.map { max($0.1.hi95, $0.2 ?? $0.1.hi95) }.max()!
    reports.chart.append("chart \(name) method \(modelNames[best])")
    reports.chart.append("scale low \(real(low)) high \(real(high))")
    for (period, row, actual) in chartRows {
        reports.chart.append("\(period) |\(forecastChart(row, actual, low, high))|")
    }
    let peak = components.multiplicative.map { abs($0 - 1) }.max()!
    reports.chart.append("profile peak \(real(peak))")
    for (j, value) in components.multiplicative.enumerated() {
        let width = Int(floor(abs(value - 1) / peak * 30 + 0.5))
        let position = String(repeating: " ", count: max(0, 2 - String(j + 1).count)) + String(j + 1)
        reports.chart.append("season \(position) \(real(value)) [\(centeredBar(value - 1, 30, width, nil))]")
    }
    reports.plan.append("series \(name) method \(modelNames[best])")
    inventoryPlan(finalModel, demands, data.futurePeriods, record.inventory, settings, &reports.plan)
    yearlyTotals(record, data, demands, &reports.plan)
}

let (series, settings) = readInputs()
var reports = Reports()
for record in series {
    analyze(record, settings, &reports)
}
for (name, lines) in [
    ("decomposition.csv", reports.decomposition), ("models.txt", reports.models),
    ("forecasts.csv", reports.forecasts), ("accuracy.csv", reports.accuracy),
    ("cv.csv", reports.cv), ("correlogram.txt", reports.correlogram),
    ("chart.txt", reports.chart), ("plan.txt", reports.plan)
] {
    writeLines(name, lines)
}
