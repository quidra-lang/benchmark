import Foundation

let causeNames = ["control", "structural", "load_use", "raw"]
let stageNames = ["IF", "ID", "EX", "MEM", "WB"]
struct Timing { let fetch: Int; let decode: Int; let execute: Int; let memory: Int; let writeback: Int }
struct StallRecord { let cause: Int; let cycles: Int; let responsible: Int; let waiting: Int?; let producer: Int? }
struct Simulation {
    let timings: [Timing]
    let records: [StallRecord]
    let delays: [Int]
    var cycles: Int { timings.last!.writeback }
    var stallCycles: [Int] { var sums = Array(repeating: 0, count: 4); for record in records { sums[record.cause] += record.cycles }; return sums }
    var stallEvents: [Int] { var sums = Array(repeating: 0, count: 4); for record in records { sums[record.cause] += 1 }; return sums }
}
func simulate(_ instructions: [Instruction], _ sources: [[Source]], _ variant: Variant, _ mispredicted: [Bool]) -> Simulation {
    var timings: [Timing] = [], records: [StallRecord] = [], delays: [Int] = []
    for (i, instruction) in instructions.enumerated() {
        let latency = instruction.kind == .multiply ? variant.latency : 1
        let fetch: Int, decode: Int
        var execute = 3
        if i == 0 { fetch = 1; decode = 2 }
        else {
            let previous = timings[i - 1], ideal = previous.execute + 1
            fetch = mispredicted[i - 1] ? previous.execute + (idResolved(instructions[i - 1], variant) ? 0 : 1) : previous.decode
            decode = max(fetch + 1, previous.execute)
            var loadReady = ideal, rawReady = ideal, loadProducer: Int?, rawProducer: Int?
            for source in sources[i] {
                guard let p = source.producer else { continue }
                let ready = readyCycle(instruction, instructions[p], timings[p], variant)
                if instructions[p].kind == .load { if ready > loadReady { loadReady = ready; loadProducer = p } } else if ready > rawReady { rawReady = ready; rawProducer = p }
            }
            let bounds = [decode + 1, previous.memory, loadReady, rawReady], producers: [Int?] = [nil, nil, loadProducer, rawProducer]
            execute = ideal
            for cause in 0..<4 where bounds[cause] > execute { records.append(StallRecord(cause: cause, cycles: bounds[cause] - execute, responsible: cause < 2 ? i - 1 : i, waiting: i, producer: producers[cause])); execute = bounds[cause] }
            delays.append(execute - ideal)
        }
        timings.append(Timing(fetch: fetch, decode: decode, execute: execute, memory: execute + latency, writeback: execute + latency + 1))
    }
    if instructions.last!.kind == .multiply && variant.latency >= 2 { records.append(StallRecord(cause: 1, cycles: variant.latency - 1, responsible: instructions.count - 1, waiting: nil, producer: nil)) }
    return Simulation(timings: timings, records: records, delays: delays)
}
