#include "defense.hpp"

Lines readLines(const std::string& path) {
    std::ifstream input(path, std::ios::binary);
    Lines lines;
    std::string line;
    while (std::getline(input, line)) lines.push_back(line);
    return lines;
}
Lines splitFields(const std::string& line) {
    std::istringstream input(line);
    Lines fields;
    std::string field;
    while (input >> field) fields.push_back(field);
    return fields;
}
static void writeLines(const std::string& name, const Lines& lines) {
    std::ofstream output("output/" + name, std::ios::binary);
    for (const std::string& line : lines) output << line << '\n';
}
static std::string oneDecimal(Integer numerator, Integer denominator) {
    if (denominator == 0) return "-";
    Integer rounded = (20 * numerator + denominator) / (2 * denominator);
    return std::to_string(rounded / 10) + "." + std::to_string(rounded % 10);
}
static char digit(Integer count) { return count == 0 ? '.' : count < 10 ? static_cast<char>('0' + count) : '*'; }
static Lines ruled(const Lines& rows) {
    Lines lines{std::string("  ")};
    for (std::size_t x = 0; x < rows[0].size(); ++x) lines[0] += static_cast<char>('0' + x % 10);
    for (std::size_t y = 0; y < rows.size(); ++y) lines.push_back(std::to_string(y % 10) + " " + rows[y]);
    return lines;
}
static void append(Lines& first, const Lines& second) { first.insert(first.end(), second.begin(), second.end()); }
struct Parameters {
    Integer gold, lives, interestRate, interestCap, sellRate, start, interval, early;
    std::set<Integer> snapshots;
    explicit Parameters(const Lines& lines) {
        gold = std::stoll(splitFields(lines[0])[1]); lives = std::stoll(splitFields(lines[1])[1]);
        Lines interest = splitFields(lines[2]);
        interestRate = std::stoll(interest[1]); interestCap = std::stoll(interest[2]);
        sellRate = std::stoll(splitFields(lines[3])[1]);
        Lines schedule = splitFields(lines[4]);
        start = std::stoll(schedule[1]); interval = std::stoll(schedule[2]);
        early = std::stoll(splitFields(lines[5])[1]);
        Lines ticks = splitFields(lines[6]);
        for (std::size_t index = 1; index < ticks.size(); ++index) snapshots.insert(std::stoll(ticks[index]));
    }
};
struct Action {
    Integer tick;
    std::string command;
    Lines arguments;
    explicit Action(const std::string& line) {
        Lines fields = splitFields(line);
        tick = std::stoll(fields[0]); command = fields[1];
        arguments.assign(fields.begin() + 2, fields.end());
    }
};
struct WaveRecord {
    std::size_t number;
    Integer start, end = 0;
    std::string status;
    std::vector<Integer> released;
    Integer spawned = 0, peak = 0, kills = 0, leaks = 0, livesLost = 0;
    Integer bounty = 0, reward = 0, interest = 0, gold = 0, lives = 0;
    std::map<std::size_t, Integer> towerDamage;
    WaveRecord(std::size_t id, const Wave& wave, Integer tick) : number(id), start(tick), released(wave.groups.size(), 0) {}
    bool allReleased(const Wave& wave) const {
        for (std::size_t index = 0; index < released.size(); ++index) if (released[index] != wave.groups[index].count) return false;
        return true;
    }
    void close(const std::string& result, Integer tick, Integer currentGold, Integer currentLives) {
        status = result; end = tick; gold = currentGold; lives = currentLives;
    }
    std::string csvRow(std::size_t towerCount) const {
        std::ostringstream row;
        row << number << ',' << start << ',' << end << ',' << status << ',' << spawned << ',' << peak << ',' << kills << ',' << leaks << ',' << livesLost << ',' << bounty << ',' << reward << ',' << interest << ',' << gold << ',' << lives;
        for (std::size_t number = 1; number <= towerCount; ++number) {
            std::map<std::size_t, Integer>::const_iterator found = towerDamage.find(number);
            row << ',' << (found == towerDamage.end() ? 0 : found->second);
        }
        return row.str();
    }
};
class Game {
    GridMap grid;
    std::vector<TowerType> towerTypes;
    std::map<std::string, std::size_t> towerNames;
    std::vector<EnemyType> enemyTypes;
    std::vector<Wave> waves;
    Parameters parameters;
    Integer tick = 0, gold, lives;
    std::vector<Tower> towers;
    std::deque<Enemy> enemies;
    std::vector<Projectile> projectiles;
    std::size_t projectileCount = 0;
    std::vector<WaveRecord> records;
    int active = -1;
    Integer nextStart;
    std::string outcome;
    DistanceField field;
    std::vector<Integer> killCounts;
    std::array<Integer, 5> income{};
    Integer spent = 0, done = 0, refused = 0;
    template<class... Parts> void record(const Parts&... parts) {
        std::ostringstream line;
        line << tick;
        ((line << ' ' << parts), ...);
        events.push_back(line.str());
    }
    Integer livingCount() const {
        Integer count = 0;
        for (const Enemy& enemy : enemies) if (enemy.alive) ++count;
        return count;
    }
    std::vector<bool> towerCells() const {
        std::vector<bool> occupied(grid.width * grid.height, false);
        for (const Tower& tower : towers) if (tower.standing()) occupied[grid.index(tower.cell)] = true;
        return occupied;
    }
    const Tower* towerAt(Cell cell) const {
        for (const Tower& tower : towers) if (tower.standing() && tower.cell == cell) return &tower;
        return nullptr;
    }
    Tower* standingTower(const std::string& word) {
        std::size_t number = static_cast<std::size_t>(std::stoll(word));
        return number >= 1 && number <= towers.size() && towers[number - 1].standing() ? &towers[number - 1] : nullptr;
    }
    std::string buildRefusal(const std::string& name, Cell cell) const {
        std::map<std::string, std::size_t>::const_iterator kind = towerNames.find(name);
        if (kind == towerNames.end()) return "type";
        if (!grid.inside(cell)) return "bounds";
        if (!grid.buildable(cell)) return "terrain";
        if (towerAt(cell)) return "tower";
        if (gold < towerTypes[kind->second].levels[0].cost) return "gold";
        for (const Enemy& enemy : enemies) if (enemy.alive && !enemy.flying(enemyTypes) && (enemy.cell == cell || enemy.nextCell == cell)) return "enemy";
        std::vector<bool> occupied = towerCells();
        occupied[grid.index(cell)] = true;
        DistanceField trial(grid, occupied);
        for (Cell spawn : grid.spawns) if (trial.at(spawn) < 0) return "blocked";
        for (const Enemy& enemy : enemies) if (enemy.alive && !enemy.flying(enemyTypes) && trial.at(enemy.nextCell) < 0) return "blocked";
        return "";
    }
    void updateField() {
        DistanceField before = field;
        field = DistanceField(grid, towerCells());
        for (std::size_t index = 0; index < grid.spawns.size(); ++index) {
            Cell spawn = grid.spawns[index];
            if (before.at(spawn) != field.at(spawn)) record("REPATH", index + 1, before.at(spawn), field.at(spawn));
        }
    }
    bool perform(const Action& action) {
        const Lines& arguments = action.arguments;
        if (action.command == "BUILD") {
            Cell cell{std::stoi(arguments[1]), std::stoi(arguments[2])};
            std::string reason = buildRefusal(arguments[0], cell);
            if (!reason.empty()) { record("BUILD_REFUSED", arguments[0], arguments[1], arguments[2], reason); return false; }
            std::size_t kind = towerNames.at(arguments[0]);
            Integer cost = towerTypes[kind].levels[0].cost;
            towers.emplace_back(towers.size() + 1, kind, cell, tick, towerTypes);
            gold -= cost; spent += cost;
            record("BUILD", "T" + std::to_string(towers.back().number), arguments[0], cell.x, cell.y, "cost", cost, "gold", gold);
            updateField();
            return true;
        }
        if (action.command == "CALL") {
            if (active >= 0) { record("CALL_REFUSED", "active"); return false; }
            Integer bonus = (nextStart - tick) * parameters.early;
            gold += bonus; income[3] += bonus; nextStart = tick;
            record("CALL", records.size() + 1, "bonus", bonus, "gold", gold);
            return true;
        }
        Tower* tower = standingTower(arguments[0]);
        std::string reason;
        if (!tower) reason = "notower";
        else if (action.command == "UPGRADE") {
            if (tower->level == towerTypes[tower->kind].levels.size()) reason = "maxlevel";
            else {
                Integer cost = towerTypes[tower->kind].levels[tower->level].cost;
                if (gold < cost) reason = "gold";
                else {
                    gold -= cost; spent += cost; ++tower->level; tower->investment += cost;
                    record("UPGRADE", "T" + arguments[0], "level", tower->level, "cost", cost, "gold", gold);
                    return true;
                }
            }
        } else if (action.command == "SELL") {
            Integer rate = tick == tower->built ? 100 : parameters.sellRate;
            Integer refund = tower->investment * rate / 100;
            tower->sold = tick; gold += refund; income[4] += refund;
            record("SELL", "T" + arguments[0], "refund", refund, "gold", gold);
            updateField();
            return true;
        } else {
            if (std::find(TargetModes.begin(), TargetModes.end(), arguments[1]) == TargetModes.end()) reason = "mode";
            else { tower->mode = arguments[1]; record("TARGET", "T" + arguments[0], arguments[1]); return true; }
        }
        record(action.command + "_REFUSED", "T" + arguments[0], reason);
        return false;
    }
    void addEnemy(Enemy enemy) {
        ++records[active].spawned;
        ++enemyTypes[enemy.kind].spawned;
        enemies.push_back(std::move(enemy));
    }
    void spawnEnemies() {
        if (tick == nextStart) {
            records.emplace_back(records.size() + 1, waves[records.size()], tick);
            active = static_cast<int>(records.size() - 1);
            nextStart = 0;
            record("WAVE_START", records.back().number, "enemies", waves[active].enemyCount());
        }
        if (active < 0) return;
        WaveRecord& wave = records[active];
        const Wave& plan = waves[active];
        for (std::size_t index = 0; index < plan.groups.size(); ++index) {
            const Group& group = plan.groups[index];
            Integer released = wave.released[index];
            if (released == group.count || group.spawnTick(wave.start, released) != tick) continue;
            ++wave.released[index];
            Cell spawn = grid.spawns[group.spawn - 1];
            Enemy enemy(enemies.size() + 1, group.kind, group.multiplier, enemyTypes);
            if (enemy.flying(enemyTypes)) enemy.point = cellCenter(spawn);
            else { enemy.cell = spawn; enemy.nextCell = field.nextCell(spawn); }
            std::size_t number = enemy.number;
            Integer hp = enemy.hp;
            addEnemy(std::move(enemy));
            record("SPAWN", "E" + std::to_string(number), enemyTypes[group.kind].name, group.spawn, "hp", hp);
        }
        wave.peak = std::max(wave.peak, livingCount());
    }
    void credit(Tower& tower, Enemy& enemy, Integer damage) {
        tower.damage += damage;
        enemyTypes[enemy.kind].damage += damage;
        records[active].towerDamage[tower.number] += damage;
    }
    void kill(Enemy& enemy, Tower& tower) {
        enemy.alive = false;
        ++killCounts[grid.index(enemy.occupiedCell(enemyTypes))];
        WaveRecord& wave = records[active];
        EnemyType& kind = enemyTypes[enemy.kind];
        ++tower.kills; ++wave.kills; ++kind.kills;
        gold += kind.bounty; wave.bounty += kind.bounty; income[0] += kind.bounty;
        record("KILL", "E" + std::to_string(enemy.number), kind.name, "T" + std::to_string(tower.number), "bounty", kind.bounty, "gold", gold);
        for (Integer index = 0; index < kind.splitCount; ++index) {
            Enemy child = enemy.split(enemies.size() + 1, enemyTypes);
            std::size_t number = child.number, type = child.kind;
            Integer hp = child.hp;
            addEnemy(std::move(child));
            record("SPAWN", "E" + std::to_string(number), enemyTypes[type].name, "E" + std::to_string(enemy.number), "hp", hp);
        }
    }
    void leak(Enemy& enemy) {
        enemy.alive = false;
        Integer lost = std::min(lives, enemyTypes[enemy.kind].lives);
        lives -= lost;
        WaveRecord& wave = records[active];
        ++wave.leaks; wave.livesLost += lost; ++enemyTypes[enemy.kind].leaks;
        record("LEAK", "E" + std::to_string(enemy.number), enemyTypes[enemy.kind].name, "lives", lives);
        if (lives == 0) {
            record("DEFEAT"); outcome = "defeat";
            wave.close("lost", tick, gold, lives); active = -1;
        }
    }
    void moveEnemy(Enemy& enemy) {
        if (enemy.burn.active()) {
            Tower& source = towers[enemy.burn.source - 1];
            Integer damage = std::min(enemy.hp, enemy.burn.strength);
            enemy.hp -= damage; credit(source, enemy, damage); enemy.burn.advanceTime();
            if (enemy.hp == 0) { kill(enemy, source); return; }
        }
        enemy.hp = std::min(enemy.hp + enemyTypes[enemy.kind].regeneration, enemy.maxHp);
        Integer speed = enemy.slowedSpeed(enemyTypes);
        if (enemy.slow.active()) enemy.slow.advanceTime();
        bool arrived = false;
        if (enemy.flying(enemyTypes)) {
            std::pair<Point, bool> moved = advance(enemy.point, cellCenter(grid.exit), speed);
            enemy.point = moved.first; arrived = moved.second;
        } else {
            if (grid.water(enemy.occupiedCell(enemyTypes))) speed /= 2;
            while (speed > 0) {
                Integer rest = 100 - enemy.progress;
                if (speed < rest) { enemy.progress += speed; speed = 0; }
                else {
                    speed -= rest; enemy.cell = enemy.nextCell; enemy.progress = 0;
                    if (enemy.cell == grid.exit) { arrived = true; break; }
                    enemy.nextCell = field.nextCell(enemy.cell);
                }
            }
        }
        if (arrived) leak(enemy);
    }
    void fireTowers() {
        for (Tower& tower : towers) {
            if (!tower.standing() || tick < tower.ready) continue;
            std::size_t target = tower.selectTarget(enemies, enemyTypes, towerTypes, field);
            if (!target) continue;
            const Level& stats = tower.stats(towerTypes);
            projectiles.push_back({++projectileCount, tower.number, target, tower.center(), enemies[target - 1].position(enemyTypes), towerTypes[tower.kind].targets, stats.power, stats.shotSpeed, stats.splash, stats.slowRate, stats.slowTime, stats.burnAmount, stats.burnTime});
            ++tower.shots; tower.ready = tick + stats.interval;
            record("SHOT", "T" + std::to_string(tower.number), "E" + std::to_string(target));
        }
    }
    void impact(const Projectile& projectile) {
        Tower& tower = towers[projectile.tower - 1];
        std::vector<std::size_t> victims;
        if (projectile.splash == 0) {
            if (enemies[projectile.target - 1].alive) victims.push_back(projectile.target);
        } else {
            for (const Enemy& enemy : enemies) if (enemy.alive && canAim(projectile.targets, enemy, enemyTypes) && squaredDistance(enemy.position(enemyTypes), projectile.aim) <= projectile.splash * projectile.splash) victims.push_back(enemy.number);
        }
        if (victims.empty()) ++tower.fizzles;
        for (std::size_t number : victims) {
            Enemy& enemy = enemies[number - 1];
            ++tower.hits;
            Integer damage = damageDealt(enemy.hp, projectile.power, enemyTypes[enemy.kind].armor);
            enemy.hp -= damage; credit(tower, enemy, damage);
            if (enemy.hp == 0) { kill(enemy, tower); continue; }
            if (projectile.slowRate > 0) enemy.slow.receive(projectile.slowRate, projectile.slowTime);
            if (projectile.burnAmount > 0) enemy.burn.receive(projectile.burnAmount, projectile.burnTime, tower.number);
        }
    }
    void moveProjectiles() {
        std::vector<Projectile> flying;
        for (Projectile& projectile : projectiles) {
            const Enemy& target = enemies[projectile.target - 1];
            if (target.alive) projectile.aim = target.position(enemyTypes);
            if (projectile.fly()) impact(projectile);
            else flying.push_back(projectile);
        }
        projectiles = std::move(flying);
    }
    void checkWaveEnd() {
        if (active < 0 || livingCount() || !records[active].allReleased(waves[active])) return;
        WaveRecord& wave = records[active];
        gold += waves[active].reward;
        Integer interest = std::min(parameters.interestCap, gold * parameters.interestRate / 100);
        gold += interest; wave.reward = waves[active].reward; wave.interest = interest;
        income[1] += wave.reward; income[2] += interest;
        active = -1;
        record("WAVE_END", wave.number, "reward", wave.reward, "interest", interest, "gold", gold);
        if (wave.number == waves.size()) { record("VICTORY"); outcome = "victory"; }
        else nextStart = tick + parameters.interval;
        wave.close("cleared", tick, gold, lives);
    }
    Lines picture(int mode) const {
        Lines rows = grid.rows;
        if (mode == 0) {
            for (Cell spawn : grid.spawns) for (Cell cell : field.path(spawn)) if (grid.terrain(cell) == '.' || grid.water(cell)) rows[cell.y][cell.x] = '+';
            for (const Tower& tower : towers) if (tower.standing()) rows[tower.cell.y][tower.cell.x] = towerTypes[tower.kind].symbol;
            std::vector<Integer> occupants(grid.width * grid.height, 0);
            for (const Enemy& enemy : enemies) if (enemy.alive) {
                Cell cell = enemy.occupiedCell(enemyTypes);
                Integer count = ++occupants[grid.index(cell)];
                rows[cell.y][cell.x] = count == 1 ? enemyTypes[enemy.kind].symbol : '*';
            }
            return rows;
        }
        for (int y = 0; y < grid.height; ++y) for (int x = 0; x < grid.width; ++x) {
            Cell cell{x, y};
            char terrain = grid.terrain(cell);
            const Tower* tower = towerAt(cell);
            char value;
            if (mode == 1) {
                if (terrain == '#' || terrain == 'E') value = terrain;
                else if (tower) value = towerTypes[tower->kind].symbol;
                else value = field.at(cell) < 0 ? '?' : std::string("^>v<")[field.direction(cell)];
            } else if (mode == 2) {
                if (terrain == '#') value = '#';
                else if (tower) value = towerTypes[tower->kind].symbol;
                else {
                    Integer count = 0;
                    for (const Tower& other : towers) if (other.standing() && other.inRange(cellCenter(cell), towerTypes)) ++count;
                    value = digit(count);
                }
            } else {
                Integer count = killCounts[grid.index(cell)];
                value = count > 0 ? digit(count) : terrain == '#' ? '#' : '.';
            }
            rows[y][x] = value;
        }
        return rows;
    }
    Lines block(const std::string& label) const {
        std::ostringstream header;
        header << label << ' ' << tick << " wave " << records.size() << " next " << (active < 0 && outcome.empty() ? std::to_string(nextStart) : "-") << " gold " << gold << " lives " << lives;
        Lines lines{header.str()};
        append(lines, ruled(picture(0)));
        for (std::size_t index = 0; index < grid.spawns.size(); ++index) lines.push_back("PATH " + std::to_string(index + 1) + " length " + std::to_string(field.at(grid.spawns[index])));
        for (const Tower& tower : towers) if (tower.standing()) {
            std::ostringstream line;
            line << 'T' << tower.number << ' ' << towerTypes[tower.kind].name << ' ' << tower.cell.x << ' ' << tower.cell.y << " level " << tower.level << " mode " << tower.mode << " ready " << tower.ready;
            lines.push_back(line.str());
        }
        for (const Enemy& enemy : enemies) if (enemy.alive) {
            Point point = enemy.position(enemyTypes);
            std::ostringstream line;
            line << 'E' << enemy.number << ' ' << enemyTypes[enemy.kind].name << ' ' << point.x << ' ' << point.y << " hp " << enemy.hp << '/' << enemy.maxHp << " slow " << enemy.slow.strength << ' ' << enemy.slow.remaining << " burn " << enemy.burn.strength << ' ' << enemy.burn.remaining;
            lines.push_back(line.str());
        }
        for (const Projectile& projectile : projectiles) {
            std::ostringstream line;
            line << 'P' << projectile.number << " T" << projectile.tower << " E" << projectile.target << ' ' << projectile.position.x << ' ' << projectile.position.y;
            lines.push_back(line.str());
        }
        return lines;
    }
public:
    Lines events, snapshots;
    Game(GridMap map, std::vector<TowerType> towerKinds, std::vector<EnemyType> enemyKinds, std::vector<Wave> plans, Parameters settings) : grid(std::move(map)), towerTypes(std::move(towerKinds)), enemyTypes(std::move(enemyKinds)), waves(std::move(plans)), parameters(std::move(settings)), gold(parameters.gold), lives(parameters.lives), nextStart(parameters.start), field(grid, std::vector<bool>(grid.width * grid.height, false)), killCounts(grid.width * grid.height, 0) {
        for (std::size_t index = 0; index < towerTypes.size(); ++index) towerNames[towerTypes[index].name] = index;
    }
    void run(const std::vector<Action>& actions) {
        std::size_t index = 0;
        for (;;) {
            ++tick;
            while (index < actions.size() && actions[index].tick == tick) {
                if (perform(actions[index])) ++done;
                else ++refused;
                ++index;
            }
            spawnEnemies();
            std::size_t count = enemies.size();
            for (std::size_t enemy = 0; enemy < count; ++enemy) {
                if (enemies[enemy].alive) moveEnemy(enemies[enemy]);
                if (!outcome.empty()) break;
            }
            if (!outcome.empty()) break;
            fireTowers(); moveProjectiles(); checkWaveEnd();
            if (parameters.snapshots.count(tick)) append(snapshots, block("SNAPSHOT"));
            if (!outcome.empty()) break;
        }
        append(snapshots, block("FINAL"));
        const std::array<std::string, 3> titles = {"FLOW", "COVERAGE", "KILLS"};
        for (int mode = 1; mode <= 3; ++mode) { snapshots.push_back(titles[mode - 1]); append(snapshots, ruled(picture(mode))); }
    }
    Lines waveLines() const {
        std::string header = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives";
        for (const Tower& tower : towers) header += ",T" + std::to_string(tower.number);
        Lines lines{header};
        for (const WaveRecord& wave : records) lines.push_back(wave.csvRow(towers.size()));
        return lines;
    }
    Lines summaryLines(std::size_t actionCount) const {
        Integer cleared = 0, perfect = 0, spawned = 0, killed = 0, leaked = 0, totalDamage = 0;
        for (const WaveRecord& wave : records) if (wave.status == "cleared") { ++cleared; if (wave.leaks == 0) ++perfect; }
        for (const EnemyType& kind : enemyTypes) { spawned += kind.spawned; killed += kind.kills; leaked += kind.leaks; }
        const Tower* best = nullptr;
        for (const Tower& tower : towers) { totalDamage += tower.damage; if (!best || tower.damage > best->damage) best = &tower; }
        Integer score = 10 * killed + 100 * lives + 50 * perfect + gold;
        Lines lines{"outcome " + outcome, "ticks " + std::to_string(tick), "waves " + std::to_string(cleared) + "/" + std::to_string(waves.size()) + " perfect " + std::to_string(perfect), "lives " + std::to_string(lives) + "/" + std::to_string(parameters.lives), "gold " + std::to_string(gold), "enemies spawned " + std::to_string(spawned) + " killed " + std::to_string(killed) + " leaked " + std::to_string(leaked)};
        lines.push_back("income bounty " + std::to_string(income[0]) + " reward " + std::to_string(income[1]) + " interest " + std::to_string(income[2]) + " early " + std::to_string(income[3]) + " refund " + std::to_string(income[4]));
        lines.push_back("spent " + std::to_string(spent)); lines.push_back("damage " + std::to_string(totalDamage));
        lines.push_back("actions total " + std::to_string(actionCount) + " done " + std::to_string(done) + " refused " + std::to_string(refused) + " unused " + std::to_string(static_cast<Integer>(actionCount) - done - refused));
        lines.push_back("score " + std::to_string(score));
        lines.push_back(best ? "mvp T" + std::to_string(best->number) + " damage " + std::to_string(best->damage) : "mvp -");
        for (const EnemyType& kind : enemyTypes) lines.push_back("ENEMY " + kind.name + " spawned " + std::to_string(kind.spawned) + " killed " + std::to_string(kind.kills) + " leaked " + std::to_string(kind.leaks) + " damage " + std::to_string(kind.damage));
        for (const Tower& tower : towers) {
            std::ostringstream line;
            line << "TOWER T" << tower.number << ' ' << towerTypes[tower.kind].name << ' ' << tower.cell.x << ' ' << tower.cell.y << " level " << tower.level << " mode " << tower.mode << ' ' << (tower.standing() ? "active" : "sold " + std::to_string(tower.sold)) << " shots " << tower.shots << " hits " << tower.hits << " fizzles " << tower.fizzles << " kills " << tower.kills << " damage " << tower.damage << " per_shot " << oneDecimal(tower.damage, tower.shots) << " share " << oneDecimal(100 * tower.damage, totalDamage) << " invested " << tower.investment;
            lines.push_back(line.str());
        }
        return lines;
    }
};
int main() {
    GridMap grid = readMap("input/map.txt");
    std::vector<TowerType> towers = parseTowerTypes(readLines("input/towers.txt"));
    std::vector<EnemyType> enemies;
    std::vector<Wave> waves;
    parseWaves(readLines("input/waves.txt"), enemies, waves);
    std::vector<Action> actions;
    for (const std::string& line : readLines("input/actions.txt")) actions.emplace_back(line);
    Game game(std::move(grid), std::move(towers), std::move(enemies), std::move(waves), Parameters(readLines("input/params.txt")));
    game.run(actions);
    std::filesystem::create_directories("output");
    writeLines("events.txt", game.events);
    writeLines("waves.csv", game.waveLines());
    writeLines("snapshots.txt", game.snapshots);
    writeLines("summary.txt", game.summaryLines(actions.size()));
}
