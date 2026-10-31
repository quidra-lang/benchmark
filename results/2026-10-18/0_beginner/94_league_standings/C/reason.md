# Task B selection: 94_league_standings / C

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.c`. Selected original locations: L5,L6,L7,L8,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L37,L38,L39,L40,L41,L43,L44,L45,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57.

- L5: `typedef struct {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    const char *name;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    int played, wins, draws, losses, gf, ga, points;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `} Team;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `void record(Team *t, int gf, int ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    t->played++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    t->gf += gf;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    t->ga += ga;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    if (gf > ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        t->wins++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        t->points += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    } else if (gf == ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        t->draws++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        t->points++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        t->losses++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `int compare(const void *a, const void *b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    const Team *x = a, *y = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    if (x->points != y->points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        return y->points - x->points;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    if (x->gf - x->ga != y->gf - y->ga)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        return (y->gf - y->ga) - (x->gf - x->ga);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    if (x->gf != y->gf)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        return y->gf - x->gf;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    return strcmp(x->name, y->name);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `    const char *names[] = {"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    const char *matches[] = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        "Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `    for (int i = 0; i < 6; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        teams[i] = (Team){.name = names[i]};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    for (int i = 0; i < 15; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        sscanf(matches[i], "%31s %d-%d %31s", home, &h, &a, away);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        int x = 0, y = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        while (strcmp(teams[x].name, home))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `            x++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `        while (strcmp(teams[y].name, away))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `            y++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        record(&teams[x], h, a);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        record(&teams[y], a, h);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L57: `    qsort(teams, 6, sizeof(Team), compare);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **827 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 760 tokens. The contiguous original span L5–L57 costs 876 tokens; the complete original source costs 1101 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L5: 821 tokens; removes `typedef struct {` from the dependency chain described above.
- Without L6: 818 tokens; removes `const char *name;` from the dependency chain described above.
- Without L7: 803 tokens; removes `int played, wins, draws, losses, gf, ga, points;` from the dependency chain described above.
- Without L8: 822 tokens; removes `} Team;` from the dependency chain described above.
- Without L10: 805 tokens; removes `void record(Team *t, int gf, int ga) {` from the dependency chain described above.
- Without L11: 820 tokens; removes `t->played++;` from the dependency chain described above.
- Without L12: 817 tokens; removes `t->gf += gf;` from the dependency chain described above.
- Without L13: 817 tokens; removes `t->ga += ga;` from the dependency chain described above.
- Without L14: 814 tokens; removes `if (gf > ga) {` from the dependency chain described above.
- Without L15: 819 tokens; removes `t->wins++;` from the dependency chain described above.
- Without L16: 816 tokens; removes `t->points += 3;` from the dependency chain described above.
- Without L17: 810 tokens; removes `} else if (gf == ga) {` from the dependency chain described above.
- Without L18: 819 tokens; removes `t->draws++;` from the dependency chain described above.
- Without L19: 819 tokens; removes `t->points++;` from the dependency chain described above.
- Without L20: 820 tokens; removes `} else {` from the dependency chain described above.
- Without L21: 819 tokens; removes `t->losses++;` from the dependency chain described above.
- Without L22: 824 tokens; removes `}` from the dependency chain described above.
- Without L23: 825 tokens; removes `}` from the dependency chain described above.
- Without L25: 805 tokens; removes `int compare(const void *a, const void *b) {` from the dependency chain described above.
- Without L26: 806 tokens; removes `const Team *x = a, *y = b;` from the dependency chain described above.
- Without L27: 812 tokens; removes `if (x->points != y->points)` from the dependency chain described above.
- Without L28: 812 tokens; removes `return y->points - x->points;` from the dependency chain described above.
- Without L29: 800 tokens; removes `if (x->gf - x->ga != y->gf - y->ga)` from the dependency chain described above.
- Without L30: 796 tokens; removes `return (y->gf - y->ga) - (x->gf - x->ga);` from the dependency chain described above.
- Without L31: 812 tokens; removes `if (x->gf != y->gf)` from the dependency chain described above.
- Without L32: 812 tokens; removes `return y->gf - x->gf;` from the dependency chain described above.
- Without L33: 811 tokens; removes `return strcmp(x->name, y->name);` from the dependency chain described above.
- Without L34: 825 tokens; removes `}` from the dependency chain described above.
- Without L37: 784 tokens; removes `const char *names[] = {"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"};` from the dependency chain described above.
- Without L38: 814 tokens; removes `const char *matches[] = {` from the dependency chain described above.
- Without L39: 770 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` from the dependency chain described above.
- Without L40: 770 tokens; removes `"Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` from the dependency chain described above.
- Without L41: 769 tokens; removes `"Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"};` from the dependency chain described above.
- Without L43: 803 tokens; removes `for (int i = 0; i < 6; i++)` from the dependency chain described above.
- Without L44: 803 tokens; removes `teams[i] = (Team){.name = names[i]};` from the dependency chain described above.
- Without L45: 800 tokens; removes `for (int i = 0; i < 15; i++) {` from the dependency chain described above.
- Without L48: 786 tokens; removes `sscanf(matches[i], "%31s %d-%d %31s", home, &h, &a, away);` from the dependency chain described above.
- Without L49: 809 tokens; removes `int x = 0, y = 0;` from the dependency chain described above.
- Without L50: 809 tokens; removes `while (strcmp(teams[x].name, home))` from the dependency chain described above.
- Without L51: 820 tokens; removes `x++;` from the dependency chain described above.
- Without L52: 809 tokens; removes `while (strcmp(teams[y].name, away))` from the dependency chain described above.
- Without L53: 820 tokens; removes `y++;` from the dependency chain described above.
- Without L54: 809 tokens; removes `record(&teams[x], h, a);` from the dependency chain described above.
- Without L55: 809 tokens; removes `record(&teams[y], a, h);` from the dependency chain described above.
- Without L56: 824 tokens; removes `}` from the dependency chain described above.
- Without L57: 808 tokens; removes `qsort(teams, 6, sizeof(Team), compare);` from the dependency chain described above.
