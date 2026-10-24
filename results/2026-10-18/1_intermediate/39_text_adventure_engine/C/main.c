#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

enum { MAX_DEFINITIONS = 200, MAX_FLAGS = 400, MAX_WORDS = 51 };
static const char *directions[] = {"north", "south", "east", "west", "up", "down"};
typedef struct { char storage[101]; char *words[MAX_WORDS]; int count; } Words;
typedef struct { char **words; int count; } Phrase;
typedef struct { const char *lines[MAX_DEFINITIONS]; int count; } TextLines;
typedef struct { char id[13]; const char *name; bool dark; TextLines description; } Room;
typedef struct {
    char id[13]; const char *name; int weight, points, capacity, key;
    bool light, container, fixed; TextLines details;
} Item;
typedef enum { FLOOR, PLAYER, INSIDE, NOWHERE } PlaceKind;
typedef struct { PlaceKind kind; int index; } Place;
typedef enum { OPEN, CLOSED, LOCKED } ContainerState;
typedef struct { int destination, key; bool locked; } Exit;
typedef enum { NONE, WON, DEAD } EndStatus;
typedef struct {
    int room, bonus, moves, darkness;
    Place places[MAX_DEFINITIONS];
    ContainerState containers[MAX_DEFINITIONS];
    int fuel[MAX_DEFINITIONS];
    bool lit[MAX_DEFINITIONS], flags[MAX_FLAGS], visited[MAX_DEFINITIONS];
    Exit exits[MAX_DEFINITIONS][6];
    EndStatus ended;
} State;
typedef enum { MESSAGE, OPEN_EXIT, REMOVE_ITEM, ADD_ITEM, SET_FLAG, CLEAR_FLAG, POINTS } EffectKind;
typedef struct { EffectKind kind; int a, b, c; const char *text; } Effect;
typedef enum { ALWAYS, IF_FLAG, UNLESS_FLAG } Condition;
typedef struct { bool entry; int first, second, flag; Condition condition; Effect effect; } Rule;
typedef struct { int item; char word[13]; } Alias;
typedef enum {
    GO, LOOK, EXAMINE, TAKE, DROP, PUT, INVENTORY, OPEN_CONTAINER, CLOSE_CONTAINER,
    UNLOCK, LOCK, USE, LIGHT, EXTINGUISH, WAIT, SCORE, SAVE, RESTORE, VERBOSE, BRIEF
} Verb;

static char definitions[MAX_DEFINITIONS][101], flag_names[MAX_FLAGS][13];
static Room rooms[MAX_DEFINITIONS];
static Item items[MAX_DEFINITIONS];
static Alias aliases[MAX_DEFINITIONS];
static Rule rules[MAX_DEFINITIONS];
static int definition_count, room_count, item_count, flag_count, alias_count, rule_count;
static int ordered[MAX_DEFINITIONS], trophy, max_weight, pronoun = -1;
static State state, saved;
static bool has_save, verbose, has_previous;
static char previous[101];
static jmp_buf command_error;

static void fail(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    vprintf(format, arguments);
    va_end(arguments);
    putchar('\n');
    longjmp(command_error, 1);
}

static void split_words(const char *line, Words *result) {
    strcpy(result->storage, line);
    result->count = 0;
    for (char *word = strtok(result->storage, " "); word; word = strtok(NULL, " "))
        result->words[result->count++] = word;
}

static void normalize(const char *line, Words *result) {
    split_words(line, result);
    int count = 0;
    for (int i = 0; i < result->count; ++i) {
        char *word = result->words[i];
        for (char *p = word; *p; ++p) if (*p >= 'A' && *p <= 'Z') *p += 'a' - 'A';
        if (strcmp(word, "the") && strcmp(word, "a") && strcmp(word, "an")) result->words[count++] = word;
    }
    result->count = count;
}

static int direction(const char *word) {
    for (int i = 0; i < 6; ++i)
        if (!strcmp(word, directions[i]) || (word[0] == directions[i][0] && !word[1])) return i;
    return -1;
}

static int room_id(const char *id) {
    for (int i = 0; i < room_count; ++i) if (!strcmp(rooms[i].id, id)) return i;
    abort();
}

