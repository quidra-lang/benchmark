#include "dungeon.hpp"
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <stdexcept>

static Lines readLines(const std::string& name) { std::ifstream file("input/" + name, std::ios::binary); if (!file) throw std::runtime_error("cannot read " + name); Lines lines; std::string line; while (std::getline(file, line)) lines.push_back(line); if (file.bad()) throw std::runtime_error("cannot read " + name); return lines; }
static Lines words(const std::string& line) { std::istringstream stream(line); Lines result; std::string word; while (stream >> word) result.push_back(word); return result; }
static std::string decOne(int numerator, int denominator) { if (!denominator) return "-"; int rounded = (20 * numerator + denominator) / (2 * denominator); return text(rounded / 10, '.', rounded % 10); }
static void extend(Lines& first, const Lines& second) { first.insert(first.end(), second.begin(), second.end()); }
static void writeLines(const std::string& name, const Lines& lines) { std::ofstream file("output/" + name, std::ios::binary); if (!file) throw std::runtime_error("cannot write " + name); for (const std::string& line : lines) file << line << '\n'; file.close(); if (!file) throw std::runtime_error("cannot write " + name); }
struct Config {
    Integer generationSeed, gameSeed;
    int width, height, minSize, maxSplit, roomMin, roomMax, levelCount, monsterBase, monsterStep, itemBase, itemStep, sleep, wake, radius, hp, regeneration;
    Dice hitDie;
    int foodStart, foodMax, hungry, weak, packLimit;
    Lines start;
    std::vector<int> xp;
    std::set<int> checkpoints;
};
static Config readConfig() {
    std::map<std::string, Lines> entries;
    for (const std::string& line : readLines("config.txt")) { Lines fields = words(line); entries[fields[0]] = Lines(fields.begin() + 1, fields.end()); }
    Config c;
    c.generationSeed = std::stoll(entries.at("seed")[0]); c.gameSeed = std::stoll(entries.at("seed")[1]);
    c.width = std::stoi(entries.at("map")[0]); c.height = std::stoi(entries.at("map")[1]); c.minSize = std::stoi(entries.at("bsp")[0]); c.maxSplit = std::stoi(entries.at("bsp")[1]); c.roomMin = std::stoi(entries.at("room")[0]); c.roomMax = std::stoi(entries.at("room")[1]);
    c.levelCount = std::stoi(entries.at("levels")[0]); c.monsterBase = std::stoi(entries.at("monsters")[0]); c.monsterStep = std::stoi(entries.at("monsters")[1]); c.itemBase = std::stoi(entries.at("items")[0]); c.itemStep = std::stoi(entries.at("items")[1]);
    c.sleep = std::stoi(entries.at("sleep")[0]); c.wake = std::stoi(entries.at("sleep")[1]); c.radius = std::stoi(entries.at("fov")[0]); c.hp = std::stoi(entries.at("player")[0]); c.regeneration = std::stoi(entries.at("player")[1]); c.hitDie = parseDice(entries.at("hitdie")[0]);
    c.foodStart = std::stoi(entries.at("food")[0]); c.foodMax = std::stoi(entries.at("food")[1]); c.hungry = std::stoi(entries.at("food")[2]); c.weak = std::stoi(entries.at("food")[3]); c.packLimit = std::stoi(entries.at("pack")[0]); c.start = entries.at("start");
    for (const std::string& value : entries.at("xp")) c.xp.push_back(std::stoi(value));
    for (const std::string& value : entries.at("checkpoints")) c.checkpoints.insert(std::stoi(value));
    return c;
}
struct Command { std::string name, argument; };
static std::vector<Command> readCommands() {
    std::vector<Command> result;
    for (const std::string& line : readLines("commands.txt")) {
        Lines fields = words(line); std::string argument; int count = 1;
        if (fields[0] == "wait") { if (fields.size() == 2) count = std::stoi(fields[1]); }
        else { if (fields.size() > 1) argument = fields[1]; if (fields.size() == 3) count = std::stoi(fields[2]); }
        for (int i = 0; i < count; ++i) result.push_back({fields[0], argument});
    }
    return result;
}
struct Player {
    Point position;
    int depth = 1, hp, maxHp, level = 1, xp = 0, gold = 0, food, poison = 0;
    std::vector<std::shared_ptr<Item>> pack;
    std::shared_ptr<Item> weapon, armor;
    int defense() const { return armor ? 10 + armor->kind.armor + armor->bonus : 10; }
};
struct AttackStats {
    int count = 0, hits = 0, criticals = 0, damage = 0;
    void record(Attack result) { ++count; if (result.outcome != AttackOutcome::miss) { ++hits; damage += result.damage; } criticals += result.outcome == AttackOutcome::critical; }
    std::string line(const std::string& label) const { return text(label, ' ', count, " hits ", hits, " criticals ", criticals, " damage ", damage, " accuracy ", decOne(100 * hits, count)); }
};
class Game {
    Config config;
    std::vector<MonsterType> monsterTypes;
    std::vector<ItemType> itemTypes;
    std::vector<Command> commands;
    Minstd generation, random;
    std::vector<Level> levels;
    Player player;
    int turn = 1, succeeded = 0, failed = 0, unused = 0, moves = 0, poisonDamage = 0, starvationDamage = 0;
    std::array<int, 6> usage{};
    std::vector<int> kills;
    AttackStats playerAttacks, monsterAttacks;
    Lines messages, maps;
    std::vector<std::vector<bool>> visible;
    std::vector<std::vector<int>> distance;
    std::string result, cause;
    Level& current() { return levels[player.depth - 1]; }
    const Level& current() const { return levels[player.depth - 1]; }
    void say(const std::string& message) { std::ostringstream stream; stream << std::setw(4) << std::setfill('0') << turn << ' ' << message; messages.push_back(stream.str()); }
    std::string hunger() const { return player.food > config.hungry ? "normal" : player.food > config.weak ? "hungry" : player.food > 0 ? "weak" : "starving"; }
    void finish(const std::string& outcome, const std::string& reason) { result = outcome; cause = reason; }
    void die(const std::string& reason) { say("You die."); finish("died", reason); }
    void buildLevels() {
        for (int depth = 1; depth <= config.levelCount; ++depth) {
            Level level = generateLevel(generation, depth, config.width, config.height, config.minSize, config.maxSplit, config.roomMin, config.roomMax);
            if (depth < config.levelCount) level.terrain[level.target.second][level.target.first] = '>';
            else { ItemType amulet; amulet.category = "amulet"; amulet.name = "amulet"; level.items.push_back(std::make_shared<Item>(Item{amulet, level.target, 0, 0})); }
            std::vector<int> candidates, weights;
            for (int i = 0; i < static_cast<int>(monsterTypes.size()); ++i) if (monsterTypes[i].minDepth <= depth && depth <= monsterTypes[i].maxDepth) { candidates.push_back(i); weights.push_back(monsterTypes[i].weight); }
            int monsterCount = config.monsterBase + config.monsterStep * (depth - 1);
            for (int number = 1; number <= monsterCount; ++number) {
                int type = candidates[generation.select(weights)]; Point point; int room;
                while (true) { int x, y; std::tie(room, x, y) = level.drawRoomCell(generation); point = {x, y}; if (room != level.arrivalRoom && level.terrain[y][x] == '.' && level.monsterAt(point) < 0) break; }
                int hp = generation.roll(monsterTypes[type].hp); bool asleep = generation.draw() % 100 < config.sleep;
                level.monsters.push_back({number, type, point, hp, hp, asleep, 0, false, true});
            }
            level.monstersCreated = monsterCount;
            candidates.clear(); weights.clear();
            for (int i = 0; i < static_cast<int>(itemTypes.size()); ++i) if (itemTypes[i].minDepth <= depth && depth <= itemTypes[i].maxDepth) { candidates.push_back(i); weights.push_back(itemTypes[i].weight); }
            int itemCount = config.itemBase + config.itemStep * (depth - 1);
            for (int number = 0; number < itemCount; ++number) {
                int type = candidates[generation.select(weights)]; Point point;
                while (true) { int room, x, y; std::tie(room, x, y) = level.drawRoomCell(generation); point = {x, y}; if (level.terrain[y][x] == '.' && level.itemAt(point) < 0) break; }
                int amount = itemTypes[type].category == "gold" ? generation.roll(itemTypes[type].dice) : 0;
                level.items.push_back(std::make_shared<Item>(Item{itemTypes[type], point, amount, 0}));
            }
            level.itemsPlaced = static_cast<int>(level.items.size()); levels.push_back(std::move(level));
        }
    }
    void updateView() {
        Level& level = current(); visible = fieldOfView(level, player.position, config.radius);
        for (int y = 0; y < level.height; ++y) for (int x = 0; x < level.width; ++x) if (visible[y][x]) { int item = level.itemAt({x, y}); level.memory[y][x] = item < 0 ? level.terrain[y][x] : level.items[item]->symbol(); }
        for (Monster& monster : level.monsters) if (monster.alive) { bool seen = visible[monster.position.second][monster.position.first]; if (seen && !monster.wasVisible) say(text("You see the ", monsterTypes[monster.type].name, '.')); monster.wasVisible = seen; }
    }
    void gainXp(int amount) {
        player.xp += amount;
        while (player.level <= static_cast<int>(config.xp.size()) && player.xp >= config.xp[player.level - 1]) { ++player.level; int hp = random.roll(config.hitDie); player.maxHp += hp; player.hp += hp; say(text("Welcome to level ", player.level, '.')); }
    }
    void playerAttack(Monster& monster) {
        monster.asleep = false;
        const MonsterType& kind = monsterTypes[monster.type];
        int toHit = player.level, bonus = 0; Dice dice{1, 2};
        if (player.weapon) { toHit += player.weapon->kind.toHit + player.weapon->bonus; bonus = player.weapon->bonus; dice = player.weapon->kind.dice; }
        if (hunger() == "weak" || hunger() == "starving") toHit -= 2;
        Attack attack = resolveAttack(random, toHit, kind.defense, dice, bonus); playerAttacks.record(attack);
        if (attack.outcome == AttackOutcome::miss) { say(text("You miss the ", kind.name, '.')); return; }
        say(text("You hit the ", kind.name, attack.outcome == AttackOutcome::critical ? " hard for " : " for ", attack.damage, '.'));
        monster.hp -= attack.damage;
        if (monster.hp <= 0) { say(text("You kill the ", kind.name, '.')); monster.alive = false; ++current().kills; ++kills[monster.type]; gainXp(kind.xp); }
    }
    void monsterAttack(const Monster& monster) {
        const MonsterType& kind = monsterTypes[monster.type];
        Attack attack = resolveAttack(random, kind.toHit, player.defense(), kind.damage, 0); monsterAttacks.record(attack);
        if (attack.outcome == AttackOutcome::miss) { say(text("The ", kind.name, " misses you.")); return; }
        say(text("The ", kind.name, attack.outcome == AttackOutcome::critical ? " hits you hard for " : " hits you for ", attack.damage, '.'));
        player.hp -= attack.damage;
        if (player.hp <= 0) die("killed_by " + kind.name);
        else if (kind.traits.find('P') != std::string::npos) { player.poison += 5; say("You are poisoned."); }
    }
    bool move(Point direction) {
        Level& level = current(); Point target{player.position.first + direction.first, player.position.second + direction.second};
        if (!passable(level, target)) { say("You bump into a wall."); return false; }
        if (!canMove(level, player.position, direction)) { say("You cannot move diagonally through a door."); return false; }
        int monster = level.monsterAt(target);
        if (monster >= 0) { playerAttack(level.monsters[monster]); return true; }
        player.position = target; ++moves; int item = level.itemAt(target);
        if (item >= 0) say("You see " + level.items[item]->referenceName() + " here.");
        else if (level.terrain[target.second][target.first] == '>') say("There is a staircase down here.");
        return true;
    }
    bool pickup() {
        Level& level = current(); int index = level.itemAt(player.position);
        if (index < 0) { say("There is nothing here."); return false; }
        std::shared_ptr<Item> item = level.items[index]; const std::string& category = item->kind.category;
        if (category == "gold") { player.gold += item->amount; say("You pick up " + item->displayName() + '.'); }
        else if (category == "amulet") { say("You pick up the amulet."); say("You win!"); finish("won", "amulet"); }
        else if (player.pack.size() >= static_cast<std::size_t>(config.packLimit)) { say("Your pack is full."); return false; }
        else { player.pack.push_back(item); say(text("You pick up the ", item->displayName(), " (", player.pack.size(), ").")); }
        level.items.erase(level.items.begin() + index); ++level.picked; ++usage[0]; return true;
    }
    bool useItem(const std::string& name, int number) {
        if (number > static_cast<int>(player.pack.size())) { say("You do not have that item."); return false; }
        std::shared_ptr<Item> item = player.pack[number - 1];
        static const std::map<std::string, std::string> categories{{"quaff", "potion"}, {"read", "scroll"}, {"wield", "weapon"}, {"wear", "armor"}, {"eat", "food"}};
        if (item->kind.category != categories.at(name)) { say("You cannot " + name + " that."); return false; }
        if (name == "wield" || name == "wear") {
            std::shared_ptr<Item>& equipped = name == "wield" ? player.weapon : player.armor;
            if (equipped == item) { say(name == "wield" ? "You are already wielding that." : "You are already wearing that."); return false; }
            equipped = item; ++usage[name == "wield" ? 4 : 5]; say(text(name == "wield" ? "You are now wielding the " : "You are now wearing the ", item->displayName(), '.')); return true;
        }
        player.pack.erase(player.pack.begin() + number - 1);
        if (name == "eat") { ++usage[3]; player.food = std::min(player.food + item->kind.nutrition, config.foodMax); say("You eat the " + item->displayName() + '.'); return true; }
        const std::string& effect = item->kind.effect;
        if (name == "quaff") {
            ++usage[1]; say("You quaff the " + item->displayName() + '.');
            if (effect == "heal") { player.hp += random.roll(item->kind.dice); if (player.hp > player.maxHp) { ++player.maxHp; player.hp = player.maxHp; } player.poison = 0; say("You feel better."); }
            else if (effect == "poison") { player.poison += item->kind.poison; say("You feel very sick."); }
            else { say("You feel more experienced."); if (player.level <= static_cast<int>(config.xp.size())) gainXp(config.xp[player.level - 1] - player.xp); }
            return true;
        }
        ++usage[2]; say("You read the " + item->displayName() + '.'); Level& level = current();
        if (effect == "mapping") { for (int y = 0; y < level.height; ++y) for (int x = 0; x < level.width; ++x) if (level.terrain[y][x] != ' ' && level.memory[y][x] == ' ') level.memory[y][x] = level.terrain[y][x]; say("A map forms in your mind."); }
        else if (effect == "teleport") { while (true) { int room, x, y; std::tie(room, x, y) = level.drawRoomCell(random); Point target{x, y}; if (target != player.position && level.monsterAt(target) < 0) { player.position = target; break; } } say("You are teleported."); }
        else if (effect == "enchant_weapon") { if (player.weapon) { say("Your " + player.weapon->displayName() + " glows blue."); ++player.weapon->bonus; } else say("Your hands twitch."); }
        else if (effect == "enchant_armor") { if (player.armor) { say("Your " + player.armor->displayName() + " glows silver."); ++player.armor->bonus; } else say("Your skin tingles."); }
        return true;
    }
    bool execute(const Command& command) {
        if (command.name == "move") { int index = static_cast<int>(std::find(directionNames.begin(), directionNames.end(), command.argument) - directionNames.begin()); return move(directions[index]); }
        if (command.name == "wait") return true;
        if (command.name == "pickup") return pickup();
        if (command.name == "descend") { if (current().terrain[player.position.second][player.position.first] != '>') { say("There are no stairs here."); return false; } ++player.depth; player.position = current().arrival; say(text("You descend to depth ", player.depth, '.')); return true; }
        return useItem(command.name, std::stoi(command.argument));
    }
    bool canAttack(const Monster& monster) const { Point direction{player.position.first - monster.position.first, player.position.second - monster.position.second}; return std::max(std::abs(direction.first), std::abs(direction.second)) == 1 && canMove(current(), monster.position, direction); }
    void wander(Monster& monster) {
        Point direction = directions[static_cast<std::size_t>(random.draw() % 8)]; if (!canMove(current(), monster.position, direction)) return;
        Point target{monster.position.first + direction.first, monster.position.second + direction.second};
        if (target == player.position) monsterAttack(monster); else if (current().monsterAt(target) < 0) monster.position = target;
    }
    void chase(Monster& monster) {
        if (canAttack(monster)) { monsterAttack(monster); return; }
        int here = distance[monster.position.second][monster.position.first], bestDistance = 0; bool found = false; Point best;
        for (const Point& direction : directions) {
            if (!canMove(current(), monster.position, direction)) continue;
            Point target{monster.position.first + direction.first, monster.position.second + direction.second}; int value = distance[target.second][target.first];
            if (value < 0 || (here >= 0 && value >= here) || current().monsterAt(target) >= 0 || target == player.position) continue;
            if (!found || value < bestDistance) { found = true; best = target; bestDistance = value; }
        }
        if (found) monster.position = best;
    }
    void monstersAct() {
        distance = distances(current(), player.position);
        for (Monster& monster : current().monsters) if (monster.alive) {
            const MonsterType& kind = monsterTypes[monster.type]; monster.energy += kind.speed;
            while (monster.energy >= 2) {
                monster.energy -= 2; bool sees = visible[monster.position.second][monster.position.first];
                if (monster.asleep) { if (sees && random.draw() % 100 < config.wake) { monster.asleep = false; say(text("The ", kind.name, " wakes up.")); } }
                else if (kind.traits.find('S') != std::string::npos) { if (canAttack(monster)) monsterAttack(monster); }
                else if (kind.traits.find('E') != std::string::npos && random.draw() % 2 == 0) wander(monster);
                else if (sees) chase(monster); else wander(monster);
                if (!result.empty()) return;
            }
        }
    }
    void endTurn() {
        for (Monster& monster : current().monsters) if (monster.alive && monsterTypes[monster.type].traits.find('R') != std::string::npos && monster.hp < monster.maxHp) ++monster.hp;
        if (player.poison > 0) { --player.hp; ++poisonDamage; if (player.hp <= 0) { die("poison"); return; } --player.poison; if (!player.poison) say("You feel less sick."); }
        if (!player.food) { --player.hp; ++starvationDamage; if (player.hp <= 0) { die("starvation"); return; } }
        else { std::string before = hunger(); --player.food; std::string after = hunger(); if (before != after) say(after == "hungry" ? "You are getting hungry." : after == "weak" ? "You feel weak from hunger." : "You are starving."); }
        if (turn % config.regeneration == 0 && !player.poison && player.food > 0 && player.hp < player.maxHp) ++player.hp;
    }
    std::pair<int, int> exploration(const Level& level) const { int explored = 0, total = 0; for (int y = 0; y < level.height; ++y) for (int x = 0; x < level.width; ++x) if (level.terrain[y][x] != ' ') { ++total; explored += level.memory[y][x] != ' '; } return {explored, total}; }
    Lines mapRows(const Level& level, bool currentView) const {
        std::string border = '+' + std::string(level.width, '-') + '+'; Lines rows{border};
        for (int y = 0; y < level.height; ++y) {
            std::string row = "|";
            for (int x = 0; x < level.width; ++x) {
                char symbol = level.memory[y][x];
                if (currentView && visible[y][x]) {
                    Point point{x, y}; int monster = level.monsterAt(point), item = level.itemAt(point);
                    symbol = point == player.position ? '@' : monster >= 0 ? monsterTypes[level.monsters[monster].type].symbol : item >= 0 ? level.items[item]->symbol() : level.terrain[y][x];
                }
                row += symbol;
            }
            rows.push_back(row + '|');
        }
        rows.push_back(border); return rows;
    }
    std::string status() const { return text("STATUS hp ", player.hp, '/', player.maxHp, " level ", player.level, " xp ", player.xp, " defense ", player.defense(), " gold ", player.gold, " food ", player.food, ' ', hunger(), " poison ", player.poison); }
    Lines statsLines() const {
        Lines lines{text("result ", result), text("cause ", cause), text("turns ", succeeded), text("depth ", player.depth), text("level ", player.level), text("xp ", player.xp), text("hp ", player.hp, '/', player.maxHp), text("defense ", player.defense()), text("gold ", player.gold), text("food ", player.food, ' ', hunger()), text("poison ", player.poison), text("weapon ", player.weapon ? player.weapon->displayName() : "-"), text("armor ", player.armor ? player.armor->displayName() : "-"), text("commands ", commands.size(), " executed ", succeeded, " failed ", failed, " unused ", unused), text("moves ", moves), playerAttacks.line("player_attacks"), monsterAttacks.line("monster_attacks"), text("poison_damage ", poisonDamage, " starvation_damage ", starvationDamage), text("picked ", usage[0], " quaffed ", usage[1], " read ", usage[2], " eaten ", usage[3], " wielded ", usage[4], " worn ", usage[5])};
        int totalKills = 0; for (int count : kills) totalKills += count; add(lines, "kills ", totalKills);
        for (std::size_t i = 0; i < monsterTypes.size(); ++i) if (kills[i]) add(lines, "KILL ", monsterTypes[i].name, ' ', kills[i]);
        for (const Level& level : levels) { std::pair<int, int> explored = exploration(level); add(lines, "LEVEL ", level.depth, " rooms ", level.rooms.size(), " explored ", explored.first, '/', explored.second, ' ', decOne(100 * explored.first, explored.second), " monsters ", level.kills, '/', level.monstersCreated, " items ", level.picked, '/', level.itemsPlaced); }
        for (std::size_t i = 0; i < player.pack.size(); ++i) add(lines, "INVENTORY ", i + 1, ' ', player.pack[i]->displayName(), player.pack[i] == player.weapon ? " (wielded)" : player.pack[i] == player.armor ? " (worn)" : "");
        return lines;
    }
public:
    Game(Config config, std::vector<MonsterType> monsterTypes, std::vector<ItemType> itemTypes, std::vector<Command> commands) : config(std::move(config)), monsterTypes(std::move(monsterTypes)), itemTypes(std::move(itemTypes)), commands(std::move(commands)), generation(this->config.generationSeed), random(this->config.gameSeed), kills(this->monsterTypes.size()) {
        buildLevels(); player.position = levels.front().arrival; player.hp = player.maxHp = this->config.hp; player.food = this->config.foodStart;
        for (const std::string& name : this->config.start) {
            const ItemType* kind = nullptr; for (const ItemType& candidate : this->itemTypes) if (candidate.name == name) { kind = &candidate; break; }
            std::shared_ptr<Item> item = std::make_shared<Item>(Item{*kind, player.position, 0, 0}); player.pack.push_back(item);
            if (kind->category == "weapon" && !player.weapon) player.weapon = item;
            if (kind->category == "armor" && !player.armor) player.armor = item;
        }
    }
    void run() {
        updateView();
        for (const Command& command : commands) {
            if (!result.empty()) { ++unused; continue; }
            if (!execute(command)) { ++failed; continue; }
            ++succeeded; if (!result.empty()) continue;
            updateView(); monstersAct(); if (!result.empty()) continue;
            endTurn(); if (!result.empty()) continue;
            if (config.checkpoints.count(turn)) { add(maps, "CHECKPOINT turn ", turn, " depth ", player.depth); extend(maps, mapRows(current(), true)); maps.push_back(status()); }
            ++turn;
        }
        if (result.empty()) finish("alive", "commands_exhausted");
        add(maps, "FINAL turn ", succeeded, " depth ", player.depth);
        for (int depth = 1; depth <= player.depth; ++depth) { const Level& level = levels[depth - 1]; std::pair<int, int> explored = exploration(level); add(maps, "LEVEL ", depth, " explored ", explored.first, '/', explored.second); extend(maps, mapRows(level, depth == player.depth)); }
        maps.push_back(status());
        std::filesystem::create_directories("output"); writeLines("messages.txt", messages); writeLines("maps.txt", maps); writeLines("stats.txt", statsLines());
    }
};
int main() {
    Config config = readConfig(); std::vector<MonsterType> monsters; std::vector<ItemType> items;
    for (const std::string& line : readLines("monsters.txt")) monsters.push_back(parseMonsterType(words(line)));
    for (const std::string& line : readLines("items.txt")) items.push_back(parseItemType(words(line)));
    Game game(std::move(config), std::move(monsters), std::move(items), readCommands()); game.run();
}
