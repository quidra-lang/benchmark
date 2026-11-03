import Foundation

let labels = ["N", "V", "A"]

struct Levels {
    var spki: Int
    var npki: Int
    var spkf: Int
    var npkf: Int
    var text: String { "spki=\(spki) npki=\(npki) spkf=\(spkf) npkf=\(npkf)" }
}

struct Thresholds {
    let integrated: Int
    let filtered: Int
    var integratedLow: Int { floorDivide(integrated, 2) }
    var filteredLow: Int { floorDivide(filtered, 2) }
}

func thresholds(_ levels: Levels) -> Thresholds {
    Thresholds(integrated: levels.npki + floorDivide(levels.spki - levels.npki, 4),
                filtered: levels.npkf + floorDivide(levels.spkf - levels.npkf, 4))
}

enum LevelUpdate {
    case signal, noise, searchback
}

final class Detection {
    let peaks: [Peak]
    let parameters: [String: Int]
    let initial: Levels
    var levels: Levels
    var registered: [Peak] = []
    var intervals: [Int] = []
    var average1 = 200
    var average2 = 200

    init(_ peaks: [Peak], _ signals: Signals, _ parameters: [String: Int]) {
        self.peaks = peaks
        self.parameters = parameters
        let initial = initialLevels(signals)
        self.initial = initial
        levels = initial
    }

    func register(_ peak: Peak) {
        if let last = registered.last {
            let elapsed = peak.time - last.time
            intervals.append(elapsed)
            if intervals.count > 8 { intervals.removeFirst() }
            average1 = intervals.reduce(0, +) / intervals.count
            if 92 * average1 <= 100 * elapsed && 100 * elapsed <= 116 * average1 { average2 = average1 }
        }
        registered.append(peak)
    }

    func update(_ peak: Peak, _ category: LevelUpdate) {
        switch category {
        case .signal:
            levels.spki = floorDivide(peak.integrated + 7 * levels.spki, 8)
            levels.spkf = floorDivide(peak.filtered + 7 * levels.spkf, 8)
        case .noise:
            levels.npki = floorDivide(peak.integrated + 7 * levels.npki, 8)
            levels.npkf = floorDivide(peak.filtered + 7 * levels.npkf, 8)
        case .searchback:
            levels.spki = floorDivide(peak.integrated + 3 * levels.spki, 4)
            levels.spkf = floorDivide(peak.filtered + 3 * levels.spkf, 4)
        }
    }

    func searchBack(_ time: Int) {
        while true {
            let last = registered.last?.time ?? 0
            if time - last <= average2 * parameters["searchback_percent"]! / 100 { return }
            let threshold = thresholds(levels)
            let candidates = peaks.filter {
                $0.category == .noise && last < $0.time && $0.time < time
                    && $0.integrated > threshold.integratedLow && $0.filtered > threshold.filteredLow
            }
            guard let chosen = candidates.min(by: {
                $0.integrated == $1.integrated ? $0.time < $1.time : $0.integrated > $1.integrated
            }) else { return }
            update(chosen, .searchback)
            chosen.category = .searchback
            register(chosen)
        }
    }

    func run(_ sampleCount: Int) {
        let refractory = parameters["refractory_ms"]! / 5
        let twave = parameters["twave_ms"]! / 5
        for peak in peaks {
            searchBack(peak.time)
            let threshold = thresholds(levels)
            peak.thresholdI = threshold.integrated
            peak.thresholdF = threshold.filtered
            let last = registered.last
            if let last, peak.time - last.time < refractory {
                peak.category = .refractory
                continue
            }
            if peak.integrated > threshold.integrated && peak.filtered > threshold.filtered {
                if let last, peak.time - last.time < twave, 2 * peak.slope < last.slope {
                    peak.category = .twave
                    update(peak, .noise)
                } else {
                    peak.category = .qrs
                    update(peak, .signal)
                    register(peak)
                }
            } else {
                peak.category = .noise
                update(peak, .noise)
            }
        }
        searchBack(sampleCount)
    }
}

