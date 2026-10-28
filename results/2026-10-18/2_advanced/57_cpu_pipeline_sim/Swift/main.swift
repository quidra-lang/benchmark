import Foundation

let operandRules: [InstructionClass: [Int]] = [.alu: [1, 1, 2], .multiply: [1, 1, 1], .load: [1, 1, 0], .store: [0, 1, 1], .branch: [0, 1, 2], .jump: [2, 2, 0], .nop: [0, 0, 0]]
let missNames = ["direction", "btb_miss", "wrong_target"]
struct Rejection { let line: Int; let reason: String }
struct Gap { let line: Int; let expected: Int; let found: Int }
struct Trace { let lines: Int; let instructions: [Instruction]; let rejected: [Rejection]; let gaps: [Gap]; let staticInstructions: [Int: Instruction] }
func checkRecord(_ line: String, _ number: Int, _ lineNumber: Int, _ previous: [Int: Instruction]) -> (instruction: Instruction?, reason: String?) {
    let fields = line.components(separatedBy: " ")
    if fields.count != 8 || fields.contains("") { return (nil, "fields") }
    guard let pc = parseHex(fields[0]), pc % 4 == 0 else { return (nil, "pc") }
    guard let kind = InstructionClass(rawValue: fields[1]) else { return (nil, "class") }
    let texts = Array(fields[2...4]), registers = texts.map { parseRegister($0) }
    for i in 0..<3 { if texts[i] != "-" && registers[i] == nil { return (nil, "register") } }
    for i in 0..<3 { let usage = operandRules[kind]![i]; if (usage == 1 && texts[i] == "-") || (usage == 0 && texts[i] != "-") { return (nil, "operands") } }
    let allowed = kind == .branch ? ["T", "N"] : kind == .jump ? ["T"] : ["-"]
    if !allowed.contains(fields[5]) { return (nil, "taken") }
    let target = parseHex(fields[6]), address = parseHex(fields[7]), control = kind == .branch || kind == .jump
    if control { if target == nil || target! % 4 != 0 || target! == pc + 4 { return (nil, "target") } } else if fields[6] != "-" { return (nil, "target") }
    if kind == .load || kind == .store { if address == nil || address! % 4 != 0 { return (nil, "address") } } else if fields[7] != "-" { return (nil, "address") }
    let instruction = Instruction(number: number, line: lineNumber, pc: pc, kind: kind, destination: registers[0], firstSource: registers[1], secondSource: registers[2], taken: fields[5] == "T", target: target, address: address)
    if let first = previous[pc] {
        if kind != first.kind || instruction.destination != first.destination || instruction.firstSource != first.firstSource || instruction.secondSource != first.secondSource { return (nil, "conflict") }
        if (kind == .branch || (kind == .jump && instruction.firstSource == nil)) && target != first.target { return (nil, "conflict") }
    }
    return (instruction, nil)
}
func validateTrace(_ lines: [String]) -> Trace {
    var instructions: [Instruction] = [], rejected: [Rejection] = [], gaps: [Gap] = [], first: [Int: Instruction] = [:]
    for (i, line) in lines.enumerated() {
        let checked = checkRecord(line, instructions.count + 1, i + 1, first)
        if let reason = checked.reason { rejected.append(Rejection(line: i + 1, reason: reason)); continue }
        let instruction = checked.instruction!
        if let previous = instructions.last, previous.nextPC != instruction.pc { gaps.append(Gap(line: i + 1, expected: previous.nextPC, found: instruction.pc)) }
        instructions.append(instruction)
        if first[instruction.pc] == nil { first[instruction.pc] = instruction }
    }
    return Trace(lines: lines.count, instructions: instructions, rejected: rejected, gaps: gaps, staticInstructions: first)
}
struct PredictionDetail { let predicted: Int; let kind: Int? }
struct PredictionStatistics {
    var lookups = 0
    var hits = 0
    var calls = 0
    var returns = 0
    var rasPredictions = 0
    var rasCorrect = 0
    var mispredictions = 0
    var kinds = [0, 0]
    var kindMisses = [0, 0]
    var misses = [0, 0, 0]
    var control: Int { kinds.reduce(0, +) }
}
struct Prediction {
    let definition: PredictorDefinition
    let details: [PredictionDetail?]
    let flags: [Bool]
    let statistics: PredictionStatistics
    let bits: Int
    func accuracy(_ kind: Int? = nil) -> String { if let kind { return percentage(statistics.kinds[kind] - statistics.kindMisses[kind], statistics.kinds[kind]) }; return percentage(statistics.control - statistics.mispredictions, statistics.control) }
}
func predictTrace(_ instructions: [Instruction], _ definition: PredictorDefinition, _ config: Configuration) -> Prediction {
    var btb = BTB(config.btb), ras = ReturnStack(depth: config.ras), direction = DirectionPredictor(definition), statistics = PredictionStatistics(), flags = Array(repeating: false, count: instructions.count), details = Array<PredictionDetail?>(repeating: nil, count: instructions.count)
    for (i, instruction) in instructions.enumerated() where instruction.control {
        let pc = instruction.pc, target = instruction.target!, kind = instruction.kind == .branch ? 0 : 1
        var candidate = btb.lookup(pc)
        statistics.lookups += 1; if candidate != nil { statistics.hits += 1 }
        let isReturn = instruction.kind == .jump && instruction.destination == nil && instruction.firstSource == 31, isCall = instruction.kind == .jump && instruction.destination == 31
        if isReturn { statistics.returns += 1; if let address = ras.pop() { candidate = address; statistics.rasPredictions += 1; if address == target { statistics.rasCorrect += 1 } } }
        if isCall { statistics.calls += 1; ras.push(pc + 4) }
        let predictedTaken = instruction.kind == .branch ? direction.predict(pc, target) : true
        let predicted = definition.scheme == "PERFECT" ? instruction.nextPC : (instruction.kind == .jump || predictedTaken) ? (candidate ?? pc + 4) : pc + 4
        let missed = predicted != instruction.nextPC
        var miss: Int?
        if missed { miss = instruction.kind == .branch && predictedTaken != instruction.taken ? 0 : candidate == nil ? 1 : 2; statistics.misses[miss!] += 1; statistics.mispredictions += 1; statistics.kindMisses[kind] += 1 }
        flags[i] = missed; details[i] = PredictionDetail(predicted: predicted, kind: miss); statistics.kinds[kind] += 1
        if instruction.kind == .branch { direction.update(pc, instruction.taken) }
        if instruction.taken { btb.insert(pc, target) }
    }
    return Prediction(definition: definition, details: details, flags: flags, statistics: statistics, bits: direction.storageBits)
}
struct Combination { let variant: Int; let predictor: Int; let result: Simulation }
func allCombinations(_ instructions: [Instruction], _ sources: [[Source]], _ predictions: [Prediction], _ config: Configuration) -> [Combination] {
    var pairs: [Combination] = []
    for v in config.variants.indices { for p in predictions.indices { pairs.append(Combination(variant: v, predictor: p, result: simulate(instructions, sources, config.variants[v], predictions[p].flags))) } }
    return pairs.sorted {
        if $0.result.cycles != $1.result.cycles { return $0.result.cycles < $1.result.cycles }
        let av = config.variants[$0.variant].name, bv = config.variants[$1.variant].name
        return av == bv ? predictions[$0.predictor].definition.name < predictions[$1.predictor].definition.name : av < bv
    }
}
func dataflowHeight(_ instructions: [Instruction], _ sources: [[Source]], _ latency: Int) -> Int {
    var finish: [Int] = []
    for (i, instruction) in instructions.enumerated() { let start = sources[i].compactMap { $0.producer.map { finish[$0] } }.max() ?? 0, cost = instruction.kind == .load ? 2 : instruction.kind == .multiply ? latency : 1; finish.append(start + cost) }
    return finish.max()!
}
struct CharacterSpan { let first: Int; let last: Int; let symbol: String }
struct StageSpan { let stage: Int; let first: Int; let last: Int }
struct DiagramRow { let number: Int?; let pc: Int; let kind: String; let annotation: String; let characters: [CharacterSpan]; let stages: [StageSpan] }
func buildRows(_ instructions: [Instruction], _ primary: Simulation, _ variant: Variant, _ prediction: Prediction) -> [DiagramRow] {
    var annotations = Array(repeating: "", count: instructions.count), rows: [DiagramRow] = []
    for record in primary.records { if let waiting = record.waiting { annotations[waiting] += " \(causeNames[record.cause]) \(record.cycles)" } }
    for (i, instruction) in instructions.enumerated() {
        let t = primary.timings[i]
        if prediction.flags[i] { annotations[i] += " mispredict " + missNames[prediction.details[i]!.kind!] }
        let characters = [CharacterSpan(first: t.fetch, last: t.fetch, symbol: "F"), CharacterSpan(first: t.fetch + 1, last: t.decode - 1, symbol: "*"), CharacterSpan(first: t.decode, last: t.decode, symbol: "D"), CharacterSpan(first: t.decode + 1, last: t.execute - 1, symbol: "*"), CharacterSpan(first: t.execute, last: t.memory - 1, symbol: "X"), CharacterSpan(first: t.memory, last: t.memory, symbol: "M"), CharacterSpan(first: t.writeback, last: t.writeback, symbol: "W")]
        let stages = [StageSpan(stage: 0, first: t.fetch, last: t.decode - 1), StageSpan(stage: 1, first: t.decode, last: t.execute - 1), StageSpan(stage: 2, first: t.execute, last: t.memory - 1), StageSpan(stage: 3, first: t.memory, last: t.memory), StageSpan(stage: 4, first: t.writeback, last: t.writeback)]
        rows.append(DiagramRow(number: instruction.number, pc: instruction.pc, kind: instruction.kind.rawValue, annotation: annotations[i], characters: characters, stages: stages))
        if !prediction.flags[i] { continue }
        let resolved = idResolved(instruction, variant), cancel = t.execute + (resolved ? 0 : 1), pc = prediction.details[i]!.predicted
        var wrong = [CharacterSpan(first: t.decode, last: t.decode, symbol: "F"), CharacterSpan(first: t.decode + 1, last: t.execute - 1, symbol: "*"), CharacterSpan(first: cancel, last: cancel, symbol: "x")], wrongStages = [StageSpan(stage: 0, first: t.decode, last: t.execute - 1)]
        if !resolved { wrong.append(CharacterSpan(first: t.execute, last: t.execute, symbol: "D")); wrongStages.append(StageSpan(stage: 1, first: t.execute, last: t.execute)) }
        rows.append(DiagramRow(number: nil, pc: pc, kind: "FLUSH", annotation: "", characters: wrong, stages: wrongStages))
        if !resolved { rows.append(DiagramRow(number: nil, pc: pc + 4, kind: "FLUSH", annotation: "", characters: [CharacterSpan(first: t.execute, last: t.execute, symbol: "F"), CharacterSpan(first: t.execute + 1, last: t.execute + 1, symbol: "x")], stages: [StageSpan(stage: 0, first: t.execute, last: t.execute)])) }
    }
    return rows
}
func pipelineLines(_ rows: [DiagramRow], _ primary: Simulation, _ variant: Variant, _ predictor: String, _ config: Configuration) -> [String] {
    let first = config.firstCycle, last = config.lastCycle, width = last - first + 1
    var lines = ["pipeline variant=\(variant.name) predictor=\(predictor) cycles \(first)-\(last)", cycleHeading(first, last)], contents = Array(repeating: Array(repeating: ".", count: 5), count: width), visible = 0, stalled = 0, flushed = 0
    for row in rows {
        var characters = Array(repeating: ".", count: width)
        for span in row.characters { let start = max(first, span.first), stop = min(last, span.last); if start <= stop { for cycle in start...stop { characters[cycle - first] = span.symbol } } }
        if characters.contains(where: { $0 != "." }) { visible += 1; stalled += characters.filter { $0 == "*" }.count; flushed += characters.filter { $0 == "x" }.count; lines.append(diagramRow(row.number, row.pc, row.kind, characters.joined(), row.annotation)) }
        for span in row.stages { let start = max(first, span.first), stop = min(last, span.last); if start <= stop { for cycle in start...stop { contents[cycle - first][span.stage] = row.number.map(String.init) ?? "w" } } }
    }
    let completed = primary.timings.filter { first <= $0.writeback && $0.writeback <= last }.count
    lines += ["rows \(visible) completed \(completed) stall_cells \(stalled) flushed \(flushed)", "", "stages", "cycle IF ID EX MEM WB"]
    for (i, content) in contents.enumerated() { lines.append("\(first + i) " + content.joined(separator: " ")) }
    return lines
}

