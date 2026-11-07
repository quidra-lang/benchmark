#include "truss.h"

typedef struct {
    Properties properties[80];
    Matrix matrix, free_matrix, lower;
    int unstable, removed;
} System;
typedef struct {
    Model model;
    int degrees, order[40], numbers[40], node_dofs[40][2], owners[80][2];
    bool adjacent[40][40];
    int degree[40], free_dofs[80], nf, restrained[80], nr, support_directions[20][3],
        direction_count;
    double prescribed[80], limits[80], uses[80][10], governing[80], weight;
    int choices[80], governing_cases[80], group_members[20][80], group_sizes[20], group_count;
    char group_names[20][13];
    Geometry geometry[80];
    System final_system;
    Result results[20], units[40];
    bool unit_ready[40];
} Truss;

static const char *real(double value, int digits) {
    static char buffers[64][128];
    static unsigned current;
    char *text = buffers[current++ % 64];
    snprintf(text, 128, "%.*f", digits, value);
    if (text[0] == '-' && strtod(text, NULL) == 0)
        memmove(text, text + 1, strlen(text));
    return text;
}
static double rounded(double value) { return strtod(real(value, 4), NULL); }
static int extreme(const double *values, int count, bool minimum) {
    int chosen = 0;
    double best = rounded(values[0]);
    for (int i = 1; i < count; ++i) {
        double value = rounded(values[i]);
        if (minimum ? value < best : value > best) {
            chosen = i;
            best = value;
        }
    }
    return chosen;
}
static FILE *output(const char *name) {
    char path[128];
    snprintf(path, sizeof path, "output/%s", name);
    return fopen(path, "w");
}
static bool node_before(const Truss *t, int a, int b) {
    return t->degree[a] < t->degree[b] ||
           (t->degree[a] == t->degree[b] && t->model.nodes[a].id < t->model.nodes[b].id);
}
static void initialize(Truss *t) {
    Model *m = &t->model;
    t->degrees = 2 * m->node_count;
    for (int i = 0; i < m->member_count; ++i) {
        Member *member = &m->members[i];
        t->adjacent[member->start][member->end] = true;
        t->adjacent[member->end][member->start] = true;
        t->choices[i] = member->section;
        int group = 0;
        while (group < t->group_count && strcmp(t->group_names[group], member->group))
            ++group;
        if (group == t->group_count)
            strcpy(t->group_names[t->group_count++], member->group);
        t->group_members[group][t->group_sizes[group]++] = i;
    }
    for (int i = 0; i < m->node_count; ++i)
        for (int j = 0; j < m->node_count; ++j)
            t->degree[i] += t->adjacent[i][j];
    int first = 0;
    for (int i = 1; i < m->node_count; ++i)
        if (node_before(t, i, first))
            first = i;
    bool visited[40] = {false};
    visited[first] = true;
    int count = 1;
    t->order[0] = first;
    for (int i = 0; i < count; ++i) {
        int following[40], n = 0;
        for (int j = 0; j < m->node_count; ++j)
            if (t->adjacent[t->order[i]][j] && !visited[j]) {
                int position = n++;
                while (position > 0 && node_before(t, j, following[position - 1])) {
                    following[position] = following[position - 1];
                    --position;
                }
                following[position] = j;
            }
        for (int j = 0; j < n; ++j) {
            visited[following[j]] = true;
            t->order[count++] = following[j];
        }
    }
    for (int i = 0; i < count / 2; ++i) {
        int v = t->order[i];
        t->order[i] = t->order[count - 1 - i];
        t->order[count - 1 - i] = v;
    }
    for (int i = 0; i < count; ++i)
        t->numbers[t->order[i]] = i;
    for (int node = 0; node < m->node_count; ++node)
        for (int axis = 0; axis < 2; ++axis) {
            int d = 2 * t->numbers[node] + axis;
            t->node_dofs[node][axis] = d;
            t->owners[d][0] = node;
            t->owners[d][1] = axis;
        }
    bool fixed[80] = {false};
    for (int i = 0; i < m->support_count; ++i)
        for (int axis = 0; axis < 2; ++axis)
            if (m->supports[i].fixed[axis]) {
                const Support *s = &m->supports[i];
                int d = t->node_dofs[s->node][axis];
                t->prescribed[d] = s->prescribed[axis];
                fixed[d] = true;
                int *direction = t->support_directions[t->direction_count++];
                direction[0] = s->node;
                direction[1] = axis;
                direction[2] = d;
            }
    for (int d = 0; d < t->degrees; ++d) {
        if (fixed[d])
            t->restrained[t->nr++] = d;
        else
            t->free_dofs[t->nf++] = d;
    }
    member_geometry(m, t->node_dofs, t->geometry);
}
static void make_system(const Truss *t, int removed, System *out) {
    member_properties(&t->model, t->choices, t->geometry, out->properties);
    assemble(t->geometry, out->properties, t->model.member_count, t->degrees, removed,
             &out->matrix);
    memset(&out->free_matrix, 0, sizeof out->free_matrix);
    out->free_matrix.n = t->nf;
    for (int i = 0; i < t->nf; ++i)
        for (int j = 0; j < t->nf; ++j)
            out->free_matrix.v[i][j] = out->matrix.v[t->free_dofs[i]][t->free_dofs[j]];
    out->unstable = cholesky(&out->free_matrix, t->free_dofs, &out->lower);
    out->removed = removed;
}
static void displacement(const Truss *t, const System *s, const double *force, bool settlement,
                         double *out) {
    memset(out, 0, (size_t)t->degrees * sizeof *out);
    for (int i = 0; i < t->nr; ++i) {
        int d = t->restrained[i];
        out[d] = settlement ? t->prescribed[d] : 0;
    }
    double right[80], solution[80];
    for (int i = 0; i < t->nf; ++i) {
        int d = t->free_dofs[i];
        double value = force[d];
        for (int j = 0; j < t->nr; ++j)
            value -= s->matrix.v[d][t->restrained[j]] * out[t->restrained[j]];
        right[i] = value;
    }
    solve(&s->lower, right, solution);
    for (int i = 0; i < t->nf; ++i)
        out[t->free_dofs[i]] = solution[i];
}
static void case_result(const Truss *t, const System *s, const LoadCase *load_case, Result *out) {
    memset(out, 0, sizeof *out);
    strcpy(out->name, load_case->name);
    Loading loading;
    load_vectors(load_case, t->geometry, s->properties, t->node_dofs, t->model.member_count,
                 t->degrees, s->removed, &loading);
    displacement(t, s, loading.total, loading.settlement, out->displacement);
    axial_forces(t->geometry, s->properties, t->model.member_count, out->displacement,
                 loading.temperature, s->removed, out->forces);
    reactions(&s->matrix, out->displacement, loading.total, t->restrained, t->nr, out->reactions);
    memcpy(out->external, loading.external, (size_t)t->degrees * sizeof *out->external);
}
static void analyze(const Truss *t, const System *s, Result *out) {
    const Model *m = &t->model;
    for (int i = 0; i < m->case_count; ++i)
        case_result(t, s, &m->cases[i], &out[i]);
    for (int i = 0; i < m->combination_count; ++i)
        superpose(&m->combinations[i], out, m->member_count, t->degrees, &out[m->case_count + i]);
}
static const Result *find_result(const Truss *t, const char *name) {
    for (int i = 0; i < t->model.case_count + t->model.combination_count; ++i)
        if (!strcmp(t->results[i].name, name))
            return &t->results[i];
    return NULL;
}
static const Result *unit_result(Truss *t, int node) {
    if (!t->unit_ready[node]) {
        Result *unit = &t->units[node];
        strcpy(unit->name, "unit");
        unit->external[t->node_dofs[node][1]] = -1000;
        displacement(t, &t->final_system, unit->external, false, unit->displacement);
        double temperature[80] = {0};
        axial_forces(t->geometry, t->final_system.properties, t->model.member_count,
                     unit->displacement, temperature, -1, unit->forces);
        reactions(&t->final_system.matrix, unit->displacement, unit->external, t->restrained, t->nr,
                  unit->reactions);
        t->unit_ready[node] = true;
    }
    return &t->units[node];
}
static void magnitudes(const Truss *t, const Result *result, double *out) {
    for (int node = 0; node < t->model.node_count; ++node) {
        double x = result->displacement[t->node_dofs[node][0]],
               y = result->displacement[t->node_dofs[node][1]];
        out[node] = sqrt(x * x + y * y);
    }
}
static void metrics(const Truss *t, const int *mapping, int *bandwidth, int *profile) {
    *bandwidth = 0;
    *profile = 0;
    for (int i = 0; i < t->model.member_count; ++i) {
        const Member *m = &t->model.members[i];
        int width = abs(mapping[m->start] - mapping[m->end]);
        if (width > *bandwidth)
            *bandwidth = width;
    }
    for (int i = 0; i < t->model.node_count; ++i) {
        int low = mapping[i];
        for (int j = 0; j < t->model.node_count; ++j)
            if (t->adjacent[i][j] && mapping[j] < low)
                low = mapping[j];
        *profile += mapping[i] - low;
    }
}
static void design_sections(Truss *t, FILE *out) {
    Model *m = &t->model;
    int last_round = 0;
    bool converged = false;
    for (int round = 1; round <= 10; ++round) {
        last_round = round;
        make_system(t, -1, &t->final_system);
        analyze(t, &t->final_system, t->results);
        const Result *combinations = &t->results[m->case_count];
        double values[800];
        int n = 0;
        t->weight = 0;
        for (int member = 0; member < m->member_count; ++member) {
            t->limits[member] =
                slenderness_limit(member, combinations, m->combination_count,
                                  m->settings.compression_limit, m->settings.tension_limit);
            for (int c = 0; c < m->combination_count; ++c) {
                double value =
                    utilization(combinations[c].forces[member], &t->final_system.properties[member],
                                &t->geometry[member], NULL);
                t->uses[member][c] = value;
                values[n++] = value;
            }
            t->weight += member_weight(&t->final_system.properties[member], &t->geometry[member]);
        }
        int next[20], changes[20], change_count = 0;
        for (int group = 0; group < t->group_count; ++group) {
            next[group] =
                select_section(t->group_members[group], t->group_sizes[group], m->sections,
                               m->section_count, t->final_system.properties, t->geometry,
                               combinations, m->combination_count, t->limits);
            if (next[group] != t->choices[t->group_members[group][0]])
                changes[change_count++] = group;
        }
        int best = extreme(values, n, false), member = best / m->combination_count,
            c = best % m->combination_count;
        fprintf(out, "round %d weight %s max_utilization %s at %d %s changes %d\n", round,
                real(t->weight / 1000, 4), real(values[best], 4), m->members[member].id,
                combinations[c].name, change_count);
        for (int i = 0; i < change_count; ++i) {
            int group = changes[i];
            n = 0;
            for (int k = 0; k < t->group_sizes[group]; ++k)
                for (int j = 0; j < m->combination_count; ++j)
                    values[n++] = t->uses[t->group_members[group][k]][j];
            fprintf(out, "change %s %s %s utilization %s\n", t->group_names[group],
                    m->sections[t->choices[t->group_members[group][0]]].name,
                    m->sections[next[group]].name, real(values[extreme(values, n, false)], 4));
        }
        if (!change_count) {
            converged = true;
            break;
        }
        if (round == 10)
            break;
        for (int group = 0; group < t->group_count; ++group)
            for (int i = 0; i < t->group_sizes[group]; ++i)
                t->choices[t->group_members[group][i]] = next[group];
    }
    fprintf(out, "result %s rounds %d\n", converged ? "converged" : "not_converged", last_round);
    for (int member = 0; member < m->member_count; ++member) {
        int c = extreme(t->uses[member], m->combination_count, false);
        t->governing_cases[member] = c;
        t->governing[member] = t->uses[member][c];
    }
}
static void design_report(const Truss *t, FILE *out) {
    const Model *m = &t->model;
    const Result *combinations = &t->results[m->case_count];
    for (int group = 0; group < t->group_count; ++group) {
        double values[80];
        for (int i = 0; i < t->group_sizes[group]; ++i)
            values[i] = t->governing[t->group_members[group][i]];
        int member = t->group_members[group][extreme(values, t->group_sizes[group], false)];
        fprintf(out, "group %s section %s members %d utilization %s at %d\n", t->group_names[group],
                m->sections[t->choices[member]].name, t->group_sizes[group],
                real(t->governing[member], 4), m->members[member].id);
    }
    for (int i = 0; i < m->member_count; ++i) {
        double ratio = slenderness(&t->final_system.properties[i], &t->geometry[i], NULL);
        fprintf(
            out,
            "member %d group %s section %s utilization %s governing %s slenderness %s limit %s %s\n",
            m->members[i].id, m->members[i].group, m->sections[t->choices[i]].name,
            real(t->governing[i], 4), combinations[t->governing_cases[i]].name, real(ratio, 4),
            real(t->limits[i], 4), t->governing[i] <= 1 && ratio <= t->limits[i] ? "ok" : "over");
    }
    int rank[80];
    for (int i = 0; i < m->member_count; ++i) {
        int p = i;
        while (p > 0 && rounded(t->governing[i]) > rounded(t->governing[rank[p - 1]])) {
            rank[p] = rank[p - 1];
            --p;
        }
        rank[p] = i;
    }
    for (int i = 0; i < m->member_count && i < 5; ++i)
        fprintf(out, "rank %d member %d utilization %s\n", i + 1, m->members[rank[i]].id,
                real(t->governing[rank[i]], 4));
    for (int member = 0; member < m->member_count; ++member) {
        double values[10];
        for (int c = 0; c < m->combination_count; ++c)
            values[c] = combinations[c].forces[member] / 1000;
        int high = extreme(values, m->combination_count, false),
            low = extreme(values, m->combination_count, true);
        fprintf(out, "envelope %d max %s %s min %s %s\n", m->members[member].id,
                real(values[high], 4), combinations[high].name, real(values[low], 4),
                combinations[low].name);
    }
    for (int section = 0; section < m->section_count; ++section) {
        int count = 0;
        double length = 0;
        for (int i = 0; i < m->member_count; ++i)
            if (t->choices[i] == section) {
                ++count;
                length += t->geometry[i].length;
            }
        if (count)
            fprintf(out, "section %s members %d length %s\n", m->sections[section].name, count,
                    real(length, 4));
    }
    fprintf(out, "weight %s\n", real(t->weight / 1000, 4));
}
static void analysis_report(Truss *t, FILE *out) {
    const Model *m = &t->model;
    const Result *combinations = &t->results[m->case_count];
    fprintf(
        out,
        "model nodes %d members %d supports %d free_dofs %d restrained_dofs %d indeterminacy %d\n",
        m->node_count, m->member_count, m->support_count, t->nf, t->nr,
        m->member_count + t->nr - t->degrees);
    fputs("renumbering", out);
    for (int i = 0; i < m->node_count; ++i)
        fprintf(out, " %d", m->nodes[t->order[i]].id);
    fputc('\n', out);
    int original[40], before_band, before_profile, after_band, after_profile;
    for (int i = 0; i < m->node_count; ++i)
        original[i] = i;
    metrics(t, original, &before_band, &before_profile);
    metrics(t, t->numbers, &after_band, &after_profile);
    fprintf(out, "bandwidth before %d after %d\nprofile before %d after %d\n", before_band,
            after_band, before_profile, after_profile);
    for (int i = 0; i < m->member_count; ++i) {
        const Member *member = &m->members[i];
        const Geometry *g = &t->geometry[i];
        fprintf(out, "member %d nodes %d %d length %s cos %s sin %s\n", member->id,
                m->nodes[member->start].id, m->nodes[member->end].id, real(g->length, 4),
                real(g->cosine, 6), real(g->sine, 6));
    }
    for (int index = 0; index < m->case_count + m->combination_count; ++index) {
        const Result *r = &t->results[index];
        double moves[40];
        magnitudes(t, r, moves);
        int chosen = extreme(moves, m->node_count, false);
        double energy = 0, scale = 1, reaction[2] = {0}, external[2] = {0};
        for (int member = 0; member < m->member_count; ++member) {
            const Properties *p = &t->final_system.properties[member];
            energy += r->forces[member] * r->forces[member] * t->geometry[member].length /
                      (2 * p->young * p->area);
        }
        for (int node = 0; node < m->node_count; ++node)
            for (int a = 0; a < 2; ++a) {
                int d = t->node_dofs[node][a];
                reaction[a] += r->reactions[d];
                external[a] += r->external[d];
                scale = fmax(scale, fabs(r->reactions[d]));
                scale = fmax(scale, fabs(r->external[d]));
            }
        fprintf(
            out,
            "%s %s equilibrium %s max_displacement %s at %d energy %s reactions %s %s loads %s %s\n",
            index < m->case_count ? "case" : "combination", r->name,
            equilibrium_residual(r, t->geometry, m->member_count, t->degrees) <= 0.000001 * scale
                ? "ok"
                : "failed",
            real(moves[chosen], 4), m->nodes[chosen].id, real(energy / 1000, 4),
            real(reaction[0] / 1000, 4), real(reaction[1] / 1000, 4), real(external[0] / 1000, 4),
            real(external[1] / 1000, 4));
    }
    for (int i = 0; i < t->direction_count; ++i) {
        const int *d = t->support_directions[i];
        double values[10];
        bool uplift = false;
        for (int c = 0; c < m->combination_count; ++c) {
            values[c] = combinations[c].reactions[d[2]] / 1000;
            if (combinations[c].reactions[d[2]] < 0)
                uplift = true;
        }
        int high = extreme(values, m->combination_count, false),
            low = extreme(values, m->combination_count, true);
        fprintf(out, "reaction_envelope %d %c max %s %s min %s %s", m->nodes[d[0]].id, "xy"[d[1]],
                real(values[high], 4), combinations[high].name, real(values[low], 4),
                combinations[low].name);
        if (d[1])
            fprintf(out, " uplift %s", uplift ? "yes" : "no");
        fputc('\n', out);
    }
    for (int node = 0; node < m->node_count; ++node) {
        double values[10], moves[40];
        for (int c = 0; c < m->combination_count; ++c) {
            magnitudes(t, &combinations[c], moves);
            values[c] = moves[node];
        }
        int chosen = extreme(values, m->combination_count, false);
        fprintf(out, "displacement_envelope %d max %s %s\n", m->nodes[node].id,
                real(values[chosen], 4), combinations[chosen].name);
    }
    const Result *deflection = find_result(t, m->settings.deflection);
    int anchors[40], anchor_count = 0;
    for (int k = 0; k < m->settings.deck_count; ++k)
        for (int i = 0; i < t->direction_count; ++i)
            if (t->support_directions[i][0] == m->settings.deck[k] &&
                t->support_directions[i][1] == 1)
                anchors[anchor_count++] = k;
    for (int span = 1; span < anchor_count; ++span) {
        int a = anchors[span - 1], b = anchors[span], na = m->settings.deck[a],
            nb = m->settings.deck[b];
        double va = deflection->displacement[t->node_dofs[na][1]],
               vb = deflection->displacement[t->node_dofs[nb][1]], values[40];
        int n = 0;
        for (int k = a + 1; k < b; ++k) {
            int node = m->settings.deck[k];
            values[n++] = fabs(deflection->displacement[t->node_dofs[node][1]] -
                               (va + (vb - va) * (m->nodes[node].x - m->nodes[na].x) /
                                         (m->nodes[nb].x - m->nodes[na].x)));
        }
        int chosen = extreme(values, n, false), nt = m->settings.deck[a + 1 + chosen];
        double limit = (double)(m->nodes[nb].x - m->nodes[na].x) / m->settings.deflection_ratio;
        fprintf(out, "deflection %s span %d %d max %s at %d limit %s %s\n", deflection->name,
                m->nodes[na].id, m->nodes[nb].id, real(values[chosen], 4), m->nodes[nt].id,
                real(limit, 4), values[chosen] <= limit ? "ok" : "exceeded");
        const Result *unit = unit_result(t, nt);
        double work = 0;
        for (int i = 0; i < m->member_count; ++i) {
            const Properties *p = &t->final_system.properties[i];
            work += deflection->forces[i] * (unit->forces[i] / 1000) * t->geometry[i].length /
                    (p->young * p->area);
        }
        double stiffness = -deflection->displacement[t->node_dofs[nt][1]];
        fprintf(out, "virtual_work %s node %d stiffness %s virtual %s %s\n", deflection->name,
                m->nodes[nt].id, real(stiffness, 4), real(work, 4),
                fabs(work - stiffness) <= 0.000001 * fmax(1, fabs(stiffness)) ? "ok" : "failed");
    }
    const Combination *definition = NULL;
    for (int c = 0; c < m->combination_count; ++c)
        if (!strcmp(m->combinations[c].name, m->settings.removal))
            definition = &m->combinations[c];
    System *structure = malloc(sizeof *structure);
    for (int removed = 0; removed < m->member_count; ++removed) {
        make_system(t, removed, structure);
        if (structure->unstable >= 0) {
            const int *owner = t->owners[structure->unstable];
            fprintf(out, "removal %d unstable at %d %c\n", m->members[removed].id,
                    m->nodes[owner[0]].id, "xy"[owner[1]]);
        } else {
            bool needed[10] = {false};
            Result cases[10] = {0}, r;
            for (int i = 0; i < definition->count; ++i)
                needed[definition->terms[i].index] = true;
            for (int i = 0; i < m->case_count; ++i)
                if (needed[i])
                    case_result(t, structure, &m->cases[i], &cases[i]);
            superpose(definition, cases, m->member_count, t->degrees, &r);
            double values[80], moves[40];
            int members[80], n = 0;
            for (int i = 0; i < m->member_count; ++i)
                if (i != removed) {
                    members[n] = i;
                    values[n++] =
                        utilization(r.forces[i], &structure->properties[i], &t->geometry[i], NULL);
                }
            int chosen = extreme(values, n, false);
            magnitudes(t, &r, moves);
            int node = extreme(moves, m->node_count, false);
            fprintf(out, "removal %d stable max_utilization %s at %d max_displacement %s at %d\n",
                    m->members[removed].id, real(values[chosen], 4), m->members[members[chosen]].id,
                    real(moves[node], 4), m->nodes[node].id);
        }
    }
    free(structure);
}
static double ordinate(const Truss *t, const double *values, int x) {
    const Model *m = &t->model;
    const Settings *s = &m->settings;
    if (x < m->nodes[s->deck[0]].x || x > m->nodes[s->deck[s->deck_count - 1]].x)
        return 0;
    if (x == m->nodes[s->deck[s->deck_count - 1]].x)
        return values[s->deck_count - 1];
    int k = 0;
    while (m->nodes[s->deck[k + 1]].x <= x)
        ++k;
    return values[k] + (values[k + 1] - values[k]) * (x - m->nodes[s->deck[k]].x) /
                           (m->nodes[s->deck[k + 1]].x - m->nodes[s->deck[k]].x);
}
static void vehicle(const Truss *t, const double *values, const int *positions, int count,
                    double *effects) {
    for (int i = 0; i < count; ++i) {
        double value = 0;
        for (int a = 0; a < t->model.settings.axle_count; ++a) {
            const Axle *axle = &t->model.settings.axles[a];
            value += axle->load * ordinate(t, values, positions[i] - axle->offset);
        }
        effects[i] = value;
    }
}
static void influence_report(Truss *t, FILE *out) {
    const Model *m = &t->model;
    const Settings *s = &m->settings;
    double member_lines[80][40], reaction_lines[80][40];
    for (int k = 0; k < s->deck_count; ++k) {
        const Result *unit = unit_result(t, s->deck[k]);
        for (int i = 0; i < m->member_count; ++i)
            member_lines[i][k] = unit->forces[i] / 1000;
        for (int i = 0; i < t->nr; ++i) {
            int d = t->restrained[i];
            reaction_lines[d][k] = unit->reactions[d] / 1000;
        }
    }
    for (int i = 0; i < s->influence_count; ++i) {
        int member = s->influence[i];
        const double *values = member_lines[member];
        double positive = 0, negative = 0;
        fprintf(out, "influence %d\n", m->members[member].id);
        for (int k = 0; k < s->deck_count; ++k) {
            fprintf(out, "node %d %s\n", m->nodes[s->deck[k]].id, real(values[k], 4));
            if (values[k] > 0)
                positive += values[k];
            else if (values[k] < 0)
                negative += values[k];
        }
        int high = extreme(values, s->deck_count, false),
            low = extreme(values, s->deck_count, true);
        fprintf(out, "max %s at %d min %s at %d positive %s negative %s\n", real(values[high], 4),
                m->nodes[s->deck[high]].id, real(values[low], 4), m->nodes[s->deck[low]].id,
                real(positive, 4), real(negative, 4));
        double crossings[40];
        int count = 0;
        for (int k = 0; k + 1 < s->deck_count; ++k)
            if ((values[k] > 0 && values[k + 1] < 0) || (values[k] < 0 && values[k + 1] > 0))
                crossings[count++] =
                    m->nodes[s->deck[k]].x + (m->nodes[s->deck[k + 1]].x - m->nodes[s->deck[k]].x) *
                                                 values[k] / (values[k] - values[k + 1]);
        fprintf(out, "crossings %d", count);
        for (int k = 0; k < count; ++k)
            fprintf(out, " %s", real(crossings[k], 1));
        fputc('\n', out);
    }
    int positions[1000], count = 0;
    for (int p = m->nodes[s->deck[0]].x;
         p <= m->nodes[s->deck[s->deck_count - 1]].x + s->axles[s->axle_count - 1].offset;
         p += s->vehicle_step)
        positions[count++] = p;
    fprintf(out, "vehicle axles %d positions %d\n", s->axle_count, count);
    double effects[1000], tension[80], compression[80];
    for (int member = 0; member < m->member_count; ++member) {
        vehicle(t, member_lines[member], positions, count, effects);
        int high = extreme(effects, count, false), low = extreme(effects, count, true);
        tension[member] = effects[high];
        compression[member] = effects[low];
        fprintf(out, "vehicle_member %d max %s at %d min %s at %d\n", m->members[member].id,
                real(effects[high], 4), positions[high], real(effects[low], 4), positions[low]);
    }
    for (int i = 0; i < t->direction_count; ++i) {
        const int *d = t->support_directions[i];
        vehicle(t, reaction_lines[d[2]], positions, count, effects);
        int high = extreme(effects, count, false), low = extreme(effects, count, true);
        fprintf(out, "vehicle_reaction %d %c max %s at %d min %s at %d\n", m->nodes[d[0]].id,
                "xy"[d[1]], real(effects[high], 4), positions[high], real(effects[low], 4),
                positions[low]);
    }
    const Result *dead = find_result(t, s->rating);
    double ratings[160];
    int rating_members[160], rating_kinds[160], rating_count = 0;
    for (int i = 0; i < m->member_count; ++i) {
        const Properties *p = &t->final_system.properties[i];
        double nd = dead->forces[i] / 1000, pt = p->area * p->yield_stress / 1000,
               pc =
                   fmin(p->area * p->yield_stress, buckling(p, &t->geometry[i], p->inertia)) / 1000;
        const char *tension_text = "none", *compression_text = "none";
        if (rounded(tension[i]) > 0) {
            double value = (pt - s->dead_factor * nd) / (s->vehicle_factor * tension[i]);
            tension_text = real(value, 4);
            ratings[rating_count] = value;
            rating_members[rating_count] = i;
            rating_kinds[rating_count++] = 0;
        }
        if (rounded(compression[i]) < 0) {
            double value = (pc + s->dead_factor * nd) / (s->vehicle_factor * (-compression[i]));
            compression_text = real(value, 4);
            ratings[rating_count] = value;
            rating_members[rating_count] = i;
            rating_kinds[rating_count++] = 1;
        }
        fprintf(out, "rating %d tension %s compression %s\n", m->members[i].id, tension_text,
                compression_text);
    }
    int low = extreme(ratings, rating_count, true);
    fprintf(out, "rating_min %s at %d %s\n", real(ratings[low], 4),
            m->members[rating_members[low]].id, rating_kinds[low] ? "compression" : "tension");
}
static void vibration_report(const Truss *t, FILE *out) {
    const Model *m = &t->model;
    const Settings *s = &m->settings;
    const Result *loading = find_result(t, s->vibration);
    double masses[40], free_masses[80], total_mass = 0;
    for (int node = 0; node < m->node_count; ++node) {
        masses[node] = -loading->external[t->node_dofs[node][1]] / 9.81;
        total_mass += masses[node];
    }
    for (int i = 0; i < t->nf; ++i)
        free_masses[i] = masses[t->owners[t->free_dofs[i]][0]];
    fprintf(out, "vibration %s mass %s iterations %d\n", loading->name, real(total_mass, 4),
            s->iterations);
    double modes[3][80];
    for (int mode = 0; mode < s->modes; ++mode) {
        double x[80];
        for (int i = 0; i < t->nf; ++i)
            x[i] = 1;
        for (int iteration = 0; iteration < s->iterations; ++iteration) {
            for (int previous = 0; previous < mode; ++previous) {
                double beta = 0;
                for (int i = 0; i < t->nf; ++i)
                    beta += modes[previous][i] * free_masses[i] * x[i];
                for (int i = 0; i < t->nf; ++i)
                    x[i] = x[i] - beta * modes[previous][i];
            }
            double right[80], y[80], norm = 0;
            for (int i = 0; i < t->nf; ++i)
                right[i] = free_masses[i] * x[i];
            solve(&t->final_system.lower, right, y);
            for (int i = 0; i < t->nf; ++i)
                norm += free_masses[i] * y[i] * y[i];
            norm = sqrt(norm);
            for (int i = 0; i < t->nf; ++i)
                x[i] = y[i] / norm;
        }
        memcpy(modes[mode], x, (size_t)t->nf * sizeof *x);
        double numerator = 0, denominator = 0;
        for (int i = 0; i < t->nf; ++i) {
            double kx = 0;
            for (int j = 0; j < t->nf; ++j)
                kx += t->final_system.free_matrix.v[i][j] * x[j];
            numerator += x[i] * kx;
            denominator += free_masses[i] * x[i] * x[i];
        }
        double frequency = sqrt(1000 * (numerator / denominator)) / (2 * PI);
        fprintf(out, "mode %d frequency %s period %s\n", mode + 1, real(frequency, 4),
                real(1 / frequency, 4));
        int peak = 0;
        for (int i = 1; i < t->nf; ++i)
            if (fabs(x[i]) > fabs(x[peak]))
                peak = i;
        double normalized[80] = {0};
        for (int i = 0; i < t->nf; ++i)
            normalized[t->free_dofs[i]] = x[i] / x[peak];
        for (int node = 0; node < m->node_count; ++node)
            fprintf(out, "node %d %s %s\n", m->nodes[node].id,
                    real(normalized[t->node_dofs[node][0]], 4),
                    real(normalized[t->node_dofs[node][1]], 4));
    }
}
typedef struct {
    int column, row;
} Point;
typedef struct {
    int x0, y1, horizontal, vertical, width, height;
    char *grid;
} Canvas;
static Canvas canvas(const Model *m, int wc, int hc) {
    int x0 = m->nodes[0].x, x1 = x0, y0 = m->nodes[0].y, y1 = y0;
    for (int i = 1; i < m->node_count; ++i) {
        const Node *p = &m->nodes[i];
        if (p->x < x0)
            x0 = p->x;
        if (p->x > x1)
            x1 = p->x;
        if (p->y < y0)
            y0 = p->y;
        if (p->y > y1)
            y1 = p->y;
    }
    Canvas out = {x0,
                  y1,
                  wc,
                  hc,
                  (int)floor((double)(x1 - x0) / wc + 0.5) + 5,
                  (int)floor((double)(y1 - y0) / hc + 0.5) + 5,
                  NULL};
    out.grid = malloc((size_t)out.width * out.height);
    memset(out.grid, ' ', (size_t)out.width * out.height);
    return out;
}
static Point position(const Canvas *c, double x, double y) {
    return (Point){(int)floor((x - c->x0) / c->horizontal + 0.5) + 2,
                   (int)floor((c->y1 - y) / c->vertical + 0.5) + 2};
}
static void put(Canvas *c, Point p, char character) {
    if (p.column >= 0 && p.column < c->width && p.row >= 0 && p.row < c->height)
        c->grid[(size_t)p.row * c->width + p.column] = character;
}
static void segment(Canvas *canvas, Point first, Point last, char character) {
    int c = first.column, r = first.row, dc = abs(last.column - c), dr = -abs(last.row - r),
        sc = c < last.column ? 1 : -1, sr = r < last.row ? 1 : -1, error = dc + dr;
    for (;;) {
        put(canvas, (Point){c, r}, character);
        if (c == last.column && r == last.row)
            break;
        int twice = 2 * error;
        if (twice >= dr) {
            error += dr;
            c += sc;
        }
        if (twice <= dc) {
            error += dc;
            r += sr;
        }
    }
}
static void frame(const Canvas *c, FILE *out) {
    for (int pass = 0; pass < 2; ++pass) {
        fputc('+', out);
        for (int i = 0; i < c->width; ++i)
            fputc('-', out);
        fputs("+\n", out);
        if (pass == 0)
            for (int r = 0; r < c->height; ++r) {
                fputc('|', out);
                fwrite(c->grid + (size_t)r * c->width, 1, (size_t)c->width, out);
                fputs("|\n", out);
            }
    }
}
static void drawing_report(const Truss *t, FILE *out) {
    const Model *m = &t->model;
    const Settings *s = &m->settings;
    for (int i = 0; i < s->drawing_count; ++i) {
        const Drawing *d = &s->drawings[i];
        Canvas c = canvas(m, d->horizontal, d->vertical);
        const Result *r = find_result(t, d->name);
        Point original[40], deformed[40];
        for (int node = 0; node < m->node_count; ++node) {
            const Node *p = &m->nodes[node];
            original[node] = position(&c, p->x, p->y);
            deformed[node] =
                position(&c, p->x + d->magnification * r->displacement[t->node_dofs[node][0]],
                         p->y + d->magnification * r->displacement[t->node_dofs[node][1]]);
        }
        for (int k = 0; k < m->member_count; ++k)
            segment(&c, original[m->members[k].start], original[m->members[k].end], '.');
        for (int node = 0; node < m->node_count; ++node)
            put(&c, original[node], '+');
        for (int k = 0; k < m->member_count; ++k)
            segment(&c, deformed[m->members[k].start], deformed[m->members[k].end], '*');
        for (int node = 0; node < m->node_count; ++node)
            put(&c, deformed[node], 'o');
        fprintf(out, "drawing %s magnification %d columns %d rows %d\n", d->name, d->magnification,
                c.width, c.height);
        frame(&c, out);
        free(c.grid);
    }
    Canvas c = canvas(m, s->map_horizontal, s->map_vertical);
    Point points[40];
    for (int node = 0; node < m->node_count; ++node)
        points[node] = position(&c, m->nodes[node].x, m->nodes[node].y);
    for (int member = 0; member < m->member_count; ++member) {
        char character =
            t->governing[member] >= 1 ? '#' : (char)('0' + (int)floor(10 * t->governing[member]));
        segment(&c, points[m->members[member].start], points[m->members[member].end], character);
    }
    for (int node = 0; node < m->node_count; ++node)
        put(&c, points[node], 'o');
    fprintf(out, "utilization_map columns %d rows %d\n", c.width, c.height);
    frame(&c, out);
    free(c.grid);
}
static void csv_reports(const Truss *t) {
    FILE *displacement_file = output("displacements.csv"),
         *force_file = output("member_forces.csv"), *reaction_file = output("reactions.csv");
    fputs("case,node,dx,dy\n", displacement_file);
    fputs("case,member,force,stress,utilization\n", force_file);
    fputs("case,node,rx,ry\n", reaction_file);
    const Model *m = &t->model;
    for (int index = 0; index < m->case_count + m->combination_count; ++index) {
        const Result *r = &t->results[index];
        for (int node = 0; node < m->node_count; ++node)
            fprintf(displacement_file, "%s,%d,%s,%s\n", r->name, m->nodes[node].id,
                    real(r->displacement[t->node_dofs[node][0]], 4),
                    real(r->displacement[t->node_dofs[node][1]], 4));
        for (int i = 0; i < m->member_count; ++i)
            fprintf(force_file, "%s,%d,%s,%s,%s\n", r->name, m->members[i].id,
                    real(r->forces[i] / 1000, 4),
                    real(r->forces[i] / t->final_system.properties[i].area, 4),
                    real(utilization(r->forces[i], &t->final_system.properties[i], &t->geometry[i],
                                     NULL),
                         4));
        for (int i = 0; i < m->support_count; ++i) {
            int node = m->supports[i].node;
            fprintf(reaction_file, "%s,%d,%s,%s\n", r->name, m->nodes[node].id,
                    real(r->reactions[t->node_dofs[node][0]] / 1000, 4),
                    real(r->reactions[t->node_dofs[node][1]] / 1000, 4));
        }
    }
    fclose(displacement_file);
    fclose(force_file);
    fclose(reaction_file);
}
int main(void) {
    Truss *t = calloc(1, sizeof *t);
    read_model(&t->model);
    initialize(t);
    mkdir("output", 0777);
    FILE *file = output("design.txt");
    design_sections(t, file);
    design_report(t, file);
    fclose(file);
    file = output("analysis.txt");
    analysis_report(t, file);
    fclose(file);
    file = output("influence.txt");
    influence_report(t, file);
    fclose(file);
    file = output("vibration.txt");
    vibration_report(t, file);
    fclose(file);
    file = output("drawing.txt");
    drawing_report(t, file);
    fclose(file);
    csv_reports(t);
    free(t->model.settings.drawings);
    free(t->model.settings.influence);
    free(t);
    return 0;
}
