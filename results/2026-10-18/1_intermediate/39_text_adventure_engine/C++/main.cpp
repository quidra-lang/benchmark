#include <algorithm>
#include <array>
#include <functional>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <variant>
#include <vector>

using namespace std;

using Lines = vector<string>;
struct Failure { Lines rows; };
[[noreturn]] void fail(string message) { throw Failure{{move(message)}}; }
[[noreturn]] void fail(Lines rows) { throw Failure{move(rows)}; }
void append(Lines& target, const Lines& rows) { target.insert(target.end(), rows.begin(), rows.end()); }
Lines words(const string& line) {
    istringstream input(line);
    Lines result;
    for (string word; input >> word;) result.push_back(word);
    return result;
}
Lines normalized(string line) {
    for (char& ch : line) if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
    auto result = words(line);
    result.erase(remove_if(result.begin(), result.end(), [](const string& word) { return word == "the" || word == "a" || word == "an"; }), result.end());
    return result;
}
Lines tail(const Lines& parts, size_t first) { return Lines(parts.begin() + first, parts.end()); }
string join(const Lines& parts, const string& separator = " ") {
    string result;
    for (const auto& part : parts) { if (!result.empty()) result += separator; result += part; }
    return result;
}
enum class Direction { North, South, East, West, Up, Down };
const array<string, 6> directionNames = {"north", "south", "east", "west", "up", "down"};
string directionName(Direction direction) { return directionNames[static_cast<size_t>(direction)]; }
optional<Direction> directionWord(const string& word) {
    for (size_t index = 0; index < directionNames.size(); ++index)
        if (word == directionNames[index] || word == directionNames[index].substr(0, 1)) return static_cast<Direction>(index);
    return nullopt;
}
Direction opposite(Direction direction) { return static_cast<Direction>(static_cast<int>(direction) ^ 1); }
enum class Verb { Go, Look, Examine, Take, Drop, Put, Inventory, Open, Close, Unlock, Lock, Use, Light, Extinguish, Wait, Score, Save, Restore, Verbose, Brief };
const array<string, 20> verbNames = {"go", "look", "examine", "take", "drop", "put", "inventory", "open", "close", "unlock", "lock", "use", "light", "extinguish", "wait", "score", "save", "restore", "verbose", "brief"};
const map<string, Verb> verbWords = [] {
    const array<string, 20> synonyms = {"go walk run", "look l", "examine x inspect read", "take get grab", "drop discard", "put insert place", "inventory inv i", "open", "close shut", "unlock", "lock", "use apply", "light ignite", "extinguish douse snuff", "wait z", "score", "save", "restore load", "verbose", "brief"};
    map<string, Verb> result;
    for (size_t index = 0; index < synonyms.size(); ++index)
        for (const auto& word : words(synonyms[index])) result.emplace(word, static_cast<Verb>(index));
    return result;
}();
const set<Verb> noObjects = {Verb::Look, Verb::Inventory, Verb::Wait, Verb::Score, Verb::Save, Verb::Restore, Verb::Verbose, Verb::Brief};
const set<Verb> actions = {Verb::Go, Verb::Take, Verb::Drop, Verb::Put, Verb::Open, Verb::Close, Verb::Unlock, Verb::Lock, Verb::Use, Verb::Light, Verb::Extinguish, Verb::Wait};

