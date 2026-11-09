#include "dungeon.hpp"

MonsterType parseMonsterType(const Lines& words) { return {words[0], words[1][0], std::stoi(words[2]), std::stoi(words[3]), std::stoi(words[4]), parseDice(words[5]), std::stoi(words[6]), std::stoi(words[7]), parseDice(words[8]), std::stoi(words[9]), std::stoi(words[10]), words[11]}; }
ItemType parseItemType(const Lines& words) {
    ItemType kind; kind.category = words[0]; kind.name = words[1]; kind.minDepth = std::stoi(words[2]); kind.maxDepth = std::stoi(words[3]); kind.weight = std::stoi(words[4]);
    if (kind.category == "weapon") { kind.dice = parseDice(words[5]); kind.toHit = std::stoi(words[6]); }
    else if (kind.category == "armor") kind.armor = std::stoi(words[5]);
    else if (kind.category == "potion") { kind.effect = words[5]; if (kind.effect == "heal") kind.dice = parseDice(words[6]); else if (kind.effect == "poison") kind.poison = std::stoi(words[6]); }
    else if (kind.category == "scroll") kind.effect = words[5];
    else if (kind.category == "food") kind.nutrition = std::stoi(words[5]);
    else if (kind.category == "gold") kind.dice = parseDice(words[5]);
    return kind;
}
char Item::symbol() const { static const std::map<std::string, char> symbols{{"weapon", ')'}, {"armor", '['}, {"potion", '!'}, {"scroll", '?'}, {"food", '%'}, {"gold", '$'}, {"amulet", '"'}}; return symbols.at(kind.category); }
std::string Item::displayName() const {
    std::string name = kind.name; std::replace(name.begin(), name.end(), '_', ' ');
    if (kind.category == "weapon" || kind.category == "armor") return text('+', bonus, ' ', name);
    return kind.category == "gold" ? text(amount, " gold") : name;
}
std::string Item::referenceName() const { return kind.category == "gold" ? displayName() : "the " + displayName(); }
