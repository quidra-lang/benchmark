#include "solver.hpp"
static Model makeModel(const RawModel &raw) {
    Model out;
    out.name = raw.name;
    out.direction = raw.direction;
    out.constraints = raw.constraints;
    out.error = raw.error;
    if (out.error)
        return out;
    std::map<std::string, int> index;
    const auto registerTerms = [&](const Terms &terms) {
        for (const Term &term : terms)
            if (!index.count(term.name)) {
                index[term.name] = static_cast<int>(out.variables.size());
                out.variables.push_back(term.name);
            }
    };
    registerTerms(raw.objective);
    for (const Constraint &constraint : raw.constraints)
        registerTerms(constraint.terms);
    std::size_t count = out.variables.size();
    out.cost.resize(count);
    out.lower.resize(count, Rational());
    out.upper.resize(count);
    out.integer.resize(count);
    for (const Term &term : raw.objective) {
        int j = index.at(term.name);
        out.cost[j] = out.cost[j] + term.coefficient;
    }
    for (Constraint &constraint : out.constraints) {
        constraint.coefficients.resize(count);
        for (const Term &term : constraint.terms) {
            int j = index.at(term.name);
            constraint.coefficients[j] = constraint.coefficients[j] + term.coefficient;
        }
    }
    std::set<std::string> seen;
    for (const Constraint &constraint : out.constraints)
        if (!seen.insert(constraint.name).second) {
            out.error = ModelError{constraint.line, "duplicate constraint " + constraint.name};
            return out;
        }
    const auto inconsistent = [&](int j) {
        return out.lower[j] && out.upper[j] && out.lower[j]->compare(*out.upper[j]) > 0;
    };
    for (const BoundLine &bound : raw.bounds) {
        auto found = index.find(bound.name);
        if (found == index.end()) {
            out.error = ModelError{bound.line, "unknown variable " + bound.name};
            return out;
        }
        int j = found->second;
        if (bound.kind == BoundKind::Lower || bound.kind == BoundKind::Both)
            out.lower[j] = bound.lower;
        if (bound.kind == BoundKind::Upper || bound.kind == BoundKind::Both)
            out.upper[j] = bound.upper;
        if (inconsistent(j)) {
            out.error = ModelError{bound.line, "inconsistent bounds " + bound.name};
            return out;
        }
    }
    for (const Declaration &declaration : raw.integers)
        for (const std::string &name : declaration.names) {
            auto found = index.find(name);
            if (found == index.end()) {
                out.error = ModelError{declaration.line, "unknown variable " + name};
                return out;
            }
            int j = found->second;
            out.integer[j] = true;
            if (out.lower[j])
                out.lower[j] = Rational(out.lower[j]->ceil());
            if (out.upper[j])
                out.upper[j] = Rational(out.upper[j]->floor());
            if (inconsistent(j)) {
                out.error = ModelError{declaration.line, "inconsistent bounds " + name};
                return out;
            }
        }
    for (const Declaration &declaration : raw.binaries)
        for (const std::string &name : declaration.names) {
            auto found = index.find(name);
            if (found == index.end()) {
                out.error = ModelError{declaration.line, "unknown variable " + name};
                return out;
            }
            int j = found->second;
            out.integer[j] = true;
            out.lower[j] = Rational(0);
            out.upper[j] = Rational(1);
        }
    return out;
}
int integerCount(const Model &model) {
    return static_cast<int>(std::count(model.integer.begin(), model.integer.end(), true));
}
static Standard standardForm(const Model &model, const Bounds &lower, const Bounds &upper) {
    Standard out;
    out.sign = model.direction == "maximize" ? -1 : 1;
    const auto addVariable = [&](const std::string &name, int variable, int direction) {
        int column = static_cast<int>(out.columns.size());
        out.columns.push_back(name);
        out.columnVariable.push_back(variable);
        out.directions.push_back(direction);
        return column;
    };
    for (int j = 0; j < static_cast<int>(model.variables.size()); ++j) {
        VariableMap mapping;
        const std::string &name = model.variables[j];
        if (lower[j]) {
            mapping.kind = MapKind::Shift;
            mapping.offset = *lower[j];
            mapping.columns = {addVariable(name, j, 1)};
        } else if (upper[j]) {
            mapping.kind = MapKind::Reflect;
            mapping.offset = *upper[j];
            mapping.columns = {addVariable(name + "'", j, -1)};
        } else {
            mapping.kind = MapKind::Split;
            mapping.columns = {addVariable(name + "+", j, 1), addVariable(name + "-", j, -1)};
        }
        out.constant = out.constant + model.cost[j] * mapping.offset;
        out.maps.push_back(std::move(mapping));
    }
    std::size_t decisionColumns = out.columns.size();
    Tableau &tableau = out.tableau;
    for (const Constraint &constraint : model.constraints) {
        Values row(decisionColumns);
        Rational rhs = constraint.rhs;
        for (std::size_t j = 0; j < out.maps.size(); ++j) {
            const VariableMap &mapping = out.maps[j];
            rhs = rhs - constraint.coefficients[j] * mapping.offset;
            for (int column : mapping.columns)
                row[column] = constraint.coefficients[j] * Rational(out.directions[column]);
        }
        tableau.values.push_back(std::move(row));
        tableau.beta.push_back(rhs);
        out.rows.push_back(constraint.name);
        out.comparisons.push_back(constraint.comparison);
    }
    for (std::size_t j = 0; j < out.maps.size(); ++j)
        if (out.maps[j].kind == MapKind::Shift && upper[j]) {
            Values row(decisionColumns);
            row[out.maps[j].columns[0]] = Rational(1);
            out.maps[j].upperRow = static_cast<int>(out.rows.size());
            out.rows.push_back(model.variables[j] + ".ub");
            out.comparisons.push_back("<=");
            tableau.values.push_back(std::move(row));
            tableau.beta.push_back(*upper[j] - *lower[j]);
        }
    for (std::size_t i = 0; i < out.rows.size(); ++i) {
        int sigma = 1;
        if (tableau.beta[i].numerator < 0) {
            sigma = -1;
            tableau.beta[i] = -tableau.beta[i];
            for (Rational &value : tableau.values[i])
                value = -value;
            if (out.comparisons[i] == "<=")
                out.comparisons[i] = ">=";
            else if (out.comparisons[i] == ">=")
                out.comparisons[i] = "<=";
        }
        out.sigma.push_back(sigma);
        out.slack.push_back(-1);
        out.initial.push_back(-1);
    }
    out.artificial.resize(decisionColumns);
    const auto addExtra = [&](const std::string &name, int row, Rational value, bool artificial) {
        int column = static_cast<int>(out.columns.size());
        out.columns.push_back(name);
        out.columnVariable.push_back(-1);
        out.directions.push_back(0);
        for (Values &values : tableau.values)
            values.push_back(Rational());
        tableau.values[row][column] = value;
        out.artificial.push_back(artificial);
        return column;
    };
    for (int i = 0; i < static_cast<int>(out.rows.size()); ++i)
        if (out.comparisons[i] != "=") {
            out.slack[i] = addExtra("s:" + out.rows[i], i,
                                    Rational(out.comparisons[i] == "<=" ? 1 : -1), false);
            if (out.comparisons[i] == "<=")
                out.initial[i] = out.slack[i];
        }
    for (int i = 0; i < static_cast<int>(out.rows.size()); ++i)
        if (out.comparisons[i] != "<=")
            out.initial[i] = addExtra("a:" + out.rows[i], i, Rational(1), true);
    out.costs1.resize(out.columns.size());
    out.costs2.resize(out.columns.size());
    for (std::size_t column = 0; column < out.columns.size(); ++column) {
        int j = out.columnVariable[column];
        if (j >= 0)
            out.costs2[column] = model.cost[j] * Rational(out.sign * out.directions[column]);
        if (out.artificial[column])
            out.costs1[column] = Rational(1);
    }
    tableau.basis = out.initial;
    return out;
}
Values Standard::originalValues(const Values &columns, bool direction) const {
    Values out(maps.size());
    for (std::size_t j = 0; j < maps.size(); ++j) {
        if (!direction)
            out[j] = maps[j].offset;
        for (int column : maps[j].columns)
            out[j] = out[j] + columns[column] * Rational(directions[column]);
    }
    return out;
}
Values Standard::solution() const {
    Values columns(this->columns.size());
    for (std::size_t i = 0; i < tableau.basis.size(); ++i)
        columns[tableau.basis[i]] = tableau.beta[i];
    return originalValues(columns, false);
}
static LPResult solveLP(const Model &model, const Bounds &lower, const Bounds &upper, int number,
                        int level) {
    LPResult out;
    out.standard = standardForm(model, lower, upper);
    Standard &standard = out.standard;
    Tableau &tableau = standard.tableau;
    int artificials =
        static_cast<int>(std::count(standard.artificial.begin(), standard.artificial.end(), true));
    const auto emit = [&](int required, const std::string &line) {
        if (required <= level)
            out.log.push_back(line);
    };
    const auto display = [&](const std::string &heading, const Values &cost, bool phase1) {
        if (level >= 2)
            append(out.log, tableau.display(heading, standard.columns, standard.rows, cost,
                                            phase1 ? Rational() : standard.constant,
                                            phase1 ? 1 : standard.sign));
    };
    const auto finish = [&]() {
        emit(0, text("RESULT ", out.status, " objective ",
                     out.status == "OPTIMAL" ? out.objective.str() : "-", " phase1 ", out.phase1,
                     " phase2 ", out.phase2, " drives ", out.drives, " redundant ", out.redundant));
    };
    emit(0, text("SOLVE node ", number, " rows ", standard.rows.size(), " columns ",
                 standard.columns.size(), " artificials ", artificials));
    for (std::size_t j = 0; j < standard.maps.size(); ++j) {
        const VariableMap &mapping = standard.maps[j];
        std::string line = "MAP " + model.variables[j] + " " +
                           (mapping.kind == MapKind::Shift     ? "shift"
                            : mapping.kind == MapKind::Reflect ? "reflect"
                                                               : "split");
        if (mapping.kind != MapKind::Split)
            line += " " + mapping.offset.str();
        if (mapping.kind == MapKind::Shift && upper[j])
            line += " upper " + upper[j]->str();
        emit(1, line);
    }
    for (std::size_t row = 0; row < standard.rows.size(); ++row)
        if (standard.sigma[row] < 0)
            emit(1, "FLIP " + standard.rows[row]);
    std::vector<bool> all(standard.columns.size(), true), real(standard.columns.size());
    for (std::size_t k = 0; k < real.size(); ++k)
        real[k] = !standard.artificial[k];
    if (artificials) {
        emit(1, "PHASE 1");
        display("phase 1 start", standard.costs1, true);
        PhaseResult phase1 = phase(tableau, standard.costs1, all, standard.columns, standard.rows,
                                   [](Rational value) { return value; });
        out.phase1 = phase1.iterations;
        for (const std::string &line : phase1.lines)
            emit(1, line);
        auto [reduced, value] = tableau.reduced(standard.costs1);
        out.w = value;
        emit(1, text("PHASE 1 END objective ", value, " iterations ", out.phase1));
        if (value.numerator > 0) {
            out.status = "INFEASIBLE";
            for (std::size_t row = 0; row < standard.rows.size(); ++row) {
                int column = standard.initial[row];
                out.farkas.push_back((standard.costs1[column] - reduced[column]) *
                                     Rational(standard.sigma[row]));
            }
            display("final", standard.costs1, true);
            finish();
            return out;
        }
        for (int row = 0; row < static_cast<int>(tableau.basis.size()); ++row) {
            int previous = tableau.basis[row];
            if (!standard.artificial[previous])
                continue;
            int column = -1;
            for (int k = 0; k < static_cast<int>(standard.columns.size()); ++k)
                if (!standard.artificial[k] && tableau.values[row][k].numerator) {
                    column = k;
                    break;
                }
            if (column < 0) {
                ++out.redundant;
                emit(1, "REDUNDANT row " + standard.rows[row]);
            } else {
                emit(1, text("DRIVE row ", standard.rows[row], " enter ", standard.columns[column],
                             " leave ", standard.columns[previous]));
                tableau.pivot(row, column);
                ++out.drives;
            }
        }
    }
    emit(1, "PHASE 2");
    display("phase 2 start", standard.costs2, false);
    const auto objective = [&](Rational value) {
        return standard.constant + Rational(standard.sign) * value;
    };
    PhaseResult phase2 =
        phase(tableau, standard.costs2, real, standard.columns, standard.rows, objective);
    out.phase2 = phase2.iterations;
    for (const std::string &line : phase2.lines)
        emit(1, line);
    out.objective = objective(tableau.reduced(standard.costs2).second);
    out.solution = standard.solution();
    out.status = "OPTIMAL";
    if (phase2.entering >= 0) {
        out.status = "UNBOUNDED";
        emit(1, "UNBOUNDED enter " + standard.columns[phase2.entering]);
        Values delta(standard.columns.size());
        delta[phase2.entering] = Rational(1);
        for (std::size_t row = 0; row < tableau.basis.size(); ++row)
            delta[tableau.basis[row]] = -tableau.values[row][phase2.entering];
        out.ray = standard.originalValues(delta, true);
        for (std::size_t j = 0; j < out.ray.size(); ++j)
            out.rate = out.rate + model.cost[j] * out.ray[j];
    }
    emit(1, text("PHASE 2 END objective ", out.objective, " iterations ", out.phase2));
    display("final", standard.costs2, false);
    finish();
    return out;
}
static std::string rangeText(Rational base, const Bound &limit, bool lower) {
    return limit ? (base + *limit).str() : boundText({}, lower);
}
static Lines sensitivity(const Model &model, const LPResult &root) {
    const Standard &standard = root.standard;
    const Tableau &tableau = standard.tableau;
    Values reduced = tableau.reduced(standard.costs2).first;
    std::vector<bool> basic(standard.columns.size());
    Lines basis;
    int primal = 0, dual = 0;
    for (std::size_t row = 0; row < tableau.basis.size(); ++row) {
        int column = tableau.basis[row];
        basic[column] = true;
        basis.push_back(standard.columns[column]);
        if (!standard.artificial[column] && !tableau.beta[row].numerator)
            ++primal;
    }
    for (std::size_t k = 0; k < standard.columns.size(); ++k)
        if (!basic[k] && !standard.artificial[k] && !reduced[k].numerator)
            ++dual;
    Values prices(model.constraints.size()), variableReduced = model.cost;
    Rational dualObjective;
    for (std::size_t i = 0; i < model.constraints.size(); ++i) {
        const Constraint &constraint = model.constraints[i];
        prices[i] = reduced[standard.initial[i]] * Rational(-standard.sign * standard.sigma[i]);
        dualObjective = dualObjective + prices[i] * constraint.rhs;
        for (std::size_t j = 0; j < model.variables.size(); ++j)
            variableReduced[j] = variableReduced[j] - prices[i] * constraint.coefficients[j];
    }
    for (std::size_t j = 0; j < model.variables.size(); ++j)
        dualObjective = dualObjective + variableReduced[j] * root.solution[j];
    Lines out{text("MODEL ", model.name,
                   integerCount(model) ? " relaxation objective " : " lp objective ",
                   root.objective),
              "BASIS " + join(basis), text("DEGENERACY primal ", primal, " dual ", dual),
              text("DUAL objective ", dualObjective)};
    for (std::size_t i = 0; i < model.constraints.size(); ++i) {
        const Constraint &constraint = model.constraints[i];
        Bound lower, upper;
        bool fixed = false;
        for (std::size_t row = 0; row < tableau.basis.size(); ++row) {
            Rational rho = tableau.values[row][standard.initial[i]] * Rational(standard.sigma[i]);
            if (!rho.numerator)
                continue;
            if (standard.artificial[tableau.basis[row]]) {
                fixed = true;
                break;
            }
            Rational limit = -tableau.beta[row] / rho;
            if (rho.numerator > 0) {
                if (!lower || limit.compare(*lower) > 0)
                    lower = limit;
            } else if (!upper || limit.compare(*upper) < 0)
                upper = limit;
        }
        out.push_back(
            text("CONSTRAINT ", constraint.name, " price ", prices[i], " rhs ", constraint.rhs,
                 " range ", fixed ? constraint.rhs.str() : rangeText(constraint.rhs, lower, true),
                 " ", fixed ? constraint.rhs.str() : rangeText(constraint.rhs, upper, false)));
    }
    for (std::size_t j = 0; j < model.variables.size(); ++j) {
        const VariableMap &mapping = standard.maps[j];
        std::string status = "basic";
        if (mapping.kind == MapKind::Split) {
            if (!basic[mapping.columns[0]] && !basic[mapping.columns[1]])
                status = "zero";
        } else if (mapping.kind == MapKind::Reflect) {
            if (!basic[mapping.columns[0]])
                status = "upper";
        } else if (!basic[mapping.columns[0]])
            status = "lower";
        else if (mapping.upperRow >= 0 && !basic[standard.slack[mapping.upperRow]])
            status = "upper";
        Values h(standard.columns.size());
        for (int column : mapping.columns)
            h[column] = Rational(standard.sign * standard.directions[column]);
        Bound lower, upper;
        for (std::size_t k = 0; k < standard.columns.size(); ++k)
            if (!basic[k] && !standard.artificial[k]) {
                Rational eta = h[k];
                for (std::size_t row = 0; row < tableau.basis.size(); ++row)
                    eta = eta - h[tableau.basis[row]] * tableau.values[row][k];
                if (!eta.numerator)
                    continue;
                Rational limit = -reduced[k] / eta;
                if (eta.numerator > 0) {
                    if (!lower || limit.compare(*lower) > 0)
                        lower = limit;
                } else if (!upper || limit.compare(*upper) < 0)
                    upper = limit;
            }
        out.push_back(text("VARIABLE ", model.variables[j], " ", status, " value ",
                           root.solution[j], " reduced ", variableReduced[j], " cost ",
                           model.cost[j], " range ", rangeText(model.cost[j], lower, true), " ",
                           rangeText(model.cost[j], upper, false)));
    }
    return out;
}
static std::string coefficientStats(const Model &model) {
    std::array<Values, 4> sets;
    int nonzeros = 0;
    for (const Constraint &constraint : model.constraints) {
        for (Rational value : constraint.coefficients)
            if (value.numerator) {
                sets[0].push_back(value.abs());
                ++nonzeros;
            }
        if (constraint.rhs.numerator)
            sets[2].push_back(constraint.rhs.abs());
    }
    for (Rational value : model.cost)
        if (value.numerator)
            sets[1].push_back(value.abs());
    for (std::size_t j = 0; j < model.variables.size(); ++j)
        for (Bound bound : {model.lower[j], model.upper[j]})
            if (bound && bound->numerator)
                sets[3].push_back(bound->abs());
    const std::array<const char *, 4> names{"matrix", "objective", "rhs", "bounds"};
    std::string out = text("STATS nonzeros ", nonzeros);
    for (int i = 0; i < 4; ++i) {
        std::string low = "-", high = "-";
        if (!sets[i].empty()) {
            Rational minimum = sets[i][0], maximum = minimum;
            for (Rational value : sets[i]) {
                if (value.compare(minimum) < 0)
                    minimum = value;
                if (value.compare(maximum) > 0)
                    maximum = value;
            }
            low = minimum.str();
            high = maximum.str();
        }
        out += text(" ", names[i], " ", low, " ", high);
    }
    return out;
}
static Lines constraintValues(const Model &model, const Values &solution) {
    Lines out;
    for (const Constraint &constraint : model.constraints) {
        Rational value;
        for (std::size_t j = 0; j < solution.size(); ++j)
            value = value + constraint.coefficients[j] * solution[j];
        Rational margin =
            constraint.comparison == "<=" ? constraint.rhs - value : value - constraint.rhs;
        out.push_back(text("ROW ", constraint.name, " ", value, " ", margin));
    }
    return out;
}
static void writeLines(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    if (!output)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        output << line << '\n';
    if (!output)
        throw std::runtime_error("cannot write " + name);
}
int main() {
    Settings settings = readSettings();
    Lines iterations, solutions, sensitivities, tree,
        summary{"model,status,objective,approx,relaxation,nodes,pivots"};
    std::map<std::string, int> statuses;
    int solves = 0, phase1 = 0, phase2 = 0, drives = 0, analyzed = 0, integerModels = 0,
        integerNodes = 0, integerLimits = 0;
    std::vector<RawModel> models = readModels();
    for (const RawModel &raw : models) {
        Model model = makeModel(raw);
        if (model.error) {
            ++statuses["ERROR"];
            iterations.push_back("MODEL " + model.name + " error");
            solutions.push_back("MODEL " + model.name);
            solutions.push_back(
                text("STATUS ERROR line ", model.error->line, " ", model.error->message));
            sensitivities.push_back("MODEL " + model.name + " skipped ERROR");
            summary.push_back(model.name + ",ERROR,-,-,-,0,0");
            continue;
        }
        int level = settings.logs.count(model.name) ? settings.logs.at(model.name) : settings.level,
            limit =
                settings.limits.count(model.name) ? settings.limits.at(model.name) : settings.limit;
        iterations.push_back(text("MODEL ", model.name, " level ", level));
        Solve solve = [&](const Bounds &lower, const Bounds &upper, int number) {
            return solveLP(model, lower, upper, number, level);
        };
        ModelResult result;
        int integers = integerCount(model);
        if (integers) {
            result = branchBound(model, limit, solve);
            ++integerModels;
            integerNodes += static_cast<int>(result.solves.size());
            if (result.status == "NODE_LIMIT")
                ++integerLimits;
            tree.push_back(text("MODEL ", model.name, " ", model.direction, " integers ", integers,
                                " node_limit ", limit));
            append(tree, result.tree);
        } else {
            LPResult root = solve(model.lower, model.upper, 1);
            result.status = root.status;
            if (root.status == "OPTIMAL") {
                result.hasSolution = true;
                result.objective = root.objective;
                result.solution = root.solution;
            }
            result.solves.push_back(std::move(root));
        }
        int pivots = 0;
        for (const LPResult &lp : result.solves) {
            append(iterations, lp.log);
            ++solves;
            phase1 += lp.phase1;
            phase2 += lp.phase2;
            drives += lp.drives;
            pivots += lp.pivots();
        }
        ++statuses[result.status];
        solutions.push_back(text("MODEL ", model.name, " ", model.direction, " variables ",
                                 model.variables.size(), " constraints ", model.constraints.size(),
                                 " integers ", integers));
        solutions.push_back(coefficientStats(model));
        solutions.push_back("STATUS " + result.status);
        std::string objective = "-", approx = "-", relaxation = "-";
        if (result.hasSolution) {
            objective = result.objective.str();
            approx = result.objective.approx();
            solutions.push_back("OBJECTIVE " + objective + " approx " + approx);
        }
        const LPResult &root = result.solves[0];
        if (root.status == "OPTIMAL") {
            relaxation = root.objective.str();
            if (integers)
                solutions.push_back("RELAXATION " + relaxation + " approx " +
                                    root.objective.approx());
            append(sensitivities, sensitivity(model, root));
            ++analyzed;
        } else
            sensitivities.push_back("MODEL " + model.name + " skipped " + root.status);
        if (root.status == "INFEASIBLE") {
            solutions.push_back(text("INFEASIBILITY ", root.w));
            for (std::size_t i = 0; i < root.farkas.size(); ++i)
                solutions.push_back(text("FARKAS ", root.standard.rows[i], " ", root.farkas[i]));
        }
        if (result.hasSolution || result.status == "UNBOUNDED") {
            const Values &values = result.hasSolution ? result.solution : root.solution;
            for (std::size_t j = 0; j < values.size(); ++j)
                solutions.push_back(text("VALUE ", model.variables[j], " ", values[j]));
        }
        if (result.status == "UNBOUNDED") {
            for (std::size_t j = 0; j < root.ray.size(); ++j)
                solutions.push_back(text("RAY ", model.variables[j], " ", root.ray[j]));
            solutions.push_back(text("RATE ", root.rate));
        }
        if (result.hasSolution)
            append(solutions, constraintValues(model, result.solution));
        if (integers)
            solutions.push_back(text("NODES ", result.solves.size()));
        solutions.push_back(text("PIVOTS ", pivots));
        summary.push_back(text(model.name, ",", result.status, ",", objective, ",", approx, ",",
                               relaxation, ",", result.solves.size(), ",", pivots));
    }
    iterations.push_back(text("TOTAL solves ", solves, " phase1 ", phase1, " phase2 ", phase2,
                              " drives ", drives, " pivots ", phase1 + phase2 + drives));
    solutions.push_back(text("SUMMARY models ", models.size(), " optimal ", statuses["OPTIMAL"],
                             " infeasible ", statuses["INFEASIBLE"], " unbounded ",
                             statuses["UNBOUNDED"], " node_limit ", statuses["NODE_LIMIT"],
                             " error ", statuses["ERROR"]));
    sensitivities.push_back(
        text("SUMMARY analyzed ", analyzed, " skipped ", models.size() - analyzed));
    tree.push_back(text("SUMMARY models ", integerModels, " nodes ", integerNodes, " node_limit ",
                        integerLimits));
    std::filesystem::create_directories("output");
    writeLines("iterations.txt", iterations);
    writeLines("solutions.txt", solutions);
    writeLines("sensitivity.txt", sensitivities);
    writeLines("bnb_tree.txt", tree);
    writeLines("summary.csv", summary);
}
