import Foundation

func nonreceiveEvent(_ process: ProcessState, _ own: Int) { process.lamport += 1; process.vector[own] += 1 }
func receiveEvent(_ process: ProcessState, _ own: Int, _ sender: Event) { process.lamport = max(process.lamport, sender.lamport) + 1; process.vector = process.vector.indices.map { max(process.vector[$0], sender.vector[$0]) }; process.vector[own] += 1 }
func lessEqual(_ a: [Int], _ b: [Int]) -> Bool { a.indices.allSatisfy { a[$0] <= b[$0] } }
func happensBefore(_ a: [Int], _ b: [Int]) -> Bool { a != b && lessEqual(a, b) }
func relation(_ a: [Int], _ b: [Int]) -> String { happensBefore(a, b) ? "->" : happensBefore(b, a) ? "<-" : "||" }
func broadcastDeliverable(_ stamp: [Int], _ received: [Int], _ source: Int) -> Bool { stamp.indices.allSatisfy { $0 == source ? stamp[$0] == received[$0] + 1 : stamp[$0] <= received[$0] } }
func missingIndices(_ stamp: [Int], _ received: [Int], _ source: Int) -> [Int] { stamp.indices.filter { stamp[$0] > received[$0] + ($0 == source ? 1 : 0) } }
func vectorText(_ vector: [Int]) -> String { vector.map(String.init).joined(separator: ",") }
