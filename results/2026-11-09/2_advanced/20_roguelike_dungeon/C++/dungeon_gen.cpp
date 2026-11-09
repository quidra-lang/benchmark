#include "dungeon.hpp"

Level::Level(int depth, int width, int height) : depth(depth), width(width), height(height), terrain(height, std::string(width, ' ')), memory(height, std::string(width, ' ')) {}
int Level::monsterAt(Point point) const { for (int i = 0; i < static_cast<int>(monsters.size()); ++i) if (monsters[i].alive && monsters[i].position == point) return i; return -1; }
int Level::itemAt(Point point) const { for (int i = 0; i < static_cast<int>(items.size()); ++i) if (items[i]->position == point) return i; return -1; }
Point Level::drawInteriorCell(Minstd& generator, int room) const { const Room& chosen = rooms[room]; int x = chosen.x + 1 + generator.rnd(chosen.width - 2), y = chosen.y + 1 + generator.rnd(chosen.height - 2); return {x, y}; }
std::tuple<int, int, int> Level::drawRoomCell(Minstd& generator) const { int room = generator.rnd(static_cast<int>(rooms.size())); Point point = drawInteriorCell(generator, room); return {room, point.first, point.second}; }
struct Region { int x, y, width, height, leaf = -1; std::unique_ptr<Region> first, second; Region(int x, int y, int width, int height) : x(x), y(y), width(width), height(height) {} };
class Generator {
    Minstd& random;
    int minimum, maximumDepth, roomMinimum, roomMaximum;
    void split(Region& region, int depth, std::vector<Region*>& leaves) {
        bool cv = region.width >= 2 * minimum, ch = region.height >= 2 * minimum;
        if (depth == maximumDepth || (!cv && !ch)) { region.leaf = static_cast<int>(leaves.size()); leaves.push_back(&region); return; }
        bool vertical;
        if (cv && ch) { if (4 * region.width >= 5 * region.height) vertical = true; else if (4 * region.height >= 5 * region.width) vertical = false; else vertical = random.draw() % 2 == 0; } else vertical = cv;
        if (vertical) { int cut = minimum + random.rnd(region.width - 2 * minimum + 1); region.first = std::make_unique<Region>(region.x, region.y, cut, region.height); region.second = std::make_unique<Region>(region.x + cut, region.y, region.width - cut, region.height); }
        else { int cut = minimum + random.rnd(region.height - 2 * minimum + 1); region.first = std::make_unique<Region>(region.x, region.y, region.width, cut); region.second = std::make_unique<Region>(region.x, region.y + cut, region.width, region.height - cut); }
        split(*region.first, depth + 1, leaves); split(*region.second, depth + 1, leaves);
    }
    Room makeRoom(Level& level, const Region& region) {
        int width = roomMinimum + random.rnd(std::min(roomMaximum, region.width - 1) - roomMinimum + 1);
        int height = roomMinimum + random.rnd(std::min(roomMaximum, region.height - 1) - roomMinimum + 1);
        int x = region.x + random.rnd(region.width - width), y = region.y + random.rnd(region.height - height);
        for (int row = y; row < y + height; ++row) for (int column = x; column < x + width; ++column) level.terrain[row][column] = row == y || row == y + height - 1 ? '-' : column == x || column == x + width - 1 ? '|' : '.';
        return {x, y, width, height};
    }
    void carve(Level& level, Point point) { char& cell = level.terrain[point.second][point.first]; if (cell == ' ') cell = '#'; else if (cell == '-' || cell == '|') cell = '+'; }
    void dig(Level& level, Point a, Point b, bool horizontal) {
        int sx = b.first >= a.first ? 1 : -1, sy = b.second >= a.second ? 1 : -1;
        if (horizontal) { for (int x = a.first; ; x += sx) { carve(level, {x, a.second}); if (x == b.first) break; } for (int y = a.second; ; y += sy) { carve(level, {b.first, y}); if (y == b.second) break; } }
        else { for (int y = a.second; ; y += sy) { carve(level, {a.first, y}); if (y == b.second) break; } for (int x = a.first; ; x += sx) { carve(level, {x, b.second}); if (x == b.first) break; } }
    }
    std::vector<int> connect(Level& level, const Region& region) {
        if (region.leaf >= 0) return {region.leaf};
        std::vector<int> first = connect(level, *region.first), second = connect(level, *region.second);
        int bestA = -1, bestB = -1, distance = 0;
        for (int a : first) for (int b : second) { Point x = level.rooms[a].center(), y = level.rooms[b].center(); int trial = std::abs(x.first - y.first) + std::abs(x.second - y.second); if (bestA < 0 || trial < distance) { bestA = a; bestB = b; distance = trial; } }
        bool horizontal = random.draw() % 2 == 0;
        dig(level, level.rooms[bestA].center(), level.rooms[bestB].center(), horizontal);
        first.insert(first.end(), second.begin(), second.end()); return first;
    }
public:
    Generator(Minstd& random, int minimum, int maximumDepth, int roomMinimum, int roomMaximum) : random(random), minimum(minimum), maximumDepth(maximumDepth), roomMinimum(roomMinimum), roomMaximum(roomMaximum) {}
    Level generate(int depth, int width, int height) {
        Level level(depth, width, height); Region root(0, 0, width, height); std::vector<Region*> leaves;
        split(root, 0, leaves); for (const Region* leaf : leaves) level.rooms.push_back(makeRoom(level, *leaf)); connect(level, root);
        int room, x, y; std::tie(room, x, y) = level.drawRoomCell(random); level.arrivalRoom = room; level.arrival = {x, y}; level.terrain[y][x] = '<';
        int other = random.rnd(static_cast<int>(level.rooms.size() - 1)); if (other >= room) ++other; level.target = level.drawInteriorCell(random, other);
        return level;
    }
};
Level generateLevel(Minstd& generator, int depth, int width, int height, int minimumSize, int maximumSplit, int roomMinimum, int roomMaximum) { return Generator(generator, minimumSize, maximumSplit, roomMinimum, roomMaximum).generate(depth, width, height); }
