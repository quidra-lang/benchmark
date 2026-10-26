#include "defense.hpp"

Integer Group::spawnTick(Integer start, Integer released) const { return start + delay + released * interval; }
Integer Wave::enemyCount() const {
    Integer count = 0;
    for (const Group& group : groups) count += group.count;
    return count;
}
void parseWaves(const Lines& lines, std::vector<EnemyType>& types, std::vector<Wave>& waves) {
    std::map<std::string, std::size_t> known;
    for (const std::string& line : lines) {
        Lines fields = splitFields(line);
        if (fields[0] == "enemy") {
            EnemyType type;
            type.name = fields[1]; type.symbol = fields[2][0]; type.movement = fields[3];
            type.hp = std::stoll(fields[4]); type.armor = std::stoll(fields[5]); type.speed = std::stoll(fields[6]);
            type.bounty = std::stoll(fields[7]); type.lives = std::stoll(fields[8]); type.regeneration = std::stoll(fields[9]);
            if (fields[10] != "-") type.splitInto = static_cast<int>(known.at(fields[10]));
            type.splitCount = std::stoll(fields[11]);
            known[type.name] = types.size();
            types.push_back(std::move(type));
        } else if (fields[0] == "wave") waves.push_back({std::stoll(fields[1]), {}});
        else waves.back().groups.push_back({known.at(fields[1]), std::stoi(fields[2]), std::stoll(fields[3]), std::stoll(fields[4]), std::stoll(fields[5]), std::stoll(fields[6])});
    }
}
Enemy::Enemy(std::size_t id, std::size_t type, Integer factor, const std::vector<EnemyType>& types) : number(id), kind(type), multiplier(factor), maxHp(types[type].hp * factor / 100), hp(maxHp) {}
bool Enemy::flying(const std::vector<EnemyType>& types) const { return types[kind].movement == "air"; }
Point Enemy::position(const std::vector<EnemyType>& types) const {
    if (flying(types)) return point;
    return {100 * cell.x + (nextCell.x - cell.x) * progress, 100 * cell.y + (nextCell.y - cell.y) * progress};
}
Cell Enemy::occupiedCell(const std::vector<EnemyType>& types) const {
    if (flying(types)) return {static_cast<int>((point.x + 50) / 100), static_cast<int>((point.y + 50) / 100)};
    return progress < 50 ? cell : nextCell;
}
Integer Enemy::remaining(const std::vector<EnemyType>& types, const DistanceField& field) const {
    if (flying(types)) return integerSqrt(squaredDistance(point, cellCenter(field.exit)));
    return 100 * field.at(nextCell) + 100 - progress;
}
Integer Enemy::slowedSpeed(const std::vector<EnemyType>& types) const { return slow.active() ? types[kind].speed * (100 - slow.strength) / 100 : types[kind].speed; }
Enemy Enemy::split(std::size_t newNumber, const std::vector<EnemyType>& types) const {
    Enemy child(newNumber, static_cast<std::size_t>(types[kind].splitInto), multiplier, types);
    child.cell = cell; child.nextCell = nextCell; child.progress = progress; child.point = point;
    return child;
}
