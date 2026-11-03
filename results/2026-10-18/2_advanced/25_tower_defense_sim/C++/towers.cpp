#include "defense.hpp"

const std::array<std::string, 5> TargetModes = {"FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST"};
std::vector<TowerType> parseTowerTypes(const Lines& lines) {
    std::vector<TowerType> types;
    std::size_t index = 0;
    while (index < lines.size()) {
        Lines fields = splitFields(lines[index++]);
        TowerType type{fields[1], fields[2][0], fields[3], {}};
        int count = std::stoi(fields[4]);
        for (int level = 0; level < count; ++level) {
            fields = splitFields(lines[index++]);
            type.levels.push_back({std::stoll(fields[1]), std::stoll(fields[2]), std::stoll(fields[3]), std::stoll(fields[4]), std::stoll(fields[5]), std::stoll(fields[6]), std::stoll(fields[7]), std::stoll(fields[8]), std::stoll(fields[9]), std::stoll(fields[10])});
        }
        types.push_back(std::move(type));
    }
    return types;
}
bool canAim(const std::string& targets, const Enemy& enemy, const std::vector<EnemyType>& types) { return targets == "both" || targets == types[enemy.kind].movement; }
Tower::Tower(std::size_t id, std::size_t type, Cell position, Integer tick, const std::vector<TowerType>& types) : number(id), kind(type), cell(position), ready(tick), investment(types[type].levels[0].cost), built(tick) {}
const Level& Tower::stats(const std::vector<TowerType>& types) const { return types[kind].levels[level - 1]; }
Point Tower::center() const { return cellCenter(cell); }
bool Tower::standing() const { return sold == 0; }
bool Tower::inRange(Point point, const std::vector<TowerType>& types) const { Integer range = stats(types).range; return squaredDistance(center(), point) <= range * range; }
Integer Tower::targetKey(const Enemy& enemy, const std::vector<EnemyType>& types, const DistanceField& field) const {
    if (mode == "FIRST") return enemy.remaining(types, field);
    if (mode == "LAST") return -enemy.remaining(types, field);
    if (mode == "STRONGEST") return -enemy.hp;
    if (mode == "WEAKEST") return enemy.hp;
    return squaredDistance(center(), enemy.position(types));
}
std::size_t Tower::selectTarget(const std::deque<Enemy>& enemies, const std::vector<EnemyType>& enemyTypes, const std::vector<TowerType>& types, const DistanceField& field) const {
    std::size_t best = 0;
    Integer bestKey = 0;
    for (const Enemy& enemy : enemies) {
        if (!enemy.alive || !canAim(types[kind].targets, enemy, enemyTypes) || !inRange(enemy.position(enemyTypes), types)) continue;
        Integer key = targetKey(enemy, enemyTypes, field);
        if (best == 0 || key < bestKey) { best = enemy.number; bestKey = key; }
    }
    return best;
}
