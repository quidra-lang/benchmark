import Foundation

func orderedSum<S: Sequence>(_ values: S) -> Double where S.Element == Double { var total = 0.0; for value in values { total += value }; return total }
func squaredErrors(_ series: [Double], _ coefficient: Double, _ observations: [Int]) -> Double { var total = 0.0; for i in series.indices { let difference = coefficient * series[i] - Double(observations[i]); total += difference * difference }; return total }
func peak<T: Comparable>(_ series: [T]) -> Int { var best = 0; for i in series.indices.dropFirst() { if series[i] > series[best] { best = i } }; return best }
func multiplierSequence(_ interventions: [Intervention], _ days: Int) -> [Double] { var values: [Double] = [], index = 0; for day in 1...days { while index + 1 < interventions.count && interventions[index + 1].day <= day { index += 1 }; values.append(interventions[index].multiplier) }; return values }
func finalSize(_ reproduction: Double) -> Double { if reproduction <= 1 { return 0 }; var lower = 1 - 1 / reproduction, upper = 1.0; for _ in 0..<20 { let middle = (lower + upper) / 2, value = 1 - middle - exp(-reproduction * middle); if value > 0 { lower = middle } else { upper = middle } }; return (lower + upper) / 2 }
func powerMethod(_ matrix: [[Double]]) -> (value: Double, vector: [Double]) { var vector = Array(repeating: 1 / Double(matrix.count), count: matrix.count), eigenvalue = 0.0; for _ in 0..<200 { let product = matrix.map { row in orderedSum(row.indices.map { row[$0] * vector[$0] }) }; eigenvalue = orderedSum(product); vector = product.map { $0 / eigenvalue } }; return (eigenvalue, vector) }
struct FitKey: Hashable { let beta: Double; let gamma: Double }
final class Study {
    let cases: [Int]
    let deaths: [Int]
    let groups: [AgeGroup]
    let contacts: [[Double]]
    let interventions: [Intervention]
    let settings: Settings
    let days: Int
    let populations: [Double]
    let fatalities: [Double]
    let population: Int
    let totalPopulation: Double
    let caseTotal: Int
    let deathTotal: Int
    let fatality: Double
    let sigma: Double
    let gamma0: Double
    let initial: [Double]
    let sirInitial: [Double]
    let ageInitial: [Double]
    let multipliers: [Double]
    let weeks: [Range<Int>]
    var incidenceCache: [FitKey: [Double]] = [:]
    var fitLines: [String] = []
    var reproductionLines: [String] = []
    var ageLines: [String] = []
    var scenarioRows: [String] = []
    var deltaBeta = 0.0
    var deltaRho = 0.0
    var gridBeta = 0.0
    var gridRho = 0.0
    var gridSSE = 0.0
    var goldenBeta = 0.0
    var goldenSSE = 0.0
    var beta = 0.0
    var gamma = 0.0
    var rho = 0.0
    var fittedSSE = 0.0
    var r0 = 0.0
    var states: [[Double]] = []
    var incidence: [Double] = []
    var reported: [Double] = []
    var residuals: [Double] = []
    var modelDeaths: [Double] = []
    var rt: [Double] = []
    var averages: [Double] = []
    var cumulativeCases: [Int] = []
    var cumulativeReported: [Double] = []
    var reportedTotal = 0.0
    var standardErrors: [Double] = []
    var normalizedContacts: [[Double]] = []
    var ageStates: [[Double]] = []
    var ageIncidence: [Double] = []
    init(_ input: Inputs) {
        let population = input.groups.reduce(0) { $0 + $1.population }, total = Double(population), exposed = input.settings.exposed, infectious = input.settings.infectious
        cases = input.cases; deaths = input.deaths; groups = input.groups; contacts = input.contacts; interventions = input.interventions; settings = input.settings; days = input.cases.count; populations = input.groups.map { Double($0.population) }; fatalities = input.groups.map { $0.fatality }; self.population = population; totalPopulation = total; caseTotal = input.cases.reduce(0, +); deathTotal = input.deaths.reduce(0, +); fatality = orderedSum(input.groups.map { Double($0.population) * $0.fatality }) / total; sigma = input.settings.sigma; gamma0 = input.settings.gamma
        initial = [total - exposed - infectious, exposed, infectious, 0, 0, 0]; sirInitial = [total - exposed - infectious, exposed + infectious, 0, 0]
        var age: [Double] = []
        for group in input.groups { let number = Double(group.population), e = exposed * number / total, i = infectious * number / total; age += [number - e - i, e, i, 0, 0, 0] }
        ageInitial = age; multipliers = multiplierSequence(input.interventions, input.cases.count); weeks = stride(from: 0, to: input.cases.count, by: 7).map { $0..<min($0 + 7, input.cases.count) }
    }
    func rmse(_ error: Double, _ count: Int? = nil) -> Double { sqrt(error / Double(count ?? days)) }
    func seirdStates(_ beta: Double, _ gamma: Double, multipliers: [Double]? = nil, initial: [Double]? = nil, sigma: Double? = nil) -> [[Double]] { simulate(seird(totalPopulation, sigma ?? self.sigma, fatality, beta, gamma), initial ?? self.initial, multipliers ?? self.multipliers, [5]) }
    func incidenceFor(_ beta: Double, _ gamma: Double) -> [Double] { let key = FitKey(beta: beta, gamma: gamma); if let values = incidenceCache[key] { return values }; let values = seirdStates(beta, gamma).map { $0[5] }; incidenceCache[key] = values; return values }
    func error(_ beta: Double, _ gamma: Double, _ rho: Double) -> Double { squaredErrors(incidenceFor(beta, gamma), rho, cases) }
    func goldenRecords(_ round: Int, _ name: String, _ search: GoldenResult) { for (index, record) in search.records.enumerated() { fitLines.append("golden \(round) \(name) \(index) a \(fmt(record.a, 6)) b \(fmt(record.b, 6)) c \(fmt(record.c, 6)) d \(fmt(record.d, 6)) rmse \(fmt(rmse(record.fc))) \(fmt(rmse(record.fd)))") }; fitLines.append("golden_result \(round) \(name) \(fmt(search.point, 6)) sse \(fmt(search.value, 1))") }
    func fitModel() {
        let betaGrid = settings.betaGrid, rhoGrid = settings.rhoGrid, betas = (0..<betaGrid.count).map { betaGrid.minimum + (betaGrid.maximum - betaGrid.minimum) * Double($0) / Double(betaGrid.count - 1) }, rhos = (0..<rhoGrid.count).map { rhoGrid.minimum + (rhoGrid.maximum - rhoGrid.minimum) * Double($0) / Double(rhoGrid.count - 1) }
        deltaBeta = (betaGrid.maximum - betaGrid.minimum) / Double(betaGrid.count - 1); deltaRho = (rhoGrid.maximum - rhoGrid.minimum) / Double(rhoGrid.count - 1)
        fitLines += ["data days \(days) cases \(caseTotal) deaths \(deathTotal) population \(population) fatality \(fmt(fatality, 6))", "grid gamma \(fmt(gamma0)) rho " + rhos.map { fmt($0) }.joined(separator: " ")]
        var best = Double.infinity
        for b in betas { var errors: [Double] = []; for r in rhos { let value = error(b, gamma0, r); errors.append(value); if value < best { best = value; gridBeta = b; gridRho = r } }; fitLines.append("grid beta \(fmt(b)) rmse " + errors.map { fmt(rmse($0), 2) }.joined(separator: " ")) }
        gridSSE = best
        fitLines.append("grid_best beta \(fmt(gridBeta)) rho \(fmt(gridRho)) sse \(fmt(gridSSE, 1)) rmse \(fmt(rmse(gridSSE)))")
        var b = gridBeta, r = gridRho
        for round in 1...settings.goldenRounds { let betaSearch = golden({ self.error($0, self.gamma0, r) }, b - deltaBeta, b + deltaBeta, settings.goldenIterations); goldenRecords(round, "beta", betaSearch); b = betaSearch.point; let rhoSearch = golden({ self.error(b, self.gamma0, $0) }, r - deltaRho, r + deltaRho, settings.goldenIterations); goldenRecords(round, "rho", rhoSearch); r = rhoSearch.point; goldenSSE = rhoSearch.value }
        goldenBeta = b; rho = r
        let result = nelderMead({ self.error($0, $1, r) }, b, gamma0, settings.simplex, settings.nelderMead)
        for vertex in result.initial { fitLines.append("simplex \(vertex.number) beta \(fmt(vertex.point.beta, 6)) gamma \(fmt(vertex.point.gamma, 6)) rmse \(fmt(rmse(vertex.value)))") }
        for (index, record) in result.records.enumerated() { let vertex = record.vertex; fitLines.append("nelder_mead \(index + 1) \(record.operation) beta \(fmt(vertex.point.beta, 6)) gamma \(fmt(vertex.point.gamma, 6)) rmse \(fmt(rmse(vertex.value)))") }
        for (index, vertex) in result.vertices.enumerated() { fitLines.append("final_simplex \(index + 1) beta \(fmt(vertex.point.beta, 6)) gamma \(fmt(vertex.point.gamma, 6)) rmse \(fmt(rmse(vertex.value)))") }
        let vertex = result.vertices[0]
        beta = vertex.point.beta; gamma = vertex.point.gamma; fittedSSE = vertex.value; r0 = beta / gamma
        let mean = Double(caseTotal) / Double(days), sst = orderedSum(cases.map { let difference = Double($0) - mean; return difference * difference })
        fitLines += ["fitted beta \(fmt(beta, 6)) gamma \(fmt(gamma, 6)) rho \(fmt(rho, 6)) sigma \(fmt(sigma, 6)) r0 \(fmt(r0))", "sse grid \(fmt(gridSSE, 1)) golden \(fmt(goldenSSE, 1)) nelder_mead \(fmt(fittedSSE, 1)) rmse \(fmt(rmse(fittedSSE))) r2 \(fmt(1 - fittedSSE / sst))"]
        let stages = [("grid", gridBeta, gamma0, gridRho, gridSSE), ("golden", goldenBeta, gamma0, rho, goldenSSE), ("nelder_mead", beta, gamma, rho, fittedSSE)]
        for (name, b, g, r, value) in stages { fitLines.append("stage \(name) beta \(fmt(b, 6)) gamma \(fmt(g, 6)) rho \(fmt(r, 6)) r0 \(fmt(b / g)) rmse \(fmt(rmse(value)))") }
    }
    func fittedDiagnostics() {
        states = [initial] + seirdStates(beta, gamma); incidence = states.dropFirst().map { $0[5] }; reported = incidence.map { rho * $0 }; residuals = cases.indices.map { Double(cases[$0]) - reported[$0] }; modelDeaths = (1...days).map { states[$0][4] - states[$0 - 1][4] }; rt = cases.indices.map { r0 * multipliers[$0] * states[$0][0] / totalPopulation }; averages = cases.indices.map { Double(cases[max(0, $0 - 6)...$0].reduce(0, +)) / Double(min($0 + 1, 7)) }
        var observedTotal = 0, fittedTotal = 0.0
        for i in cases.indices { observedTotal += cases[i]; fittedTotal += reported[i]; cumulativeCases.append(observedTotal); cumulativeReported.append(fittedTotal) }
        reportedTotal = fittedTotal
        let absolute = residuals.map { abs($0) }, largest = peak(absolute), positive = residuals.filter { $0 > 0 }.count, runs = 1 + (1..<days).filter { (residuals[$0] > 0) != (residuals[$0 - 1] > 0) }.count, residualSquare = orderedSum(residuals.map { $0 * $0 }), differences = (1..<days).map { residuals[$0] - residuals[$0 - 1] }, durbinWatson = orderedSum(differences.map { $0 * $0 }) / residualSquare
        fitLines.append("residuals sum \(fmt(orderedSum(residuals), 1)) mae \(fmt(orderedSum(absolute) / Double(days), 1)) max \(fmt(residuals[largest], 1)) day \(largest + 1) positive \(positive) runs \(runs) durbin_watson \(fmt(durbinWatson))")
        let correlations = (1...7).map { lag in orderedSum((0..<(days - lag)).map { residuals[$0] * residuals[$0 + lag] }) / residualSquare }
        fitLines.append("autocorrelation " + correlations.map { fmt($0) }.joined(separator: " "))
        var outliers = 0
        for i in cases.indices { let z = residuals[i] / sqrt(reported[i]); if abs(z) > settings.outlier { outliers += 1; fitLines.append("outlier \(i + 1) observed \(cases[i]) fitted \(fmt(reported[i], 1)) z \(fmt(z))") } }
        fitLines.append("outliers \(outliers)")
        var weekdayFactors: [Double] = []
        for weekday in 0..<7 { let indices = Array(stride(from: weekday, to: days, by: 7)), observed = indices.reduce(0) { $0 + cases[$1] }, fitted = orderedSum(indices.map { reported[$0] }), factor = Double(observed) / fitted; weekdayFactors.append(factor); fitLines.append("weekday \(weekday + 1) observed \(observed) fitted \(fmt(fitted, 1)) factor \(fmt(factor))") }
        fitLines.append("weekday_adjusted rmse \(fmt(rmse(squaredErrors(reported.indices.map { reported[$0] * weekdayFactors[$0 % 7] }, 1, cases))))")
        let infections = orderedSum(incidence)
        fitLines.append("burden infections \(fmt(infections, 1)) ascertainment \(fmt(Double(caseTotal) / infections)) deaths_per_infection \(fmt(Double(deathTotal) / infections, 6))")
        deathAnalysis()
        var previous: Int?
        for (week, range) in weeks.enumerated() { let observed = cases[range].reduce(0, +), fitted = orderedSum(reported[range]), deathsObserved = deaths[range].reduce(0, +), deathsModel = orderedSum(modelDeaths[range]), growth = previous.map { fmt(Double(observed) / Double($0)) } ?? "-"; fitLines.append("weekly \(week + 1) days \(range.lowerBound + 1) \(range.upperBound) observed \(observed) fitted \(fmt(fitted, 1)) deaths_observed \(deathsObserved) deaths_model \(fmt(deathsModel, 1)) growth \(growth)"); previous = observed }
    }
    func deathAnalysis() {
        let numerator = orderedSum(cases.indices.map { modelDeaths[$0] * Double(deaths[$0]) }), denominator = orderedSum(modelDeaths.map { $0 * $0 }), scale = numerator / denominator
        fitLines.append("deaths observed \(deathTotal) model \(fmt(states.last![4], 1)) rmse \(fmt(rmse(squaredErrors(modelDeaths, 1, deaths)))) scale \(fmt(scale)) implied_fatality \(fmt(fatality * scale, 6)) cfr \(fmt(Double(deathTotal) / Double(caseTotal)))")
        var correlations: [Double] = []
        for lag in 0...settings.deathLag { let a = (0..<(days - lag)).reduce(0) { $0 + cases[$1] * deaths[$1 + lag] }, b = cases.prefix(days - lag).reduce(0) { $0 + $1 * $1 }, y = deaths.dropFirst(lag).reduce(0) { $0 + $1 * $1 }, correlation = Double(a) / sqrt(Double(b) * Double(y)), cfr = Double(deaths.dropFirst(lag).reduce(0, +)) / Double(cases.prefix(days - lag).reduce(0, +)); correlations.append(correlation); fitLines.append("death_lag \(lag) correlation \(fmt(correlation)) cfr \(fmt(cfr))") }
        fitLines.append("death_best_lag \(peak(correlations))")
    }
    func profiles() {
        let fitted = [beta, gamma, rho], names = ["beta", "gamma", "rho"], variance = fittedSSE / Double(days - 3)
        for index in fitted.indices { let value = fitted[index]; var errors: [Double] = []; for offset in -5...5 { let point = value * (1 + Double(offset) / 100); var parameters = fitted; parameters[index] = point; let error = self.error(parameters[0], parameters[1], parameters[2]); errors.append(error); fitLines.append("profile \(names[index]) \(offset) value \(fmt(point, 6)) rmse \(fmt(rmse(error)))") }; let h = value / 100, curvature = (errors[6] - 2 * errors[5] + errors[4]) / (h * h), standardError = sqrt(2 * variance / curvature); standardErrors.append(standardError); fitLines.append("profile_se \(names[index]) \(fmt(standardError, 6))") }
    }
    func backtest() {
        let count = days - settings.holdout, multipliers = Array(self.multipliers.prefix(count)), observations = Array(cases.prefix(count))
        var cache: [Double: [Double]] = [:]
        func trainingError(_ beta: Double, _ rho: Double) -> Double { if cache[beta] == nil { cache[beta] = seirdStates(beta, gamma, multipliers: multipliers).map { $0[5] } }; return squaredErrors(cache[beta]!, rho, observations) }
        let betaSearch = golden({ trainingError($0, rho) }, beta - deltaBeta, beta + deltaBeta, settings.goldenIterations), rhoSearch = golden({ trainingError(betaSearch.point, $0) }, rho - deltaRho, rho + deltaRho, settings.goldenIterations), forecasts = incidenceFor(betaSearch.point, gamma).dropFirst(count).map { rhoSearch.point * $0 }, heldCases = Array(cases.dropFirst(count)), testError = squaredErrors(forecasts, 1, heldCases), fullError = squaredErrors(Array(reported.dropFirst(count)), 1, heldCases)
        fitLines.append("backtest train_days \(count) beta \(fmt(betaSearch.point, 6)) rho \(fmt(rhoSearch.point, 6)) train_rmse \(fmt(rmse(rhoSearch.value, count))) test_rmse \(fmt(rmse(testError, settings.holdout))) full_fit_test_rmse \(fmt(rmse(fullError, settings.holdout)))")
        for (index, forecast) in forecasts.enumerated() { let day = count + index; fitLines.append("backtest_day \(day + 1) observed \(cases[day]) forecast \(fmt(forecast, 1)) error \(fmt(Double(cases[day]) - forecast, 1))") }
    }
    func estimateEffects() {
        var estimated = interventions, after = fittedSSE
        for index in 1..<interventions.count { let intervention = interventions[index]; let result = golden({ value in var changed = estimated; changed[index].multiplier = value; let incidence = self.seirdStates(self.beta, self.gamma, multipliers: multiplierSequence(changed, self.days)).map { $0[5] }; return squaredErrors(incidence, self.rho, self.cases) }, intervention.multiplier - settings.effectWidth, intervention.multiplier + settings.effectWidth, settings.goldenIterations); estimated[index].multiplier = result.point; after = result.value; fitLines.append("effect \(index + 1) day \(intervention.day) given \(fmt(intervention.multiplier)) estimated \(fmt(result.point, 6)) sse \(fmt(after, 1))") }
        fitLines.append("effect_sse before \(fmt(fittedSSE, 1)) after \(fmt(after, 1)) rmse \(fmt(rmse(after)))")
    }
    func sensitivity() {
        let fitted = [beta, gamma, sigma, rho], names = ["beta", "gamma", "sigma", "rho"]
        for index in fitted.indices { for factor in [0.9, 1.1] { var values = fitted; values[index] *= factor; let states = seirdStates(values[0], values[1], sigma: values[2]), incidence = states.map { $0[5] }, day = peak(incidence), attack = (totalPopulation - states.last![0]) / totalPopulation; fitLines.append("sensitivity \(names[index]) \(fmt(factor, 2)) r0 \(fmt(values[0] / values[1])) rmse \(fmt(rmse(squaredErrors(incidence, values[3], cases)))) peak_day \(day + 1) peak \(fmt(values[3] * incidence[day], 1)) attack \(fmt(attack))") } }
    }
}
extension Study {
    func ageStatesFor(contacts: [[Double]]? = nil, multipliers: [Double]? = nil, initial: [Double]? = nil) -> [[Double]] { simulate(ageSEIRD(populations, fatalities, sigma, beta, gamma, contacts ?? normalizedContacts), initial ?? ageInitial, multipliers ?? self.multipliers, Array(stride(from: 5, to: groups.count * 6, by: 6))) }
    func nextGeneration(_ contacts: [[Double]]) -> [[Double]] { groups.indices.map { g in groups.indices.map { h in r0 * contacts[g][h] * populations[g] / populations[h] } } }
    func analyzeAge() {
        let rowTotals = contacts.map { orderedSum($0) }, kbar = orderedSum(groups.indices.map { populations[$0] * rowTotals[$0] }) / totalPopulation
        normalizedContacts = contacts.map { row in row.map { $0 / kbar } }
        let matrix = nextGeneration(normalizedContacts), eigen = powerMethod(matrix)
        for (index, group) in groups.enumerated() { ageLines.append("ngm \(group.name) " + matrix[index].map { fmt($0) }.joined(separator: " ")) }
        ageLines.append("r0_age \(fmt(eigen.value)) ratio \(fmt(eigen.value / r0)) kbar \(fmt(kbar)) eigenvector " + eigen.vector.map { fmt($0) }.joined(separator: " "))
        var sizes = Array(repeating: 1.0, count: groups.count)
        for _ in 0..<100 { let previous = sizes; sizes = normalizedContacts.map { row in 1 - exp(-orderedSum(groups.indices.map { r0 * row[$0] * previous[$0] })) } }
        let longStates = ageStatesFor(multipliers: Array(repeating: 1, count: 730)), simulated = groups.indices.map { (populations[$0] - longStates.last![6 * $0]) / populations[$0] }
        for (g, group) in groups.enumerated() { ageLines.append("final_size_age \(group.name) equation \(fmt(sizes[g])) simulated \(fmt(simulated[g]))") }
        let equationTotal = orderedSum(groups.indices.map { populations[$0] * sizes[$0] }) / totalPopulation, simulatedTotal = orderedSum(groups.indices.map { populations[$0] * simulated[$0] }) / totalPopulation
        ageLines.append("final_size_age total equation \(fmt(equationTotal)) simulated \(fmt(simulatedTotal))")
        ageStates = [ageInitial] + ageStatesFor(); ageIncidence = ageStates.dropFirst().map { state in orderedSum(groups.indices.map { state[6 * $0 + 5] }) }
        for day in stride(from: 1, through: days, by: 7) { let previous = ageStates[day - 1], matrix = groups.indices.map { g in groups.indices.map { h in multipliers[day - 1] * r0 * normalizedContacts[g][h] * previous[6 * g] / populations[h] } }; ageLines.append("age_rt \(day) \(fmt(powerMethod(matrix).value)) homogeneous \(fmt(rt[day - 1]))") }
        for (week, range) in weeks.enumerated() { let totals = groups.indices.map { g in orderedSum(range.map { ageStates[$0 + 1][6 * g + 5] }) }; ageLines.append("age_weekly \(week + 1) days \(range.lowerBound + 1) \(range.upperBound) " + totals.map { fmt($0, 1) }.joined(separator: " ")) }
        let infections = groups.indices.map { g in orderedSum(ageStates.dropFirst().map { $0[6 * g + 5] }) }, infectionTotal = orderedSum(infections)
        for (g, group) in groups.enumerated() { let incidence = ageStates.dropFirst().map { $0[6 * g + 5] }, day = peak(incidence), attack = (populations[g] - ageStates.last![6 * g]) / populations[g], deaths = ageStates.last![6 * g + 4]; ageLines.append("age \(group.name) attack \(fmt(attack)) infections \(fmt(infections[g], 1)) share \(fmt(infections[g] / infectionTotal)) deaths \(fmt(deaths, 1)) peak_day \(day + 1) peak \(fmt(incidence[day], 1))") }
        for change in settings.contactChanges {
            let target = groups.firstIndex { $0.name == change.group }!, tau = groups.indices.map { $0 == target ? change.factor : 1 }, contacts = groups.indices.map { g in groups.indices.map { h in normalizedContacts[g][h] * tau[g] * tau[h] } }, eigenvalue = powerMethod(nextGeneration(contacts)).value, states = ageStatesFor(contacts: contacts)
            let infections = orderedSum(states.map { state in orderedSum(groups.indices.map { state[6 * $0 + 5] }) }), deaths = orderedSum(groups.indices.map { states.last![6 * $0 + 4] }), attack = orderedSum(groups.indices.map { populations[$0] - states.last![6 * $0] }) / totalPopulation
            ageLines.append("contact_change \(change.name) group \(change.group) factor \(fmt(change.factor)) r0_age \(fmt(eigenvalue)) infections \(fmt(infections, 1)) deaths \(fmt(deaths, 1)) attack \(fmt(attack))")
        }
    }
    func sirIncidence(_ beta: Double) -> [Double] { simulate(sir(totalPopulation, beta, gamma), sirInitial, multipliers, [3]).map { $0[3] } }
    func compareModels() {
        for (name, incidence) in [("sir", sirIncidence(beta)), ("seir", self.incidence), ("age", ageIncidence)] { let error = squaredErrors(incidence, rho, cases), numerator = orderedSum(cases.indices.map { Double(cases[$0]) * incidence[$0] }), denominator = orderedSum(incidence.map { $0 * $0 }), optimalRho = numerator / denominator, optimal = squaredErrors(incidence, optimalRho, cases); fitLines.append("model \(name) rmse \(fmt(rmse(error))) peak_day \(peak(incidence) + 1) rho_opt \(fmt(optimalRho, 6)) rmse_opt \(fmt(rmse(optimal)))") }
        let result = golden({ squaredErrors(self.sirIncidence($0), self.rho, self.cases) }, settings.betaGrid.minimum, settings.betaGrid.maximum, settings.goldenIterations)
        fitLines.append("model sir_fit beta \(fmt(result.point, 6)) rmse \(fmt(rmse(result.value))) peak_day \(peak(sirIncidence(result.point)) + 1)")
    }
    func generationInterval() -> [Double?] {
        let length = settings.generation, states = simulate(generation(sigma, gamma), [1, 0, 0], Array(repeating: 1, count: length), [2]), amounts = states.map { $0[2] }, coverage = orderedSum(amounts), weights = amounts.map { $0 / coverage }, mean = orderedSum(weights.indices.map { (Double($0 + 1) - 0.5) * weights[$0] }), theory = 1 / sigma + 1 / gamma
        reproductionLines.append("generation mean \(fmt(mean)) theory \(fmt(theory)) coverage \(fmt(coverage))")
        for (index, weight) in weights.enumerated() { reproductionLines.append("generation_weight \(index + 1) \(fmt(weight, 6))") }
        let pressures = cases.indices.map { index in orderedSum((0..<min(length, index)).map { weights[$0] * Double(cases[index - $0 - 1]) }) }
        return cases.indices.map { index in if index + 1 < length + 7 { return nil }; return Double(cases[(index - 6)...index].reduce(0, +)) / orderedSum(pressures[(index - 6)...index]) }
    }
    func epidemicPeaks() {
        let incidenceDay = peak(incidence), infectious = states.dropFirst().map { $0[2] }, infectiousDay = peak(infectious), observedDay = peak(cases), averageDay = peak(averages)
        reproductionLines += ["peak model day \(incidenceDay + 1) incidence \(fmt(incidence[incidenceDay], 1)) reported \(fmt(reported[incidenceDay], 1)) infectious_day \(infectiousDay + 1) infectious \(fmt(infectious[infectiousDay], 1))", "peak observed day \(observedDay + 1) cases \(cases[observedDay]) average7_day \(averageDay + 1) average7 \(fmt(averages[averageDay], 2))"]
    }
    func periodsAndMilestones() {
        for (index, intervention) in interventions.enumerated() { let end = index + 1 < interventions.count ? interventions[index + 1].day - 1 : days, range = (intervention.day - 1)..<end, error = orderedSum(residuals[range].map { $0 * $0 }), observed = cases[range].reduce(0, +), fitted = orderedSum(reported[range]), bias = orderedSum(residuals[range]) / Double(range.count); reproductionLines.append("period \(index + 1) days \(intervention.day) \(end) multiplier \(fmt(intervention.multiplier)) rt_start \(fmt(rt[intervention.day - 1])) rt_end \(fmt(rt[end - 1])) observed \(observed) fitted \(fmt(fitted, 1)) rmse \(fmt(rmse(error, range.count))) bias \(fmt(bias, 1))") }
        for target in settings.milestones { let observed = cumulativeCases.firstIndex { $0 >= target }.map { String($0 + 1) } ?? "never", fitted = cumulativeReported.firstIndex { $0 >= Double(target) }.map { String($0 + 1) } ?? "never"; reproductionLines.append("milestone \(target) observed \(observed) fitted \(fitted)") }
    }
    func counterfactualReported(_ interventions: [Intervention]) -> [Double] { seirdStates(beta, gamma, multipliers: multiplierSequence(interventions, days)).map { rho * $0[5] } }
    func counterfactuals() {
        let reported = counterfactualReported(Array(interventions.prefix(1))), total = orderedSum(reported), day = peak(reported)
        reproductionLines.append("counterfactual none reported \(fmt(total, 1)) peak_day \(day + 1) peak \(fmt(reported[day], 1)) averted \(fmt(total - reportedTotal, 1))")
        for index in 1..<interventions.count { var changed = interventions; changed.remove(at: index); let total = orderedSum(counterfactualReported(changed)); reproductionLines.append("counterfactual without \(index + 1) reported \(fmt(total, 1)) averted \(fmt(total - reportedTotal, 1))") }
        for index in 1..<interventions.count { for shift in [-7, 7] { var changed = interventions; changed[index].day += shift; let total = orderedSum(counterfactualReported(changed)); reproductionLines.append("timing \(index + 1) shift \(shift) reported \(fmt(total, 1)) change \(fmt(total - reportedTotal, 1))") } }
    }
    func analyzeReproduction() {
        reproductionLines.append("r0 \(fmt(r0)) herd_immunity \(fmt(1 - 1 / r0))")
        let longStates = seirdStates(beta, gamma, multipliers: Array(repeating: 1, count: 730)), attack = (totalPopulation - longStates.last![0]) / totalPopulation
        reproductionLines.append("final_size equation \(fmt(finalSize(r0))) simulated \(fmt(attack))")
        let empirical = generationInterval()
        epidemicPeaks(); periodsAndMilestones(); counterfactuals()
        for index in 1..<days { if (rt[index] < 1) != (rt[index - 1] < 1) { reproductionLines.append("rt_cross day \(index + 1) \(rt[index] < 1 ? "down" : "up")") } }
        for index in cases.indices { reproductionLines.append("rt \(index + 1) model \(fmt(rt[index])) empirical \(empirical[index].map { fmt($0) } ?? "-")") }
        reproductionLines += ageLines
    }
    func scenarioProjections() {
        scenarioRows = ["scenario,day,incidence,reported"]
        var baseline: Double?
        for scenario in settings.scenarios {
            let future = Array(repeating: scenario.multiplier, count: settings.horizon), states = seirdStates(beta, gamma, multipliers: future, initial: self.states.last!), incidence = states.map { $0[5] }, reported = incidence.map { rho * $0 }, reproduction = r0 * scenario.multiplier * self.states.last![0] / totalPopulation, total = orderedSum(reported), day = peak(reported), attack = (totalPopulation - states.last![0]) / totalPopulation, below = reported.firstIndex { $0 < settings.threshold }.map { String(days + $0 + 1) } ?? "never", above = reported.filter { $0 >= settings.threshold }.count
            for index in reported.indices { scenarioRows.append("\(scenario.name),\(days + index + 1),\(fmt(incidence[index], 1)),\(fmt(reported[index], 1))") }
            if baseline == nil { baseline = total }
            reproductionLines.append("scenario \(scenario.name) multiplier \(fmt(scenario.multiplier)) rt \(fmt(reproduction)) reported \(fmt(total, 1)) peak_day \(days + day + 1) peak \(fmt(reported[day], 1)) attack \(fmt(attack)) final_size \(fmt(finalSize(r0 * scenario.multiplier))) averted \(fmt(baseline! - total, 1)) below \(below) days_above \(above)")
            let betaLow = beta - 2 * standardErrors[0], betaHigh = beta + 2 * standardErrors[0]
            var band: [Double] = []
            for value in [betaLow, betaHigh] { let full = seirdStates(value, gamma, multipliers: multipliers + future); band.append(orderedSum(full.dropFirst(days).map { rho * $0[5] })) }
            reproductionLines.append("scenario_band \(scenario.name) beta_low \(fmt(betaLow, 6)) reported_low \(fmt(band[0], 1)) beta_high \(fmt(betaHigh, 6)) reported_high \(fmt(band[1], 1))")
            let ageStates = ageStatesFor(multipliers: future, initial: self.ageStates.last!), attacks = groups.indices.map { (populations[$0] - ageStates.last![6 * $0]) / populations[$0] }, deaths = orderedSum(groups.indices.map { ageStates.last![6 * $0 + 4] })
            reproductionLines.append("scenario_age \(scenario.name) attack " + attacks.map { fmt($0) }.joined(separator: " ") + " deaths \(fmt(deaths, 1))")
        }
    }
    func trajectories() -> [String] {
        var lines = ["day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported"]
        for i in cases.indices { let row = [String(i + 1)] + states[i + 1].map { fmt($0, 1) } + [fmt(reported[i], 1), String(cases[i]), fmt(averages[i], 2), String(cumulativeCases[i]), fmt(cumulativeReported[i], 1)]; lines.append(row.joined(separator: ",")) }
        return lines
    }
    func analyze() -> [(String, [String])] {
        fitModel(); fittedDiagnostics(); profiles(); backtest(); estimateEffects(); sensitivity(); analyzeAge(); compareModels(); analyzeReproduction(); scenarioProjections()
        return [("fit.txt", fitLines), ("trajectories.csv", trajectories()), ("scenarios.csv", scenarioRows), ("reproduction.txt", reproductionLines), ("curve_plot.txt", curvePlot(cases, reported))]
    }
}
let study = try Study(readInputs())
try writeOutputs(study.analyze())
