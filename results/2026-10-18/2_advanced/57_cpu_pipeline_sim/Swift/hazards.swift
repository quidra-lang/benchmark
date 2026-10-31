import Foundation

struct Source { let register: Int; let field: Int; let producer: Int? }
func dependencies(_ instructions: [Instruction]) -> [[Source]] {
    var writers: [Int: Int] = [:], sources: [[Source]] = []
    for (i, instruction) in instructions.enumerated() {
        var current: [Source] = []
        for (field, value) in [instruction.firstSource, instruction.secondSource].enumerated() { if let register = value, register != 0 { current.append(Source(register: register, field: field, producer: writers[register])) } }
        sources.append(current)
        if let destination = instruction.destination, destination != 0 { writers[destination] = i }
    }
    return sources
}
func idResolved(_ instruction: Instruction, _ variant: Variant) -> Bool { (instruction.kind == .jump && instruction.firstSource == nil) || (instruction.control && variant.stage == "ID") }
func readyCycle(_ instruction: Instruction, _ producer: Instruction, _ timing: Timing, _ variant: Variant) -> Int {
    if !variant.forwarding { return timing.writeback + 1 }
    return (producer.kind == .load ? timing.writeback : timing.memory) + (idResolved(instruction, variant) ? 1 : 0)
}
func forwardingPath(_ instruction: Instruction, _ producer: Timing?, _ timing: Timing, _ variant: Variant) -> Int {
    guard let producer, variant.forwarding else { return 0 }
    let resolved = idResolved(instruction, variant), cycle = timing.execute - (resolved ? 1 : 0)
    if producer.memory == cycle { return 1 }
    if !resolved && producer.writeback == cycle { return 2 }
    return 0
}
