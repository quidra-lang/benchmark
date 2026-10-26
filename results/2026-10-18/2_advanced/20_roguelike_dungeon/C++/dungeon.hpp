#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
using Point = std::pair<int, int>;
using Points = std::vector<Point>;
template<class... Parts> std::string text(const Parts&... parts) { std::ostringstream stream; (stream << ... << parts); return stream.str(); }
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
struct Dice { int count = 1, sides = 1; };
Dice parseDice(const std::string& token);
class Minstd {
    Integer state;
public:
    explicit Minstd(Integer seed) : state(seed) {}
    Integer draw();
    int rnd(int limit);
    int roll(Dice dice);
    int select(const std::vector<int>& weights);
};
struct MonsterType { std::string name; char symbol; int minDepth, maxDepth, weight; Dice hp; int toHit, defense; Dice damage; int speed, xp; std::string traits; };
struct ItemType { std::string category, name; int minDepth = 0, maxDepth = 0, weight = 0; Dice dice; int toHit = 0, armor = 0; std::string effect; int poison = 0, nutrition = 0; };
MonsterType parseMonsterType(const Lines& words);
ItemType parseItemType(const Lines& words);
struct Monster { int number, type; Point position; int hp, maxHp; bool asleep; int energy = 0; bool wasVisible = false, alive = true; };
struct Item {
    ItemType kind;
    Point position;
    int amount = 0, bonus = 0;
    char symbol() const;
    std::string displayName() const;
    std::string referenceName() const;
};
struct Room { int x, y, width, height; Point center() const { return {x + width / 2, y + height / 2}; } };
struct Level {
    int depth, width, height;
    Lines terrain, memory;
    std::vector<Room> rooms;
    Point arrival, target;
    int arrivalRoom = 0;
    std::vector<Monster> monsters;
    std::vector<std::shared_ptr<Item>> items;
    int monstersCreated = 0, itemsPlaced = 0, kills = 0, picked = 0;
    Level(int depth, int width, int height);
    int monsterAt(Point point) const;
    int itemAt(Point point) const;
    Point drawInteriorCell(Minstd& generator, int room) const;
    std::tuple<int, int, int> drawRoomCell(Minstd& generator) const;
};
Level generateLevel(Minstd& generator, int depth, int width, int height, int minimumSize, int maximumSplit, int roomMinimum, int roomMaximum);
enum class AttackOutcome { miss, hit, critical };
struct Attack { AttackOutcome outcome; int damage; };
Attack resolveAttack(Minstd& generator, int toHit, int defense, Dice dice, int bonus);
extern const Lines directionNames;
extern const std::array<Point, 8> directions;
bool passable(const Level& level, Point point);
bool canMove(const Level& level, Point point, Point direction);
Points line(Point first, Point last);
std::vector<std::vector<bool>> fieldOfView(const Level& level, Point point, int radius);
std::vector<std::vector<int>> distances(const Level& level, Point point);