struct Beat {
    let number: Int
    let sample: Int
    let rr: Int?
    let heartRate: Int?
    let width: Int
    let label: String
    let method: String
    var annotation: Int?
    var offset: Int?
}

struct Segment {
    let start: Int
    let end: Int
    let references: Int
    let tp: Int
    let fp: Int
    let fn: Int
    let noisePeaks: Int
    let beats: Int
    let intervals: [Int]
    var prefix: String { padded(start, 6) + "-" + padded(end, 6) }
}

func buildBeats(_ registered: [Peak], _ bandpass: [Int], _ parameters: [String: Int]) -> [Beat] {
    var beats: [Beat] = []
    for peak in registered {
        let number = beats.count + 1
        let sample = max(0, peak.r - 21)
        let rr = beats.last.map { 5 * (sample - $0.sample) }
        let width = widthMilliseconds(bandpass, peak.r)
        var label = "N"
        if number >= 10 {
            let previousEight = beats[(number - 9)..<(number - 1)].reduce(0) { $0 + $1.rr! }
            if 800 * rr! < parameters["premature_percent"]! * previousEight {
                label = width > parameters["qrs_width_ms"]! ? "V" : "A"
            }
        }
        beats.append(Beat(number: number, sample: sample, rr: rr, heartRate: rr.map { rdiv(6000000, $0) },
                           width: width, label: label, method: peak.category == .qrs ? "threshold" : "searchback"))
    }
    return beats
}

func matchAnnotations(_ beats: inout [Beat], _ annotations: inout [Annotation], _ tolerance: Int) {
    for index in beats.indices {
        let sample = beats[index].sample
        let candidates = annotations.indices.filter { annotations[$0].beat == nil && abs(annotations[$0].sample - sample) <= tolerance }
        guard let chosen = candidates.min(by: { first, second in
            let a = abs(annotations[first].sample - sample)
            let b = abs(annotations[second].sample - sample)
            return a == b ? annotations[first].sample < annotations[second].sample : a < b
        }) else { continue }
        annotations[chosen].beat = index
        beats[index].annotation = chosen
        beats[index].offset = 5 * (sample - annotations[chosen].sample)
    }
}

func segmentRows(_ beats: [Beat], _ annotations: [Annotation], _ peaks: [Peak],
                 _ sampleCount: Int, _ width: Int) -> [Segment] {
    stride(from: 0, to: sampleCount, by: width).map { start in
        let end = min(start + width, sampleCount)
        let references = annotations.filter { start <= $0.sample && $0.sample < end }
        let detected = beats.filter { start <= $0.sample && $0.sample < end }
        let tp = references.filter { $0.beat != nil }.count
        return Segment(start: 5 * start, end: 5 * end, references: references.count, tp: tp,
                        fp: detected.filter { $0.annotation == nil }.count, fn: references.count - tp,
                        noisePeaks: peaks.filter { $0.category == .noise && start <= $0.time && $0.time < end }.count,
                        beats: detected.count, intervals: detected.compactMap { $0.rr })
    }
}

func padded(_ text: String, _ width: Int) -> String { String(repeating: " ", count: max(0, width - text.count)) + text }
func padded(_ value: Int, _ width: Int) -> String { padded(String(value), width) }

func beatLines(_ beats: [Beat], _ annotations: [Annotation]) -> [String] {
    ["beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"] + beats.map { beat in
        let reference = beat.annotation.map { annotations[$0] }
        return [String(beat.number), String(beat.sample), String(5 * beat.sample), missing(beat.rr),
                beat.heartRate.map(two) ?? "-", String(beat.width), beat.label, beat.method,
                missing(reference?.sample), reference?.label ?? "-"].joined(separator: ",")
    }
}

