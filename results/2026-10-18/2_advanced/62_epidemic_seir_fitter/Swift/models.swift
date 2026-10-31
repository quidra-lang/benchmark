import Foundation

typealias Rates = ([Double], Double) -> [Double]
func seird(_ population: Double, _ sigma: Double, _ fatality: Double, _ beta: Double, _ gamma: Double) -> Rates { { state, multiplier in let flow = beta * multiplier * state[0] * state[2] / population, progression = sigma * state[1], removal = gamma * state[2]; return [-flow, flow - progression, progression - removal, (1 - fatality) * gamma * state[2], fatality * gamma * state[2], progression] } }
func sir(_ population: Double, _ beta: Double, _ gamma: Double) -> Rates { { state, multiplier in let flow = beta * multiplier * state[0] * state[1] / population, removal = gamma * state[1]; return [-flow, flow - removal, removal, flow] } }
func ageSEIRD(_ populations: [Double], _ fatalities: [Double], _ sigma: Double, _ beta: Double, _ gamma: Double, _ contacts: [[Double]]) -> Rates {
    { state, multiplier in
        var result: [Double] = []
        for group in populations.indices { let start = 6 * group; var pressure = 0.0; for other in populations.indices { pressure += contacts[group][other] * state[6 * other + 2] / populations[other] }; let force = beta * multiplier * pressure, flow = force * state[start], progression = sigma * state[start + 1], removal = gamma * state[start + 2]; result += [-flow, flow - progression, progression - removal, (1 - fatalities[group]) * gamma * state[start + 2], fatalities[group] * gamma * state[start + 2], progression] }
        return result
    }
}
func generation(_ sigma: Double, _ gamma: Double) -> Rates { { state, _ in let progression = sigma * state[0], removal = gamma * state[1]; return [-progression, progression - removal, removal] } }
