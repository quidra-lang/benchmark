#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
struct Cell {
    int x = 0;
    int y = 0;
    bool operator==(const Cell& other) const { return x == other.x && y == other.y; }
    bool operator!=(const Cell& other) const { return !(*this == other); }
};
struct Point { Integer x = 0; Integer y = 0; };
Point cellCenter(Cell cell);
struct GridMap {
    int width = 0;
    int height = 0;
    Lines rows;
    Cell exit;
    std::vector<Cell> spawns;
    bool inside(Cell cell) const;
    char terrain(Cell cell) const;
    bool rock(Cell cell) const;
    bool water(Cell cell) const;
    bool buildable(Cell cell) const;
    std::size_t index(Cell cell) const;
};
GridMap readMap(const std::string& path);
extern const std::array<Cell, 4> Directions;
Cell neighbor(Cell cell, int direction);
struct DistanceField {
    std::vector<int> distances;
    int width = 0;
    int height = 0;
    Cell exit;
    DistanceField() = default;
    DistanceField(const GridMap& grid, const std::vector<bool>& occupied);
    int at(Cell cell) const;
    int direction(Cell cell) const;
    Cell nextCell(Cell cell) const;
    std::vector<Cell> path(Cell cell) const;
};
Integer integerSqrt(Integer value);
Integer squaredDistance(Point first, Point second);
std::pair<Point, bool> advance(Point point, Point goal, Integer step);
Integer damageDealt(Integer hp, Integer power, Integer armor);
struct Effect {
    Integer strength = 0;
    Integer remaining = 0;
    std::size_t source = 0;
    bool active() const;
    void receive(Integer amount, Integer duration, std::size_t tower = 0);
    void advanceTime();
};
struct EnemyType {
    std::string name;
    char symbol;
    std::string movement;
    Integer hp, armor, speed, bounty, lives, regeneration;
    int splitInto = -1;
    Integer splitCount = 0;
    Integer spawned = 0, kills = 0, leaks = 0, damage = 0;
};
struct Group {
    std::size_t kind;
    int spawn;
    Integer count, delay, interval, multiplier;
    Integer spawnTick(Integer start, Integer released) const;
};
struct Wave {
    Integer reward;
    std::vector<Group> groups;
    Integer enemyCount() const;
};
void parseWaves(const Lines& lines, std::vector<EnemyType>& types, std::vector<Wave>& waves);
struct Enemy {
    std::size_t number;
    std::size_t kind;
    Integer multiplier;
    Integer maxHp;
    Integer hp;
    Effect slow, burn;
    bool alive = true;
    Cell cell, nextCell;
    Integer progress = 0;
    Point point;
    Enemy(std::size_t number, std::size_t kind, Integer multiplier, const std::vector<EnemyType>& types);
    bool flying(const std::vector<EnemyType>& types) const;
    Point position(const std::vector<EnemyType>& types) const;
    Cell occupiedCell(const std::vector<EnemyType>& types) const;
    Integer remaining(const std::vector<EnemyType>& types, const DistanceField& field) const;
    Integer slowedSpeed(const std::vector<EnemyType>& types) const;
    Enemy split(std::size_t newNumber, const std::vector<EnemyType>& types) const;
};
struct Level {
    Integer cost, range, power, interval, shotSpeed, splash, slowRate, slowTime, burnAmount, burnTime;
};
struct TowerType {
    std::string name;
    char symbol;
    std::string targets;
    std::vector<Level> levels;
};
extern const std::array<std::string, 5> TargetModes;
std::vector<TowerType> parseTowerTypes(const Lines& lines);
bool canAim(const std::string& targets, const Enemy& enemy, const std::vector<EnemyType>& types);
struct Tower {
    std::size_t number, kind;
    Cell cell;
    std::size_t level = 1;
    std::string mode = "FIRST";
    Integer ready, investment, built;
    Integer sold = 0;
    Integer shots = 0, hits = 0, fizzles = 0, kills = 0, damage = 0;
    Tower(std::size_t number, std::size_t kind, Cell cell, Integer tick, const std::vector<TowerType>& types);
    const Level& stats(const std::vector<TowerType>& types) const;
    Point center() const;
    bool standing() const;
    bool inRange(Point point, const std::vector<TowerType>& types) const;
    Integer targetKey(const Enemy& enemy, const std::vector<EnemyType>& types, const DistanceField& field) const;
    std::size_t selectTarget(const std::deque<Enemy>& enemies, const std::vector<EnemyType>& enemyTypes, const std::vector<TowerType>& types, const DistanceField& field) const;
};
struct Projectile {
    std::size_t number, tower, target;
    Point position, aim;
    std::string targets;
    Integer power, speed, splash, slowRate, slowTime, burnAmount, burnTime;
    bool fly();
};
Lines readLines(const std::string& path);
Lines splitFields(const std::string& line);
