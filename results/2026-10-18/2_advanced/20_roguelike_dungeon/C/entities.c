#include "dungeon.h"

MonsterType parse_monster_type(char **tokens) {
    MonsterType result = {0};
    result.name = tokens[0]; result.symbol = tokens[1][0];
    result.min_depth = atoi(tokens[2]); result.max_depth = atoi(tokens[3]); result.weight = atoi(tokens[4]);
    result.hp = parse_dice(tokens[5]); result.to_hit = atoi(tokens[6]); result.defense = atoi(tokens[7]);
    result.damage = parse_dice(tokens[8]); result.speed = atoi(tokens[9]); result.xp = atoi(tokens[10]);
    result.erratic = strchr(tokens[11], 'E') != NULL;
    result.stationary = strchr(tokens[11], 'S') != NULL;
    result.regenerates = strchr(tokens[11], 'R') != NULL;
    result.poisonous = strchr(tokens[11], 'P') != NULL;
    return result;
}

ItemType parse_item_type(char **tokens) {
    const char *classes[] = {"weapon", "armor", "potion", "scroll", "food", "gold"};
    ItemType result = {0};
    for (int i = 0; i < 6; ++i) if (!strcmp(tokens[0], classes[i])) result.category = (enum ItemClass)i;
    result.name = tokens[1];
    result.min_depth = atoi(tokens[2]); result.max_depth = atoi(tokens[3]); result.weight = atoi(tokens[4]);
    if (result.category == WEAPON) { result.dice = parse_dice(tokens[5]); result.to_hit = atoi(tokens[6]); }
    else if (result.category == ARMOR) result.armor = atoi(tokens[5]);
    else if (result.category == POTION) {
        result.effect = tokens[5];
        if (!strcmp(result.effect, "heal")) result.dice = parse_dice(tokens[6]);
        else if (!strcmp(result.effect, "poison")) result.poison_turns = atoi(tokens[6]);
    } else if (result.category == SCROLL) result.effect = tokens[5];
    else if (result.category == FOOD) result.nutrition = atoi(tokens[5]);
    else if (result.category == GOLD) result.dice = parse_dice(tokens[5]);
    return result;
}

char item_symbol(const Item *item) { static const char symbols[] = ")[!?%$\""; return symbols[item->kind->category]; }

char *display_name(const Item *item) {
    char *name = format("%s", item->kind->name);
    for (char *character = name; *character; ++character) if (*character == '_') *character = ' ';
    if (item->kind->category == WEAPON || item->kind->category == ARMOR) return format("+%d %s", item->bonus, name);
    if (item->kind->category == GOLD) return format("%d gold", item->amount);
    return name;
}

char *reference_name(const Item *item) { return item->kind->category == GOLD ? display_name(item) : format("the %s", display_name(item)); }