static int item_id(const char *id) {
    for (int i = 0; i < item_count; ++i) if (!strcmp(items[i].id, id)) return i;
    abort();
}

static int flag_id(const char *id) {
    for (int i = 0; i < flag_count; ++i) if (!strcmp(flag_names[i], id)) return i;
    strcpy(flag_names[flag_count], id);
    return flag_count++;
}

static const char *remaining(const char *line, const Words *words, int at) {
    return line + (words->words[at] - words->storage);
}

static Effect read_effect(const char *line, const Words *words, int at) {
    char *const *w = words->words;
    Effect effect = {0};
    if (!strcmp(w[at], "MESSAGE")) { effect.kind = MESSAGE; effect.text = remaining(line, words, at + 1); }
    else if (!strcmp(w[at], "OPEN")) {
        effect.kind = OPEN_EXIT; effect.a = room_id(w[at + 1]); effect.b = direction(w[at + 2]); effect.c = room_id(w[at + 3]);
    } else if (!strcmp(w[at], "REMOVE")) { effect.kind = REMOVE_ITEM; effect.a = item_id(w[at + 1]); }
    else if (!strcmp(w[at], "ADD")) { effect.kind = ADD_ITEM; effect.a = item_id(w[at + 1]); effect.b = room_id(w[at + 2]); }
    else if (!strcmp(w[at], "SET")) { effect.kind = SET_FLAG; effect.a = flag_id(w[at + 1]); }
    else if (!strcmp(w[at], "CLEAR")) { effect.kind = CLEAR_FLAG; effect.a = flag_id(w[at + 1]); }
    else { effect.kind = POINTS; effect.a = atoi(w[at + 1]); }
    return effect;
}

static int compare_items(const void *a, const void *b) {
    return strcmp(items[*(const int *)a].id, items[*(const int *)b].id);
}

static void build_world(void) {
    for (int i = 0; i < definition_count; ++i) {
        Words words; split_words(definitions[i], &words);
        if (!strcmp(words.words[0], "ROOM")) strcpy(rooms[room_count++].id, words.words[1]);
        else if (!strcmp(words.words[0], "ITEM")) strcpy(items[item_count++].id, words.words[1]);
    }
    for (int r = 0; r < room_count; ++r) for (int d = 0; d < 6; ++d) state.exits[r][d] = (Exit){-1, -1, false};
    for (int i = 0; i < item_count; ++i) { state.places[i] = (Place){NOWHERE, 0}; items[i].key = -1; ordered[i] = i; }
    for (int i = 0; i < definition_count; ++i) {
        const char *line = definitions[i];
        Words words; split_words(line, &words); char **w = words.words;
        if (!strcmp(w[0], "ROOM")) {
            Room *room = &rooms[room_id(w[1])]; room->dark = !strcmp(w[2], "DARK");
            room->name = remaining(line, &words, room->dark ? 3 : 2);
        } else if (!strcmp(w[0], "DESC")) {
            TextLines *text = &rooms[room_id(w[1])].description;
            text->lines[text->count++] = remaining(line, &words, 2);
        } else if (!strcmp(w[0], "EXIT")) {
            bool locked = words.count > 4;
            state.exits[room_id(w[1])][direction(w[2])] = (Exit){room_id(w[3]), locked ? item_id(w[5]) : -1, locked};
        } else if (!strcmp(w[0], "ITEM")) {
            int id = item_id(w[1]), at = 4; Item *item = &items[id];
            state.places[id] = !strcmp(w[2], "PLAYER") ? (Place){PLAYER, 0} : !strcmp(w[2], "NOWHERE") ? (Place){NOWHERE, 0} : (Place){FLOOR, room_id(w[2])};
            item->weight = atoi(w[3]);
            if (!strcmp(w[at], "TREASURE")) { item->points = atoi(w[at + 1]); at += 2; }
            if (!strcmp(w[at], "LIGHT")) { item->light = true; state.fuel[id] = atoi(w[at + 1]); at += 2; }
            if (!strcmp(w[at], "CONTAINER")) {
                item->container = true; item->capacity = atoi(w[at + 1]); at += 2;
                if (!strcmp(w[at], "CLOSED")) { state.containers[id] = CLOSED; ++at; }
                if (!strcmp(w[at], "LOCKED")) { item->key = item_id(w[at + 1]); state.containers[id] = LOCKED; at += 2; }
            }
            if (!strcmp(w[at], "FIXED")) { item->fixed = true; ++at; }
            item->name = remaining(line, &words, at);
        } else if (!strcmp(w[0], "INSIDE")) state.places[item_id(w[1])] = (Place){INSIDE, item_id(w[2])};
        else if (!strcmp(w[0], "ALIAS")) {
            aliases[alias_count].item = item_id(w[1]); strcpy(aliases[alias_count++].word, w[2]);
        } else if (!strcmp(w[0], "DETAIL")) {
            TextLines *text = &items[item_id(w[1])].details;
            text->lines[text->count++] = remaining(line, &words, 2);
        } else if (!strcmp(w[0], "RULE") || !strcmp(w[0], "ENTER")) {
            Rule rule = {0}; rule.entry = !strcmp(w[0], "ENTER");
            rule.first = rule.entry ? room_id(w[1]) : item_id(w[1]);
            int at = rule.entry ? 2 : 3;
            if (!rule.entry) rule.second = item_id(w[2]);
            if (!strcmp(w[at], "IF") || !strcmp(w[at], "UNLESS")) {
                rule.condition = !strcmp(w[at], "IF") ? IF_FLAG : UNLESS_FLAG;
                rule.flag = flag_id(w[at + 1]); at += 2;
            }
            rule.effect = read_effect(line, &words, at); rules[rule_count++] = rule;
        } else if (!strcmp(w[0], "TROPHY")) trophy = room_id(w[1]);
        else if (!strcmp(w[0], "START")) state.room = room_id(w[1]);
        else if (!strcmp(w[0], "MAXWEIGHT")) max_weight = atoi(w[1]);
    }
    state.visited[state.room] = true;
    qsort(ordered, item_count, sizeof(*ordered), compare_items);
}

