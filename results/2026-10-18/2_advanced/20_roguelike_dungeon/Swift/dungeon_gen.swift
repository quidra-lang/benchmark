struct Cell: Hashable { let x: Int; let y: Int }
struct Room {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    var center: Cell { Cell(x: x + width / 2, y: y + height / 2) }
}
private final class Region {
    let rectangle: Room
    var first: Region?
    var second: Region?
    var leaf: Int?
    init(_ rectangle: Room) { self.rectangle = rectangle }
}
final class Level {
    let depth: Int
    let width: Int
    let height: Int
    var terrain: [[UInt8]]
    var memory: [[UInt8]]
    var rooms: [Room] = []
    var arrival = Cell(x: 0, y: 0)
    var arrivalRoom = 0
    var target = Cell(x: 0, y: 0)
    var monsters: [Monster] = []
    var items: [Item] = []
    var monstersCreated = 0
    var itemsPlaced = 0
    var kills = 0
    var picked = 0
    init(_ depth: Int, _ width: Int, _ height: Int) {
        self.depth = depth; self.width = width; self.height = height
        terrain = Array(repeating: Array(repeating: 32, count: width), count: height)
        memory = Array(repeating: Array(repeating: 32, count: width), count: height)
    }
    func monsterAt(_ x: Int, _ y: Int) -> Monster? { monsters.first { $0.x == x && $0.y == y } }
    func itemAt(_ x: Int, _ y: Int) -> Item? { items.first { $0.x == x && $0.y == y } }
    func drawInteriorCell(_ generator: Minstd, _ number: Int) -> Cell {
        let room = rooms[number]
        let x = room.x + 1 + generator.rnd(room.width - 2)
        let y = room.y + 1 + generator.rnd(room.height - 2)
        return Cell(x: x, y: y)
    }
    func drawRoomCell(_ generator: Minstd) -> (Int, Cell) {
        let room = generator.rnd(rooms.count)
        return (room, drawInteriorCell(generator, room))
    }
}
struct LevelGenerator {
    let minimum: Int
    let maxSplit: Int
    let roomMin: Int
    let roomMax: Int
    func generate(_ generator: Minstd, _ depth: Int, _ width: Int, _ height: Int) -> Level {
        let level = Level(depth, width, height)
        let root = Region(Room(x: 0, y: 0, width: width, height: height))
        var leaves: [Region] = []
        split(generator, root, 0, &leaves)
        for leaf in leaves { level.rooms.append(makeRoom(generator, level, leaf.rectangle)) }
        _ = connect(generator, level, root)
        let (room, arrival) = level.drawRoomCell(generator)
        level.arrival = arrival; level.arrivalRoom = room; level.terrain[arrival.y][arrival.x] = 60
        var other = generator.rnd(level.rooms.count - 1)
        if other >= room { other += 1 }
        level.target = level.drawInteriorCell(generator, other)
        return level
    }
    private func split(_ generator: Minstd, _ region: Region, _ depth: Int, _ leaves: inout [Region]) {
        let r = region.rectangle
        let cv = r.width >= 2 * minimum
        let ch = r.height >= 2 * minimum
        if depth == maxSplit || !(cv || ch) { region.leaf = leaves.count; leaves.append(region); return }
        let vertical: Bool
        if cv && ch {
            if 4 * r.width >= 5 * r.height { vertical = true }
            else if 4 * r.height >= 5 * r.width { vertical = false }
            else { vertical = generator.draw() % 2 == 0 }
        } else { vertical = cv }
        let first: Room
        let second: Room
        if vertical {
            let cut = minimum + generator.rnd(r.width - 2 * minimum + 1)
            first = Room(x: r.x, y: r.y, width: cut, height: r.height)
            second = Room(x: r.x + cut, y: r.y, width: r.width - cut, height: r.height)
        } else {
            let cut = minimum + generator.rnd(r.height - 2 * minimum + 1)
            first = Room(x: r.x, y: r.y, width: r.width, height: cut)
            second = Room(x: r.x, y: r.y + cut, width: r.width, height: r.height - cut)
        }
        let a = Region(first)
        let b = Region(second)
        region.first = a; region.second = b
        split(generator, a, depth + 1, &leaves)
        split(generator, b, depth + 1, &leaves)
    }
    private func makeRoom(_ generator: Minstd, _ level: Level, _ r: Room) -> Room {
        let width = roomMin + generator.rnd(min(roomMax, r.width - 1) - roomMin + 1)
        let height = roomMin + generator.rnd(min(roomMax, r.height - 1) - roomMin + 1)
        let x = r.x + generator.rnd(r.width - width)
        let y = r.y + generator.rnd(r.height - height)
        for row in y..<(y + height) { for column in x..<(x + width) {
            level.terrain[row][column] = row == y || row == y + height - 1 ? 45 : (column == x || column == x + width - 1 ? 124 : 46)
        } }
        return Room(x: x, y: y, width: width, height: height)
    }
    private func connect(_ generator: Minstd, _ level: Level, _ region: Region) -> [Int] {
        if let leaf = region.leaf { return [leaf] }
        let first = connect(generator, level, region.first!)
        let second = connect(generator, level, region.second!)
        var best: (Int, Int, Int)?
        for a in first { for b in second {
            let start = level.rooms[a].center
            let end = level.rooms[b].center
            let candidate = (abs(start.x - end.x) + abs(start.y - end.y), a, b)
            if best == nil || candidate < best! { best = candidate }
        } }
        let horizontal = generator.draw() % 2 == 0
        dig(level, level.rooms[best!.1].center, level.rooms[best!.2].center, horizontal)
        return first + second
    }
    private func dig(_ level: Level, _ start: Cell, _ end: Cell, _ horizontal: Bool) {
        func span(_ a: Int, _ b: Int) -> [Int] { Array(stride(from: a, through: b, by: a <= b ? 1 : -1)) }
        let path: [Cell]
        if horizontal { path = span(start.x, end.x).map { Cell(x: $0, y: start.y) } + span(start.y, end.y).map { Cell(x: end.x, y: $0) } }
        else { path = span(start.y, end.y).map { Cell(x: start.x, y: $0) } + span(start.x, end.x).map { Cell(x: $0, y: end.y) } }
        for cell in path {
            switch level.terrain[cell.y][cell.x] {
            case 32: level.terrain[cell.y][cell.x] = 35
            case 45, 124: level.terrain[cell.y][cell.x] = 43
            default: break
            }
        }
    }
}
