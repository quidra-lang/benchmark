import Foundation

let doodsonWeights = [0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1]
let leadingConstituents = ["M2", "S2", "K1", "O1"]
func sum(_ values: [Double]) -> Double { var result = 0.0; for value in values { result += value }; return result }
func average(_ values: [Double]) -> Double { sum(values) / Double(values.count) }
func rms(_ values: [Double]) -> Double { sqrt(sum(values.map { $0 * $0 }) / Double(values.count)) }
func maximumIndex(_ values: [Double]) -> Int { var best = 0; for index in values.indices.dropFirst() { if values[index] > values[best] { best = index } }; return best }
func minimumIndex(_ values: [Double]) -> Int { var best = 0; for index in values.indices.dropFirst() { if values[index] < values[best] { best = index } }; return best }
func selectConstituents(_ constituents: [Constituent], _ length: Int, _ rayleigh: Double) -> (selected: [Constituent], status: [String]) {
    var selected: [Constituent] = [], status: [String] = []
    for constituent in constituents { if constituent.speed * Double(length) < 360 * rayleigh { status.append("short") } else if let conflict = selected.first(where: { abs(constituent.speed - $0.speed) * Double(length) < 360 * rayleigh }) { status.append("conflict:" + conflict.name) } else { status.append("fitted"); selected.append(constituent) } }
    return (selected, status)
}
struct ResidualStatistics { let values: [Int: Double]; let squared: Double; let variance: Double; let dof: Int; let rms: Double; let maximumAbsolute: Double; let explained: Double; let lag1: Double }
func residualStatistics(_ observed: [Int: Double], _ usable: [Int], _ model: Model) -> ResidualStatistics {
    let residuals = Dictionary(uniqueKeysWithValues: usable.map { ($0, observed[$0]! - predictHeight(model, Double($0))) }), squared = sum(usable.map { residuals[$0]! * residuals[$0]! }), dof = usable.count - model.unknowns, mean = average(usable.map { observed[$0]! }), variation = sum(usable.map { let difference = observed[$0]! - mean; return difference * difference }), paired = usable.filter { residuals[$0 + 1] != nil }, numerator = sum(paired.map { residuals[$0]! * residuals[$0 + 1]! }), denominator = sum(paired.map { residuals[$0]! * residuals[$0]! })
    return ResidualStatistics(values: residuals, squared: squared, variance: squared / Double(dof), dof: dof, rms: sqrt(squared / Double(usable.count)), maximumAbsolute: usable.map { abs(residuals[$0]!) }.max()!, explained: 100 * (1 - squared / variation), lag1: numerator / denominator)
}
struct ConstantError { let amplitude: Double; let phase: Double; let snr: Double; let significant: Bool }
func constituentErrors(_ model: Model, _ variance: Double, _ minimumSNR: Double) -> [String: ConstantError] {
    var result: [String: ConstantError] = [:]
    for constant in model.constants { let a = constant.a, b = constant.b, amplitude = constant.amplitude, ia = constant.indexA, ib = constant.indexB, va = variance * model.inverse[ia][ia], vb = variance * model.inverse[ib][ib], cab = variance * model.inverse[ia][ib], amplitudeError = sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amplitude, phaseError = sqrt(b * b * va + a * a * vb - 2 * a * b * cab) / (amplitude * amplitude) * 180 / pi, fraction = amplitude / amplitudeError, snr = fraction * fraction; result[constant.name] = ConstantError(amplitude: amplitudeError, phase: phaseError, snr: snr, significant: snr >= minimumSNR) }
    return result
}
struct Validation { let midpoint: Int; let training: Int; let testing: Int; let constituents: Int; let rms: Double; let inSampleRMS: Double; let skill: Double }
func crossValidate(_ observed: [Int: Double], _ usable: [Int], _ first: Int, _ last: Int, _ constituents: [Constituent], _ rayleigh: Double, _ residuals: [Int: Double]) -> Validation {
    let midpoint = first + (last - first) / 2, training = usable.filter { $0 <= midpoint }, testing = usable.filter { $0 > midpoint }, selected = selectConstituents(constituents, training.last! - training.first!, rayleigh).selected, model = fit(observed, training, selected), errors = testing.map { observed[$0]! - predictHeight(model, Double($0)) }, squared = sum(errors.map { $0 * $0 }), mean = average(testing.map { observed[$0]! }), variation = sum(testing.map { let difference = observed[$0]! - mean; return difference * difference }), inSample = sum(testing.map { residuals[$0]! * residuals[$0]! })
    return Validation(midpoint: midpoint, training: training.count, testing: testing.count, constituents: selected.count, rms: sqrt(squared / Double(testing.count)), inSampleRMS: sqrt(inSample / Double(testing.count)), skill: 1 - squared / variation)
}
struct Surge { let positive: Bool; let first: Int; let last: Int; let peak: Int; let value: Double }
func residualEvents(_ usable: [Int], _ residuals: [Int: Double], _ threshold: Double, _ minimumHours: Int) -> [Surge] {
    var events: [Surge] = [], current: [Int] = [], currentSign = 0
    func flush() { if current.count < minimumHours { return }; var peak = current[0]; for time in current.dropFirst() { if currentSign == 1 ? residuals[time]! > residuals[peak]! : residuals[time]! < residuals[peak]! { peak = time } }; events.append(Surge(positive: currentSign == 1, first: current.first!, last: current.last!, peak: peak, value: residuals[peak]!)) }
    for time in usable { let value = residuals[time]!, sign = value > threshold ? 1 : value < -threshold ? -1 : 0, consecutive = current.last.map { time == $0 + 1 } ?? false; if sign != 0 && sign == currentSign && consecutive { current.append(time) } else { flush(); current = sign == 0 ? [] : [time]; currentSign = sign } }
    flush()
    return events
}
struct DailyMean { let day: Int; let level: Double; let filled: Int }
struct DailyMeans { let rows: [DailyMean]; let average: Double; let slope: Double; let maximum: DailyMean; let minimum: DailyMean }
func dailyMeans(_ cleaning: Cleaning, _ model: Model) -> DailyMeans {
    let usable = Set(cleaning.usable)
    var rows: [DailyMean] = []
    for day in (cleaning.first / 24)...(cleaning.last / 24) { let noon = day * 24 + 12; if noon - 19 < cleaning.first || noon + 19 > cleaning.last { continue }; var weighted = 0.0, missing = 0; for offset in -19...19 { let time = noon + offset, value: Double; if usable.contains(time) { value = cleaning.values[time]! } else { value = predictHeight(model, Double(time)); missing += 1 }; weighted += Double(doodsonWeights[abs(offset)]) * value }; rows.append(DailyMean(day: day, level: weighted / 30, filled: missing)) }
    let levels = rows.map { $0.level }, mean = average(levels), x = rows.map { Double($0.day - rows[0].day) }, xm = average(x), numerator = sum(rows.indices.map { (x[$0] - xm) * (levels[$0] - mean) }), denominator = sum(x.map { let difference = $0 - xm; return difference * difference })
    return DailyMeans(rows: rows, average: mean, slope: 1000 * numerator / denominator, maximum: rows[maximumIndex(levels)], minimum: rows[minimumIndex(levels)])
}
struct DailyTides { let day: Int; let highs: Int; let lows: Int; let hhw: Double?; let llw: Double?; let range: Double? }
func refineExtrema(_ raw: [Extremum], _ minimumRange: Double) -> [Extremum] {
    var extrema = raw
    while extrema.count >= 2 { let differences = (0..<(extrema.count - 1)).map { abs(extrema[$0].height - extrema[$0 + 1].height) }, index = minimumIndex(differences); if differences[index] >= minimumRange { break }; extrema.removeSubrange(index..<(index + 2)) }
    for day in Set(extrema.map { $0.day }).sorted() { let indices = extrema.indices.filter { extrema[$0].day == day }, highs = indices.filter { extrema[$0].kind == .high }, lows = indices.filter { extrema[$0].kind == .low }; if !highs.isEmpty { let best = highs[maximumIndex(highs.map { extrema[$0].height })]; for index in highs { extrema[index].label = index == best ? "HHW" : "LHW" } }; if !lows.isEmpty { let best = lows[minimumIndex(lows.map { extrema[$0].height })]; for index in lows { extrema[index].label = index == best ? "LLW" : "HLW" } } }
    return extrema
}
func dailyExtrema(_ extrema: [Extremum], _ startDay: Int, _ days: Int) -> [DailyTides] { (0..<days).map { offset in let day = startDay + offset, highs = extrema.filter { $0.day == day && $0.kind == .high }, lows = extrema.filter { $0.day == day && $0.kind == .low }, hhw = highs.map { $0.height }.max(), llw = lows.map { $0.height }.min(), range: Double? = hhw != nil && llw != nil ? hhw! - llw! : nil; return DailyTides(day: day, highs: highs.count, lows: lows.count, hhw: hhw, llw: llw, range: range) } }
struct Datums { let mhhw: Double; let mllw: Double; let mhw: Double; let mlw: Double; let mtl: Double; let dtl: Double; let mn: Double; let gt: Double }
struct BeatEvent { let spring: Bool; let minute: Int }
struct Characteristics {
    let formNumber: Double
    let type: String
    let spring: Double
    let neap: Double
    let datums: Datums
    let rise: Double
    let fall: Double
    let m4m2: Double
    let relativePhase: Double
    let flood: Bool
    let hat: Double
    let lat: Double
    let highs: [Extremum]
    let lows: [Extremum]
    let highest: Extremum
    let lowest: Extremum
    let widest: DailyTides
    let narrowest: DailyTides
    let above: Double
    let below: Double
    let beats: [BeatEvent]
}
func springNeapEvents(_ constants: [String: HarmonicConstant], _ start: Int, _ hours: Int) -> [BeatEvent] {
    let m2 = constants["M2"]!, s2 = constants["S2"]!, dw = s2.speed - m2.speed, dg = s2.phase - m2.phase, first = (dw * Double(start) - dg) / 180, last = (dw * Double(start + hours) - dg) / 180, minimum = Int(ceil(min(first, last))), maximum = Int(floor(max(first, last)))
    if minimum > maximum { return [] }
    var results: [BeatEvent] = []
    for q in minimum...maximum { let hour = (dg + 180 * Double(q)) / dw; if Double(start) <= hour && hour <= Double(start + hours) { results.append(BeatEvent(spring: q % 2 == 0, minute: Int(floor(hour * 60 + 0.5)))) } }
    return results
}
func characteristics(_ model: Model, _ extrema: [Extremum], _ daily: [DailyTides], _ hourly: [Double], _ start: Int, _ hours: Int) -> Characteristics {
    let constants = Dictionary(uniqueKeysWithValues: model.constants.map { ($0.name, $0) }), m2 = constants["M2"]!, s2 = constants["S2"]!, m4 = constants["M4"]!, form = (constants["K1"]!.amplitude + constants["O1"]!.amplitude) / (m2.amplitude + s2.amplitude), type = form < 0.25 ? "semidiurnal" : form < 1.5 ? "mixed_semidiurnal" : form < 3 ? "mixed_diurnal" : "diurnal", highs = extrema.filter { $0.kind == .high }, lows = extrema.filter { $0.kind == .low }, mhhw = average(daily.compactMap { $0.hhw }), mllw = average(daily.compactMap { $0.llw }), mhw = average(highs.map { $0.height }), mlw = average(lows.map { $0.height }), datums = Datums(mhhw: mhhw, mllw: mllw, mhw: mhw, mlw: mlw, mtl: (mhw + mlw) / 2, dtl: (mhhw + mllw) / 2, mn: mhw - mlw, gt: mhhw - mllw)
    var rises: [Double] = [], falls: [Double] = [], phase = 2 * m2.phase - m4.phase
    for index in 1..<extrema.count { let previous = extrema[index - 1], current = extrema[index], elapsed = Double(current.rounded - previous.rounded); if previous.kind == .low && current.kind == .high { rises.append(elapsed) }; if previous.kind == .high && current.kind == .low { falls.append(elapsed) } }
    while phase < 0 { phase += 360 }; while phase >= 360 { phase -= 360 }
    let complete = daily.filter { $0.range != nil }, ranges = complete.map { $0.range! }, amplitudeSum = sum(model.constants.map { $0.amplitude })
    return Characteristics(formNumber: form, type: type, spring: 2 * (m2.amplitude + s2.amplitude), neap: 2 * (m2.amplitude - s2.amplitude), datums: datums, rise: average(rises), fall: average(falls), m4m2: m4.amplitude / m2.amplitude, relativePhase: phase, flood: phase < 180, hat: model.meanLevel + amplitudeSum, lat: model.meanLevel - amplitudeSum, highs: highs, lows: lows, highest: highs[maximumIndex(highs.map { $0.height })], lowest: lows[minimumIndex(lows.map { $0.height })], widest: complete[maximumIndex(ranges)], narrowest: complete[minimumIndex(ranges)], above: 100 * Double(hourly.filter { $0 > mhhw }.count) / Double(hourly.count), below: 100 * Double(hourly.filter { $0 < mllw }.count) / Double(hourly.count), beats: springNeapEvents(constants, start, hours))
}
struct StationResult {
    let definition: StationDefinition
    let cleaning: Cleaning
    let statuses: [String]
    let model: Model
    let residual: ResidualStatistics
    let errors: [String: ConstantError]
    let validation: Validation
    let surges: [Surge]
    let means: DailyMeans
    let hourly: [Double]
    let extrema: [Extremum]
    let rawExtrema: Int
    let daily: [DailyTides]
    let characteristics: Characteristics
}
func inspectStation(_ definition: StationDefinition, _ observations: ObservationSeries, _ constituents: [Constituent], _ settings: Settings) -> StationResult {
    var cleaning = prepareRecord(observations, settings.flatRun)
    let selection = selectConstituents(constituents, cleaning.length, settings.rayleigh), preliminary = fit(cleaning.values, cleaning.candidates, selection.selected), preResiduals = Dictionary(uniqueKeysWithValues: cleaning.candidates.map { ($0, cleaning.values[$0]! - predictHeight(preliminary, Double($0))) })
    cleaning.prefitRMS = rms(cleaning.candidates.map { preResiduals[$0]! }); detectSpikes(&cleaning, preResiduals, settings)
    let model = fit(cleaning.values, cleaning.usable, selection.selected), residual = residualStatistics(cleaning.values, cleaning.usable, model), errors = constituentErrors(model, residual.variance, settings.snrMinimum), validation = crossValidate(cleaning.values, cleaning.usable, cleaning.first, cleaning.last, constituents, settings.rayleigh, residual.values), surges = residualEvents(cleaning.usable, residual.values, settings.surgeThreshold, settings.surgeHours), means = dailyMeans(cleaning, model), hourly = predictHours(model, settings.predictionHour, settings.predictionHours), raw = findExtrema(model, settings.predictionHour, settings.predictionHours, settings.gridMinutes), extrema = refineExtrema(raw, settings.minimumRange), daily = dailyExtrema(extrema, settings.predictionHour / 24, settings.predictionHours / 24)
    return StationResult(definition: definition, cleaning: cleaning, statuses: selection.status, model: model, residual: residual, errors: errors, validation: validation, surges: surges, means: means, hourly: hourly, extrema: extrema, rawExtrema: raw.count, daily: daily, characteristics: characteristics(model, extrema, daily, hourly, settings.predictionHour, settings.predictionHours))
}
func cleaningLines(_ stations: [StationResult], _ settings: Settings) -> [String] {
    var lines: [String] = []
    for station in stations { let cleaning = station.cleaning, reasons = cleaning.reasons
        lines += ["station=\(station.definition.code) name=\(station.definition.name)", "span start=\(datetimeAtHour(settings.epoch, cleaning.first)) end=\(datetimeAtHour(settings.epoch, cleaning.last)) hours=\(cleaning.length + 1) record_length=\(cleaning.length)", "counts rows=\(cleaning.rows) numeric=\(cleaning.numericTimes.count) na=\(reasons.values.filter { $0 == .na }.count) absent=\(reasons.values.filter { $0 == .absent }.count) flat=\(reasons.values.filter { $0 == .flat }.count) spikes=\(cleaning.spikes.count) usable=\(cleaning.usable.count)"]
        for flat in cleaning.flatRuns { lines.append("flat start=\(datetimeAtHour(settings.epoch, flat.first)) end=\(datetimeAtHour(settings.epoch, flat.last)) value=\(decimal(flat.value, 3)) removed=\(flat.last - flat.first)") }
        lines.append("spike_test window=\(settings.spikeWindow) candidates=\(cleaning.candidates.count) tested=\(cleaning.tested) prefit_rms=\(decimal(cleaning.prefitRMS, 4))")
        for spike in cleaning.spikes { lines.append("spike time=\(datetimeAtHour(settings.epoch, spike.time)) value=\(decimal(spike.value, 3)) residual=\(decimal(spike.residual, 4)) median=\(decimal(spike.median, 4)) mad=\(decimal(spike.mad, 4)) limit=\(decimal(spike.limit, 4))") }
        for gap in cleaning.gaps { lines.append("gap start=\(datetimeAtHour(settings.epoch, gap.first)) end=\(datetimeAtHour(settings.epoch, gap.last)) hours=\(gap.last - gap.first + 1) cause=\(gap.cause)") }
    }
    return lines
}
func constituentLines(_ stations: [StationResult], _ constituents: [Constituent]) -> [String] {
    var lines = ["station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant"]
    for station in stations { let constants = Dictionary(uniqueKeysWithValues: station.model.constants.map { ($0.name, $0) }); for (index, constituent) in constituents.enumerated() { let status = station.statuses[index], prefix = "\(station.definition.code),\(constituent.name),\(decimal(constituent.speed, 7)),\(status)"; if status != "fitted" { lines.append(prefix + ",,,,,,"); continue }; let constant = constants[constituent.name]!, error = station.errors[constituent.name]!; lines.append(prefix + "," + [decimal(constant.amplitude, 4), decimal(constant.phase, 2), decimal(error.amplitude, 4), decimal(error.phase, 2), decimal(error.snr, 1), error.significant ? "yes" : "no"].joined(separator: ",")) } }
    return lines
}
func predictionLines(_ stations: [StationResult], _ settings: Settings) -> [String] { ["time," + stations.map { $0.definition.code }.joined(separator: ",")] + (0...settings.predictionHours).map { offset in datetimeAtHour(settings.epoch, settings.predictionHour + offset) + "," + stations.map { decimal($0.hourly[offset], 3) }.joined(separator: ",") } }
func extremaLines(_ stations: [StationResult], _ settings: Settings) -> [String] {
    var lines: [String] = []
    for station in stations { let extrema = station.extrema; lines.append("station=\(station.definition.code) extremes=\(extrema.count) raw=\(station.rawExtrema) removed=\(station.rawExtrema - extrema.count)"); for (index, item) in extrema.enumerated() { let change = index == 0 ? "none" : decimal(item.height - extrema[index - 1].height, 3); lines.append("\(datetimeAtMinute(settings.epoch, item.rounded)) \(item.label) \(decimal(item.height, 3)) change=\(change)") }; for day in station.daily { lines.append("day date=\(dateAtDay(settings.epoch, day.day)) high_waters=\(day.highs) low_waters=\(day.lows) hhw=\(optional(day.hhw, 3)) llw=\(optional(day.llw, 3)) range=\(optional(day.range, 3))") } }
    return lines
}
func stationSummaryHeader(_ station: StationResult, _ settings: Settings) -> [String] {
    let cleaning = station.cleaning, model = station.model, residual = station.residual, validation = station.validation
    var lines = ["[station \(station.definition.code)] \(station.definition.name)", "record first=\(datetimeAtHour(settings.epoch, cleaning.first)) last=\(datetimeAtHour(settings.epoch, cleaning.last)) length=\(cleaning.length) usable=\(cleaning.usable.count)", "fit constituents=\(model.selected.count) unknowns=\(model.unknowns) dof=\(residual.dof) mean_level=\(decimal(model.meanLevel, 4))", "residual rms=\(decimal(residual.rms, 4)) max_abs=\(decimal(residual.maximumAbsolute, 4)) explained_percent=\(decimal(residual.explained, 4)) lag1_autocorrelation=\(decimal(residual.lag1, 4))"]
    let largest = cleaning.usable.sorted { abs(residual.values[$0]!) == abs(residual.values[$1]!) ? $0 < $1 : abs(residual.values[$0]!) > abs(residual.values[$1]!) }.prefix(settings.topResiduals)
    for (rank, time) in largest.enumerated() { lines.append("top_residual rank=\(rank + 1) time=\(datetimeAtHour(settings.epoch, time)) observed=\(decimal(cleaning.values[time]!, 3)) fitted=\(decimal(predictHeight(model, Double(time)), 4)) residual=\(decimal(residual.values[time]!, 4))") }
    lines.append("validation split=\(datetimeAtHour(settings.epoch, validation.midpoint)) train=\(validation.training) test=\(validation.testing) constituents=\(validation.constituents) rms=\(decimal(validation.rms, 4)) in_sample_rms=\(decimal(validation.inSampleRMS, 4)) skill=\(decimal(validation.skill, 4))")
    return lines
}
func characteristicsLines(_ station: StationResult, _ settings: Settings) -> [String] {
    let c = station.characteristics, d = c.datums
    var lines = ["form_number=\(decimal(c.formNumber, 4)) type=\(c.type)", "ranges spring=\(decimal(c.spring, 3)) neap=\(decimal(c.neap, 3)) mn=\(decimal(d.mn, 3)) gt=\(decimal(d.gt, 3))", "asymmetry rise_minutes=\(decimal(c.rise, 1)) fall_minutes=\(decimal(c.fall, 1)) m4_m2_ratio=\(decimal(c.m4m2, 4)) relative_phase=\(decimal(c.relativePhase, 2)) dominance=\(c.flood ? "flood" : "ebb")", "datums mhhw=\(decimal(d.mhhw, 3)) mhw=\(decimal(d.mhw, 3)) mtl=\(decimal(d.mtl, 3)) dtl=\(decimal(d.dtl, 3)) mlw=\(decimal(d.mlw, 3)) mllw=\(decimal(d.mllw, 3))", "bounds hat=\(decimal(c.hat, 3)) lat=\(decimal(c.lat, 3))", "window high_waters=\(c.highs.count) low_waters=\(c.lows.count) highest=\(decimal(c.highest.height, 3)) highest_time=\(datetimeAtMinute(settings.epoch, c.highest.rounded)) lowest=\(decimal(c.lowest.height, 3)) lowest_time=\(datetimeAtMinute(settings.epoch, c.lowest.rounded))", "daily_range widest=\(decimal(c.widest.range!, 3)) widest_date=\(dateAtDay(settings.epoch, c.widest.day)) narrowest=\(decimal(c.narrowest.range!, 3)) narrowest_date=\(dateAtDay(settings.epoch, c.narrowest.day))", "exceedance above_mhhw=\(decimal(c.above, 2)) below_mllw=\(decimal(c.below, 2))"]
    for beat in c.beats { lines.append("\(beat.spring ? "spring" : "neap") time=\(datetimeAtMinute(settings.epoch, beat.minute))") }
    lines.append("surges count=\(station.surges.count) threshold=\(decimal(settings.surgeThreshold, 3)) min_hours=\(settings.surgeHours)")
    for surge in station.surges { lines.append("surge type=\(surge.positive ? "positive" : "negative") start=\(datetimeAtHour(settings.epoch, surge.first)) end=\(datetimeAtHour(settings.epoch, surge.last)) hours=\(surge.last - surge.first + 1) peak=\(decimal(surge.value, 4)) peak_time=\(datetimeAtHour(settings.epoch, surge.peak))") }
    return lines
}
func dailyMeanLines(_ station: StationResult, _ settings: Settings) -> [String] {
    let means = station.means
    return ["daily_mean days=\(means.rows.count) average=\(decimal(means.average, 4)) slope_mm_per_day=\(decimal(means.slope, 3)) max=\(decimal(means.maximum.level, 4)) max_date=\(dateAtDay(settings.epoch, means.maximum.day)) min=\(decimal(means.minimum.level, 4)) min_date=\(dateAtDay(settings.epoch, means.minimum.day))"] + means.rows.map { "daily_mean date=\(dateAtDay(settings.epoch, $0.day)) level=\(decimal($0.level, 4)) filled=\($0.filled)" }
}
func nearestReferenceLag(_ extrema: [Extremum], _ reference: [Extremum]) -> Double { var offsets: [Double] = []; for item in extrema { var closest = reference[0]; for candidate in reference.dropFirst() { let difference = abs(candidate.rounded - item.rounded), previous = abs(closest.rounded - item.rounded); if difference < previous || (difference == previous && candidate.rounded < closest.rounded) { closest = candidate } }; offsets.append(Double(item.rounded - closest.rounded)) }; return average(offsets) }
func comparisonLines(_ stations: [StationResult], _ settings: Settings) -> [String] {
    let reference = stations.first { $0.definition.code == settings.reference }!, ref = reference.characteristics, referenceConstants = Dictionary(uniqueKeysWithValues: reference.model.constants.map { ($0.name, $0) })
    var lines = ["[comparison] reference=\(settings.reference)"]
    for station in stations where station.definition.code != settings.reference { let own = station.characteristics, code = station.definition.code, constants = Dictionary(uniqueKeysWithValues: station.model.constants.map { ($0.name, $0) }); lines.append("\(code) tide hw_lag_min=\(decimal(nearestReferenceLag(own.highs, ref.highs), 1)) lw_lag_min=\(decimal(nearestReferenceLag(own.lows, ref.lows), 1)) range_ratio=\(decimal(own.datums.gt / ref.datums.gt, 4)) mtl_diff=\(decimal(own.datums.mtl - ref.datums.mtl, 3))"); for name in leadingConstituents { let current = constants[name]!, reference = referenceConstants[name]!; var phase = current.phase - reference.phase; if phase > 180 { phase -= 360 }; if phase <= -180 { phase += 360 }; lines.append("\(code) \(name) amplitude_ratio=\(decimal(current.amplitude / reference.amplitude, 4)) phase_diff=\(decimal(phase, 2)) time_lag_min=\(decimal(phase / current.speed * 60, 1))") } }
    return lines
}
struct LagCorrelation { let lag: Int; let value: Double; let count: Int }
func correlationAtLag(_ first: StationResult, _ second: StationResult, _ lag: Int) -> LagCorrelation {
    let pairs = first.cleaning.usable.filter { second.residual.values[$0 + lag] != nil }.map { (first.residual.values[$0]!, second.residual.values[$0 + lag]!) }, mx = average(pairs.map { $0.0 }), my = average(pairs.map { $0.1 }), covariance = sum(pairs.map { ($0.0 - mx) * ($0.1 - my) }), varianceX = sum(pairs.map { let value = $0.0 - mx; return value * value }), varianceY = sum(pairs.map { let value = $0.1 - my; return value * value })
    return LagCorrelation(lag: lag, value: covariance / sqrt(varianceX * varianceY), count: pairs.count)
}
func correlationLines(_ stations: [StationResult], _ maximumLag: Int) -> [String] {
    var lines = ["[correlation] max_lag=\(maximumLag)"]
    for first in stations.indices { for second in (first + 1)..<stations.count { var best: LagCorrelation?, zero = 0.0; for lag in (-maximumLag)...maximumLag { let result = correlationAtLag(stations[first], stations[second], lag); if lag == 0 { zero = result.value }; if let previous = best { if result.value > previous.value || (result.value == previous.value && (abs(lag) < abs(previous.lag) || (abs(lag) == abs(previous.lag) && lag < previous.lag))) { best = result } } else { best = result } }; lines.append("\(stations[first].definition.code)-\(stations[second].definition.code) lag0=\(decimal(zero, 4)) best_lag=\(best!.lag) best=\(decimal(best!.value, 4)) pairs=\(best!.count)") } }
    return lines
}
func plotLines(_ station: StationResult, _ settings: Settings) -> [String] {
    let rows = (settings.plotTop - settings.plotBottom) / settings.plotStep + 1, width = settings.plotHours, start = settings.predictionHour, zeroRow = Int(floor((Double(settings.plotTop) - 100 * station.model.meanLevel) / Double(settings.plotStep) + 0.5))
    var grid = Array(repeating: Array(repeating: " ", count: width), count: rows), marks: [Int: String] = [:]
    if zeroRow >= 0 && zeroRow < rows { grid[zeroRow] = Array(repeating: "-", count: width) }
    for item in station.extrema { let column = (item.rounded - 60 * start + 30) / 60; if column >= 0 && column < width { marks[column] = item.kind == .high ? "H" : "L" } }
    for column in 0..<width { let height = station.hourly[column], row = Int(floor((Double(settings.plotTop) - 100 * height) / Double(settings.plotStep) + 0.5)); if row < 0 { grid[0][column] = "^" } else if row >= rows { grid[rows - 1][column] = "v" } else { grid[row][column] = marks[column] ?? "*" } }
    return ["[plot] station=\(station.definition.code) start=\(datetimeAtHour(settings.epoch, start)) hours=\(width) step_cm=\(settings.plotStep)"] + renderPlot(grid, settings.plotTop, settings.plotStep)
}
func summaryLines(_ stations: [StationResult], _ settings: Settings) -> [String] { var lines: [String] = []; for station in stations { lines += stationSummaryHeader(station, settings) + characteristicsLines(station, settings) + dailyMeanLines(station, settings) }; lines += comparisonLines(stations, settings) + correlationLines(stations, settings.correlationLag); lines += plotLines(stations.first { $0.definition.code == settings.plotCode }!, settings); return lines }
let inputs = try readInputs(), settings = inputs.settings, stations = settings.stations.indices.map { inspectStation(settings.stations[$0], inputs.observations[$0], inputs.constituents, settings) }
try writeLines("cleaning.txt", cleaningLines(stations, settings))
try writeLines("constituents.csv", constituentLines(stations, inputs.constituents))
try writeLines("predictions.csv", predictionLines(stations, settings))
try writeLines("extremes.txt", extremaLines(stations, settings))
try writeLines("summary.txt", summaryLines(stations, settings))