static bool same_place(Place a, Place b) { return a.kind == b.kind && a.index == b.index; }

static bool reachable(int item, Place root) {
    Place place = state.places[item];
    while (place.kind == INSIDE) {
        if (state.containers[place.index] != OPEN) return false;
        place = state.places[place.index];
    }
    return same_place(place, root);
}

static bool carried(int item) { return reachable(item, (Place){PLAYER, 0}); }
static bool room_item(int item) { return reachable(item, (Place){FLOOR, state.room}); }

static bool room_lit(void) {
    if (!rooms[state.room].dark) return true;
    for (int i = 0; i < item_count; ++i) if (state.lit[i] && (carried(i) || room_item(i))) return true;
    return false;
}

static int total_weight(int item) {
    int weight = items[item].weight;
    for (int i = 0; i < item_count; ++i) if (same_place(state.places[i], (Place){INSIDE, item})) weight += total_weight(i);
    return weight;
}

static int place_weight(Place place) {
    int weight = 0;
    for (int i = 0; i < item_count; ++i) if (same_place(state.places[i], place)) weight += total_weight(i);
    return weight;
}

static bool nested_in(int item, int ancestor) {
    Place place = state.places[item];
    while (place.kind == INSIDE) {
        if (place.index == ancestor) return true;
        place = state.places[place.index];
    }
    return false;
}

static bool stored(int item) {
    Place place = state.places[item];
    while (place.kind == INSIDE) place = state.places[place.index];
    return same_place(place, (Place){FLOOR, trophy});
}

static int treasure_points(void) {
    int result = 0;
    for (int i = 0; i < item_count; ++i) if (items[i].points && stored(i)) result += items[i].points;
    return result;
}

static int score(void) { return state.bonus + treasure_points(); }

static int children(Place place, int *result) {
    int count = 0;
    for (int i = 0; i < item_count; ++i) if (same_place(state.places[ordered[i]], place)) result[count++] = ordered[i];
    return count;
}

static void display_name(int item) {
    fputs(items[item].name, stdout);
    bool container = items[item].container, lit = items[item].light && state.lit[item];
    if (!container && !lit) return;
    fputs(" (", stdout);
    if (container) fputs(state.containers[item] == OPEN ? "open" : state.containers[item] == CLOSED ? "closed" : "locked", stdout);
    if (container && lit) fputs(", ", stdout);
    if (lit) fputs("lit", stdout);
    putchar(')');
}

