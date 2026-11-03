#include "crossword.h"

static const char *outcomes[] = {"filled", "unfillable", "budget"};
static const int letter_points[] = {1,3,3,2,1,4,2,4,1,8,5,1,3,1,1,3,10,1,1,1,1,4,4,8,4,10};
typedef struct { int node_budget, min_score, relax_step, weak_score; char *symmetry; } Settings;
typedef struct { WordIndex index; int lines; Lines invalid, duplicates; } WordList;
typedef struct { int word, number, uses; char *text; } Clue;
typedef struct { Clue clues[200]; int count, entries; Lines invalid, unknown; } ClueBook;
typedef struct {
    char *name; Lines options, rows; int budget, min_score; char *symmetry, *error;
    char *themes[400]; int theme_count;
    Layout layout; State initial; bool theme_slots[150];
    Attempt *attempts[100], *final; int attempt_count;
    State *state; char *chosen[150];
} Template;

static Lines read_lines(const char *name) {
    FILE *file = fopen(format("input/%s", name), "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines result = {0};
    Text line = {0};
    int character;
    while ((character = fgetc(file)) != EOF) {
        if (character == '\n') {
            add_line(&result, "%s", line.data ? line.data : "");
            line.size = 0;
            if (line.data) line.data[0] = '\0';
        } else text_add(&line, "%c", character);
    }
    if (ferror(file)) exit(EXIT_FAILURE);
    fclose(file);
    return result;
}

static bool ignored(const char *line) { return !line[0] || line[0] == '#'; }

static Settings read_settings(void) {
    Settings result = {0};
    Lines source = read_lines("params.txt");
    for (int i = 0; i < source.count; ++i) {
        char *line = source.items[i];
        if (ignored(line)) continue;
        char *space = strchr(line, ' ');
        *space = '\0';
        char *value = space + 1;
        if (!strcmp(line, "node_budget")) result.node_budget = atoi(value);
        else if (!strcmp(line, "min_score")) result.min_score = atoi(value);
        else if (!strcmp(line, "relax_step")) result.relax_step = atoi(value);
        else if (!strcmp(line, "weak_score")) result.weak_score = atoi(value);
        else result.symmetry = value;
    }
    return result;
}

static WordList *read_words(void) {
    WordList *result = allocate(sizeof(*result));
    Lines source = read_lines("words.txt");
    result->lines = source.count;
    for (int i = 0; i < source.count; ++i) {
        char *line = source.items[i];
        const char *error = word_line_error(line);
        if (error) { add_line(&result->invalid, "invalid %d %s", i + 1, error); continue; }
        char *space = strchr(line, ' ');
        *space = '\0';
        int existing = find_word(&result->index, line);
        if (existing >= 0) add_line(&result->duplicates, "duplicate %d %s first=%d", i + 1, line, result->index.words[existing].first);
        else result->index.words[result->index.count++] = (Word){line, atoi(space + 1), i + 1, {NULL,0}};
    }
    build_index(&result->index);
    return result;
}

static ClueBook read_clues(WordIndex *index) {
    ClueBook book = {0};
    Lines source = read_lines("clues.txt");
    for (int i = 0; i < source.count; ++i) {
        char *line = source.items[i];
        if (ignored(line)) continue;
        ++book.entries;
        const char *error = clue_line_error(line);
        if (error) { add_line(&book.invalid, "clue_invalid %d %s", i + 1, error); continue; }
        char *bar = strchr(line, '|');
        *bar = '\0';
        int word = find_word(index, line);
        if (word < 0) { add_line(&book.unknown, "clue_unknown %d %s", i + 1, line); continue; }
        IntList *clues = &index->words[word].clues;
        if (!clues->values) clues->values = allocate(200 * sizeof(int));
        clues->values[clues->count++] = book.count;
        book.clues[book.count++] = (Clue){word, clues->count, 0, bar + 1};
    }
    return book;
}

static char *choose_clue(const WordIndex *index, ClueBook *book, int word) {
    IntList clues = index->words[word].clues;
    if (!clues.count) return NULL;
    int chosen = clues.values[0];
    for (int i = 1; i < clues.count; ++i) if (book->clues[clues.values[i]].uses < book->clues[chosen].uses) chosen = clues.values[i];
    ++book->clues[chosen].uses;
    return book->clues[chosen].text;
}

static Template *read_templates(Settings settings, int *count) {
    Template *templates = allocate(30 * sizeof(*templates));
    *count = 0;
    Template *current = NULL;
    Lines source = read_lines("templates.txt");
    for (int i = 0; i < source.count; ++i) {
        char *line = source.items[i];
        if (!current) {
            if (!strncmp(line, "TEMPLATE ", 9)) {
                current = &templates[*count];
                current->name = line + 9;
                current->budget = settings.node_budget;
                current->min_score = settings.min_score;
                current->symmetry = settings.symmetry;
            }
        } else if (!strcmp(line, "END")) { ++*count; current = NULL; }
        else if (strchr(line, ' ')) add_line(&current->options, "%s", line);
        else add_line(&current->rows, "%s", line);
    }
    return templates;
}

static bool valid_name(const char *name) {
    size_t length = strlen(name);
    if (length < 1 || length > 20) return false;
    for (size_t i = 0; i < length; ++i) if (!((name[i] >= 'a' && name[i] <= 'z') || (name[i] >= '0' && name[i] <= '9') || name[i] == '_')) return false;
    return true;
}

static bool valid_symmetry(const char *name) { return !strcmp(name, "rot180") || !strcmp(name, "mirror") || !strcmp(name, "none"); }

static int read_options(Template *template) {
    bool budget = false, minimum = false, symmetry = false;
    for (int i = 0; i < template->options.count; ++i) {
        char *line = format("%s", template->options.items[i]);
        char *space = strchr(line, ' ');
        *space = '\0';
        char *value = space + 1;
        if (!strcmp(line, "theme")) {
            if (!valid_word(value)) return i + 1;
            for (int j = 0; j < template->theme_count; ++j) if (!strcmp(template->themes[j], value)) return i + 1;
            template->themes[template->theme_count++] = value;
        } else if (!strcmp(line, "node_budget") && !budget && valid_integer(value, 1, 100000)) {
            template->budget = atoi(value);
            budget = true;
        } else if (!strcmp(line, "min_score") && !minimum && valid_integer(value, 1, 100)) {
            template->min_score = atoi(value);
            minimum = true;
        } else if (!strcmp(line, "symmetry") && !symmetry && valid_symmetry(value)) {
            template->symmetry = value;
            symmetry = true;
        } else return i + 1;
    }
    return 0;
}

static char *cell_text(const Grid *grid, int cell) { return format("%d,%d", cell / grid->width + 1, cell % grid->width + 1); }

static char *check_template(Template *template, const Template *earlier, int earlier_count, const WordIndex *index) {
    if (!valid_name(template->name)) return "bad name";
    for (int i = 0; i < earlier_count; ++i) if (!strcmp(earlier[i].name, template->name)) return "duplicate name";
    int option = read_options(template);
    if (option) return format("bad option %d", option);
    if (template->rows.count < 3 || template->rows.count > 15) return "bad height";
    int width = (int)strlen(template->rows.items[0]);
    Grid grid = {width, template->rows.count, {0}};
    for (int i = 0; i < template->rows.count; ++i) {
        char *row = template->rows.items[i];
        bool valid = strlen(row) == (size_t)width && width >= 3 && width <= 15;
        for (int j = 0; row[j]; ++j) if (row[j] != '.' && row[j] != '#' && (row[j] < 'A' || row[j] > 'Z')) valid = false;
        if (!valid) return format("bad row %d", i + 1);
        memcpy(grid.cells + i * width, row, (size_t)width);
    }
    if (strcmp(template->symmetry, "none")) {
        int cell = asymmetric_cell(&grid, template->symmetry);
        if (cell >= 0) return format("asymmetric at %s", cell_text(&grid, cell));
    }
    int components = component_count(&grid);
    if (components != 1) return format("disconnected components=%d", components);
    bool across;
    int short_cell = short_run(&grid, &across);
    if (short_cell >= 0) return format("short slot at %s %s", cell_text(&grid, short_cell), across ? "across" : "down");
    template->layout = extract_slots(grid);
    for (int cell = 0; cell < grid.width * grid.height; ++cell) if (grid.cells[cell] != '#' && !owner_count(&template->layout, cell)) return format("orphan cell %s", cell_text(&grid, cell));
    initial_state(&template->layout, &template->initial);
    for (int i = 0; i < template->theme_count; ++i) {
        int word = find_word(index, template->themes[i]);
        if (word < 0) return format("unknown theme %d", i + 1);
        int chosen = -1;
        for (int s = 0; s < template->layout.count; ++s) {
            Slot *slot = &template->layout.slots[s];
            if (template->initial.words[s] >= 0 || strlen(index->words[word].text) != (size_t)slot->length) continue;
            if (word_matches(index->words[word].text, slot_pattern(&template->initial, slot))) { chosen = s; break; }
        }
        if (chosen < 0) return format("theme %d does not fit", i + 1);
        assign_word(&template->initial, &template->layout.slots[chosen], index, word);
        template->initial.words[chosen] = word;
        template->theme_slots[chosen] = true;
    }
    return NULL;
}

static void process_template(Template *template, const WordIndex *index, ClueBook *book, int relax_step) {
    int minimum = template->min_score;
    while (true) {
        Attempt *attempt = allocate(sizeof(*attempt));
        run_attempt(attempt, &template->layout, index, &template->initial, minimum, template->budget);
        template->attempts[template->attempt_count++] = attempt;
        template->final = attempt;
        if (attempt->outcome == FILLED || relax_step == 0 || minimum == 1) break;
        minimum -= relax_step;
        if (minimum < 1) minimum = 1;
    }
    template->state = template->final->outcome == FILLED ? &template->final->state : &template->final->best;
    for (int direction = 0; direction < 2; ++direction) {
        for (int s = 0; s < template->layout.count; ++s) {
            if (template->layout.slots[s].across != (direction == 0)) continue;
            int word = template->state->words[s];
            if (word >= 0) template->chosen[s] = choose_clue(index, book, word);
        }
    }
}

static char *entry(const Template *template, const WordIndex *index, int slot) {
    const Word *word = &index->words[template->state->words[slot]];
    return format("%s:%s:%d", template->layout.slots[slot].label, word->text, word->score);
}

static int total_score(const Template *template, const WordIndex *index) {
    int total = 0;
    for (int s = 0; s < template->layout.count; ++s) total += index->words[template->state->words[s]].score;
    return total;
}

static Lines grid_paragraph(const Template *template) {
    Lines lines = {0};
    add_line(&lines, "TEMPLATE %s", template->name);
    if (template->error) { add_line(&lines, "error %s", template->error); return lines; }
    add_line(&lines, "outcome=%s attempts=%d min_score=%d", outcomes[template->final->outcome], template->attempt_count, template->final->min_score);
    render_grid(&template->layout.grid, template->state, &lines);
    add_line(&lines, "numbers");
    render_numbers(&template->layout, &lines);
    return lines;
}

static Lines clue_paragraph(const Template *template, const WordIndex *index) {
    Lines lines = {0};
    add_line(&lines, "TEMPLATE %s", template->name);
    int clued = 0, missing = 0, unfilled = 0;
    for (int direction = 0; direction < 2; ++direction) {
        bool heading = false;
        for (int s = 0; s < template->layout.count; ++s) {
            const Slot *slot = &template->layout.slots[s];
            if (slot->across != (direction == 0)) continue;
            if (!heading) { add_line(&lines, "%s", direction == 0 ? "ACROSS" : "DOWN"); heading = true; }
            int word = template->state->words[s];
            if (word < 0) {
                ++unfilled;
                add_line(&lines, "%s", list_line(slot, "(unfilled)", slot_pattern(template->state, slot), "-", false));
            } else {
                const char *clue = template->chosen[s];
                if (clue) ++clued;
                else { ++missing; clue = "(no clue)"; }
                add_line(&lines, "%s", list_line(slot, clue, index->words[word].text, format("%d", index->words[word].score), template->theme_slots[s]));
            }
        }
    }
    add_line(&lines, "clued=%d missing=%d unfilled=%d", clued, missing, unfilled);
    return lines;
}

static void quality_lines(const Template *template, const WordIndex *index, int weak_score, Lines *lines) {
    const Layout *layout = &template->layout;
    int total = total_score(template, index), weakest = 0;
    Text weak = {0};
    for (int s = 0; s < layout->count; ++s) {
        int score = index->words[template->state->words[s]].score;
        if (score < index->words[template->state->words[weakest]].score) weakest = s;
        if (score < weak_score) text_add(&weak, "%s%s", weak.size ? "," : "", entry(template, index, s));
    }
    add_line(lines, "quality total=%d average=%s weakest=%s weak=%s", total, decimal(total, layout->count, 2), entry(template, index, weakest), weak.size ? weak.data : "-");
    bool used[26] = {false};
    int whites = 0, points = 0, worst = -1, worst_sum = 0;
    for (int cell = 0; cell < layout->grid.width * layout->grid.height; ++cell) {
        if (layout->grid.cells[cell] == '#') continue;
        ++whites;
        int letter = template->state->letters[cell] - 'A';
        used[letter] = true;
        points += letter_points[letter];
        if (owner_count(layout, cell) == 2) {
            int score = index->words[template->state->words[layout->across[cell]]].score + index->words[template->state->words[layout->down[cell]]].score;
            if (worst < 0 || score < worst_sum) { worst = cell; worst_sum = score; }
        }
    }
    Text missing = {0};
    int distinct = 0;
    for (int letter = 0; letter < 26; ++letter) {
        if (used[letter]) ++distinct;
        else text_add(&missing, "%c", 'A' + letter);
    }
    char *crossing = "-";
    if (worst >= 0) {
        int across = layout->across[worst], down = layout->down[worst];
        crossing = format("%s %s:%s+%s:%s=%d", cell_text(&layout->grid, worst), layout->slots[across].label, index->words[template->state->words[across]].text, layout->slots[down].label, index->words[template->state->words[down]].text, worst_sum);
    }
    add_line(lines, "letters distinct=%d pangram=%s missing=%s scrabble=%s worst_crossing=%s", distinct, missing.size ? "no" : "yes", missing.size ? missing.data : "-", decimal(points, whites, 2), crossing);
}

static Lines stats_paragraph(const Template *template, const WordIndex *index, int weak_score) {
    Lines lines = {0};
    const Layout *layout = &template->layout;
    const Grid *grid = &layout->grid;
    add_line(&lines, "TEMPLATE %s", template->name);
    int whites = 0, givens = 0, unchecked = 0;
    for (int cell = 0; cell < grid->width * grid->height; ++cell) if (grid->cells[cell] != '#') {
        ++whites;
        givens += grid->cells[cell] != '.';
        unchecked += owner_count(layout, cell) == 1;
    }
    int black = grid->width * grid->height - whites;
    bool rot = asymmetric_cell(grid, "rot180") < 0, mirror = asymmetric_cell(grid, "mirror") < 0;
    const char *symmetries = rot ? (mirror ? "rot180,mirror" : "rot180") : mirror ? "mirror" : "none";
    add_line(&lines, "grid size=%dx%d blocks=%d white=%d density=%s givens=%d required=%s symmetry=%s", grid->width, grid->height, black, whites, decimal(100 * black, grid->width * grid->height, 1), givens, template->symmetry, symmetries);
    int lengths[16] = {0}, across = 0, longest = 0, length_sum = 0;
    Text themes = {0};
    for (int s = 0; s < layout->count; ++s) {
        const Slot *slot = &layout->slots[s];
        ++lengths[slot->length];
        across += slot->across;
        length_sum += slot->length;
        if (slot->length > longest) longest = slot->length;
        if (template->theme_slots[s]) text_add(&themes, "%s%s", themes.size ? " " : "", entry(template, index, s));
    }
    Text distribution = {0}, coverage = {0};
    for (int length = 3; length <= 15; ++length) if (lengths[length]) {
        text_add(&distribution, "%s%d:%d", distribution.size ? "," : "", length, lengths[length]);
        int supply = 0;
        IntList pool = index->length[length];
        for (int i = 0; i < pool.count; ++i) supply += index->words[pool.values[i]].score >= template->min_score;
        text_add(&coverage, "%s%d:%d", coverage.size ? " " : "", length, supply);
    }
    add_line(&lines, "slots across=%d down=%d total=%d lengths=%s avg_length=%s longest=%d unchecked=%d", across, layout->count - across, layout->count, distribution.data, decimal(length_sum, layout->count, 2), longest, unchecked);
    if (themes.size) add_line(&lines, "themes %s", themes.data);
    add_line(&lines, "coverage %s", coverage.data);
    int tight[150], counts[150], tight_count = 0;
    for (int s = 0; s < layout->count; ++s) if (!template->theme_slots[s]) {
        counts[s] = candidates(index, slot_pattern(&template->initial, &layout->slots[s]), template->min_score, template->initial.used, NULL);
        int position = tight_count++;
        while (position > 0 && counts[s] < counts[tight[position - 1]]) { tight[position] = tight[position - 1]; --position; }
        tight[position] = s;
    }
    Text tightest = {0};
    for (int i = 0; i < tight_count && i < 3; ++i) text_add(&tightest, "%s%s:%d", i ? " " : "", layout->slots[tight[i]].label, counts[tight[i]]);
    add_line(&lines, "tightest %s", tightest.size ? tightest.data : "-");
    for (int i = 0; i < template->attempt_count; ++i) {
        const Attempt *attempt = template->attempts[i];
        add_line(&lines, "attempt %d min_score=%d budget=%d outcome=%s nodes=%d backtracks=%d prunes=%d dead_ends=%d max_depth=%d", i + 1, attempt->min_score, attempt->budget, outcomes[attempt->outcome], attempt->nodes, attempt->backtracks, attempt->prunes, attempt->dead_ends, attempt->max_depth);
    }
    Text trace = {0};
    for (int i = 0; i < template->final->trace_count; ++i) text_add(&trace, "%s%s", i ? " " : "", template->final->trace[i]);
    add_line(&lines, "trace %s", trace.size ? trace.data : "-");
    int hot[150], hot_count = 0;
    for (int s = 0; s < layout->count; ++s) if (template->final->failures[s]) {
        int position = hot_count++;
        while (position > 0 && template->final->failures[s] > template->final->failures[hot[position - 1]]) { hot[position] = hot[position - 1]; --position; }
        hot[position] = s;
    }
    Text hotspots = {0};
    for (int i = 0; i < hot_count && i < 3; ++i) text_add(&hotspots, "%s%s:%d", i ? " " : "", layout->slots[hot[i]].label, template->final->failures[hot[i]]);
    add_line(&lines, "hotspots %s", hotspots.size ? hotspots.data : "-");
    if (template->final->outcome == FILLED) {
        Text order = {0};
        for (int i = 0; i < template->final->depth; ++i) text_add(&order, "%s%s", i ? " " : "", layout->slots[template->final->sequence[i]].label);
        add_line(&lines, "order %s", order.size ? order.data : "-");
        quality_lines(template, index, weak_score, &lines);
    } else {
        int assigned = 0, letters = 0;
        Text blocked = {0};
        for (int s = 0; s < layout->count; ++s) {
            if (template->state->words[s] >= 0) ++assigned;
            else if (!candidates(index, slot_pattern(template->state, &layout->slots[s]), template->final->min_score, template->state->used, NULL)) text_add(&blocked, "%s%s", blocked.size ? "," : "", layout->slots[s].label);
        }
        for (int cell = 0; cell < grid->width * grid->height; ++cell) if (grid->cells[cell] != '#' && template->state->letters[cell] != '.') ++letters;
        add_line(&lines, "partial assigned=%d/%d letters=%d/%d blocked=%s", assigned, layout->count, letters, whites, blocked.size ? blocked.data : "-");
    }
    return lines;
}

static void totals(Template *templates, int count, const WordIndex *index, Lines *lines) {
    int filled[30], filled_count = 0, invalid = 0, outcomes_count[3] = {0}, attempts = 0, nodes = 0;
    int *appearances = allocate((size_t)index->count * sizeof(int));
    Text *names = allocate((size_t)index->count * sizeof(Text));
    for (int i = 0; i < count; ++i) {
        Template *template = &templates[i];
        if (template->error) { ++invalid; continue; }
        ++outcomes_count[template->final->outcome];
        attempts += template->attempt_count;
        for (int j = 0; j < template->attempt_count; ++j) nodes += template->attempts[j]->nodes;
        if (template->final->outcome != FILLED) continue;
        int position = filled_count++;
        int total = total_score(template, index);
        while (position > 0) {
            Template *previous = &templates[filled[position - 1]];
            int left = total * previous->layout.count, right = total_score(previous, index) * template->layout.count;
            if (left < right || (left == right && strcmp(template->name, previous->name) >= 0)) break;
            filled[position] = filled[position - 1];
            --position;
        }
        filled[position] = i;
        for (int s = 0; s < template->layout.count; ++s) {
            int word = template->state->words[s];
            text_add(&names[word], "%s%s", appearances[word] ? "," : "", template->name);
            ++appearances[word];
        }
    }
    Lines ranking = {0};
    add_line(&ranking, "RANKING");
    for (int i = 0; i < filled_count; ++i) {
        Template *template = &templates[filled[i]];
        int total = total_score(template, index);
        add_line(&ranking, "rank %d %s average=%s total=%d entries=%d", i + 1, template->name, decimal(total, template->layout.count, 2), total, template->layout.count);
    }
    paragraph(lines, ranking);
    int reused[2000], reuse_count = 0;
    for (int word = 0; word < index->count; ++word) if (appearances[word] >= 2) {
        int position = reuse_count++;
        while (position > 0) {
            int previous = reused[position - 1];
            if (appearances[word] < appearances[previous] || (appearances[word] == appearances[previous] && strcmp(index->words[word].text, index->words[previous].text) >= 0)) break;
            reused[position] = previous;
            --position;
        }
        reused[position] = word;
    }
    Lines reuse = {0};
    add_line(&reuse, "REUSE");
    for (int i = 0; i < reuse_count; ++i) {
        int word = reused[i];
        add_line(&reuse, "reused %s %d %s", index->words[word].text, appearances[word], names[word].data);
    }
    paragraph(lines, reuse);
    Lines summary = {0};
    add_line(&summary, "SUMMARY templates=%d invalid=%d filled=%d unfillable=%d budget=%d attempts=%d nodes=%d", count, invalid, outcomes_count[FILLED], outcomes_count[UNFILLABLE], outcomes_count[BUDGET], attempts, nodes);
    paragraph(lines, summary);
}

static Lines wordlist_lines(const WordList *list, const ClueBook *book) {
    const WordIndex *index = &list->index;
    Lines lines = {0};
    add_line(&lines, "WORDLIST lines=%d valid=%d invalid=%d duplicates=%d", list->lines, index->count, list->invalid.count, list->duplicates.count);
    for (int i = 0; i < list->invalid.count; ++i) add_line(&lines, "%s", list->invalid.items[i]);
    for (int i = 0; i < list->duplicates.count; ++i) add_line(&lines, "%s", list->duplicates.items[i]);
    for (int length = 3; length <= 15; ++length) {
        IntList pool = index->length[length];
        if (!pool.count) continue;
        int total = 0;
        for (int i = 0; i < pool.count; ++i) total += index->words[pool.values[i]].score;
        const Word *best = &index->words[pool.values[0]];
        add_line(&lines, "length %d words=%d average=%s best=%s:%d", length, pool.count, decimal(total, pool.count, 2), best->text, best->score);
    }
    int bands[5] = {0}, letters[26] = {0}, rare[26];
    for (int word = 0; word < index->count; ++word) {
        ++bands[(index->words[word].score - 1) / 20];
        bool seen[26] = {false};
        for (const char *letter = index->words[word].text; *letter; ++letter) seen[*letter - 'A'] = true;
        for (int letter = 0; letter < 26; ++letter) letters[letter] += seen[letter];
    }
    add_line(&lines, "bands 1-20=%d 21-40=%d 41-60=%d 61-80=%d 81-100=%d", bands[0], bands[1], bands[2], bands[3], bands[4]);
    Text top = {0};
    text_add(&top, "top");
    for (int i = 0; i < index->count && i < 5; ++i) text_add(&top, " %s:%d", index->words[i].text, index->words[i].score);
    add_line(&lines, "%s", top.data);
    for (int letter = 0; letter < 26; ++letter) {
        int position = letter;
        while (position > 0 && letters[letter] < letters[rare[position - 1]]) { rare[position] = rare[position - 1]; --position; }
        rare[position] = letter;
    }
    Text rare_text = {0};
    text_add(&rare_text, "rare_letters");
    for (int i = 0; i < 5; ++i) text_add(&rare_text, " %c:%d", 'A' + rare[i], letters[rare[i]]);
    add_line(&lines, "%s", rare_text.data);
    int clued_words = 0, used = 0, repeated = 0;
    for (int word = 0; word < index->count; ++word) clued_words += index->words[word].clues.count > 0;
    for (int i = 0; i < book->count; ++i) {
        used += book->clues[i].uses >= 1;
        repeated += book->clues[i].uses >= 2;
    }
    add_line(&lines, "CLUES entries=%d valid=%d invalid=%d unknown=%d words=%d", book->entries, book->count, book->invalid.count, book->unknown.count, clued_words);
    for (int i = 0; i < book->invalid.count; ++i) add_line(&lines, "%s", book->invalid.items[i]);
    for (int i = 0; i < book->unknown.count; ++i) add_line(&lines, "%s", book->unknown.items[i]);
    add_line(&lines, "CLUE_USE used=%d unused=%d repeated=%d", used, book->count - used, repeated);
    int alphabetical[2000];
    for (int word = 0; word < index->count; ++word) {
        int position = word;
        while (position > 0 && strcmp(index->words[word].text, index->words[alphabetical[position - 1]].text) < 0) { alphabetical[position] = alphabetical[position - 1]; --position; }
        alphabetical[position] = word;
    }
    for (int i = 0; i < index->count; ++i) {
        int word = alphabetical[i];
        IntList clues = index->words[word].clues;
        for (int j = 0; j < clues.count; ++j) {
            Clue clue = book->clues[clues.values[j]];
            if (clue.uses >= 2) add_line(&lines, "repeated %s clue=%d uses=%d", index->words[word].text, clue.number, clue.uses);
        }
    }
    return lines;
}

int main(void) {
    Settings settings = read_settings();
    WordList *word_list = read_words();
    WordIndex *index = &word_list->index;
    ClueBook book = read_clues(index);
    int count;
    Template *templates = read_templates(settings, &count);
    Lines grid = {0}, clues = {0}, stats = {0};
    for (int i = 0; i < count; ++i) {
        Template *template = &templates[i];
        template->error = check_template(template, templates, i, index);
        if (!template->error) {
            process_template(template, index, &book, settings.relax_step);
            paragraph(&clues, clue_paragraph(template, index));
            paragraph(&stats, stats_paragraph(template, index, settings.weak_score));
        }
        paragraph(&grid, grid_paragraph(template));
    }
    totals(templates, count, index, &stats);
    write_lines("grid.txt", grid);
    write_lines("clues.txt", clues);
    write_lines("search_stats.txt", stats);
    write_lines("wordlist.txt", wordlist_lines(word_list, &book));
    return 0;
}
