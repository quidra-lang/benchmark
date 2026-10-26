struct Period {
    let start: Int
    let offset: Int
    let dst: Bool
    let abbreviation: String
    func sameState(_ other: Period) -> Bool { offset == other.offset && dst == other.dst && abbreviation == other.abbreviation }
}
struct Timeline {
    let periods: [Period]
    func indexAt(_ time: Int) -> Int {
        var low = 0, high = periods.count
        while low < high { let middle = (low + high) / 2; if periods[middle].start <= time { low = middle + 1 } else { high = middle } }
        return low - 1
    }
    func periodAt(_ time: Int) -> Period { periods[indexAt(time)] }
    func endOf(_ index: Int) -> Int { index + 1 < periods.count ? periods[index + 1].start : positiveInfinity }
    func nearby(_ low: Int, _ high: Int) -> ClosedRange<Int> { indexAt(low - 57600)...indexAt(high + 57600) }
    func candidates(_ local: Int) -> [Int] {
        nearby(local, local).filter { index in let time = local - periods[index].offset; return periods[index].start <= time && time < endOf(index) }
    }
    func skippingTransition(_ local: Int) -> Int {
        nearby(local, local).first { index in index > 0 && periods[index].start + periods[index - 1].offset <= local && local < periods[index].start + periods[index].offset }!
    }
}
