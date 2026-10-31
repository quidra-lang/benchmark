struct OrderResult {
    let paths: [Path]?;
    let planned: Int;
    let failed: Int?;
    let expansions: Int;
    let trace: [String];
    let aborted: Bool
}
enum Prioritized {
    static func plan(_ grid: Grid, order: [Int], number: Int, horizon: Int, counts: SearchCounts) -> OrderResult {
        let before = counts.expansions
        var constraints = Constraints(), paths = Array(repeating: Path(), count: grid.agents.count), trace: [String] = []
        for (planned, agent) in order.enumerated() {
            let old = counts.expansions
            do {
                if let path = try LowLevel.search(grid, agent: agent, start: grid.agents[agent].start, time: 0, maximum: horizon, window: false, constraints: constraints, counts: counts) {
                    trace.append("order \(number) agent \(Report.name(agent)) cost \(path.count - 1) expansions \(counts.expansions - old)");
                    constraints.reserve(path, start: 0, permanent: true);
                    paths[agent] = path
                }
                else {
                    trace.append("order \(number) agent \(Report.name(agent)) failed expansions \(counts.expansions - old)");
                    return OrderResult(paths: nil, planned: planned, failed: agent, expansions: counts.expansions - before, trace: trace, aborted: false)
                }
            } catch {
                return OrderResult(paths: nil, planned: planned, failed: nil, expansions: counts.expansions - before, trace: trace, aborted: true)
            }
        }
        return OrderResult(paths: paths, planned: order.count, failed: nil, expansions: counts.expansions - before, trace: trace, aborted: false)
    }
}