static void item_tree(Place place, int depth) {
    for (int i = 0; i < item_count; ++i) {
        int item = ordered[i];
        if (!same_place(state.places[item], place)) continue;
        printf("%*s", 2 * depth, ""); display_name(item); putchar('\n');
        if (items[item].container && state.containers[item] == OPEN) item_tree((Place){INSIDE, item}, depth + 1);
    }
}

static void describe(bool full) {
    if (!room_lit()) { puts("It is pitch dark."); return; }
    Room *room = &rooms[state.room];
    puts(room->name);
    if (full) for (int i = 0; i < room->description.count; ++i) puts(room->description.lines[i]);
    fputs("Exits: ", stdout);
    int count = 0;
    for (int d = 0; d < 6; ++d) if (state.exits[state.room][d].destination >= 0) {
        if (count++) fputs(", ", stdout);
        fputs(directions[d], stdout);
        if (state.exits[state.room][d].locked) fputs(" (locked)", stdout);
    }
    if (!count) fputs("none", stdout);
    putchar('\n');
    int direct[MAX_DEFINITIONS];
    if (children((Place){FLOOR, state.room}, direct)) { puts("You see:"); item_tree((Place){FLOOR, state.room}, 1); }
}

static bool name_word(const char *name, const char *word) {
    size_t length = strlen(word);
    for (const char *p = name; *p;) {
        const char *end = strchr(p, ' ');
        size_t n = end ? (size_t)(end - p) : strlen(p);
        if (length == n && !strncmp(p, word, n)) return true;
        if (!end) break;
        p = end + 1;
    }
    return false;
}

static bool noun(int item, const char *word) {
    if (!strcmp(items[item].id, word)) return true;
    for (int i = 0; i < alias_count; ++i) if (aliases[i].item == item && !strcmp(aliases[i].word, word)) return true;
    return false;
}

static bool known_word(const char *word) {
    for (int i = 0; i < item_count; ++i) if (noun(i, word) || name_word(items[i].name, word)) return true;
    return false;
}

static int resolve(Phrase phrase) {
    bool lit = room_lit();
    if (phrase.count == 1 && !strcmp(phrase.words[0], "it")) {
        if (pronoun < 0) fail("I don't know what \"it\" refers to.");
        if (!carried(pronoun) && !(lit && room_item(pronoun))) fail("You can't see any such thing.");
        return pronoun;
    }
    for (int i = 0; i < phrase.count; ++i) if (!known_word(phrase.words[i])) fail("I don't know the word \"%s\".", phrase.words[i]);
    int candidates[MAX_DEFINITIONS], count = 0;
    for (int i = 0; i < item_count; ++i) {
        int item = ordered[i];
        if ((!carried(item) && !(lit && room_item(item))) || !noun(item, phrase.words[phrase.count - 1])) continue;
        bool matches = true;
        for (int j = 0; j + 1 < phrase.count; ++j) if (!name_word(items[item].name, phrase.words[j])) matches = false;
        if (matches) candidates[count++] = item;
    }
    if (!count) fail("You can't see any such thing.");
    if (count > 1) {
        fputs("Which do you mean: ", stdout);
        for (int i = 0; i < count; ++i) { if (i) fputs(", ", stdout); fputs(items[candidates[i]].name, stdout); }
        puts("?"); longjmp(command_error, 1);
    }
    return pronoun = candidates[0];
}

static int execute_rules(bool entry, int first, int second, bool *message) {
    int executed = 0;
    for (int i = 0; i < rule_count; ++i) {
        const Rule *rule = &rules[i];
        if (rule->entry != entry || rule->first != first || (!entry && rule->second != second)) continue;
        if ((rule->condition == IF_FLAG && !state.flags[rule->flag]) || (rule->condition == UNLESS_FLAG && state.flags[rule->flag])) continue;
        ++executed;
        Effect effect = rule->effect;
        switch (effect.kind) {
            case MESSAGE: puts(effect.text); *message = true; break;
            case OPEN_EXIT: state.exits[effect.a][effect.b] = (Exit){effect.c, -1, false}; break;
            case REMOVE_ITEM: state.places[effect.a] = (Place){NOWHERE, 0}; break;
            case ADD_ITEM: state.places[effect.a] = (Place){FLOOR, effect.b}; break;
            case SET_FLAG: state.flags[effect.a] = true; break;
            case CLEAR_FLAG: state.flags[effect.a] = false; break;
            case POINTS: state.bonus += effect.a; break;
        }
    }
    return executed;
}