func peakLines(_ peaks: [Peak]) -> [String] {
    ["peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"] + peaks.enumerated().map { index, peak in
        [String(index + 1), String(peak.time), String(peak.r), String(peak.integrated), String(peak.filtered),
         String(peak.slope), String(peak.thresholdI), String(peak.thresholdF), peak.category!.rawValue].joined(separator: ",")
    }
}

func matchingLines(_ beats: [Beat], _ annotations: [Annotation]) -> [String] {
    var records: [(sample: Int, order: Int, line: String)] = []
    for reference in annotations {
        let fields: [String]
        if let index = reference.beat {
            let beat = beats[index]
            fields = [String(reference.sample), reference.label, String(beat.number), String(beat.sample), beat.label,
                      String(beat.offset!), "TP", reference.label == beat.label ? "yes" : "no"]
        } else { fields = [String(reference.sample), reference.label, "-", "-", "-", "-", "FN", "-"] }
        records.append((reference.sample, 0, fields.joined(separator: ",")))
    }
    for beat in beats where beat.annotation == nil {
        records.append((beat.sample, 1, "-,-,\(beat.number),\(beat.sample),\(beat.label),-,FP,-"))
    }
    records.sort { $0.sample == $1.sample ? $0.order < $1.order : $0.sample < $1.sample }
    return ["ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"] + records.map { $0.line }
}

func excerptLines(_ samples: [Int], _ signals: Signals, _ count: Int) -> [String] {
    ["sample,ecg,lowpass,bandpass,derivative,squared,integrated"] + (0..<count).map { index in
        [index, samples[index], signals.lowpass[index], signals.bandpass[index], signals.derivative[index],
         signals.squared[index], signals.integrated[index]].map(String.init).joined(separator: ",")
    }
}

func matchingErrors(_ beats: [Beat], _ annotations: [Annotation]) -> [String] {
    var events: [(sample: Int, order: Int, text: String)] = []
    for beat in beats where beat.annotation == nil {
        events.append((beat.sample, 0, "false_positive beat=\(beat.number) sample=\(beat.sample) time_ms=\(5 * beat.sample) label=\(beat.label)"))
    }
    for reference in annotations where reference.beat == nil {
        events.append((reference.sample, 1, "false_negative sample=\(reference.sample) time_ms=\(5 * reference.sample) label=\(reference.label)"))
    }
    return events.sorted { $0.sample == $1.sample ? $0.order < $1.order : $0.sample < $1.sample }.map { $0.text }
}