enum class PlaceKind { Room, Player, Inside, Nowhere };
struct Place {
    PlaceKind kind = PlaceKind::Nowhere;
    string id;
    friend bool operator==(const Place& a, const Place& b) { return a.kind == b.kind && a.id == b.id; }
    friend bool operator<(const Place& a, const Place& b) { return tie(a.kind, a.id) < tie(b.kind, b.id); }
};
Place floorOf(string id) { return {PlaceKind::Room, move(id)}; }
Place inside(string id) { return {PlaceKind::Inside, move(id)}; }
Place player() { return {PlaceKind::Player, ""}; }
enum class ContainerState { Open, Closed, Locked };
string containerText(ContainerState state) { return state == ContainerState::Open ? "open" : state == ContainerState::Closed ? "closed" : "locked"; }
enum class EndState { None, Won, Dead };
struct Room { string name; bool dark = false; Lines description; };
struct Item {
    string id, name;
    int weight = 0, points = 0;
    bool light = false, fixed = false;
    optional<int> capacity;
    optional<string> key;
    set<string> nouns, adjectives;
    Lines details;
};
struct ItemState { Place place; ContainerState container = ContainerState::Open; bool lit = false; int fuel = 0; };
struct Exit { string destination; optional<string> key; bool locked = false; };
struct Message { string text; };
struct OpenExit { string room; Direction direction; string destination; };
struct RemoveItem { string id; };
struct AddItem { string id, room; };
struct SetFlag { string id; bool on; };
struct AddPoints { int amount; };
using Effect = variant<Message, OpenExit, RemoveItem, AddItem, SetFlag, AddPoints>;
template<class... Functions> struct Overloaded : Functions... { using Functions::operator()...; };
template<class... Functions> Overloaded(Functions...) -> Overloaded<Functions...>;
struct Condition { string flag; bool on; };
struct Rule { string first, second; optional<Condition> condition; Effect effect; };
struct GameState {
    string room;
    map<string, ItemState> items;
    map<string, map<Direction, Exit>> exits;
    set<string> flags, visited;
    int bonus = 0, moves = 0, darkness = 0;
    EndState ended = EndState::None;
};
struct Score { int stored = 0, treasures = 0, points = 0, total = 0; };
struct RuleResult { Lines rows; int executed = 0; };

class Adventure {
    map<string, Room> rooms;
    map<string, Item> items;
    vector<Rule> rules, enterRules;
    set<string> vocabulary;
    string trophy;
    int maxWeight = 0;
    GameState state;
    optional<GameState> saved;
    optional<string> pronoun, previous;
    bool verbose = false;

