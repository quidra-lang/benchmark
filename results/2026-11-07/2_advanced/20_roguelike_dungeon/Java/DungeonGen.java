import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

record Position(int x, int y) {}
record RoomCell(int room, int x, int y) {}
record Room(int x, int y, int width, int height) {
    Position center() { return new Position(x + width / 2, y + height / 2); }
}
final class Region {
    final int x, y, width, height;
    Region first, second;
    int leaf = -1;
    Region(int x, int y, int width, int height) { this.x = x; this.y = y; this.width = width; this.height = height; }
}
final class Level {
    final int depth, width, height;
    final char[][] terrain, memory;
    final List<Room> rooms = new ArrayList<>();
    Position arrival, target;
    int arrivalRoom, monstersCreated, itemsPlaced, kills, picked;
    final List<Monster> monsters = new ArrayList<>();
    final List<Item> items = new ArrayList<>();
    Level(int depth, int width, int height) {
        this.depth = depth; this.width = width; this.height = height;
        terrain = new char[height][width]; memory = new char[height][width];
        for (int y = 0; y < height; y++) { Arrays.fill(terrain[y], ' '); Arrays.fill(memory[y], ' '); }
    }
    Monster monsterAt(int x, int y) { for (Monster monster : monsters) if (monster.x == x && monster.y == y) return monster; return null; }
    Item itemAt(int x, int y) { for (Item item : items) if (item.x == x && item.y == y) return item; return null; }
    Position drawInterior(Minstd rng, int index) {
        Room room = rooms.get(index);
        int x = room.x() + 1 + rng.rnd(room.width() - 2), y = room.y() + 1 + rng.rnd(room.height() - 2);
        return new Position(x, y);
    }
    RoomCell drawRoom(Minstd rng) { int room = rng.rnd(rooms.size()); Position cell = drawInterior(rng, room); return new RoomCell(room, cell.x(), cell.y()); }
}
final class DungeonGen {
    final Minstd rng;
    final int minSize, maxSplit, roomMin, roomMax;
    DungeonGen(Minstd rng, int minSize, int maxSplit, int roomMin, int roomMax) { this.rng = rng; this.minSize = minSize; this.maxSplit = maxSplit; this.roomMin = roomMin; this.roomMax = roomMax; }
    Level generate(int depth, int width, int height) {
        Level level = new Level(depth, width, height);
        Region root = new Region(0, 0, width, height);
        List<Region> leaves = new ArrayList<>(); split(root, 0, leaves);
        for (Region leaf : leaves) level.rooms.add(makeRoom(level, leaf));
        connect(level, root); chooseStairs(level); return level;
    }
    void split(Region region, int depth, List<Region> leaves) {
        boolean cv = region.width >= 2 * minSize, ch = region.height >= 2 * minSize;
        if (depth == maxSplit || !(cv || ch)) { region.leaf = leaves.size(); leaves.add(region); return; }
        boolean vertical;
        if (cv && ch) {
            if (4 * region.width >= 5 * region.height) vertical = true;
            else if (4 * region.height >= 5 * region.width) vertical = false;
            else vertical = rng.draw() % 2 == 0;
        } else vertical = cv;
        if (vertical) {
            int cut = minSize + rng.rnd(region.width - 2 * minSize + 1);
            region.first = new Region(region.x, region.y, cut, region.height); region.second = new Region(region.x + cut, region.y, region.width - cut, region.height);
        } else {
            int cut = minSize + rng.rnd(region.height - 2 * minSize + 1);
            region.first = new Region(region.x, region.y, region.width, cut); region.second = new Region(region.x, region.y + cut, region.width, region.height - cut);
        }
        split(region.first, depth + 1, leaves); split(region.second, depth + 1, leaves);
    }
    Room makeRoom(Level level, Region region) {
        int width = roomMin + rng.rnd(Math.min(roomMax, region.width - 1) - roomMin + 1);
        int height = roomMin + rng.rnd(Math.min(roomMax, region.height - 1) - roomMin + 1);
        int x = region.x + rng.rnd(region.width - width), y = region.y + rng.rnd(region.height - height);
        for (int row = y; row < y + height; row++) for (int column = x; column < x + width; column++) level.terrain[row][column] = row == y || row == y + height - 1 ? '-' : column == x || column == x + width - 1 ? '|' : '.';
        return new Room(x, y, width, height);
    }
    List<Integer> connect(Level level, Region region) {
        if (region.leaf >= 0) return new ArrayList<>(List.of(region.leaf));
        List<Integer> first = connect(level, region.first), second = connect(level, region.second);
        int bestA = -1, bestB = -1, bestDistance = 0;
        for (int a : first) for (int b : second) {
            Position start = level.rooms.get(a).center(), end = level.rooms.get(b).center();
            int distance = Math.abs(start.x() - end.x()) + Math.abs(start.y() - end.y());
            if (bestA < 0 || distance < bestDistance) { bestA = a; bestB = b; bestDistance = distance; }
        }
        boolean horizontalFirst = rng.draw() % 2 == 0;
        dig(level, level.rooms.get(bestA).center(), level.rooms.get(bestB).center(), horizontalFirst);
        first.addAll(second); return first;
    }
    void dig(Level level, Position start, Position end, boolean horizontalFirst) {
        List<Position> path = new ArrayList<>();
        int sx = end.x() >= start.x() ? 1 : -1, sy = end.y() >= start.y() ? 1 : -1;
        if (horizontalFirst) {
            for (int x = start.x(); ; x += sx) { path.add(new Position(x, start.y())); if (x == end.x()) break; }
            for (int y = start.y(); ; y += sy) { path.add(new Position(end.x(), y)); if (y == end.y()) break; }
        } else {
            for (int y = start.y(); ; y += sy) { path.add(new Position(start.x(), y)); if (y == end.y()) break; }
            for (int x = start.x(); ; x += sx) { path.add(new Position(x, end.y())); if (x == end.x()) break; }
        }
        for (Position point : path) {
            char terrain = level.terrain[point.y()][point.x()];
            if (terrain == ' ') level.terrain[point.y()][point.x()] = '#';
            else if (terrain == '-' || terrain == '|') level.terrain[point.y()][point.x()] = '+';
        }
    }
    void chooseStairs(Level level) {
        RoomCell drawn = level.drawRoom(rng); level.arrivalRoom = drawn.room(); level.arrival = new Position(drawn.x(), drawn.y()); level.terrain[drawn.y()][drawn.x()] = '<';
        int other = rng.rnd(level.rooms.size() - 1); if (other >= drawn.room()) other++;
        level.target = level.drawInterior(rng, other);
    }
}