func performanceLines(_ beats: [Beat], _ annotations: [Annotation], _ detection: Detection,
                      _ parameters: [String: Int], _ segments: [Segment], _ count: Int) -> [String] {
    let referenceTypes = Dictionary(grouping: annotations, by: { $0.label }).mapValues { $0.count }
    let detectedTypes = Dictionary(grouping: beats, by: { $0.label }).mapValues { $0.count }
    let tp = annotations.filter { $0.beat != nil }.count
    let fn = annotations.count - tp
    let fp = beats.filter { $0.annotation == nil }.count
    let threshold = thresholds(detection.levels)
    let classCounts = PeakCategory.allCases.map { category in
        "\(category.rawValue)=\(detection.peaks.filter { $0.category == category }.count)"
    }.joined(separator: " ")
    var lines = ["DETECTOR", "samples \(count)", "duration_ms \(5 * count)", "peaks \(detection.peaks.count) \(classCounts)",
                 "initial_levels " + detection.initial.text, "final_levels " + detection.levels.text,
                 "final_thresholds thr_i=\(threshold.integrated) thr_f=\(threshold.filtered)",
                 "final_rr_averages rravg1_ms=\(5 * detection.average1) rravg2_ms=\(5 * detection.average2)", "MATCHING",
                 "tolerance_ms \(parameters["match_ms"]!)",
                 "references \(annotations.count) " + labels.map { "\($0)=\(referenceTypes[$0, default: 0])" }.joined(separator: " "),
                 "detections \(beats.count) " + labels.map { "\($0)=\(detectedTypes[$0, default: 0])" }.joined(separator: " "),
                 "true_positives \(tp)", "false_positives \(fp)", "false_negatives \(fn)",
                 "sensitivity " + ratio(tp, tp + fn), "positive_predictivity " + ratio(tp, tp + fp),
                 "detection_error_rate " + ratio(fp + fn, annotations.count)]
    let methods = ["threshold", "searchback"].map { method -> String in
        let selected = beats.filter { $0.method == method }
        return "\(method)=\(selected.filter { $0.annotation != nil }.count)/\(selected.count)"
    }
    lines.append("by_method " + methods.joined(separator: " "))
    let offsets = beats.compactMap { $0.offset }
    if !offsets.isEmpty {
        lines.append("offset_ms mean=\(two(rdiv(100 * offsets.reduce(0, +), offsets.count))) "
            + "mean_abs=\(two(rdiv(100 * offsets.map(abs).reduce(0, +), offsets.count))) max_abs=\(offsets.map(abs).max()!)")
    } else { lines.append("offset_ms none") }
    var confusion: [String: [String: Int]] = [:]
    for reference in annotations {
        let label = reference.beat.map { beats[$0].label } ?? "miss"
        confusion[reference.label, default: [:]][label, default: 0] += 1
    }
    for beat in beats where beat.annotation == nil { confusion["extra", default: [:]][beat.label, default: 0] += 1 }
    lines += ["CONFUSION", "ref  " + labels.map { padded($0, 6) }.joined() + "  miss"]
    for label in labels {
        let counts = labels.map { padded(confusion[label, default: [:]][$0, default: 0], 6) }.joined()
        lines.append(label + "    " + counts + padded(confusion[label, default: [:]]["miss", default: 0], 6))
    }
    lines.append("extra" + labels.map { padded(confusion["extra", default: [:]][$0, default: 0], 6) }.joined())
    for (label, prefix) in [("V", "veb"), ("A", "sveb")] {
        let correct = confusion[label, default: [:]][label, default: 0]
        lines.append(prefix + "_sensitivity " + ratio(correct, referenceTypes[label, default: 0]))
        lines.append(prefix + "_positive_predictivity " + ratio(correct, detectedTypes[label, default: 0]))
    }
    lines.append("SEGMENTS segment_ms=\(parameters["segment_ms"]!) segments=\(segments.count)")
    for segment in segments {
        lines.append("\(segment.prefix) refs=\(segment.references) tp=\(segment.tp) fp=\(segment.fp) fn=\(segment.fn) noise_peaks=\(segment.noisePeaks)")
    }
    lines.append("ERRORS count=\(fp + fn)")
    lines += matchingErrors(beats, annotations)
    return lines
}

struct PrematureBeat {
    let index: Int
    let nextRR: Int?
    let mean: Int
    let prematurity: Int
    let compensation: String
}

func prematureBeats(_ beats: [Beat]) -> [PrematureBeat] {
    beats.indices.filter { beats[$0].label != "N" }.map { index in
        let total = beats[(index - 8)..<index].reduce(0) { $0 + $1.rr! }
        let nextRR = index + 1 < beats.count ? beats[index + 1].rr : nil
        let compensation: String
        if let nextRR {
            let combined = beats[index].rr! + nextRR
            if 10 * abs(4 * combined - total) <= total { compensation = "full" }
            else { compensation = 4 * combined < total ? "partial" : "long" }
        } else { compensation = "-" }
        return PrematureBeat(index: index, nextRR: nextRR, mean: rdiv(100 * total, 8),
                              prematurity: rdiv(80000 * beats[index].rr!, total), compensation: compensation)
    }
}

