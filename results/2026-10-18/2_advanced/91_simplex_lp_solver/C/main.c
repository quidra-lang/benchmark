#include "solver.h"
static void append_owned(TextLines *to, TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_push(to, from->data[i]);
    free(from->data);
    *from = (TextLines){0};
}
const char *status_name(Status status) {
    static const char *names[] = {"OPTIMAL", "INFEASIBLE", "UNBOUNDED", "NODE_LIMIT", "ERROR"};
    return names[status];
}
const char *comparison_name(Comparison comparison) {
    static const char *names[] = {"<=", ">=", "="};
    return names[comparison];
}
static int variable_index(const Model *model, const char *name) {
    for (int i = 0; i < model->variable_count; ++i)
        if (!strcmp(model->variables[i], name))
            return i;
    return -1;
}
static void register_terms(Model *model, const Terms *terms) {
    for (int i = 0; i < terms->count; ++i)
        if (variable_index(model, terms->data[i].name) < 0) {
            if (model->variable_count == model->variable_capacity) {
                model->variable_capacity =
                    model->variable_capacity ? model->variable_capacity * 2 : 16;
                model->variables = resize(model->variables, (size_t)model->variable_capacity *
                                                                sizeof *model->variables);
            }
            strcpy(model->variables[model->variable_count++], terms->data[i].name);
        }
}
static bool inconsistent(const Model *model, int variable) {
    return model->lower[variable].finite && model->upper[variable].finite &&
           rat_compare(model->lower[variable].value, model->upper[variable].value) > 0;
}
static Model make_model(const RawModel *raw) {
    Model out = {0};
    strcpy(out.name, raw->name);
    out.maximize = raw->maximize;
    if (raw->error.message) {
        out.error = (ModelError){raw->error.line, copy_text(raw->error.message)};
        return out;
    }
    register_terms(&out, &raw->objective);
    for (int i = 0; i < raw->constraint_count; ++i)
        register_terms(&out, &raw->constraints[i].terms);
    int count = out.variable_count;
    out.cost = allocate((size_t)count * sizeof *out.cost);
    out.lower = allocate((size_t)count * sizeof *out.lower);
    out.upper = allocate((size_t)count * sizeof *out.upper);
    out.integer = allocate((size_t)count * sizeof *out.integer);
    for (int j = 0; j < count; ++j)
        out.lower[j] = (Bound){true, {0, 1}};
    for (int i = 0; i < raw->objective.count; ++i) {
        const Term *term = &raw->objective.data[i];
        int j = variable_index(&out, term->name);
        out.cost[j] = rat_add(out.cost[j], term->coefficient);
    }
    out.constraint_count = raw->constraint_count;
    out.constraints = allocate((size_t)out.constraint_count * sizeof *out.constraints);
    for (int i = 0; i < out.constraint_count; ++i) {
        const RawConstraint *source = &raw->constraints[i];
        Constraint *row = &out.constraints[i];
        strcpy(row->name, source->name);
        row->comparison = source->comparison;
        row->rhs = source->rhs;
        row->coefficients = allocate((size_t)count * sizeof *row->coefficients);
        for (int t = 0; t < source->terms.count; ++t) {
            const Term *term = &source->terms.data[t];
            int j = variable_index(&out, term->name);
            row->coefficients[j] = rat_add(row->coefficients[j], term->coefficient);
        }
    }
    for (int i = 0; i < out.constraint_count; ++i)
        for (int j = 0; j < i; ++j)
            if (!strcmp(out.constraints[i].name, out.constraints[j].name)) {
                out.error =
                    (ModelError){raw->constraints[i].line,
                                 format_text("duplicate constraint %s", out.constraints[i].name)};
                return out;
            }
    for (int i = 0; i < raw->bound_count; ++i) {
        const BoundLine *bound = &raw->bounds[i];
        int j = variable_index(&out, bound->name);
        if (j < 0) {
            out.error = (ModelError){bound->line, format_text("unknown variable %s", bound->name)};
            return out;
        }
        if (bound->kind == BOUND_LOWER || bound->kind == BOUND_BOTH)
            out.lower[j] = bound->lower;
        if (bound->kind == BOUND_UPPER || bound->kind == BOUND_BOTH)
            out.upper[j] = bound->upper;
        if (inconsistent(&out, j)) {
            out.error =
                (ModelError){bound->line, format_text("inconsistent bounds %s", bound->name)};
            return out;
        }
    }
    for (int i = 0; i < raw->integer_count; ++i)
        for (int k = 0; k < raw->integers[i].names.count; ++k) {
            const Declaration *declaration = &raw->integers[i];
            const char *name = declaration->names.data[k];
            int j = variable_index(&out, name);
            if (j < 0) {
                out.error =
                    (ModelError){declaration->line, format_text("unknown variable %s", name)};
                return out;
            }
            out.integer[j] = true;
            if (out.lower[j].finite)
                out.lower[j].value = integer(rat_ceil(out.lower[j].value));
            if (out.upper[j].finite)
                out.upper[j].value = integer(rat_floor(out.upper[j].value));
            if (inconsistent(&out, j)) {
                out.error =
                    (ModelError){declaration->line, format_text("inconsistent bounds %s", name)};
                return out;
            }
        }
    for (int i = 0; i < raw->binary_count; ++i)
        for (int k = 0; k < raw->binaries[i].names.count; ++k) {
            const Declaration *declaration = &raw->binaries[i];
            const char *name = declaration->names.data[k];
            int j = variable_index(&out, name);
            if (j < 0) {
                out.error =
                    (ModelError){declaration->line, format_text("unknown variable %s", name)};
                return out;
            }
            out.integer[j] = true;
            out.lower[j] = (Bound){true, {0, 1}};
            out.upper[j] = (Bound){true, {1, 1}};
        }
    return out;
}
static void model_free(Model *model) {
    free(model->variables);
    free(model->cost);
    free(model->lower);
    free(model->upper);
    free(model->integer);
    for (int i = 0; i < model->constraint_count; ++i)
        free(model->constraints[i].coefficients);
    free(model->constraints);
    free(model->error.message);
}
int integer_count(const Model *model) {
    int count = 0;
    for (int j = 0; j < model->variable_count; ++j)
        if (model->integer[j])
            ++count;
    return count;
}
static int add_variable(Standard *standard, const char *name, int variable, int direction) {
    int column = standard->tableau.columns++;
    strcpy(standard->columns[column], name);
    standard->column_variable[column] = variable;
    standard->directions[column] = direction;
    return column;
}
static int add_extra(Standard *standard, const char *name, int row, Rational value,
                     bool artificial) {
    int column = standard->tableau.columns++;
    strcpy(standard->columns[column], name);
    standard->column_variable[column] = -1;
    standard->artificial[column] = artificial;
    standard->tableau.values[row][column] = value;
    return column;
}
static void standard_form(Standard *standard, const Model *model, const Bound *lower,
                          const Bound *upper) {
    standard->sign = model->maximize ? -1 : 1;
    standard->map_count = model->variable_count;
    Tableau *tableau = &standard->tableau;
    for (int j = 0; j < model->variable_count; ++j) {
        VariableMap *mapping = &standard->maps[j];
        mapping->upper_row = -1;
        if (lower[j].finite) {
            mapping->kind = MAP_SHIFT;
            mapping->offset = lower[j].value;
            mapping->column_count = 1;
            mapping->columns[0] = add_variable(standard, model->variables[j], j, 1);
        } else if (upper[j].finite) {
            mapping->kind = MAP_REFLECT;
            mapping->offset = upper[j].value;
            mapping->column_count = 1;
            char *name = format_text("%s'", model->variables[j]);
            mapping->columns[0] = add_variable(standard, name, j, -1);
            free(name);
        } else {
            mapping->kind = MAP_SPLIT;
            mapping->column_count = 2;
            char *name = format_text("%s+", model->variables[j]);
            mapping->columns[0] = add_variable(standard, name, j, 1);
            free(name);
            name = format_text("%s-", model->variables[j]);
            mapping->columns[1] = add_variable(standard, name, j, -1);
            free(name);
        }
        standard->constant = rat_add(standard->constant, rat_mul(model->cost[j], mapping->offset));
    }
    for (int i = 0; i < model->constraint_count; ++i) {
        const Constraint *constraint = &model->constraints[i];
        int row = tableau->rows++;
        strcpy(standard->rows[row], constraint->name);
        standard->comparisons[row] = constraint->comparison;
        Rational rhs = constraint->rhs;
        for (int j = 0; j < model->variable_count; ++j) {
            const VariableMap *mapping = &standard->maps[j];
            rhs = rat_sub(rhs, rat_mul(constraint->coefficients[j], mapping->offset));
            for (int c = 0; c < mapping->column_count; ++c) {
                int column = mapping->columns[c];
                tableau->values[row][column] =
                    rat_mul(constraint->coefficients[j], integer(standard->directions[column]));
            }
        }
        tableau->beta[row] = rhs;
    }
    for (int j = 0; j < model->variable_count; ++j)
        if (standard->maps[j].kind == MAP_SHIFT && upper[j].finite) {
            int row = tableau->rows++;
            standard->maps[j].upper_row = row;
            snprintf(standard->rows[row], sizeof standard->rows[row], "%s.ub", model->variables[j]);
            standard->comparisons[row] = COMP_LE;
            tableau->values[row][standard->maps[j].columns[0]] = integer(1);
            tableau->beta[row] = rat_sub(upper[j].value, lower[j].value);
        }
    for (int row = 0; row < tableau->rows; ++row) {
        standard->sigma[row] = 1;
        standard->slack[row] = standard->initial[row] = -1;
        if (tableau->beta[row].numerator < 0) {
            standard->sigma[row] = -1;
            tableau->beta[row] = rat_neg(tableau->beta[row]);
            for (int k = 0; k < tableau->columns; ++k)
                tableau->values[row][k] = rat_neg(tableau->values[row][k]);
            if (standard->comparisons[row] == COMP_LE)
                standard->comparisons[row] = COMP_GE;
            else if (standard->comparisons[row] == COMP_GE)
                standard->comparisons[row] = COMP_LE;
        }
    }
    for (int row = 0; row < tableau->rows; ++row)
        if (standard->comparisons[row] != COMP_EQ) {
            char *name = format_text("s:%s", standard->rows[row]);
            standard->slack[row] =
                add_extra(standard, name, row,
                          integer(standard->comparisons[row] == COMP_LE ? 1 : -1), false);
            free(name);
            if (standard->comparisons[row] == COMP_LE)
                standard->initial[row] = standard->slack[row];
        }
    for (int row = 0; row < tableau->rows; ++row)
        if (standard->comparisons[row] != COMP_LE) {
            char *name = format_text("a:%s", standard->rows[row]);
            standard->initial[row] = add_extra(standard, name, row, integer(1), true);
            free(name);
        }
    for (int column = 0; column < tableau->columns; ++column) {
        int variable = standard->column_variable[column];
        if (variable >= 0)
            standard->costs2[column] = rat_mul(
                model->cost[variable], integer(standard->sign * standard->directions[column]));
        if (standard->artificial[column])
            standard->costs1[column] = integer(1);
    }
    for (int row = 0; row < tableau->rows; ++row)
        tableau->basis[row] = standard->initial[row];
}
static void original_values(const Standard *standard, const Rational *columns, bool direction,
                            Rational *out) {
    for (int j = 0; j < standard->map_count; ++j) {
        const VariableMap *mapping = &standard->maps[j];
        out[j] = direction ? integer(0) : mapping->offset;
        for (int c = 0; c < mapping->column_count; ++c) {
            int column = mapping->columns[c];
            out[j] =
                rat_add(out[j], rat_mul(columns[column], integer(standard->directions[column])));
        }
    }
}
static void lp_solution(const Standard *standard, Rational *out) {
    Rational columns[90] = {0};
    for (int row = 0; row < standard->tableau.rows; ++row)
        columns[standard->tableau.basis[row]] = standard->tableau.beta[row];
    original_values(standard, columns, false, out);
}
int lp_pivots(const LPResult *result) { return result->phase1 + result->phase2 + result->drives; }
static void emit(LPResult *result, int required, int level, char *line) {
    if (required <= level)
        lines_push(&result->log, line);
    else
        free(line);
}
static void display(LPResult *result, int level, const char *heading, const Rational *cost,
                    bool phase1) {
    if (level < 2)
        return;
    Standard *standard = &result->standard;
    TextLines lines =
        tableau_display(&standard->tableau, heading, standard, cost,
                        phase1 ? integer(0) : standard->constant, phase1 ? 1 : standard->sign);
    append_owned(&result->log, &lines);
}
static void finish(LPResult *result, int level) {
    emit(result, 0, level,
         format_text("RESULT %s objective %s phase1 %d phase2 %d drives %d redundant %d",
                     status_name(result->status),
                     result->status == OPTIMAL ? rat_text(result->objective).value : "-",
                     result->phase1, result->phase2, result->drives, result->redundant));
}
static void phase_log(LPResult *result, PhaseResult *phase, int level) {
    if (level >= 1)
        append_owned(&result->log, &phase->lines);
    else
        lines_free(&phase->lines);
}
LPResult *solve_lp(const Model *model, const Bound *lower, const Bound *upper, int number,
                   int level) {
    LPResult *out = allocate(sizeof *out);
    Standard *standard = &out->standard;
    standard_form(standard, model, lower, upper);
    Tableau *tableau = &standard->tableau;
    int artificials = 0;
    for (int k = 0; k < tableau->columns; ++k)
        if (standard->artificial[k])
            ++artificials;
    emit(out, 0, level,
         format_text("SOLVE node %d rows %d columns %d artificials %d", number, tableau->rows,
                     tableau->columns, artificials));
    for (int j = 0; j < model->variable_count; ++j) {
        const VariableMap *mapping = &standard->maps[j];
        const char *kind = mapping->kind == MAP_SHIFT     ? "shift"
                           : mapping->kind == MAP_REFLECT ? "reflect"
                                                          : "split";
        char *line;
        if (mapping->kind == MAP_SPLIT)
            line = format_text("MAP %s %s", model->variables[j], kind);
        else if (mapping->kind == MAP_SHIFT && upper[j].finite)
            line = format_text("MAP %s %s %s upper %s", model->variables[j], kind,
                               rat_text(mapping->offset).value, rat_text(upper[j].value).value);
        else
            line = format_text("MAP %s %s %s", model->variables[j], kind,
                               rat_text(mapping->offset).value);
        emit(out, 1, level, line);
    }
    for (int row = 0; row < tableau->rows; ++row)
        if (standard->sigma[row] < 0)
            emit(out, 1, level, format_text("FLIP %s", standard->rows[row]));
    bool all[90] = {0}, real[90] = {0};
    for (int k = 0; k < tableau->columns; ++k) {
        all[k] = true;
        real[k] = !standard->artificial[k];
    }
    if (artificials) {
        emit(out, 1, level, copy_text("PHASE 1"));
        display(out, level, "phase 1 start", standard->costs1, true);
        PhaseResult first = phase(tableau, standard->costs1, all, standard, integer(0), 1);
        out->phase1 = first.iterations;
        phase_log(out, &first, level);
        Rational reduced[90], w;
        tableau_reduced(tableau, standard->costs1, reduced, &w);
        out->w = w;
        emit(out, 1, level,
             format_text("PHASE 1 END objective %s iterations %d", rat_text(w).value, out->phase1));
        if (w.numerator > 0) {
            out->status = INFEASIBLE;
            for (int row = 0; row < tableau->rows; ++row) {
                int column = standard->initial[row];
                out->farkas[row] = rat_mul(rat_sub(standard->costs1[column], reduced[column]),
                                           integer(standard->sigma[row]));
            }
            display(out, level, "final", standard->costs1, true);
            finish(out, level);
            return out;
        }
        for (int row = 0; row < tableau->rows; ++row) {
            int previous = tableau->basis[row];
            if (!standard->artificial[previous])
                continue;
            int column = -1;
            for (int k = 0; k < tableau->columns; ++k)
                if (!standard->artificial[k] && tableau->values[row][k].numerator) {
                    column = k;
                    break;
                }
            if (column < 0) {
                ++out->redundant;
                emit(out, 1, level, format_text("REDUNDANT row %s", standard->rows[row]));
            } else {
                emit(out, 1, level,
                     format_text("DRIVE row %s enter %s leave %s", standard->rows[row],
                                 standard->columns[column], standard->columns[previous]));
                tableau_pivot(tableau, row, column);
                ++out->drives;
            }
        }
    }
    emit(out, 1, level, copy_text("PHASE 2"));
    display(out, level, "phase 2 start", standard->costs2, false);
    PhaseResult second =
        phase(tableau, standard->costs2, real, standard, standard->constant, standard->sign);
    out->phase2 = second.iterations;
    phase_log(out, &second, level);
    Rational reduced[90], z;
    tableau_reduced(tableau, standard->costs2, reduced, &z);
    out->objective = rat_add(standard->constant, rat_mul(integer(standard->sign), z));
    lp_solution(standard, out->solution);
    out->status = OPTIMAL;
    if (second.entering >= 0) {
        out->status = UNBOUNDED;
        emit(out, 1, level, format_text("UNBOUNDED enter %s", standard->columns[second.entering]));
        Rational delta[90] = {0};
        delta[second.entering] = integer(1);
        for (int row = 0; row < tableau->rows; ++row)
            delta[tableau->basis[row]] = rat_neg(tableau->values[row][second.entering]);
        original_values(standard, delta, true, out->ray);
        for (int j = 0; j < model->variable_count; ++j)
            out->rate = rat_add(out->rate, rat_mul(model->cost[j], out->ray[j]));
    }
    emit(out, 1, level,
         format_text("PHASE 2 END objective %s iterations %d", rat_text(out->objective).value,
                     out->phase2));
    display(out, level, "final", standard->costs2, false);
    finish(out, level);
    return out;
}
static FractionText range_text(Rational base, Bound limit, bool lower) {
    return limit.finite ? rat_text(rat_add(base, limit.value)) : bound_text(limit, lower);
}
static TextLines sensitivity(const Model *model, const LPResult *root) {
    const Standard *standard = &root->standard;
    const Tableau *tableau = &standard->tableau;
    Rational reduced[90], z;
    tableau_reduced(tableau, standard->costs2, reduced, &z);
    bool basic[90] = {0};
    TextLines basis = {0};
    int primal = 0, dual = 0;
    for (int row = 0; row < tableau->rows; ++row) {
        int column = tableau->basis[row];
        basic[column] = true;
        lines_add(&basis, standard->columns[column]);
        if (!standard->artificial[column] && !tableau->beta[row].numerator)
            ++primal;
    }
    for (int k = 0; k < tableau->columns; ++k)
        if (!basic[k] && !standard->artificial[k] && !reduced[k].numerator)
            ++dual;
    Rational prices[15] = {0}, variable_reduced[15] = {0}, dual_objective = integer(0);
    memcpy(variable_reduced, model->cost, (size_t)model->variable_count * sizeof *variable_reduced);
    for (int i = 0; i < model->constraint_count; ++i) {
        const Constraint *constraint = &model->constraints[i];
        prices[i] =
            rat_mul(reduced[standard->initial[i]], integer(-standard->sign * standard->sigma[i]));
        dual_objective = rat_add(dual_objective, rat_mul(prices[i], constraint->rhs));
        for (int j = 0; j < model->variable_count; ++j)
            variable_reduced[j] =
                rat_sub(variable_reduced[j], rat_mul(prices[i], constraint->coefficients[j]));
    }
    for (int j = 0; j < model->variable_count; ++j)
        dual_objective = rat_add(dual_objective, rat_mul(variable_reduced[j], root->solution[j]));
    TextLines out = {0};
    char *joined = join_texts(&basis, " ");
    lines_push(&out, format_text("MODEL %s %s objective %s", model->name,
                                 integer_count(model) ? "relaxation" : "lp",
                                 rat_text(root->objective).value));
    lines_push(&out, format_text("BASIS %s", joined));
    free(joined);
    lines_free(&basis);
    lines_push(&out, format_text("DEGENERACY primal %d dual %d", primal, dual));
    lines_push(&out, format_text("DUAL objective %s", rat_text(dual_objective).value));
    for (int i = 0; i < model->constraint_count; ++i) {
        const Constraint *constraint = &model->constraints[i];
        Bound lower = {0}, upper = {0};
        bool fixed = false;
        for (int row = 0; row < tableau->rows; ++row) {
            Rational rho =
                rat_mul(tableau->values[row][standard->initial[i]], integer(standard->sigma[i]));
            if (!rho.numerator)
                continue;
            if (standard->artificial[tableau->basis[row]]) {
                fixed = true;
                break;
            }
            Rational limit = rat_div(rat_neg(tableau->beta[row]), rho);
            if (rho.numerator > 0) {
                if (!lower.finite || rat_compare(limit, lower.value) > 0)
                    lower = (Bound){true, limit};
            } else if (!upper.finite || rat_compare(limit, upper.value) < 0)
                upper = (Bound){true, limit};
        }
        FractionText low = fixed ? rat_text(constraint->rhs)
                                 : range_text(constraint->rhs, lower, true),
                     high = fixed ? rat_text(constraint->rhs)
                                  : range_text(constraint->rhs, upper, false);
        lines_push(&out, format_text("CONSTRAINT %s price %s rhs %s range %s %s", constraint->name,
                                     rat_text(prices[i]).value, rat_text(constraint->rhs).value,
                                     low.value, high.value));
    }
    for (int j = 0; j < model->variable_count; ++j) {
        const VariableMap *mapping = &standard->maps[j];
        const char *status = "basic";
        if (mapping->kind == MAP_SPLIT) {
            if (!basic[mapping->columns[0]] && !basic[mapping->columns[1]])
                status = "zero";
        } else if (mapping->kind == MAP_REFLECT) {
            if (!basic[mapping->columns[0]])
                status = "upper";
        } else if (!basic[mapping->columns[0]])
            status = "lower";
        else if (mapping->upper_row >= 0 && !basic[standard->slack[mapping->upper_row]])
            status = "upper";
        Rational h[90] = {0};
        for (int c = 0; c < mapping->column_count; ++c) {
            int column = mapping->columns[c];
            h[column] = integer(standard->sign * standard->directions[column]);
        }
        Bound lower = {0}, upper = {0};
        for (int k = 0; k < tableau->columns; ++k)
            if (!basic[k] && !standard->artificial[k]) {
                Rational eta = h[k];
                for (int row = 0; row < tableau->rows; ++row)
                    eta = rat_sub(eta, rat_mul(h[tableau->basis[row]], tableau->values[row][k]));
                if (!eta.numerator)
                    continue;
                Rational limit = rat_div(rat_neg(reduced[k]), eta);
                if (eta.numerator > 0) {
                    if (!lower.finite || rat_compare(limit, lower.value) > 0)
                        lower = (Bound){true, limit};
                } else if (!upper.finite || rat_compare(limit, upper.value) < 0)
                    upper = (Bound){true, limit};
            }
        lines_push(&out,
                   format_text("VARIABLE %s %s value %s reduced %s cost %s range %s %s",
                               model->variables[j], status, rat_text(root->solution[j]).value,
                               rat_text(variable_reduced[j]).value, rat_text(model->cost[j]).value,
                               range_text(model->cost[j], lower, true).value,
                               range_text(model->cost[j], upper, false).value));
    }
    return out;
}
typedef struct {
    bool any;
    Rational minimum, maximum;
} Extrema;
static void include(Extrema *extrema, Rational value) {
    if (!value.numerator)
        return;
    value = rat_abs(value);
    if (!extrema->any || rat_compare(value, extrema->minimum) < 0)
        extrema->minimum = value;
    if (!extrema->any || rat_compare(value, extrema->maximum) > 0)
        extrema->maximum = value;
    extrema->any = true;
}
static char *coefficient_stats(const Model *model) {
    Extrema sets[4] = {0};
    int nonzeros = 0;
    for (int i = 0; i < model->constraint_count; ++i) {
        const Constraint *constraint = &model->constraints[i];
        for (int j = 0; j < model->variable_count; ++j)
            if (constraint->coefficients[j].numerator) {
                ++nonzeros;
                include(&sets[0], constraint->coefficients[j]);
            }
        include(&sets[2], constraint->rhs);
    }
    for (int j = 0; j < model->variable_count; ++j) {
        include(&sets[1], model->cost[j]);
        if (model->lower[j].finite)
            include(&sets[3], model->lower[j].value);
        if (model->upper[j].finite)
            include(&sets[3], model->upper[j].value);
    }
    static const char *names[] = {"matrix", "objective", "rhs", "bounds"};
    TextLines parts = {0};
    lines_push(&parts, format_text("STATS nonzeros %d", nonzeros));
    for (int i = 0; i < 4; ++i)
        lines_push(&parts, format_text("%s %s %s", names[i],
                                       sets[i].any ? rat_text(sets[i].minimum).value : "-",
                                       sets[i].any ? rat_text(sets[i].maximum).value : "-"));
    char *out = join_texts(&parts, " ");
    lines_free(&parts);
    return out;
}
static TextLines constraint_values(const Model *model, const Rational *solution) {
    TextLines out = {0};
    for (int i = 0; i < model->constraint_count; ++i) {
        const Constraint *constraint = &model->constraints[i];
        Rational value = integer(0);
        for (int j = 0; j < model->variable_count; ++j)
            value = rat_add(value, rat_mul(constraint->coefficients[j], solution[j]));
        Rational margin = constraint->comparison == COMP_LE ? rat_sub(constraint->rhs, value)
                                                            : rat_sub(value, constraint->rhs);
        lines_push(&out, format_text("ROW %s %s %s", constraint->name, rat_text(value).value,
                                     rat_text(margin).value));
    }
    return out;
}
static void write_lines(const char *name, const TextLines *lines) {
    char *path = format_text("output/%s", name);
    FILE *output = fopen(path, "wb");
    free(path);
    if (!output)
        exit(EXIT_FAILURE);
    for (int i = 0; i < lines->count; ++i)
        if (fputs(lines->data[i], output) == EOF || fputc('\n', output) == EOF)
            exit(EXIT_FAILURE);
    if (fclose(output))
        exit(EXIT_FAILURE);
}
static void model_result_free(ModelResult *result) {
    for (int i = 0; i < result->solve_count; ++i) {
        lines_free(&result->solves[i]->log);
        free(result->solves[i]);
    }
    free(result->solves);
    lines_free(&result->tree);
}
int main(void) {
    Settings settings = read_settings();
    int model_count;
    RawModel *raw = read_models(&model_count);
    TextLines iterations = {0}, solutions = {0}, sensitivities = {0}, tree = {0}, summary = {0};
    lines_add(&summary, "model,status,objective,approx,relaxation,nodes,pivots");
    int statuses[5] = {0}, solves = 0, phase1 = 0, phase2 = 0, drives = 0, analyzed = 0,
        integer_models = 0, integer_nodes = 0, integer_limits = 0;
    for (int i = 0; i < model_count; ++i) {
        Model model = make_model(&raw[i]);
        if (model.error.message) {
            ++statuses[ERROR];
            lines_push(&iterations, format_text("MODEL %s error", model.name));
            lines_push(&solutions, format_text("MODEL %s", model.name));
            lines_push(&solutions, format_text("STATUS ERROR line %d %s", model.error.line,
                                               model.error.message));
            lines_push(&sensitivities, format_text("MODEL %s skipped ERROR", model.name));
            lines_push(&summary, format_text("%s,ERROR,-,-,-,0,0", model.name));
            model_free(&model);
            raw_model_free(&raw[i]);
            continue;
        }
        int level = settings.level, limit = settings.limit;
        for (int j = 0; j < settings.log_count; ++j)
            if (!strcmp(model.name, settings.logs[j].name))
                level = settings.logs[j].value;
        for (int j = 0; j < settings.limit_count; ++j)
            if (!strcmp(model.name, settings.limits[j].name))
                limit = settings.limits[j].value;
        lines_push(&iterations, format_text("MODEL %s level %d", model.name, level));
        int integers = integer_count(&model);
        ModelResult result = {0};
        if (integers) {
            result = branch_bound(&model, limit, level);
            ++integer_models;
            integer_nodes += result.solve_count;
            if (result.status == NODE_LIMIT)
                ++integer_limits;
            lines_push(&tree,
                       format_text("MODEL %s %s integers %d node_limit %d", model.name,
                                   model.maximize ? "maximize" : "minimize", integers, limit));
            lines_append(&tree, &result.tree);
        } else {
            LPResult *root = solve_lp(&model, model.lower, model.upper, 1, level);
            result.status = root->status;
            result_push(&result, root);
            if (root->status == OPTIMAL) {
                result.has_solution = true;
                result.objective = root->objective;
                memcpy(result.solution, root->solution,
                       (size_t)model.variable_count * sizeof *result.solution);
            }
        }
        int pivots = 0;
        for (int j = 0; j < result.solve_count; ++j) {
            const LPResult *lp = result.solves[j];
            lines_append(&iterations, &lp->log);
            ++solves;
            phase1 += lp->phase1;
            phase2 += lp->phase2;
            drives += lp->drives;
            pivots += lp_pivots(lp);
        }
        ++statuses[result.status];
        lines_push(&solutions, format_text("MODEL %s %s variables %d constraints %d integers %d",
                                           model.name, model.maximize ? "maximize" : "minimize",
                                           model.variable_count, model.constraint_count, integers));
        lines_push(&solutions, coefficient_stats(&model));
        lines_push(&solutions, format_text("STATUS %s", status_name(result.status)));
        FractionText objective, approx, relaxation;
        strcpy(objective.value, "-");
        strcpy(approx.value, "-");
        strcpy(relaxation.value, "-");
        if (result.has_solution) {
            objective = rat_text(result.objective);
            approx = rat_approx(result.objective);
            lines_push(&solutions,
                       format_text("OBJECTIVE %s approx %s", objective.value, approx.value));
        }
        const LPResult *root = result.solves[0];
        if (root->status == OPTIMAL) {
            relaxation = rat_text(root->objective);
            if (integers)
                lines_push(&solutions, format_text("RELAXATION %s approx %s", relaxation.value,
                                                   rat_approx(root->objective).value));
            TextLines lines = sensitivity(&model, root);
            append_owned(&sensitivities, &lines);
            ++analyzed;
        } else
            lines_push(&sensitivities,
                       format_text("MODEL %s skipped %s", model.name, status_name(root->status)));
        if (root->status == INFEASIBLE) {
            lines_push(&solutions, format_text("INFEASIBILITY %s", rat_text(root->w).value));
            for (int j = 0; j < root->standard.tableau.rows; ++j)
                lines_push(&solutions, format_text("FARKAS %s %s", root->standard.rows[j],
                                                   rat_text(root->farkas[j]).value));
        }
        if (result.has_solution || result.status == UNBOUNDED) {
            const Rational *values = result.has_solution ? result.solution : root->solution;
            for (int j = 0; j < model.variable_count; ++j)
                lines_push(&solutions, format_text("VALUE %s %s", model.variables[j],
                                                   rat_text(values[j]).value));
        }
        if (result.status == UNBOUNDED) {
            for (int j = 0; j < model.variable_count; ++j)
                lines_push(&solutions, format_text("RAY %s %s", model.variables[j],
                                                   rat_text(root->ray[j]).value));
            lines_push(&solutions, format_text("RATE %s", rat_text(root->rate).value));
        }
        if (result.has_solution) {
            TextLines lines = constraint_values(&model, result.solution);
            append_owned(&solutions, &lines);
        }
        if (integers)
            lines_push(&solutions, format_text("NODES %d", result.solve_count));
        lines_push(&solutions, format_text("PIVOTS %d", pivots));
        lines_push(&summary, format_text("%s,%s,%s,%s,%s,%d,%d", model.name,
                                         status_name(result.status), objective.value, approx.value,
                                         relaxation.value, result.solve_count, pivots));
        model_result_free(&result);
        model_free(&model);
        raw_model_free(&raw[i]);
    }
    lines_push(&iterations, format_text("TOTAL solves %d phase1 %d phase2 %d drives %d pivots %d",
                                        solves, phase1, phase2, drives, phase1 + phase2 + drives));
    lines_push(&solutions,
               format_text(
                   "SUMMARY models %d optimal %d infeasible %d unbounded %d node_limit %d error %d",
                   model_count, statuses[OPTIMAL], statuses[INFEASIBLE], statuses[UNBOUNDED],
                   statuses[NODE_LIMIT], statuses[ERROR]));
    lines_push(&sensitivities,
               format_text("SUMMARY analyzed %d skipped %d", analyzed, model_count - analyzed));
    lines_push(&tree, format_text("SUMMARY models %d nodes %d node_limit %d", integer_models,
                                  integer_nodes, integer_limits));
    mkdir("output", 0755);
    write_lines("iterations.txt", &iterations);
    write_lines("solutions.txt", &solutions);
    write_lines("sensitivity.txt", &sensitivities);
    write_lines("bnb_tree.txt", &tree);
    write_lines("summary.csv", &summary);
    free(raw);
    free(settings.logs);
    free(settings.limits);
    lines_free(&iterations);
    lines_free(&solutions);
    lines_free(&sensitivities);
    lines_free(&tree);
    lines_free(&summary);
    return 0;
}
