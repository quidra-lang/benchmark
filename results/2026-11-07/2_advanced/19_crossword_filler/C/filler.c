#include "crossword.h"

void initial_state(const Layout *layout, State *state) {
    memset(state, 0, sizeof(*state));
    strcpy(state->letters, layout->grid.cells);
    for (int i = 0; i < 150; ++i) state->words[i] = -1;
}

char *slot_pattern(const State *state, const Slot *slot) {
    char *pattern = allocate((size_t)slot->length + 1);
    for (int i = 0; i < slot->length; ++i) pattern[i] = state->letters[slot->cells[i]];
    return pattern;
}

void assign_word(State *state, const Slot *slot, const WordIndex *index, int word) {
    for (int i = 0; i < slot->length; ++i) state->letters[slot->cells[i]] = index->words[word].text[i];
    state->used[word] = true;
}

static int search(Attempt *attempt) {
    int chosen = -1, smallest = 2001;
    for (int i = 0; i < attempt->layout->count; ++i) {
        if (attempt->state.words[i] >= 0) continue;
        int count = candidates(attempt->index, slot_pattern(&attempt->state, &attempt->layout->slots[i]), attempt->min_score, attempt->state.used, NULL);
        if (count < smallest) { smallest = count; chosen = i; }
    }
    if (chosen < 0) return FILLED;
    if (!smallest) { ++attempt->dead_ends; ++attempt->failures[chosen]; return UNFILLABLE; }
    const Slot *slot = &attempt->layout->slots[chosen];
    int choices[2000];
    int count = candidates(attempt->index, slot_pattern(&attempt->state, slot), attempt->min_score, attempt->state.used, choices);
    for (int i = 0; i < count; ++i) {
        if (attempt->nodes == attempt->budget) return BUDGET;
        ++attempt->nodes;
        int word = choices[i], cleared[15], clear_count = 0;
        for (int position = 0; position < slot->length; ++position) if (attempt->state.letters[slot->cells[position]] == '.') cleared[clear_count++] = slot->cells[position];
        assign_word(&attempt->state, slot, attempt->index, word);
        attempt->state.words[chosen] = word;
        attempt->sequence[attempt->depth++] = chosen;
        int wiped = -1;
        for (int j = 0; j < slot->crossings.count; ++j) {
            int other = slot->crossings.values[j];
            if (attempt->state.words[other] < 0 && !candidates(attempt->index, slot_pattern(&attempt->state, &attempt->layout->slots[other]), attempt->min_score, attempt->state.used, NULL)) { wiped = other; break; }
        }
        if (attempt->nodes <= 10) attempt->trace[attempt->trace_count++] = format("%s=%s%s", slot->label, attempt->index->words[word].text, wiped < 0 ? "" : "!");
        int result;
        if (wiped >= 0) { ++attempt->prunes; ++attempt->failures[wiped]; result = UNFILLABLE; }
        else {
            if (attempt->depth > attempt->max_depth) { attempt->max_depth = attempt->depth; attempt->best = attempt->state; }
            result = search(attempt);
        }
        if (result != UNFILLABLE) return result;
        for (int j = 0; j < clear_count; ++j) attempt->state.letters[cleared[j]] = '.';
        attempt->state.used[word] = false;
        attempt->state.words[chosen] = -1;
        --attempt->depth;
        ++attempt->backtracks;
    }
    return UNFILLABLE;
}

void run_attempt(Attempt *attempt, const Layout *layout, const WordIndex *index, const State *initial, int min_score, int budget) {
    memset(attempt, 0, sizeof(*attempt));
    attempt->layout = layout;
    attempt->index = index;
    attempt->state = *initial;
    attempt->best = *initial;
    attempt->min_score = min_score;
    attempt->budget = budget;
    attempt->outcome = search(attempt);
}