func prematureRunLines(_ beats: [Beat]) -> [String] {
    var runs: [(first: Int, text: String)] = []
    for label in ["V", "A"] {
        for range in consecutiveRanges(beats.filter { $0.label == label }.map { $0.number }) {
            let length = range.last - range.first + 1
            let kind = length == 1 ? "isolated" : length == 2 ? "couplet" : "run"
            let start = 5 * beats[range.first - 1].sample
            runs.append((range.first, "\(label) \(kind) beats=\(range.first)-\(range.last) length=\(length) start_ms=\(start)"))
        }
    }
    return runs.sorted { $0.first < $1.first }.map { $0.text }
}

func arrhythmiaLines(_ beats: [Beat], _ parameters: [String: Int]) -> [String] {
    var lines: [String] = []
    for beat in beats.dropFirst() where beat.rr! > parameters["pause_ms"]! {
        lines.append("pause beats=\(beat.number - 1)-\(beat.number) rr_ms=\(beat.rr!) start_ms=\(5 * beats[beat.number - 2].sample)")
    }
    for (kind, threshold) in [("bradycardia", parameters["brady_ms"]!), ("tachycardia", parameters["tachy_ms"]!)] {
        let selected = beats.dropFirst().filter { kind == "bradycardia" ? $0.rr! > threshold : $0.rr! < threshold }.map { $0.number }
        for range in consecutiveRanges(selected) where range.last - range.first + 1 >= 3 {
            let intervals = beats[(range.first - 1)..<range.last].map { $0.rr! }
            let start = 5 * beats[range.first - 2].sample
            lines.append("\(kind) beats=\(range.first - 1)-\(range.last) intervals=\(intervals.count) "
                + "mean_hr=\(two(meanHeartRate(intervals)!)) start_ms=\(start)")
        }
    }
    let ventricular = beats.filter { $0.label == "V" }.map { $0.number }
    for (kind, span) in [("bigeminy", 2), ("trigeminy", 3)] {
        var chains: [[Int]] = []
        var current: [Int] = []
        for number in ventricular {
            if let last = current.last, number == last + span,
               ((last + 1)..<number).allSatisfy({ beats[$0 - 1].label == "N" }) { current.append(number) }
            else {
                if !current.isEmpty { chains.append(current) }
                current = [number]
            }
        }
        if !current.isEmpty { chains.append(current) }
        for chain in chains where chain.count >= 3 {
            lines.append("\(kind) beats=\(chain[0])-\(chain.last!) cycles=\(chain.count) start_ms=\(5 * beats[chain[0] - 1].sample)")
        }
    }
    return lines
}