static void pass_turn(bool baseline) {
    ++state.moves;
    bool nearby[MAX_DEFINITIONS];
    for (int i = 0; i < item_count; ++i) nearby[i] = carried(i) || room_item(i);
    for (int i = 0; i < item_count; ++i) {
        int item = ordered[i];
        if (state.lit[item] && --state.fuel[item] == 0) {
            state.lit[item] = false;
            if (nearby[item]) printf("The %s goes out.\n", items[item].name);
        }
    }
    bool lit = room_lit();
    if (baseline && !lit) puts("It is now pitch dark.");
    else if (!baseline && lit) describe(true);
    state.darkness = lit ? 0 : state.darkness + 1;
    if (state.darkness == 2) puts("You hear something moving in the dark.");
    if (state.darkness == 3) state.ended = DEAD;
    if (state.ended == NONE) {
        int treasures = 0, count = 0;
        for (int i = 0; i < item_count; ++i) if (items[i].points) { ++treasures; if (stored(i)) ++count; }
        if (treasures > 0 && count == treasures) state.ended = WON;
    }
    if (state.ended != NONE) {
        puts(state.ended == DEAD ? "*** You have died ***" : "*** You have won ***");
        printf("You scored %d points in %d moves.\n", score(), state.moves);
    }
}

static bool all_form(Phrase phrase) { return phrase.count == 1 && !strcmp(phrase.words[0], "all"); }

static bool put_item(int item, int container, char *reason) {
    if (nested_in(container, item)) {
        snprintf(reason, 256, "The %s is inside the %s.", items[container].name, items[item].name);
        return false;
    }
    if (same_place(state.places[item], (Place){INSIDE, container})) {
        snprintf(reason, 256, "The %s is already in the %s.", items[item].name, items[container].name);
        return false;
    }
    int weight = place_weight((Place){INSIDE, container});
    if (!nested_in(item, container)) weight += total_weight(item);
    if (weight > items[container].capacity) {
        snprintf(reason, 256, "The %s doesn't fit in the %s.", items[item].name, items[container].name);
        return false;
    }
    state.places[item] = (Place){INSIDE, container};
    return true;
}

static bool take_items(Phrase target, Phrase from) {
    if (!room_lit()) fail("It is pitch dark.");
    Place source = {FLOOR, state.room};
    int container = -1;
    if (from.count) {
        container = resolve(from);
        if (!items[container].container) fail("The %s is not a container.", items[container].name);
        if (state.containers[container] != OPEN) fail("The %s is closed.", items[container].name);
        source = (Place){INSIDE, container};
    }
    if (all_form(target)) {
        int candidates[MAX_DEFINITIONS], length = children(source, candidates), count = 0;
        for (int i = 0; i < length; ++i) if (!items[candidates[i]].fixed) candidates[count++] = candidates[i];
        if (!count) {
            if (container < 0) fail("There is nothing here to take.");
            fail("There is nothing in the %s to take.", items[container].name);
        }
        bool success = false;
        for (int i = 0; i < count; ++i) {
            int item = candidates[i];
            if (!carried(item) && place_weight((Place){PLAYER, 0}) + total_weight(item) > max_weight)
                printf("%s: You can't carry any more.\n", items[item].name);
            else { state.places[item] = (Place){PLAYER, 0}; printf("%s: Taken.\n", items[item].name); success = true; }
        }
        return success;
    }
    int item = resolve(target);
    if (container >= 0 && !same_place(state.places[item], source)) fail("The %s is not in the %s.", items[item].name, items[container].name);
    if (same_place(state.places[item], (Place){PLAYER, 0})) fail("You already have the %s.", items[item].name);
    if (items[item].fixed) fail("The %s is fixed in place.", items[item].name);
    if (!carried(item) && place_weight((Place){PLAYER, 0}) + total_weight(item) > max_weight) fail("You can't carry any more.");
    state.places[item] = (Place){PLAYER, 0}; puts("Taken.");
    return true;
}