func causeText(_ values: [Int]) -> String { (0..<4).map { "\(causeNames[$0]) \(values[$0])" }.joined(separator: " ") }
struct DependencyKey: Hashable { let producer: Int; let waiting: Int; let cause: Int }
struct DependencyGroup { var cycles = 0; var events = 0 }
func statisticsLines(_ trace: Trace, _ sources: [[Source]], _ predictions: [Prediction], _ combinations: [Combination], _ primary: Combination, _ rows: [DiagramRow], _ config: Configuration) -> [String] {
    let instructions = trace.instructions, n = instructions.count, result = primary.result, variant = config.variants[primary.variant], prediction = predictions[primary.predictor], stalls = result.stallCycles, totalStalls = stalls.reduce(0, +), cycles = result.cycles
    var parts: [[String]] = []
    parts.append(["input lines \(trace.lines) accepted \(n) rejected \(trace.rejected.count) gaps \(trace.gaps.count)"] + trace.rejected.map { "reject line \($0.line) \($0.reason)" } + trace.gaps.map { "gap line \($0.line) expected \(hexadecimal($0.expected)) found \(hexadecimal($0.found))" })
    let classes = Dictionary(grouping: instructions, by: { $0.kind }).mapValues { $0.count }, branches = instructions.filter { $0.kind == .branch }, jumps = instructions.filter { $0.kind == .jump }, addresses = Set(instructions.compactMap { $0.address })
    var distances = Array(repeating: 0, count: 6)
    for (i, operands) in sources.enumerated() { for operand in operands { if let producer = operand.producer { distances[min(5, i - producer)] += 1 } } }
    parts.append(["trace", "instructions \(n)", "static_instructions \(trace.staticInstructions.count)", "mix " + InstructionClass.allCases.map { "\($0.rawValue) \(classes[$0] ?? 0)" }.joined(separator: " "),
                  "branches \(branches.count) taken \(branches.filter { $0.taken }.count) backward \(branches.filter { $0.target! < $0.pc }.count)", "jumps \(jumps.count) indirect \(jumps.filter { $0.firstSource != nil }.count) link \(jumps.filter { $0.destination != nil }.count)",
                  "static_control branches \(trace.staticInstructions.values.filter { $0.kind == .branch }.count) jumps \(trace.staticInstructions.values.filter { $0.kind == .jump }.count)", "memory loads \(classes[.load] ?? 0) stores \(classes[.store] ?? 0) distinct_addresses \(addresses.count)",
                  "operands \(sources.reduce(0) { $0 + $1.count }) with_producer \(distances.reduce(0, +)) distance " + (1...5).map { "\($0 == 5 ? "5+" : String($0)) \(distances[$0])" }.joined(separator: " ")])
    var predictionPart = ["prediction"]
    for prediction in predictions {
        let stats = prediction.statistics
        predictionPart.append("\(prediction.definition.name) \(prediction.definition.scheme) bits \(prediction.bits) control \(stats.control) mispredicted \(stats.mispredictions) accuracy \(prediction.accuracy()) branches \(prediction.accuracy(0)) jumps \(prediction.accuracy(1)) " + (0..<3).map { "\(missNames[$0]) \(stats.misses[$0])" }.joined(separator: " "))
    }
    let shared = predictions[0].statistics
    predictionPart += ["btb entries \(config.btb) lookups \(shared.lookups) hits \(shared.hits) misses \(shared.lookups - shared.hits)", "ras depth \(config.ras) calls \(shared.calls) returns \(shared.returns) predicted \(shared.rasPredictions) correct \(shared.rasCorrect)"]
    parts.append(predictionPart)
    var lengths = Array(repeating: 0, count: 6)
    for delay in result.delays where delay > 0 { lengths[min(5, delay)] += 1 }
    let height = dataflowHeight(instructions, sources, variant.latency)
    parts.append(["timing variant=\(variant.name) predictor=\(prediction.definition.name)", "forwarding \(variant.forwarding ? "on" : "off") branch_stage \(variant.stage) mul_latency \(variant.latency)", "cycles \(cycles)", "cpi \(reducedFraction(cycles, n)) \(decimal(cycles, n))", "ipc \(decimal(n, cycles))", "stall_cycles total \(totalStalls) " + causeText(stalls), "stall_events " + causeText(result.stallEvents), "flushed \(rows.filter { $0.number == nil }.count)", "cycle_check \(n) + 4 + \(totalStalls) = \(n + 4 + totalStalls)", "cpi_stack base 1.0000 fill \(decimal(4, n)) " + (0..<4).map { "\(causeNames[$0]) \(decimal(stalls[$0], n))" }.joined(separator: " "), "stall_lengths " + (1...5).map { "\($0 == 5 ? "5+" : String($0)) \(lengths[$0])" }.joined(separator: " "), "dataflow height \(height) ilp \(decimal(n, height))"])
    let whatifs: [(String, Variant, [Bool])] = [("perfect_prediction", variant, Array(repeating: false, count: n)), ("single_cycle_mul", Variant(name: variant.name, forwarding: variant.forwarding, stage: variant.stage, latency: 1), prediction.flags), (variant.forwarding ? "forwarding_off" : "forwarding_on", Variant(name: variant.name, forwarding: !variant.forwarding, stage: variant.stage, latency: variant.latency), prediction.flags), (variant.stage == "EX" ? "branch_stage_ID" : "branch_stage_EX", Variant(name: variant.name, forwarding: variant.forwarding, stage: variant.stage == "EX" ? "ID" : "EX", latency: variant.latency), prediction.flags)]
    parts.append(["whatif"] + whatifs.map { name, modified, flags in let count = simulate(instructions, sources, modified, flags).cycles; return "\(name) cycles \(count) saved \(cycles - count) speedup \(decimal(cycles, count))" })
    var classStalls: [InstructionClass: Int] = [:], byPC: [Int: [Int]] = [:], pairs: [DependencyKey: DependencyGroup] = [:]
    for record in result.records {
        let instruction = instructions[record.responsible]
        classStalls[instruction.kind, default: 0] += record.cycles; byPC[instruction.pc, default: Array(repeating: 0, count: 4)][record.cause] += record.cycles
        if record.cause >= 2 { let key = DependencyKey(producer: instructions[record.producer!].pc, waiting: instructions[record.waiting!].pc, cause: record.cause); pairs[key, default: DependencyGroup()].cycles += record.cycles; pairs[key, default: DependencyGroup()].events += 1 }
    }
    parts.append(["classes"] + InstructionClass.allCases.map { kind in let count = classes[kind] ?? 0, stall = classStalls[kind] ?? 0; return "\(kind.rawValue) count \(count) stall_cycles \(stall) per_instruction \(count == 0 ? "-" : decimal(stall, count))" })
    var forwarded = [0, 0, 0]
    for (i, instruction) in instructions.enumerated() { for source in sources[i] { let producer = source.producer.map { result.timings[$0] }; forwarded[forwardingPath(instruction, producer, result.timings[i], variant)] += 1 } }
    parts.append(["forwarding regfile \(forwarded[0]) ex_mem \(forwarded[1]) mem_wb \(forwarded[2])"])
    var occupied = Array(repeating: [0, 0], count: 5)
    for row in rows { for span in row.stages { occupied[span.stage][row.number == nil ? 1 : 0] += span.last - span.first + 1 } }
    parts.append(["occupancy cycles \(cycles)"] + (0..<5).map { stage in let correct = occupied[stage][0], wrong = occupied[stage][1]; return "\(stageNames[stage]) correct \(correct) wrong \(wrong) idle \(cycles - correct - wrong) busy \(percentage(correct + wrong, cycles))" })
    let hot = byPC.keys.sorted { let a = byPC[$0]!.reduce(0, +), b = byPC[$1]!.reduce(0, +); return a == b ? $0 < $1 : a > b }.prefix(config.top)
    parts.append(["hotspots"] + hot.enumerated().map { rank, pc in "\(rank + 1) \(hexadecimal(pc)) \(trace.staticInstructions[pc]!.kind.rawValue) stall_cycles \(byPC[pc]!.reduce(0, +)) " + causeText(byPC[pc]!) })
    let orderedPairs = pairs.keys.sorted { let a = pairs[$0]!.cycles, b = pairs[$1]!.cycles; return a == b ? [$0.producer, $0.waiting, $0.cause].lexicographicallyPrecedes([$1.producer, $1.waiting, $1.cause]) : a > b }
    parts.append(["dependencies total \(pairs.count)"] + orderedPairs.prefix(config.top).enumerated().map { rank, key in let group = pairs[key]!; return "\(rank + 1) \(hexadecimal(key.producer)) \(trace.staticInstructions[key.producer]!.kind.rawValue) -> \(hexadecimal(key.waiting)) \(trace.staticInstructions[key.waiting]!.kind.rawValue) \(causeNames[key.cause]) stall_cycles \(group.cycles) events \(group.events)" })
    var intervals = ["intervals size \(config.interval)"]
    for first in stride(from: 0, to: n, by: config.interval) { let last = min(n, first + config.interval) - 1, previous = first == 0 ? 0 : result.timings[first - 1].writeback, count = result.timings[last].writeback - previous; intervals.append("\(first + 1)-\(last + 1) cycles \(count) cpi \(decimal(count, last - first + 1))") }
    parts.append(intervals)
    var table = ["cycles_table " + config.predictors.map { $0.name }.joined(separator: " ")]
    for v in config.variants.indices { table.append(config.variants[v].name + " " + predictions.indices.map { p in String(combinations.first { $0.variant == v && $0.predictor == p }!.result.cycles) }.joined(separator: " ")) }
    parts.append(table)
    return joinParts(parts)
}
func groupExecutions(_ instructions: [Instruction]) -> [Int: [Int]] { var groups: [Int: [Int]] = [:]; for (i, instruction) in instructions.enumerated() { groups[instruction.pc, default: []].append(i) }; return groups }
func branchLines(_ instructions: [Instruction], _ groups: [Int: [Int]], _ predictions: [Prediction]) -> [String] {
    var lines = ["predictor,pc,class,executions,taken,mispredictions,accuracy"]
    for prediction in predictions {
        for pc in groups.keys.sorted() {
            let indices = groups[pc]!, instruction = instructions[indices[0]]
            if !instruction.control { continue }
            let taken = indices.filter { instructions[$0].taken }.count, missed = indices.filter { prediction.flags[$0] }.count
            lines.append("\(prediction.definition.name),\(hexadecimal(pc)),\(instruction.kind.rawValue),\(indices.count),\(taken),\(missed),\(percentage(indices.count - missed, indices.count))")
        }
    }
    return lines
}
func comparisonLines(_ combinations: [Combination], _ primary: Combination, _ predictions: [Prediction], _ config: Configuration, _ count: Int) -> [String] {
    ["rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw"] + combinations.enumerated().map { rank, pair in
        let prediction = predictions[pair.predictor], values = [String(rank + 1), config.variants[pair.variant].name, prediction.definition.name, String(pair.result.cycles), decimal(pair.result.cycles, count), decimal(primary.result.cycles, pair.result.cycles), prediction.accuracy(), String(prediction.statistics.mispredictions)] + pair.result.stallCycles.map(String.init)
        return values.joined(separator: ",")
    }
}
struct SegmentGroup { var instances = 0; var instructions = 0; var cycles = 0 }
func profileLines(_ instructions: [Instruction], _ groups: [Int: [Int]], _ predictions: [Prediction], _ primary: Simulation, _ config: Configuration) -> [String] {
    var branchPart = ["branches"], loopPart = ["loops"], indirectPart = ["indirect"], staticPart = ["instructions"], stalls: [Int: Int] = [:]
    let choices = predictions.indices.filter { predictions[$0].definition.scheme != "PERFECT" }
    for record in primary.records { stalls[instructions[record.responsible].pc, default: 0] += record.cycles }
    for pc in groups.keys.sorted() {
        let indices = groups[pc]!, instruction = instructions[indices[0]]
        if instruction.kind == .branch {
            let outcomes = indices.map { instructions[$0].taken }
            var previous: Bool?, length = 0, longestTaken = 0, longestNotTaken = 0, transitions = 0
            for outcome in outcomes { if let previous, previous != outcome { transitions += 1 }; length = previous == outcome ? length + 1 : 1; if outcome { longestTaken = max(longestTaken, length) } else { longestNotTaken = max(longestNotTaken, length) }; previous = outcome }
            let missed = predictions.map { prediction in indices.filter { prediction.flags[$0] }.count }
            var best = choices[0]
            for choice in choices.dropFirst() { if missed[choice] < missed[best] { best = choice } }
            branchPart.append("\(hexadecimal(pc)) \(instruction.target! < pc ? "backward" : "forward") executions \(indices.count) taken \(outcomes.filter { $0 }.count) transitions \(transitions) longest_taken \(longestTaken) longest_not_taken \(longestNotTaken) best \(predictions[best].definition.name) \(missed[best])")
            if instruction.target! < pc {
                var trips: [Int] = [], count = 0
                for outcome in outcomes { count += 1; if !outcome { trips.append(count); count = 0 } }
                if count > 0 { trips.append(count) }
                loopPart.append("\(hexadecimal(instruction.target!))-\(hexadecimal(pc)) body \((pc - instruction.target!) / 4 + 1) entries \(trips.count) iterations \(indices.count) avg_trip \(decimal(indices.count, trips.count)) max_trip \(trips.max()!)")
            }
        }
        if instruction.kind == .jump && instruction.firstSource != nil {
            var targets: [Int: Int] = [:]
            for i in indices { targets[instructions[i].target!, default: 0] += 1 }
            let ordered = targets.keys.sorted { targets[$0] == targets[$1] ? $0 < $1 : targets[$0]! > targets[$1]! }
            indirectPart.append("\(hexadecimal(pc)) executions \(indices.count) distinct \(targets.count) targets " + ordered.map { "\(hexadecimal($0)):\(targets[$0]!)" }.joined(separator: " "))
        }
        staticPart.append("\(hexadecimal(pc)) \(instruction.kind.rawValue) \(registerText(instruction.destination)) \(registerText(instruction.firstSource)) \(registerText(instruction.secondSource)) executions \(indices.count) stall_cycles \(stalls[pc] ?? 0)")
    }
    var segments: [Int: SegmentGroup] = [:], first = 0
    for (last, instruction) in instructions.enumerated() where instruction.control || last == instructions.count - 1 {
        let pc = instructions[first].pc, previous = first == 0 ? 0 : primary.timings[first - 1].writeback
        segments[pc, default: SegmentGroup()].instances += 1; segments[pc, default: SegmentGroup()].instructions += last - first + 1; segments[pc, default: SegmentGroup()].cycles += primary.timings[last].writeback - previous; first = last + 1
    }
    let ordered = segments.keys.sorted { segments[$0]!.cycles == segments[$1]!.cycles ? $0 < $1 : segments[$0]!.cycles > segments[$1]!.cycles }
    let segmentPart = ["segments total \(segments.count)"] + ordered.prefix(config.top).enumerated().map { rank, pc in let value = segments[pc]!; return "\(rank + 1) \(hexadecimal(pc)) instances \(value.instances) instructions \(value.instructions) cycles \(value.cycles) cpi \(decimal(value.cycles, value.instructions))" }
    return joinParts([branchPart, loopPart, segmentPart, indirectPart, staticPart])
}

let input = try readInputs(), trace = validateTrace(input.trace), config = input.config
let instructions = trace.instructions, sources = dependencies(trace.instructions), predictions = config.predictors.map { predictTrace(trace.instructions, $0, config) }
let combinations = allCombinations(instructions, sources, predictions, config)
let primary = combinations.first { config.variants[$0.variant].name == config.primaryVariant && predictions[$0.predictor].definition.name == config.primaryPredictor }!
let rows = buildRows(instructions, primary.result, config.variants[primary.variant], predictions[primary.predictor]), groups = groupExecutions(instructions)
try writeLines("pipeline.txt", pipelineLines(rows, primary.result, config.variants[primary.variant], config.primaryPredictor, config))
try writeLines("stats.txt", statisticsLines(trace, sources, predictions, combinations, primary, rows, config))
try writeLines("branches.csv", branchLines(instructions, groups, predictions))
try writeLines("comparison.csv", comparisonLines(combinations, primary, predictions, config, instructions.count))
try writeLines("profile.txt", profileLines(instructions, groups, predictions, primary.result, config))