func hrvLines(_ beats: [Beat], _ annotations: [Annotation], _ segments: [Segment], _ parameters: [String: Int]) -> [String] {
    let intervals = beats.compactMap { beat in beat.rr.map { (beat: beat.number, value: $0) } }
    let rr = rrStatistics(intervals)
    var nnIntervals: [Int: Int] = [:]
    if beats.count >= 3 {
        for index in 2..<beats.count {
            let previous = beats[index - 1]
            let current = beats[index]
            if previous.label == "N" && current.label == "N" && 5 * abs(current.rr! - previous.rr!) <= previous.rr! {
                nnIntervals[current.number] = current.rr!
            }
        }
    }
    let nnValues = nnIntervals.keys.sorted().map { nnIntervals[$0]! }
    let nnPairs = nnIntervals.keys.sorted().compactMap { number -> (Int, Int)? in
        nnIntervals[number - 1].map { ($0, nnIntervals[number]!) }
    }
    let nn = nnStatistics(nnValues, nnPairs)
    var lines = ["RR", "beats \(beats.count)", "intervals \(rr.count)", "mean_rr_ms \(maybeTwo(rr.meanRR))"]
    if let shortest = rr.shortest, let longest = rr.longest {
        lines += ["min_rr_ms \(shortest.value) beat=\(shortest.beat)", "max_rr_ms \(longest.value) beat=\(longest.beat)",
                  "mean_hr_bpm \(two(rr.meanHR!))"]
    } else { lines += ["min_rr_ms none", "max_rr_ms none", "mean_hr_bpm none"] }
    lines += ["NN", "intervals \(nn.count)", "mean_nn_ms \(maybeTwo(nn.mean))", "sdnn_ms \(maybeTwo(nn.sdnn))",
              "differences \(nn.pairs)", "rmssd_ms \(maybeTwo(nn.rmssd))", "sdsd_ms \(maybeTwo(nn.sdsd))", "nn50 \(nn.nn50)",
              nn.pnn50.map { "pnn50 \(two($0))%" } ?? "pnn50 none", "sd1_ms \(maybeTwo(nn.sd1))", "sd2_ms \(maybeTwo(nn.sd2))",
              "HISTOGRAM bin_ms=7.8125 bins=\(nn.histogram.count) max=\(nn.histogramMaximum)"]
    for bin in nn.histogram.keys.sorted() {
        let count = nn.histogram[bin]!
        lines.append("\(padded(four(78125 * bin), 10)) \(padded(four(78125 * (bin + 1)), 10)) \(padded(count, 3)) |"
            + String(repeating: "#", count: count))
    }
    lines.append(nn.count == 0 ? "triangular_index none"
        : "triangular_index \(fraction(nn.count, nn.histogramMaximum)) \(two(nn.triangularIndex!))")
    let premature = prematureBeats(beats)
    lines.append("PREMATURE count=\(premature.count) V=\(beats.filter { $0.label == "V" }.count) A=\(beats.filter { $0.label == "A" }.count)")
    for item in premature {
        let beat = beats[item.index]
        let reference = beat.annotation.map { annotations[$0].label } ?? "-"
        lines.append("beat=\(beat.number) sample=\(beat.sample) label=\(beat.label) rr_ms=\(beat.rr!) next_rr_ms=\(missing(item.nextRR)) "
            + "mean_ms=\(two(item.mean)) prematurity=\(two(item.prematurity))% compensation=\(item.compensation) width_ms=\(beat.width) ref=\(reference)")
    }
    let runs = prematureRunLines(beats)
    lines.append("RUNS count=\(runs.count)")
    lines += runs
    let events = arrhythmiaLines(beats, parameters)
    lines.append("EVENTS count=\(events.count)")
    lines += events
    lines.append("TREND segment_ms=\(parameters["segment_ms"]!) segments=\(segments.count)")
    for segment in segments {
        let prefix = "\(segment.prefix) beats=\(segment.beats) "
        if let heartRate = meanHeartRate(segment.intervals) {
            lines.append(prefix + "mean_hr=\(two(heartRate)) min_hr=\(two(rdiv(6000000, segment.intervals.max()!))) "
                + "max_hr=\(two(rdiv(6000000, segment.intervals.min()!))) |" + String(repeating: "#", count: rdiv(heartRate, 500)))
        } else { lines.append(prefix + "mean_hr=none min_hr=none max_hr=none |") }
    }
    return lines
}

func scale(_ value: Int, _ top: Int, _ bottom: Int, _ rows: Int) -> Int {
    top > bottom ? rdiv((top - value) * (rows - 1), top - bottom) : 0
}

func drawAxis(_ columns: Int, _ marker: (Int) -> Bool) -> String {
    "       +" + (0..<columns).map { marker($0) ? "+" : "-" }.joined() + "+"
}

func drawLabels(_ heading: String, _ markers: [(Int, String)]) -> String {
    var buffer = Array(padded(heading, 6) + "  ")
    for (column, value) in markers {
        let start = 8 + column
        let characters = Array(value)
        if buffer.count < start + characters.count {
            buffer += Array(repeating: " ", count: start + characters.count - buffer.count)
        }
        for offset in characters.indices { buffer[start + offset] = characters[offset] }
    }
    return String(buffer.reversed().drop(while: { $0 == " " }).reversed())
}