static void drop_items(Phrase target) {
    if (all_form(target)) {
        int candidates[MAX_DEFINITIONS], count = children((Place){PLAYER, 0}, candidates);
        if (!count) fail("You are empty-handed.");
        for (int i = 0; i < count; ++i) {
            int item = candidates[i]; state.places[item] = (Place){FLOOR, state.room};
            printf("%s: Dropped.\n", items[item].name);
        }
    } else {
        int item = resolve(target);
        if (!carried(item)) fail("You aren't carrying the %s.", items[item].name);
        state.places[item] = (Place){FLOOR, state.room}; puts("Dropped.");
    }
}

static bool put_items(Phrase first, Phrase second) {
    int item = all_form(first) ? -1 : resolve(first);
    int container = resolve(second);
    if (item >= 0) {
        if (!carried(item)) fail("You aren't carrying the %s.", items[item].name);
        if (item == container) fail("You can't put the %s inside itself.", items[item].name);
    }
    if (!items[container].container) fail("The %s is not a container.", items[container].name);
    if (state.containers[container] != OPEN) fail("The %s is closed.", items[container].name);
    char reason[256];
    if (item >= 0) {
        if (!put_item(item, container, reason)) fail("%s", reason);
        printf("You put the %s in the %s.\n", items[item].name, items[container].name);
        return true;
    }
    int candidates[MAX_DEFINITIONS], length = children((Place){PLAYER, 0}, candidates), count = 0;
    for (int i = 0; i < length; ++i) if (candidates[i] != container) candidates[count++] = candidates[i];
    if (!count) fail("You have nothing to put in the %s.", items[container].name);
    bool success = false;
    for (int i = 0; i < count; ++i) {
        int candidate = candidates[i];
        bool done = put_item(candidate, container, reason);
        printf("%s: %s\n", items[candidate].name, done ? "Done." : reason);
        success = success || done;
    }
    return success;
}

static void key_check(int key, Phrase explicit_key) {
    if (explicit_key.count) {
        int item = resolve(explicit_key);
        if (!carried(item)) fail("You aren't carrying the %s.", items[item].name);
        if (item != key) fail("The %s doesn't fit.", items[item].name);
    } else {
        if (!carried(key)) fail("You don't have the right key.");
        printf("(with the %s)\n", items[key].name);
    }
}

static void change_lock(Phrase target, Phrase explicit_key, bool locking) {
    int d = target.count == 1 ? direction(target.words[0]) : -1;
    if (d >= 0) {
        Exit *exit = &state.exits[state.room][d];
        if (exit->destination < 0) fail("There is no exit %s.", directions[d]);
        if (exit->key < 0) fail("The way %s has no lock.", directions[d]);
        if (exit->locked == locking) fail(locking ? "The way %s is already locked." : "The way %s is not locked.", directions[d]);
        key_check(exit->key, explicit_key);
        exit->locked = locking;
        Exit *opposite = &state.exits[exit->destination][d ^ 1];
        if (opposite->destination == state.room && opposite->key == exit->key) opposite->locked = locking;
    } else {
        int item = resolve(target);
        if (!items[item].container || items[item].key < 0) fail("The %s has no lock.", items[item].name);
        if ((state.containers[item] == LOCKED) == locking) fail(locking ? "The %s is already locked." : "The %s is not locked.", items[item].name);
        if (locking && state.containers[item] == OPEN) fail("You must close the %s first.", items[item].name);
        key_check(items[item].key, explicit_key);
        state.containers[item] = locking ? LOCKED : CLOSED;
    }
    puts(locking ? "Locked." : "Unlocked.");
}

static void examine(int item) {
    Item *definition = &items[item];
    if (!definition->details.count) printf("You see nothing special about the %s.\n", definition->name);
    else for (int i = 0; i < definition->details.count; ++i) puts(definition->details.lines[i]);
    if (definition->light) printf("It is %s (fuel %d).\n", state.lit[item] ? "lit" : "unlit", state.fuel[item]);
    if (definition->container) {
        if (state.containers[item] == LOCKED) puts("It is locked.");
        else if (state.containers[item] == CLOSED) puts("It is closed.");
        else {
            int direct[MAX_DEFINITIONS];
            if (children((Place){INSIDE, item}, direct)) { puts("It contains:"); item_tree((Place){INSIDE, item}, 1); }
            else puts("It is empty.");
        }
    }
    if (definition->points) printf("It is a treasure worth %d points.\n", definition->points);
    printf("It weighs %d.\n", total_weight(item));
}

