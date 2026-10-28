import Foundation

func rk4Step(_ rates: Rates, _ state: [Double], _ multiplier: Double) -> [Double] {
    let h = 0.25, half = h / 2, sixth = h / 6, k1 = rates(state, multiplier), k2 = rates(state.indices.map { state[$0] + half * k1[$0] }, multiplier), k3 = rates(state.indices.map { state[$0] + half * k2[$0] }, multiplier), k4 = rates(state.indices.map { state[$0] + h * k3[$0] }, multiplier)
    return state.indices.map { i in state[i] + sixth * (((k1[i] + 2 * k2[i]) + 2 * k3[i]) + k4[i]) }
}
func simulate(_ rates: Rates, _ initial: [Double], _ multipliers: [Double], _ inflows: [Int]) -> [[Double]] { var state = initial, daily: [[Double]] = []; for multiplier in multipliers { for index in inflows { state[index] = 0 }; for _ in 0..<4 { state = rk4Step(rates, state, multiplier) }; daily.append(state) }; return daily }