func waveformChart(_ upper: [Int], _ lower: [Int], _ height: Int) -> [String] {
    let top = upper.max()!
    let bottom = lower.min()!
    let zero = bottom <= 0 && 0 <= top ? scale(0, top, bottom, height) : nil
    return (0..<height).map { row in
        let label = row == 0 ? String(top) : row == height - 1 ? String(bottom) : row == zero ? "0" : ""
        let cells = upper.indices.map { column in
            if scale(upper[column], top, bottom, height) <= row && row <= scale(lower[column], top, bottom, height) { return "#" }
            return row == zero ? "-" : " "
        }.joined()
        return padded(label, 6) + " |" + cells + "|"
    }
}

func tachogramChart(_ beats: [Beat], _ height: Int) -> [String] {
    let intervals = beats.dropFirst().map { $0.rr! }
    guard let low = intervals.min(), let high = intervals.max() else { return ["TACHOGRAM intervals=0", "POINCARE points=0"] }
    var lines = ["TACHOGRAM intervals=\(intervals.count) min_ms=\(low) max_ms=\(high) rows=\(height)"]
    for row in 0..<height {
        let label = row == 0 ? String(high) : row == height - 1 ? String(low) : ""
        let cells = intervals.map { scale($0, high, low, height) == row ? "*" : " " }.joined()
        lines.append(padded(label, 6) + " |" + cells + "|")
    }
    lines.append(drawAxis(intervals.count) { ($0 + 2) % 10 == 0 })
    let markers = intervals.indices.filter { ($0 + 2) % 10 == 0 }.map { ($0, String($0 + 2)) }
    lines.append(drawLabels("beat", markers))
    lines.append(" label |" + beats.dropFirst().map { $0.label }.joined() + "|")
    return lines
}

func poincareChart(_ beats: [Beat], _ size: Int) -> [String] {
    let intervals = beats.dropFirst().map { $0.rr! }
    guard let low = intervals.min(), let high = intervals.max() else { return [] }
    var counts = Array(repeating: Array(repeating: 0, count: size), count: size)
    for (first, second) in zip(intervals, intervals.dropFirst()) {
        let column = high > low ? rdiv((first - low) * (size - 1), high - low) : 0
        counts[scale(second, high, low, size)][column] += 1
    }
    var lines = ["POINCARE points=\(intervals.count - 1) size=\(size) min_ms=\(low) max_ms=\(high)"]
    for row in 0..<size {
        let label = row == 0 ? String(high) : row == size - 1 ? String(low) : ""
        let cells = counts[row].map { $0 == 0 ? "." : $0 <= 9 ? String($0) : "#" }.joined()
        lines.append(padded(label, 6) + " |" + cells + "|")
    }
    lines.append(drawAxis(size) { _ in false })
    let left = String(repeating: " ", count: 8) + String(low)
    let right = String(high)
    lines.append(left + String(repeating: " ", count: max(0, 8 + size - right.count - left.count)) + right)
    return lines
}

func averageTemplate(_ samples: [Int], _ beats: [Beat], _ label: String, _ height: Int) -> [String] {
    let chosen = beats.filter { $0.label == label && 60 <= $0.sample && $0.sample <= samples.count - 100 }
    if chosen.isEmpty { return ["TEMPLATE \(label) beats=0"] }
    let baselines = chosen.map { samples[($0.sample - 60)..<($0.sample - 50)].reduce(0, +) }
    let averaged = (-60..<100).map { offset in
        let total = chosen.indices.reduce(0) { $0 + 10 * samples[chosen[$1].sample + offset] - baselines[$1] }
        return rdiv(total, 10 * chosen.count)
    }
    let maximum = averaged.max()!
    let minimum = averaged.min()!
    let maximumTime = 5 * (averaged.firstIndex(of: maximum)! - 60)
    let minimumTime = 5 * (averaged.firstIndex(of: minimum)! - 60)
    var lines = ["TEMPLATE \(label) beats=\(chosen.count) max_uv=\(maximum) max_ms=\(maximumTime) "
                    + "min_uv=\(minimum) min_ms=\(minimumTime) rows=\(height)"]
    let upper = (0..<80).map { max(averaged[2 * $0], averaged[2 * $0 + 1]) }
    let lower = (0..<80).map { min(averaged[2 * $0], averaged[2 * $0 + 1]) }
    lines += waveformChart(upper, lower, height)
    lines.append(drawAxis(80) { $0 % 10 == 0 })
    lines.append(drawLabels("ms", stride(from: 0, to: 80, by: 10).map { ($0, String(10 * $0 - 300)) }))
    return lines
}