static bool execute(Verb verb, Phrase first, Phrase second, int d, bool *baseline) {
    switch (verb) {
        case GO: {
            Exit exit = state.exits[state.room][d];
            if (exit.destination < 0) fail("You can't go that way.");
            if (exit.locked) fail("The way %s is locked.", directions[d]);
            state.room = exit.destination; *baseline = room_lit();
            describe(verbose || !state.visited[state.room]); state.visited[state.room] = true;
            bool message = false; execute_rules(true, state.room, 0, &message);
            break;
        }
        case LOOK: describe(true); break;
        case EXAMINE: examine(resolve(first)); break;
        case TAKE: return take_items(first, second);
        case DROP: drop_items(first); break;
        case PUT: return put_items(first, second);
        case INVENTORY: {
            int direct[MAX_DEFINITIONS];
            if (!children((Place){PLAYER, 0}, direct)) puts("You are empty-handed.");
            else { puts("You are carrying:"); item_tree((Place){PLAYER, 0}, 1); printf("Total weight: %d/%d\n", place_weight((Place){PLAYER, 0}), max_weight); }
            break;
        }
        case OPEN_CONTAINER: {
            int item = resolve(first);
            if (!items[item].container) fail("You can't open the %s.", items[item].name);
            if (state.containers[item] == OPEN) fail("The %s is already open.", items[item].name);
            if (state.containers[item] == LOCKED) fail("The %s is locked.", items[item].name);
            state.containers[item] = OPEN;
            int direct[MAX_DEFINITIONS], count = children((Place){INSIDE, item}, direct);
            if (!count) puts("Opened.");
            else {
                printf("Opening the %s reveals ", items[item].name);
                for (int i = 0; i < count; ++i) { if (i) fputs(", ", stdout); fputs(items[direct[i]].name, stdout); }
                puts(".");
            }
            break;
        }
        case CLOSE_CONTAINER: {
            int item = resolve(first);
            if (!items[item].container) fail("You can't close the %s.", items[item].name);
            if (state.containers[item] != OPEN) fail("The %s is already closed.", items[item].name);
            state.containers[item] = CLOSED; puts("Closed."); break;
        }
        case UNLOCK: case LOCK: change_lock(first, second, verb == LOCK); break;
        case USE: {
            int a = resolve(first);
            int b = resolve(second);
            if (!carried(a)) fail("You aren't carrying the %s.", items[a].name);
            bool message = false;
            if (!execute_rules(false, a, b, &message)) fail("Nothing happens.");
            if (!message) puts("Done.");
            break;
        }
        case LIGHT: {
            int item = resolve(first);
            if (!items[item].light) fail("You can't light the %s.", items[item].name);
            if (state.lit[item]) fail("The %s is already lit.", items[item].name);
            if (!state.fuel[item]) fail("The %s has no fuel.", items[item].name);
            state.lit[item] = true; printf("The %s is now lit.\n", items[item].name); break;
        }
        case EXTINGUISH: {
            int item = resolve(first);
            if (!items[item].light) fail("You can't extinguish the %s.", items[item].name);
            if (!state.lit[item]) fail("The %s is not lit.", items[item].name);
            state.lit[item] = false; printf("The %s is now out.\n", items[item].name); break;
        }
        case WAIT: puts("Time passes."); break;
        case SCORE: {
            int points = treasure_points(), treasures = 0, count = 0;
            for (int i = 0; i < item_count; ++i) if (items[i].points) { ++treasures; if (stored(i)) ++count; }
            printf("You have scored %d points (treasure %d, bonus %d) in %d moves.\n", points + state.bonus, points, state.bonus, state.moves);
            printf("Treasures stored: %d of %d.\n", count, treasures); break;
        }
        case SAVE: saved = state; has_save = true; puts("Game saved."); break;
        case RESTORE:
            if (!has_save) fail("There is no saved game.");
            state = saved; puts("Game restored."); describe(true); break;
        case VERBOSE: verbose = true; puts("Verbose mode."); break;
        case BRIEF: verbose = false; puts("Brief mode."); break;
    }
    return true;
}

