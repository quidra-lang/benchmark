import Foundation

struct Evidence { let variable: Int; let state: Int }
func entryCount(_ variables: [Int], _ sizes: [Int]) -> Int { variables.reduce(1) { $0 * sizes[$1] } }
func assignments(_ variables: [Int], _ sizes: [Int]) -> [[Int]] { let count = entryCount(variables, sizes); return (0..<count).map { number in var number = number, assignment = Array(repeating: 0, count: sizes.count); for variable in variables.reversed() { assignment[variable] = number % sizes[variable]; number /= sizes[variable] }; return assignment } }
func applying(_ evidence: [Evidence], _ assignment: [Int]) -> [Int] { var assignment = assignment; for item in evidence { assignment[item.variable] = item.state }; return assignment }
struct Factor {
    let variables: [Int]
    let values: [Double]
    let sizes: [Int]
    func value(_ assignment: [Int]) -> Double { values[parentRow(variables, assignment, sizes)] }
    func reduced(_ evidence: [Evidence]) -> Factor { let observed = Set(evidence.map { $0.variable }), variables = self.variables.filter { !observed.contains($0) }; return Factor(variables: variables, values: assignments(variables, sizes).map { value(applying(evidence, $0)) }, sizes: sizes) }
    func multiplied(_ other: Factor) -> Factor { let variables = Set(self.variables + other.variables).sorted(); return Factor(variables: variables, values: assignments(variables, sizes).map { value($0) * other.value($0) }, sizes: sizes) }
    func eliminating(_ variable: Int, maximize: Bool = false) -> Factor { let variables = self.variables.filter { $0 != variable }; let values = assignments(variables, sizes).map { assignment -> Double in var assignment = assignment, candidates: [Double] = []; for state in 0..<sizes[variable] { assignment[variable] = state; candidates.append(value(assignment)) }; return maximize ? candidates.max()! : total(candidates) }; return Factor(variables: variables, values: values, sizes: sizes) }
}
func cptFactor(_ variable: Int, _ parents: [Int], _ cpt: [[Double]], _ sizes: [Int]) -> Factor { let variables = ([variable] + parents).sorted(), values = assignments(variables, sizes).map { cpt[parentRow(parents, $0, sizes)][$0[variable]] }; return Factor(variables: variables, values: values, sizes: sizes) }
func multiply(_ factors: [Factor], _ sizes: [Int]) -> Factor { guard var result = factors.first else { return Factor(variables: [], values: [1], sizes: sizes) }; for factor in factors.dropFirst() { result = result.multiplied(factor) }; return result }