func chartLines(_ samples: [Int], _ beats: [Beat], _ parameters: [String: Int]) -> [String] {
    var lines = tachogramChart(beats, parameters["chart_rows"]!)
    lines += poincareChart(beats, parameters["poincare_size"]!)
    for label in labels { lines += averageTemplate(samples, beats, label, parameters["chart_rows"]!) }
    return lines
}

func rhythmStripLines(_ samples: [Int], _ beats: [Beat], _ annotations: [Annotation], _ parameters: [String: Int]) -> [String] {
    let startMilliseconds = parameters["strip_start_ms"]!
    let milliseconds = parameters["strip_ms"]!
    let start = startMilliseconds / 5
    let count = milliseconds / 5
    let end = start + count
    let columns = count / 10
    let height = parameters["strip_rows"]!
    let excerpt = samples[start..<end]
    let upper = (0..<columns).map { column in samples[(start + 10 * column)..<(start + 10 * column + 10)].max()! }
    let lower = (0..<columns).map { column in samples[(start + 10 * column)..<(start + 10 * column + 10)].min()! }
    var lines = ["RHYTHM start_ms=\(startMilliseconds) end_ms=\(startMilliseconds + milliseconds) columns=\(columns) "
                    + "rows=\(height) max_uv=\(excerpt.max()!) min_uv=\(excerpt.min()!)"]
    lines += waveformChart(upper, lower, height)
    lines.append(drawAxis(columns) { $0 % 20 == 0 })
    lines.append(drawLabels("s", stride(from: 0, to: columns, by: 20).map { ($0, String((startMilliseconds + 50 * $0) / 1000)) }))
    var beatMarks = Array(repeating: " ", count: columns)
    var referenceMarks = beatMarks
    for beat in beats where start <= beat.sample && beat.sample < end { beatMarks[(beat.sample - start) / 10] = beat.label }
    for reference in annotations where start <= reference.sample && reference.sample < end { referenceMarks[(reference.sample - start) / 10] = reference.label }
    lines.append(" beats |" + beatMarks.joined() + "|")
    lines.append("  refs |" + referenceMarks.joined() + "|")
    return lines
}

let samples = try readECG()
var annotations = try readAnnotations()
let parameters = try readParameters()
let signals = filterECG(samples)
let peaks = findPeaks(signals)
let detection = Detection(peaks, signals, parameters)
detection.run(samples.count)
var beats = buildBeats(detection.registered, signals.bandpass, parameters)
matchAnnotations(&beats, &annotations, parameters["match_ms"]! / 5)
let segments = segmentRows(beats, annotations, peaks, samples.count, parameters["segment_ms"]! / 5)
try writeLines("beats.csv", beatLines(beats, annotations))
try writeLines("peaks.csv", peakLines(peaks))
try writeLines("matching.csv", matchingLines(beats, annotations))
try writeLines("signals_excerpt.csv", excerptLines(samples, signals, parameters["excerpt_ms"]! / 5))
try writeLines("performance.txt", performanceLines(beats, annotations, detection, parameters, segments, samples.count))
try writeLines("hrv.txt", hrvLines(beats, annotations, segments, parameters))
try writeLines("charts.txt", chartLines(samples, beats, parameters))
try writeLines("rhythm_strip.txt", rhythmStripLines(samples, beats, annotations, parameters))
