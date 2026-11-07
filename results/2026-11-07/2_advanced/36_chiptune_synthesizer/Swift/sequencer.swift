func samplesPerTick(_ rate: Int, _ tempo: Int) -> Int { rate * 5 / (tempo * 2) }

func nextRow(_ song: Song, _ location: RowLocation) -> RowLocation? {
    var jump: Int?
    var patternBreak: Int?
    for cell in song.cells(location) {
        guard let effect = cell.effect else { continue }
        switch effect.name {
        case "F" where effect.value == 0: return nil
        case "B": jump = effect.value
        case "D": patternBreak = effect.value
        default: break
        }
    }
    if jump == nil && patternBreak == nil {
        return location.row < 63 ? RowLocation(position: location.position, row: location.row + 1)
            : RowLocation(position: location.position + 1, row: 0)
    }
    return RowLocation(position: jump ?? (location.position + 1),
                       row: patternBreak.map { $0 < 64 ? $0 : 0 } ?? 0)
}

func reachableRows(_ song: Song) -> Set<RowLocation> {
    var reached: Set<RowLocation> = []
    var current: RowLocation? = RowLocation(position: 0, row: 0)
    while let location = current, location.position < song.order.count, !reached.contains(location) {
        reached.insert(location)
        current = nextRow(song, location)
    }
    return reached
}
