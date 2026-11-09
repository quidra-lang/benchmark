import Foundation

struct AircraftPair: Hashable, Comparable {
    let first: Int; let second: Int
    init(_ first: Int, _ second: Int) { self.first = min(first, second); self.second = max(first, second) }
    static func < (_ first: AircraftPair, _ second: AircraftPair) -> Bool { first.first == second.first ? first.second < second.second : first.first < second.first }
    func contains(_ aircraft: Int) -> Bool { first == aircraft || second == aircraft }
    func name(_ plans: [Plan]) -> String { plans[first].callsign + "-" + plans[second].callsign }
}
struct Loss { let lo: Double; let hi: Double; let tc: Double; let distance: Double; let vertical: Double }
func lossInterval(_ p: Vector3, _ w: Vector3, _ t1: Double, _ t2: Double, _ horizontal: Double, _ vertical: Double) -> Loss? {
    let qa = w.x * w.x + w.y * w.y, qb = 2 * (p.x * w.x + p.y * w.y), qc = (p.x * p.x + p.y * p.y) - horizontal * horizontal
    var lo = t1, hi = t2
    if qa < 1e-12 { if qc >= 0 { return nil } }
    else {
        let discriminant = qb * qb - 4 * qa * qc
        if discriminant <= 0 { return nil }
        let root = sqrt(discriminant)
        lo = max(lo, t1 + (-qb - root) / (2 * qa)); hi = min(hi, t1 + (-qb + root) / (2 * qa))
    }
    if w.z == 0 { if abs(p.z) >= vertical { return nil } }
    else {
        let first = (-vertical - p.z) / w.z, second = (vertical - p.z) / w.z
        lo = max(lo, t1 + min(first, second)); hi = min(hi, t1 + max(first, second))
    }
    if hi - lo <= 1e-6 { return nil }
    let tc = min(max(qa >= 1e-12 ? t1 + (-qb / (2 * qa)) : t1, lo), hi), elapsed = tc - t1, ex = p.x + w.x * elapsed, ey = p.y + w.y * elapsed
    return Loss(lo: lo, hi: hi, tc: tc, distance: sqrt(ex * ex + ey * ey), vertical: abs(p.z + w.z * elapsed))
}
struct Piece { let a: Segment; let b: Segment; let loss: Loss }
struct Conflict {
    let pair: AircraftPair
    let start: Double
    var end: Double
    var pieces: [Piece]
    var closest: Piece
    func active(_ time: Double) -> Bool { start <= time && time < end }
}
func conflictPrecedes(_ first: Conflict, _ second: Conflict) -> Bool { first.start == second.start ? first.pair < second.pair : first.start < second.start }
func pairConflicts(_ pair: AircraftPair, _ first: Trajectory, _ second: Trajectory, _ settings: Settings) -> [Conflict] {
    var pieces: [Piece] = []
    for a in first.segments { for b in second.segments {
        let t1 = max(a.ts, b.ts), t2 = min(a.te, b.te)
        if t1 < t2, let loss = lossInterval(a.position(t1) - b.position(t1), a.velocity - b.velocity, t1, t2, Double(settings.dh), Double(settings.dv)) { pieces.append(Piece(a: a, b: b, loss: loss)) }
    } }
    pieces = pieces.enumerated().sorted { $0.element.loss.lo == $1.element.loss.lo ? $0.offset < $1.offset : $0.element.loss.lo < $1.element.loss.lo }.map { $0.element }
    var conflicts: [Conflict] = []
    for piece in pieces {
        if conflicts.isEmpty || piece.loss.lo - conflicts.last!.end > 1e-6 { conflicts.append(Conflict(pair: pair, start: piece.loss.lo, end: piece.loss.hi, pieces: [piece], closest: piece)) }
        else {
            let index = conflicts.count - 1
            conflicts[index].pieces.append(piece); conflicts[index].end = piece.loss.hi
            if piece.loss.distance < conflicts[index].closest.loss.distance - 1e-9 { conflicts[index].closest = piece }
        }
    }
    return conflicts
}
func allConflicts(_ trajectories: [Trajectory], _ settings: Settings) -> [Conflict] {
    var conflicts: [Conflict] = []
    for first in trajectories.indices { for second in (first + 1)..<trajectories.count { conflicts += pairConflicts(AircraftPair(first, second), trajectories[first], trajectories[second], settings) } }
    return conflicts.sorted(by: conflictPrecedes)
}