static const char *verb_names[] = {
    "go", "look", "examine", "take", "drop", "put", "inventory", "open", "close", "unlock",
    "lock", "use", "light", "extinguish", "wait", "score", "save", "restore", "verbose", "brief"
};
static const char *verb_aliases[] = {
    "go walk run", "look l", "examine x inspect read", "take get grab", "drop discard", "put insert place",
    "inventory inv i", "open", "close shut", "unlock", "lock", "use apply", "light ignite",
    "extinguish douse snuff", "wait z", "score", "save", "restore load", "verbose", "brief"
};

static bool no_arguments(Verb verb) {
    return verb == LOOK || verb == INVENTORY || verb == WAIT || verb == SCORE || verb == SAVE || verb == RESTORE || verb == VERBOSE || verb == BRIEF;
}

static bool action(Verb verb) {
    return verb == GO || verb == TAKE || verb == DROP || verb == PUT || verb == OPEN_CONTAINER || verb == CLOSE_CONTAINER ||
        verb == UNLOCK || verb == LOCK || verb == USE || verb == LIGHT || verb == EXTINGUISH || verb == WAIT;
}

static void interpret(Words *words) {
    if (!words->count) fail("I beg your pardon?");
    if (direction(words->words[0]) >= 0) {
        memmove(words->words + 1, words->words, words->count * sizeof(*words->words));
        words->words[0] = "go"; ++words->count;
    }
    int parsed = -1;
    for (int i = 0; i < 20; ++i) if (name_word(verb_aliases[i], words->words[0])) { parsed = i; break; }
    if (parsed < 0) fail("I don't know the verb \"%s\".", words->words[0]);
    Verb verb = (Verb)parsed;
    if (state.ended != NONE && verb != RESTORE) fail("The game is over.");
    Phrase first = {words->words + 1, words->count - 1}, second = {NULL, 0};
    if (verb == LOOK && first.count) {
        if (strcmp(first.words[0], "at")) fail("I don't understand that.");
        verb = EXAMINE; ++first.words; --first.count;
    }
    int d = -1;
    if (no_arguments(verb)) {
        if (first.count) fail("I don't understand that.");
    } else {
        if (!first.count) {
            if (verb == GO) fail("Which way do you want to go?");
            fail("What do you want to %s?", verb_names[verb]);
        }
        if (verb == GO) {
            if (first.count != 1 || (d = direction(first.words[0])) < 0) fail("I don't understand that.");
        } else {
            int split = -1;
            for (int i = 0; i < first.count; ++i) {
                const char *word = first.words[i];
                bool preposition = (verb == PUT && (!strcmp(word, "in") || !strcmp(word, "into"))) ||
                    (verb == USE && (!strcmp(word, "on") || !strcmp(word, "with"))) ||
                    ((verb == LOCK || verb == UNLOCK) && !strcmp(word, "with")) || (verb == TAKE && !strcmp(word, "from"));
                if (preposition) { split = i; break; }
            }
            if (split >= 0) {
                if (!split || split + 1 == first.count) fail("I don't understand that.");
                second = (Phrase){first.words + split + 1, first.count - split - 1}; first.count = split;
            } else if (verb == PUT || verb == USE) fail("I don't understand that.");
        }
    }
    bool baseline = room_lit();
    if (execute(verb, first, second, d, &baseline) && action(verb)) pass_turn(baseline);
}

static void process_line(const char *line) {
    if (setjmp(command_error)) return;
    Words words; normalize(line, &words);
    if (words.count && (!strcmp(words.words[0], "again") || !strcmp(words.words[0], "g"))) {
        if (words.count != 1) fail("I don't understand that.");
        if (!has_previous) fail("There is nothing to repeat.");
        normalize(previous, &words);
    } else { strcpy(previous, line); has_previous = true; }
    interpret(&words);
}

int main(void) {
    char line[102];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (!strcmp(line, "BEGIN")) break;
        strcpy(definitions[definition_count++], line);
    }
    build_world(); describe(true);
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (!strcmp(line, "QUIT")) break;
        printf("> %s\n", line); process_line(line);
    }
    printf("Final score: %d points in %d moves.\n", score(), state.moves);
    return 0;
}