    void setExit(const string& room, Direction direction, const string& destination, optional<string> key = nullopt) {
        state.exits[room][direction] = {destination, key, key.has_value()};
    }
    Exit* exitAt(const string& room, Direction direction) {
        const auto found = state.exits.find(room);
        if (found == state.exits.end()) return nullptr;
        const auto exit = found->second.find(direction);
        return exit == found->second.end() ? nullptr : &exit->second;
    }
    void define(const string& line) {
        const auto parts = words(line);
        const auto& kind = parts[0]; const auto& id = parts[1];
        if (kind == "ROOM") {
            const bool dark = parts[2] == "DARK";
            rooms[id] = {join(tail(parts, dark ? 3 : 2)), dark, {}};
        } else if (kind == "DESC") rooms.at(id).description.push_back(join(tail(parts, 2)));
        else if (kind == "EXIT") setExit(id, *directionWord(parts[2]), parts[3], parts.size() > 4 ? optional<string>(parts[5]) : nullopt);
        else if (kind == "ITEM") {
            Item item; item.id = id; item.weight = stoi(parts[3]); item.nouns.insert(id);
            ItemState value;
            value.place = parts[2] == "PLAYER" ? player() : parts[2] == "NOWHERE" ? Place{} : floorOf(parts[2]);
            size_t index = 4;
            if (parts[index] == "TREASURE") { item.points = stoi(parts[index + 1]); index += 2; }
            if (parts[index] == "LIGHT") { item.light = true; value.fuel = stoi(parts[index + 1]); index += 2; }
            if (parts[index] == "CONTAINER") {
                item.capacity = stoi(parts[index + 1]); index += 2;
                if (parts[index] == "CLOSED") { value.container = ContainerState::Closed; ++index; }
                if (parts[index] == "LOCKED") { item.key = parts[index + 1]; value.container = ContainerState::Locked; index += 2; }
            }
            if (parts[index] == "FIXED") { item.fixed = true; ++index; }
            item.name = join(tail(parts, index));
            item.adjectives.insert(parts.begin() + index, parts.end());
            items.emplace(id, move(item)); state.items.emplace(id, move(value));
        } else if (kind == "INSIDE") state.items.at(id).place = inside(parts[2]);
        else if (kind == "ALIAS") items.at(id).nouns.insert(parts[2]);
        else if (kind == "DETAIL") items.at(id).details.push_back(join(tail(parts, 2)));
        else if (kind == "RULE" || kind == "ENTER") {
            Rule rule; rule.first = id;
            size_t index = kind == "RULE" ? 3 : 2;
            if (kind == "RULE") rule.second = parts[2];
            if (parts[index] == "IF" || parts[index] == "UNLESS") {
                rule.condition = Condition{parts[index + 1], parts[index] == "IF"}; index += 2;
            }
            const string& effect = parts[index++];
            if (effect == "MESSAGE") rule.effect = Message{join(tail(parts, index))};
            else if (effect == "OPEN") rule.effect = OpenExit{parts[index], *directionWord(parts[index + 1]), parts[index + 2]};
            else if (effect == "REMOVE") rule.effect = RemoveItem{parts[index]};
            else if (effect == "ADD") rule.effect = AddItem{parts[index], parts[index + 1]};
            else if (effect == "SET" || effect == "CLEAR") rule.effect = SetFlag{parts[index], effect == "SET"};
            else rule.effect = AddPoints{stoi(parts[index])};
            (kind == "RULE" ? rules : enterRules).push_back(move(rule));
        } else if (kind == "TROPHY") trophy = id;
        else if (kind == "START") state.room = id;
        else if (kind == "MAXWEIGHT") maxWeight = stoi(id);
    }
    Lines contents(const Place& place) const {
        Lines result;
        for (const auto& [id, item] : state.items) if (item.place == place) result.push_back(id);
        return result;
    }
    map<Place, Lines> children() const {
        map<Place, Lines> result;
        for (const auto& [id, item] : state.items) result[item.place].push_back(id);
        return result;
    }
    bool isOpen(const string& id) const { return items.at(id).capacity && state.items.at(id).container == ContainerState::Open; }
    set<string> reachable(const Place& place) const {
        const auto grouped = children();
        set<string> result;
        function<void(const Place&)> visit = [&](const Place& location) {
            const auto found = grouped.find(location);
            if (found == grouped.end()) return;
            for (const auto& id : found->second) {
                result.insert(id);
                if (isOpen(id)) visit(inside(id));
            }
        };
        visit(place);
        return result;
    }
    set<string> carried() const { return reachable(player()); }
    set<string> roomItems() const { return reachable(floorOf(state.room)); }
    bool isLit() const {
        if (!rooms.at(state.room).dark) return true;
        auto nearby = carried();
        const auto ground = roomItems();
        nearby.insert(ground.begin(), ground.end());
        return any_of(nearby.begin(), nearby.end(), [&](const string& id) { return state.items.at(id).lit; });
    }
    set<string> visible() const {
        auto result = carried();
        if (isLit()) { const auto ground = roomItems(); result.insert(ground.begin(), ground.end()); }
        return result;
    }
    map<string, int> weights() const {
        const auto grouped = children();
        map<string, int> result;
        function<int(const string&)> total = [&](const string& id) {
            if (const auto found = result.find(id); found != result.end()) return found->second;
            int weight = items.at(id).weight;
            if (const auto found = grouped.find(inside(id)); found != grouped.end())
                for (const auto& child : found->second) weight += total(child);
            result[id] = weight;
            return weight;
        };
        for (const auto& [id, item] : items) total(id);
        return result;
    }
    int totalWeight(const string& id) const { return weights().at(id); }
    int contentWeight(const string& id) const { return totalWeight(id) - items.at(id).weight; }
    int carriedWeight() const {
        const auto totals = weights();
        int result = 0;
        for (const auto& id : contents(player())) result += totals.at(id);
        return result;
    }
    bool nestedIn(const string& id, const string& ancestor) const {
        Place place = state.items.at(id).place;
        while (place.kind == PlaceKind::Inside) {
            if (place.id == ancestor) return true;
            place = state.items.at(place.id).place;
        }
        return false;
    }
    Score score() const {
        Score result;
        for (const auto& [id, item] : items) if (item.points > 0) {
            ++result.treasures;
            Place place = state.items.at(id).place;
            while (place.kind == PlaceKind::Inside) place = state.items.at(place.id).place;
            if (place == floorOf(trophy)) { ++result.stored; result.points += item.points; }
        }
        result.total = result.points + state.bonus;
        return result;
    }
    string display(const string& id) const {
        const auto& item = items.at(id); const auto& value = state.items.at(id);
        Lines annotations;
        if (item.capacity) annotations.push_back(containerText(value.container));
        if (item.light && value.lit) annotations.push_back("lit");
        return item.name + (annotations.empty() ? "" : " (" + join(annotations, ", ") + ")");
    }
    Lines tree(const Place& place) const {
        const auto grouped = children();
        Lines rows;
        function<void(const Place&, int)> visit = [&](const Place& location, int depth) {
            const auto found = grouped.find(location);
            if (found == grouped.end()) return;
            for (const auto& id : found->second) {
                rows.push_back(string(2 * depth, ' ') + display(id));
                if (isOpen(id)) visit(inside(id), depth + 1);
            }
        };
        visit(place, 1);
        return rows;
    }
    Lines describe(bool full = true) const {
        if (!isLit()) return {"It is pitch dark."};
        const auto& room = rooms.at(state.room);
        Lines rows = {room.name}, exits;
        if (full) append(rows, room.description);
        if (const auto found = state.exits.find(state.room); found != state.exits.end())
            for (const auto& [direction, exit] : found->second) exits.push_back(directionName(direction) + (exit.locked ? " (locked)" : ""));
        rows.push_back("Exits: " + (exits.empty() ? "none" : join(exits, ", ")));
        if (!contents(floorOf(state.room)).empty()) { rows.push_back("You see:"); append(rows, tree(floorOf(state.room))); }
        return rows;
    }
    string resolve(const Lines& phrase) {
        const auto available = visible();
        if (phrase.size() == 1 && phrase[0] == "it") {
            if (!pronoun) fail("I don't know what \"it\" refers to.");
            if (!available.count(*pronoun)) fail("You can't see any such thing.");
            return *pronoun;
        }
        for (const auto& word : phrase) if (!vocabulary.count(word)) fail("I don't know the word \"" + word + "\".");
        Lines matches, names;
        for (const auto& [id, item] : items) if (available.count(id) && item.nouns.count(phrase.back()) &&
            all_of(phrase.begin(), phrase.end() - 1, [&](const string& word) { return item.adjectives.count(word); })) {
            matches.push_back(id); names.push_back(item.name);
        }
        if (matches.empty()) fail("You can't see any such thing.");
        if (matches.size() > 1) fail("Which do you mean: " + join(names, ", ") + "?");
        pronoun = matches[0];
        return matches[0];
    }
    RuleResult runRules(const vector<Rule>& source, const string& first, const string& second = "") {
        RuleResult result;
        for (const auto& rule : source) {
            if (rule.first != first || rule.second != second) continue;
            if (rule.condition && static_cast<bool>(state.flags.count(rule.condition->flag)) != rule.condition->on) continue;
            ++result.executed;
            visit(Overloaded{
                [&](const Message& effect) { result.rows.push_back(effect.text); },
                [&](const OpenExit& effect) { setExit(effect.room, effect.direction, effect.destination); },
                [&](const RemoveItem& effect) { state.items.at(effect.id).place = Place{}; },
                [&](const AddItem& effect) { state.items.at(effect.id).place = floorOf(effect.room); },
                [&](const SetFlag& effect) { if (effect.on) state.flags.insert(effect.id); else state.flags.erase(effect.id); },
                [&](const AddPoints& effect) { state.bonus += effect.amount; }
            }, rule.effect);
        }
        return result;
    }
    void requireContainer(const string& id) const {
        const auto& item = items.at(id);
        if (!item.capacity) fail("The " + item.name + " is not a container.");
        if (!isOpen(id)) fail("The " + item.name + " is closed.");
    }
    Lines take(const Lines& first, const optional<Lines>& second) {
        if (!isLit()) fail("It is pitch dark.");
        optional<string> container;
        Place source = floorOf(state.room);
        if (second) { container = resolve(*second); requireContainer(*container); source = inside(*container); }
        if (first.size() == 1 && first[0] == "all") {
            Lines candidates, rows;
            for (const auto& id : contents(source)) if (!items.at(id).fixed) candidates.push_back(id);
            if (candidates.empty()) fail(container ? "There is nothing in the " + items.at(*container).name + " to take." : "There is nothing here to take.");
            bool taken = false;
            for (const auto& id : candidates) {
                string outcome = "You can't carry any more.";
                if (carried().count(id) || carriedWeight() + totalWeight(id) <= maxWeight) {
                    state.items.at(id).place = player(); outcome = "Taken."; taken = true;
                }
                rows.push_back(items.at(id).name + ": " + outcome);
            }
            if (!taken) fail(move(rows));
            return rows;
        }
        const string id = resolve(first);
        const auto& item = items.at(id); auto& value = state.items.at(id);
        if (container && !(value.place == source)) fail("The " + item.name + " is not in the " + items.at(*container).name + ".");
        if (value.place.kind == PlaceKind::Player) fail("You already have the " + item.name + ".");
        if (item.fixed) fail("The " + item.name + " is fixed in place.");
        if (!carried().count(id) && carriedWeight() + totalWeight(id) > maxWeight) fail("You can't carry any more.");
        value.place = player();
        return {"Taken."};
    }
    Lines drop(const Lines& phrase) {
        if (phrase.size() == 1 && phrase[0] == "all") {
            const auto candidates = contents(player());
            if (candidates.empty()) fail("You are empty-handed.");
            Lines rows;
            for (const auto& id : candidates) {
                state.items.at(id).place = floorOf(state.room);
                rows.push_back(items.at(id).name + ": Dropped.");
            }
            return rows;
        }
        const string id = resolve(phrase);
        if (!carried().count(id)) fail("You aren't carrying the " + items.at(id).name + ".");
        state.items.at(id).place = floorOf(state.room);
        return {"Dropped."};
    }
    optional<string> putItem(const string& id, const string& container) {
        const auto& item = items.at(id); const auto& target = items.at(container); auto& value = state.items.at(id);
        if (nestedIn(container, id)) return "The " + target.name + " is inside the " + item.name + ".";
        if (value.place == inside(container)) return "The " + item.name + " is already in the " + target.name + ".";
        const int weight = contentWeight(container) + (nestedIn(id, container) ? 0 : totalWeight(id));
        if (weight > *target.capacity) return "The " + item.name + " doesn't fit in the " + target.name + ".";
        value.place = inside(container);
        return nullopt;
    }
    Lines put(const Lines& first, const Lines& second) {
        if (first.size() == 1 && first[0] == "all") {
            const string target = resolve(second);
            requireContainer(target);
            auto candidates = contents(player());
            candidates.erase(remove(candidates.begin(), candidates.end(), target), candidates.end());
            if (candidates.empty()) fail("You have nothing to put in the " + items.at(target).name + ".");
            Lines rows;
            bool succeeded = false;
            for (const auto& id : candidates) {
                const auto reason = putItem(id, target);
                if (!reason) succeeded = true;
                rows.push_back(items.at(id).name + ": " + reason.value_or("Done."));
            }
            if (!succeeded) fail(move(rows));
            return rows;
        }
        const string id = resolve(first);
        const string target = resolve(second);
        const auto& item = items.at(id);
        if (!carried().count(id)) fail("You aren't carrying the " + item.name + ".");
        if (id == target) fail("You can't put the " + item.name + " inside itself.");
        requireContainer(target);
        if (const auto reason = putItem(id, target)) fail(*reason);
        return {"You put the " + item.name + " in the " + items.at(target).name + "."};
    }
    Lines keyCheck(const string& key, const optional<Lines>& phrase) {
        if (phrase) {
            const string id = resolve(*phrase);
            const auto& name = items.at(id).name;
            if (!carried().count(id)) fail("You aren't carrying the " + name + ".");
            if (id != key) fail("The " + name + " doesn't fit.");
            return {};
        }
        if (!carried().count(key)) fail("You don't have the right key.");
        return {"(with the " + items.at(key).name + ")"};
    }
    Lines lock(const Lines& first, const optional<Lines>& second, bool locking) {
        const auto direction = first.size() == 1 ? directionWord(first[0]) : nullopt;
        if (direction) {
            Exit* exit = exitAt(state.room, *direction);
            const string name = directionName(*direction);
            if (!exit) fail("There is no exit " + name + ".");
            if (!exit->key) fail("The way " + name + " has no lock.");
            if (exit->locked == locking) fail("The way " + name + (locking ? " is already locked." : " is not locked."));
            auto rows = keyCheck(*exit->key, second);
            exit->locked = locking;
            Exit* back = exitAt(exit->destination, opposite(*direction));
            if (back && back->destination == state.room && back->key == exit->key) back->locked = locking;
            rows.push_back(locking ? "Locked." : "Unlocked.");
            return rows;
        }
        const string id = resolve(first);
        const auto& item = items.at(id); auto& value = state.items.at(id);
        if (!item.capacity || !item.key) fail("The " + item.name + " has no lock.");
        if ((value.container == ContainerState::Locked) == locking) fail("The " + item.name + (locking ? " is already locked." : " is not locked."));
        if (locking && value.container == ContainerState::Open) fail("You must close the " + item.name + " first.");
        auto rows = keyCheck(*item.key, second);
        value.container = locking ? ContainerState::Locked : ContainerState::Closed;
        rows.push_back(locking ? "Locked." : "Unlocked.");
        return rows;
    }
    Lines execute(Verb verb, const Lines& first, const optional<Lines>& second) {
        switch (verb) {
            case Verb::Look: return describe();
            case Verb::Inventory: {
                if (contents(player()).empty()) return {"You are empty-handed."};
                Lines rows = {"You are carrying:"}; append(rows, tree(player()));
                rows.push_back("Total weight: " + to_string(carriedWeight()) + "/" + to_string(maxWeight));
                return rows;
            }
            case Verb::Wait: return {"Time passes."};
            case Verb::Score: {
                const auto value = score();
                return {"You have scored " + to_string(value.total) + " points (treasure " + to_string(value.points) + ", bonus " +
                    to_string(state.bonus) + ") in " + to_string(state.moves) + " moves.",
                    "Treasures stored: " + to_string(value.stored) + " of " + to_string(value.treasures) + "."};
            }
            case Verb::Save: saved = state; return {"Game saved."};
            case Verb::Restore: {
                if (!saved) fail("There is no saved game.");
                state = *saved;
                Lines rows = {"Game restored."}; append(rows, describe());
                return rows;
            }
            case Verb::Verbose: verbose = true; return {"Verbose mode."};
            case Verb::Brief: verbose = false; return {"Brief mode."};
            case Verb::Take: return take(first, second);
            case Verb::Drop: return drop(first);
            case Verb::Put: return put(first, *second);
            case Verb::Unlock: case Verb::Lock: return lock(first, second, verb == Verb::Lock);
            case Verb::Use: {
                const string id = resolve(first);
                const string target = resolve(*second);
                if (!carried().count(id)) fail("You aren't carrying the " + items.at(id).name + ".");
                auto result = runRules(rules, id, target);
                if (!result.executed) fail("Nothing happens.");
                return result.rows.empty() ? Lines{"Done."} : result.rows;
            }
            default: break;
        }
        const string id = resolve(first);
        const auto& item = items.at(id); auto& value = state.items.at(id);
        switch (verb) {
            case Verb::Examine: {
                Lines rows = item.details.empty() ? Lines{"You see nothing special about the " + item.name + "."} : item.details;
                if (item.light) rows.push_back(string("It is ") + (value.lit ? "lit" : "unlit") + " (fuel " + to_string(value.fuel) + ").");
                if (item.capacity) {
                    if (value.container != ContainerState::Open) rows.push_back("It is " + containerText(value.container) + ".");
                    else if (!contents(inside(id)).empty()) { rows.push_back("It contains:"); append(rows, tree(inside(id))); }
                    else rows.push_back("It is empty.");
                }
                if (item.points > 0) rows.push_back("It is a treasure worth " + to_string(item.points) + " points.");
                rows.push_back("It weighs " + to_string(totalWeight(id)) + ".");
                return rows;
            }
            case Verb::Open: {
                if (!item.capacity) fail("You can't open the " + item.name + ".");
                if (value.container == ContainerState::Open) fail("The " + item.name + " is already open.");
                if (value.container == ContainerState::Locked) fail("The " + item.name + " is locked.");
                value.container = ContainerState::Open;
                Lines names;
                for (const auto& child : contents(inside(id))) names.push_back(items.at(child).name);
                return names.empty() ? Lines{"Opened."} : Lines{"Opening the " + item.name + " reveals " + join(names, ", ") + "."};
            }
            case Verb::Close:
                if (!item.capacity) fail("You can't close the " + item.name + ".");
                if (value.container != ContainerState::Open) fail("The " + item.name + " is already closed.");
                value.container = ContainerState::Closed;
                return {"Closed."};
            case Verb::Light:
                if (!item.light) fail("You can't light the " + item.name + ".");
                if (value.lit) fail("The " + item.name + " is already lit.");
                if (value.fuel == 0) fail("The " + item.name + " has no fuel.");
                value.lit = true;
                return {"The " + item.name + " is now lit."};
            case Verb::Extinguish:
                if (!item.light) fail("You can't extinguish the " + item.name + ".");
                if (!value.lit) fail("The " + item.name + " is not lit.");
                value.lit = false;
                return {"The " + item.name + " is now out."};
            default: return {};
        }
    }
    Lines endTurn(bool baseline) {
        ++state.moves;
        auto nearby = carried();
        const auto ground = roomItems();
        nearby.insert(ground.begin(), ground.end());
        Lines rows;
        for (auto& [id, value] : state.items) if (value.lit && --value.fuel == 0) {
            value.lit = false;
            if (nearby.count(id)) rows.push_back("The " + items.at(id).name + " goes out.");
        }
        const bool lit = isLit();
        if (baseline && !lit) rows.push_back("It is now pitch dark.");
        else if (!baseline && lit) append(rows, describe());
        state.darkness = lit ? 0 : state.darkness + 1;
        if (state.darkness == 2) rows.push_back("You hear something moving in the dark.");
        if (state.darkness == 3) state.ended = EndState::Dead;
        const auto value = score();
        if (state.ended == EndState::None && value.treasures > 0 && value.stored == value.treasures) state.ended = EndState::Won;
        if (state.ended != EndState::None) {
            rows.push_back(state.ended == EndState::Dead ? "*** You have died ***" : "*** You have won ***");
            rows.push_back("You scored " + to_string(value.total) + " points in " + to_string(state.moves) + " moves.");
        }
        return rows;
    }
    Lines interpret(const string& line) {
        auto parts = normalized(line);
        if (parts.empty()) fail("I beg your pardon?");
        if (directionWord(parts[0])) parts.insert(parts.begin(), "go");
        const auto found = verbWords.find(parts[0]);
        if (found == verbWords.end()) fail("I don't know the verb \"" + parts[0] + "\".");
        Verb verb = found->second;
        auto rest = tail(parts, 1);
        if (state.ended != EndState::None && verb != Verb::Restore) fail("The game is over.");
        if (verb == Verb::Look && !rest.empty()) {
            if (rest[0] != "at") fail("I don't understand that.");
            verb = Verb::Examine; rest = tail(rest, 1);
        }
        Lines first = rest;
        optional<Lines> second;
        if (noObjects.count(verb)) {
            if (!rest.empty()) fail("I don't understand that.");
        } else {
            if (rest.empty()) fail(verb == Verb::Go ? "Which way do you want to go?" : "What do you want to " + verbNames[static_cast<size_t>(verb)] + "?");
            if (verb == Verb::Go) {
                if (rest.size() != 1 || !directionWord(rest[0])) fail("I don't understand that.");
            } else {
                set<string> prepositions;
                if (verb == Verb::Put) prepositions = {"in", "into"};
                else if (verb == Verb::Use) prepositions = {"on", "with"};
                else if ((verb == Verb::Unlock || verb == Verb::Lock) && find(rest.begin(), rest.end(), "with") != rest.end()) prepositions = {"with"};
                else if (verb == Verb::Take && find(rest.begin(), rest.end(), "from") != rest.end()) prepositions = {"from"};
                if (!prepositions.empty()) {
                    const auto split = find_if(rest.begin(), rest.end(), [&](const string& word) { return prepositions.count(word); });
                    if (split == rest.end() || split == rest.begin() || split + 1 == rest.end()) fail("I don't understand that.");
                    first = Lines(rest.begin(), split); second = Lines(split + 1, rest.end());
                }
            }
        }
        bool baseline = isLit();
        Lines rows;
        if (verb == Verb::Go) {
            const Direction direction = *directionWord(rest[0]);
            Exit* exit = exitAt(state.room, direction);
            if (!exit) fail("You can't go that way.");
            if (exit->locked) fail("The way " + directionName(direction) + " is locked.");
            state.room = exit->destination;
            baseline = isLit();
            rows = describe(verbose || !state.visited.count(state.room));
            state.visited.insert(state.room);
            append(rows, runRules(enterRules, state.room).rows);
        } else rows = execute(verb, first, second);
        if (actions.count(verb)) append(rows, endTurn(baseline));
        return rows;
    }

public:
    explicit Adventure(const Lines& definitions) {
        for (const auto& line : definitions) define(line);
        state.visited.insert(state.room);
        for (const auto& [id, item] : items) {
            vocabulary.insert(item.nouns.begin(), item.nouns.end());
            vocabulary.insert(item.adjectives.begin(), item.adjectives.end());
        }
    }
    Lines initialDescription() const { return describe(); }
    string finalScore() const { return "Final score: " + to_string(score().total) + " points in " + to_string(state.moves) + " moves."; }
    Lines command(const string& line) {
        try {
            const auto parts = normalized(line);
            if (!parts.empty() && (parts[0] == "again" || parts[0] == "g")) {
                if (parts.size() != 1) fail("I don't understand that.");
                if (!previous) fail("There is nothing to repeat.");
                return interpret(*previous);
            }
            previous = line;
            return interpret(line);
        } catch (const Failure& error) { return error.rows; }
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string line;
    Lines definitions;
    while (getline(cin, line) && line != "BEGIN") definitions.push_back(line);
    Adventure adventure(definitions);
    for (const auto& row : adventure.initialDescription()) cout << row << '\n';
    while (getline(cin, line)) {
        if (line == "QUIT") { cout << adventure.finalScore() << '\n'; break; }
        cout << "> " << line << '\n';
        for (const auto& row : adventure.command(line)) cout << row << '\n';
    }
}
