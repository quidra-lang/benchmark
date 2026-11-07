import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.function.UnaryOperator;
public final class Main {
    static final class Model {
        String name, direction;
        LpParser.Error error;
        List<String> variables = new ArrayList<>();
        List<LpParser.Constraint> constraints;
        Rational[] costs, rhs, lower, upper;
        Rational[][] matrix;
        String[] comparisons;
        boolean[] integer;
        int integerCount() {
            int count = 0;
            for (boolean value : integer)
                if (value)
                    count++;
            return count;
        }
    }
    static Rational[] zeroes(int size) {
        Rational[] values = new Rational[size];
        Arrays.fill(values, Rational.ZERO);
        return values;
    }
    static Rational dot(Rational[] a, Rational[] b) {
        Rational result = Rational.ZERO;
        for (int i = 0; i < a.length; i++)
            result = result.add(a[i].multiply(b[i]));
        return result;
    }
    static Rational[] coefficients(List<LpParser.Term> terms, List<String> variables) {
        Rational[] values = zeroes(variables.size());
        for (LpParser.Term term : terms) {
            int j = variables.indexOf(term.name());
            values[j] = values[j].add(term.coefficient());
        }
        return values;
    }
    static boolean inconsistent(Rational low, Rational high) {
        return low != null && high != null && low.compareTo(high) > 0;
    }
    static Model contentCheck(LpParser.Parsed parsed) {
        Model model = new Model();
        model.name = parsed.name;
        model.error = parsed.error;
        if (model.error != null)
            return model;
        model.direction = parsed.direction;
        model.constraints = parsed.constraints;
        List<List<LpParser.Term>> expressions = new ArrayList<>();
        expressions.add(parsed.objective);
        for (LpParser.Constraint constraint : parsed.constraints)
            expressions.add(constraint.terms());
        for (List<LpParser.Term> terms : expressions)
            for (LpParser.Term term : terms)
                if (!model.variables.contains(term.name()))
                    model.variables.add(term.name());
        int n = model.variables.size(), m = model.constraints.size();
        model.costs = coefficients(parsed.objective, model.variables);
        model.matrix = new Rational[m][];
        model.rhs = new Rational[m];
        model.comparisons = new String[m];
        for (int i = 0; i < m; i++) {
            LpParser.Constraint constraint = model.constraints.get(i);
            model.matrix[i] = coefficients(constraint.terms(), model.variables);
            model.rhs[i] = constraint.rhs();
            model.comparisons[i] = constraint.comparison();
        }
        model.lower = zeroes(n);
        model.upper = new Rational[n];
        model.integer = new boolean[n];
        Set<String> seen = new HashSet<>();
        for (LpParser.Constraint constraint : model.constraints)
            if (!seen.add(constraint.name())) {
                model.error = new LpParser.Error(constraint.line(),
                                                 "duplicate constraint " + constraint.name());
                return model;
            }
        for (LpParser.Bound bound : parsed.bounds) {
            int j = model.variables.indexOf(bound.name());
            if (j < 0) {
                model.error = new LpParser.Error(bound.line(), "unknown variable " + bound.name());
                return model;
            }
            if (!bound.kind().equals("upper"))
                model.lower[j] = bound.lower();
            if (!bound.kind().equals("lower"))
                model.upper[j] = bound.upper();
            if (inconsistent(model.lower[j], model.upper[j])) {
                model.error =
                    new LpParser.Error(bound.line(), "inconsistent bounds " + bound.name());
                return model;
            }
        }
        for (LpParser.Declaration declaration : parsed.integers)
            for (String name : declaration.names()) {
                int j = model.variables.indexOf(name);
                if (j < 0) {
                    model.error =
                        new LpParser.Error(declaration.line(), "unknown variable " + name);
                    return model;
                }
                model.integer[j] = true;
                if (model.lower[j] != null)
                    model.lower[j] = new Rational(model.lower[j].ceil());
                if (model.upper[j] != null)
                    model.upper[j] = new Rational(model.upper[j].floor());
                if (inconsistent(model.lower[j], model.upper[j])) {
                    model.error =
                        new LpParser.Error(declaration.line(), "inconsistent bounds " + name);
                    return model;
                }
            }
        for (LpParser.Declaration declaration : parsed.binaries)
            for (String name : declaration.names()) {
                int j = model.variables.indexOf(name);
                if (j < 0) {
                    model.error =
                        new LpParser.Error(declaration.line(), "unknown variable " + name);
                    return model;
                }
                model.integer[j] = true;
                model.lower[j] = Rational.ZERO;
                model.upper[j] = Rational.ONE;
            }
        return model;
    }
    static final class Mapping {
        String kind;
        Rational offset;
        int[] columns, directions;
        Integer upperRow;
        Mapping(String kind, Rational offset, int[] columns, int[] directions) {
            this.kind = kind;
            this.offset = offset;
            this.columns = columns;
            this.directions = directions;
        }
    }
    static final class StandardForm {
        List<String> columnNames = new ArrayList<>(), rowNames = new ArrayList<>();
        List<Mapping> mappings = new ArrayList<>();
        Rational[][] matrix;
        Rational[] rhs, phase1, phase2;
        int[] signs, slack, initial;
        Set<Integer> artificial = new HashSet<>();
        Rational constant;
        int direction;
    }
    static StandardForm standardForm(Model model, Rational[] lower, Rational[] upper) {
        StandardForm form = new StandardForm();
        List<Integer> owners = new ArrayList<>(), directions = new ArrayList<>();
        Rational[] offsets = new Rational[model.variables.size()];
        for (int j = 0; j < model.variables.size(); j++) {
            String name = model.variables.get(j);
            int first = form.columnNames.size();
            Mapping mapping;
            if (lower[j] != null) {
                mapping = new Mapping("shift", lower[j], new int[] {first}, new int[] {1});
                form.columnNames.add(name);
            } else if (upper[j] != null) {
                mapping = new Mapping("reflect", upper[j], new int[] {first}, new int[] {-1});
                form.columnNames.add(name + "'");
            } else {
                mapping = new Mapping("split", Rational.ZERO, new int[] {first, first + 1},
                                      new int[] {1, -1});
                form.columnNames.add(name + "+");
                form.columnNames.add(name + "-");
            }
            form.mappings.add(mapping);
            offsets[j] = mapping.offset;
            for (int sign : mapping.directions) {
                owners.add(j);
                directions.add(sign);
            }
        }
        List<List<Rational>> matrix = new ArrayList<>();
        List<Rational> rhs = new ArrayList<>();
        List<String> comparisons = new ArrayList<>();
        for (int i = 0; i < model.constraints.size(); i++) {
            form.rowNames.add(model.constraints.get(i).name());
            List<Rational> row = new ArrayList<>();
            for (int k = 0; k < owners.size(); k++)
                row.add(model.matrix[i][owners.get(k)].multiply(directions.get(k)));
            matrix.add(row);
            rhs.add(model.rhs[i].subtract(dot(model.matrix[i], offsets)));
            comparisons.add(model.comparisons[i]);
        }
        for (int j = 0; j < form.mappings.size(); j++) {
            Mapping mapping = form.mappings.get(j);
            if (!mapping.kind.equals("shift") || upper[j] == null)
                continue;
            mapping.upperRow = form.rowNames.size();
            form.rowNames.add(model.variables.get(j) + ".ub");
            List<Rational> row =
                new ArrayList<>(Collections.nCopies(form.columnNames.size(), Rational.ZERO));
            row.set(mapping.columns[0], Rational.ONE);
            matrix.add(row);
            rhs.add(upper[j].subtract(lower[j]));
            comparisons.add("<=");
        }
        int rows = matrix.size();
        form.signs = new int[rows];
        Arrays.fill(form.signs, 1);
        for (int i = 0; i < rows; i++)
            if (rhs.get(i).sign() < 0) {
                List<Rational> row = matrix.get(i);
                for (int k = 0; k < row.size(); k++)
                    row.set(k, row.get(k).negate());
                rhs.set(i, rhs.get(i).negate());
                form.signs[i] = -1;
                comparisons.set(i, switch (comparisons.get(i)) {
                    case "<=" -> ">=";
                    case ">=" -> "<=";
                    default -> "=";
                });
            }
        form.slack = new int[rows];
        Arrays.fill(form.slack, -1);
        form.initial = new int[rows];
        for (int i = 0; i < rows; i++)
            if (!comparisons.get(i).equals("=")) {
                int column = form.columnNames.size();
                form.slack[i] = column;
                form.columnNames.add("s:" + form.rowNames.get(i));
                int sign = comparisons.get(i).equals("<=") ? 1 : -1;
                for (int t = 0; t < rows; t++)
                    matrix.get(t).add(new Rational(t == i ? sign : 0));
                if (sign == 1)
                    form.initial[i] = column;
            }
        for (int i = 0; i < rows; i++)
            if (!comparisons.get(i).equals("<=")) {
                int column = form.columnNames.size();
                form.artificial.add(column);
                form.initial[i] = column;
                form.columnNames.add("a:" + form.rowNames.get(i));
                for (int t = 0; t < rows; t++)
                    matrix.get(t).add(t == i ? Rational.ONE : Rational.ZERO);
            }
        form.direction = model.direction.equals("minimize") ? 1 : -1;
        form.phase1 = zeroes(form.columnNames.size());
        form.phase2 = zeroes(form.columnNames.size());
        for (int k = 0; k < owners.size(); k++)
            form.phase2[k] =
                model.costs[owners.get(k)].multiply(form.direction * directions.get(k));
        for (int k : form.artificial)
            form.phase1[k] = Rational.ONE;
        form.matrix = new Rational[rows][];
        for (int i = 0; i < rows; i++)
            form.matrix[i] = matrix.get(i).toArray(Rational[] ::new);
        form.rhs = rhs.toArray(Rational[] ::new);
        form.constant = dot(model.costs, offsets);
        return form;
    }
    static Rational[] tableauSolution(StandardForm form, Tableau tableau) {
        Rational[] columns = zeroes(form.columnNames.size()),
                   solution = new Rational[form.mappings.size()];
        for (int i = 0; i < tableau.basic.length; i++)
            columns[tableau.basic[i]] = tableau.rhs[i];
        for (int j = 0; j < solution.length; j++) {
            Mapping mapping = form.mappings.get(j);
            Rational value = mapping.offset;
            for (int i = 0; i < mapping.columns.length; i++)
                value = value.add(columns[mapping.columns[i]].multiply(mapping.directions[i]));
            solution[j] = value;
        }
        return solution;
    }
    static final class LpResult {
        String status;
        Rational objective, infeasibility = Rational.ZERO;
        Rational[] solution;
        StandardForm form;
        Tableau tableau;
        Integer unbounded;
        int phase1, phase2, drives, redundant;
        List<String> lines = new ArrayList<>();
        int pivots() { return phase1 + phase2 + drives; }
    }
    static List<String> mappingLines(Model model, StandardForm form, Rational[] lower,
                                     Rational[] upper) {
        List<String> lines = new ArrayList<>();
        for (int j = 0; j < form.mappings.size(); j++) {
            Mapping mapping = form.mappings.get(j);
            String text = "MAP " + model.variables.get(j) + " " + mapping.kind;
            if (mapping.kind.equals("shift"))
                text += " " + lower[j] + (upper[j] == null ? "" : " upper " + upper[j]);
            else if (mapping.kind.equals("reflect"))
                text += " " + upper[j];
            lines.add(text);
        }
        for (int i = 0; i < form.signs.length; i++)
            if (form.signs[i] < 0)
                lines.add("FLIP " + form.rowNames.get(i));
        return lines;
    }
    static void emit(LpResult result, int level, int required, String text) {
        if (level >= required)
            result.lines.add(text);
    }
    static void display(LpResult result, int level, String heading, Rational[] costs,
                        UnaryOperator<Rational> objective) {
        if (level >= 2)
            result.lines.addAll(result.tableau.display(heading, costs, objective));
    }
    static LpResult solveLp(Model model, Rational[] lower, Rational[] upper, int number,
                            int level) {
        StandardForm form = standardForm(model, lower, upper);
        Tableau tableau =
            new Tableau(form.rowNames, form.columnNames, form.matrix, form.rhs, form.initial);
        LpResult result = new LpResult();
        result.form = form;
        result.tableau = tableau;
        result.status = "OPTIMAL";
        UnaryOperator<Rational> identity = value -> value;
        UnaryOperator<Rational> objective =
            value -> form.constant.add(value.multiply(form.direction));
        emit(result, level, 0,
             "SOLVE node " + number + " rows " + form.rowNames.size() + " columns " +
                 form.columnNames.size() + " artificials " + form.artificial.size());
        for (String line : mappingLines(model, form, lower, upper))
            emit(result, level, 1, line);
        if (!form.artificial.isEmpty()) {
            emit(result, level, 1, "PHASE 1");
            display(result, level, "phase 1 start", form.phase1, identity);
            List<Integer> candidates = new ArrayList<>();
            for (int k = 0; k < form.columnNames.size(); k++)
                candidates.add(k);
            Simplex.Result phase = Simplex.run(tableau, form.phase1, candidates, identity);
            result.phase1 = phase.iterations();
            for (String line : phase.lines())
                emit(result, level, 1, line);
            result.infeasibility = tableau.phaseValue(form.phase1);
            emit(result, level, 1,
                 "PHASE 1 END objective " + result.infeasibility + " iterations " + result.phase1);
            if (result.infeasibility.sign() > 0) {
                result.status = "INFEASIBLE";
                display(result, level, "final", form.phase1, identity);
            } else
                for (int row = 0; row < tableau.basic.length; row++)
                    if (form.artificial.contains(tableau.basic[row])) {
                        int entering = -1;
                        for (int k = 0; k < form.columnNames.size(); k++)
                            if (!form.artificial.contains(k) &&
                                tableau.values[row][k].sign() != 0) {
                                entering = k;
                                break;
                            }
                        if (entering < 0) {
                            result.redundant++;
                            emit(result, level, 1, "REDUNDANT row " + form.rowNames.get(row));
                        } else {
                            String leaving = form.columnNames.get(tableau.basic[row]);
                            tableau.pivot(row, entering);
                            result.drives++;
                            emit(result, level, 1,
                                 "DRIVE row " + form.rowNames.get(row) + " enter " +
                                     form.columnNames.get(entering) + " leave " + leaving);
                        }
                    }
        }
        if (!result.status.equals("INFEASIBLE")) {
            emit(result, level, 1, "PHASE 2");
            display(result, level, "phase 2 start", form.phase2, objective);
            List<Integer> candidates = new ArrayList<>();
            for (int k = 0; k < form.columnNames.size(); k++)
                if (!form.artificial.contains(k))
                    candidates.add(k);
            Simplex.Result phase = Simplex.run(tableau, form.phase2, candidates, objective);
            result.phase2 = phase.iterations();
            for (String line : phase.lines())
                emit(result, level, 1, line);
            result.unbounded = phase.unbounded();
            if (result.unbounded != null) {
                result.status = "UNBOUNDED";
                emit(result, level, 1, "UNBOUNDED enter " + form.columnNames.get(result.unbounded));
            }
            emit(result, level, 1,
                 "PHASE 2 END objective " + objective.apply(tableau.phaseValue(form.phase2)) +
                     " iterations " + result.phase2);
            display(result, level, "final", form.phase2, objective);
        }
        if (result.status.equals("OPTIMAL"))
            result.objective = objective.apply(tableau.phaseValue(form.phase2));
        result.solution = tableauSolution(form, tableau);
        emit(result, level, 0,
             "RESULT " + result.status + " objective " +
                 (result.objective == null ? "-" : result.objective) + " phase1 " + result.phase1 +
                 " phase2 " + result.phase2 + " drives " + result.drives + " redundant " +
                 result.redundant);
        return result;
    }
    static Rational[] farkas(LpResult result) {
        StandardForm form = result.form;
        Rational[] reduced = result.tableau.reduced(form.phase1),
                   multipliers = new Rational[form.rowNames.size()];
        for (int i = 0; i < multipliers.length; i++)
            multipliers[i] = form.phase1[form.initial[i]]
                                 .subtract(reduced[form.initial[i]])
                                 .multiply(form.signs[i]);
        return multipliers;
    }
    static Rational[] unboundedRay(LpResult result) {
        StandardForm form = result.form;
        Tableau tableau = result.tableau;
        Rational[] delta = zeroes(form.columnNames.size()), ray = zeroes(form.mappings.size());
        delta[result.unbounded] = Rational.ONE;
        for (int i = 0; i < tableau.basic.length; i++)
            delta[tableau.basic[i]] = tableau.values[i][result.unbounded].negate();
        for (int j = 0; j < ray.length; j++) {
            Mapping mapping = form.mappings.get(j);
            for (int k = 0; k < mapping.columns.length; k++)
                ray[j] = ray[j].add(delta[mapping.columns[k]].multiply(mapping.directions[k]));
        }
        return ray;
    }
    static String magnitudeRange(List<Rational> values) {
        Rational low = null, high = null;
        for (Rational value : values)
            if (value != null && value.sign() != 0) {
                Rational magnitude = value.abs();
                if (low == null || magnitude.compareTo(low) < 0)
                    low = magnitude;
                if (high == null || magnitude.compareTo(high) > 0)
                    high = magnitude;
            }
        return low == null ? "- -" : low + " " + high;
    }
    static String statisticsLine(Model model) {
        List<Rational> matrix = new ArrayList<>(), bounds = new ArrayList<>();
        for (Rational[] row : model.matrix)
            for (Rational value : row)
                if (value.sign() != 0)
                    matrix.add(value);
        bounds.addAll(Arrays.asList(model.lower));
        bounds.addAll(Arrays.asList(model.upper));
        return "STATS nonzeros " + matrix.size() + " matrix " + magnitudeRange(matrix) +
            " objective " + magnitudeRange(Arrays.asList(model.costs)) + " rhs " +
            magnitudeRange(Arrays.asList(model.rhs)) + " bounds " + magnitudeRange(bounds);
    }
    record Range(Rational lower, Rational upper) {
        public String toString() {
            return Rational.endpoint(lower, true) + " " + Rational.endpoint(upper, false);
        }
    }
    static Range range(Rational origin, List<Rational> coefficients, List<Rational> numerators) {
        Rational lower = null, upper = null;
        for (int i = 0; i < coefficients.size(); i++) {
            Rational coefficient = coefficients.get(i);
            if (coefficient.sign() == 0)
                continue;
            Rational value = numerators.get(i).divide(coefficient);
            if (coefficient.sign() > 0 && (lower == null || value.compareTo(lower) > 0))
                lower = value;
            if (coefficient.sign() < 0 && (upper == null || value.compareTo(upper) < 0))
                upper = value;
        }
        return new Range(lower == null ? null : origin.add(lower),
                         upper == null ? null : origin.add(upper));
    }
    static Range objectiveRange(Model model, LpResult result, int variable, Rational[] reduced,
                                List<Integer> nonbasic) {
        StandardForm form = result.form;
        Tableau tableau = result.tableau;
        Rational[] h = zeroes(form.columnNames.size());
        Mapping mapping = form.mappings.get(variable);
        for (int i = 0; i < mapping.columns.length; i++)
            h[mapping.columns[i]] = new Rational(form.direction * mapping.directions[i]);
        List<Rational> eta = new ArrayList<>(), numerators = new ArrayList<>();
        for (int column : nonbasic) {
            Rational change = h[column];
            for (int row = 0; row < tableau.basic.length; row++)
                change =
                    change.subtract(h[tableau.basic[row]].multiply(tableau.values[row][column]));
            eta.add(change);
            numerators.add(reduced[column].negate());
        }
        return range(model.costs[variable], eta, numerators);
    }
    static Range rhsRange(Model model, LpResult result, int constraint) {
        StandardForm form = result.form;
        Tableau tableau = result.tableau;
        int initial = form.initial[constraint];
        List<Rational> rho = new ArrayList<>(), numerators = new ArrayList<>();
        for (int row = 0; row < tableau.basic.length; row++) {
            Rational coefficient = tableau.values[row][initial].multiply(form.signs[constraint]);
            if (coefficient.sign() != 0 && form.artificial.contains(tableau.basic[row]))
                return new Range(model.rhs[constraint], model.rhs[constraint]);
            rho.add(coefficient);
            numerators.add(tableau.rhs[row].negate());
        }
        return range(model.rhs[constraint], rho, numerators);
    }
    static String variableStatus(StandardForm form, Set<Integer> basic, int variable) {
        Mapping mapping = form.mappings.get(variable);
        if (mapping.kind.equals("split"))
            return basic.contains(mapping.columns[0]) || basic.contains(mapping.columns[1])
                ? "basic"
                : "zero";
        if (mapping.kind.equals("reflect"))
            return basic.contains(mapping.columns[0]) ? "basic" : "upper";
        if (!basic.contains(mapping.columns[0]))
            return "lower";
        if (mapping.upperRow != null && !basic.contains(form.slack[mapping.upperRow]))
            return "upper";
        return "basic";
    }
    static List<String> sensitivityLines(Model model, LpResult result) {
        StandardForm form = result.form;
        Tableau tableau = result.tableau;
        Rational[] reduced = tableau.reduced(form.phase2);
        Set<Integer> basic = new HashSet<>();
        for (int column : tableau.basic)
            basic.add(column);
        List<Integer> nonbasic = new ArrayList<>();
        for (int k = 0; k < form.columnNames.size(); k++)
            if (!basic.contains(k) && !form.artificial.contains(k))
                nonbasic.add(k);
        Rational[] dual = new Rational[model.constraints.size()],
                   variableReduced = new Rational[model.variables.size()];
        for (int i = 0; i < dual.length; i++)
            dual[i] = reduced[form.initial[i]].multiply(-form.direction * form.signs[i]);
        for (int j = 0; j < variableReduced.length; j++) {
            Rational value = model.costs[j];
            for (int i = 0; i < dual.length; i++)
                value = value.subtract(dual[i].multiply(model.matrix[i][j]));
            variableReduced[j] = value;
        }
        int primal = 0, dualDegeneracy = 0;
        for (int i = 0; i < tableau.basic.length; i++)
            if (!form.artificial.contains(tableau.basic[i]) && tableau.rhs[i].sign() == 0)
                primal++;
        for (int column : nonbasic)
            if (reduced[column].sign() == 0)
                dualDegeneracy++;
        Rational dualObjective = dot(dual, model.rhs).add(dot(variableReduced, result.solution));
        List<String> lines = new ArrayList<>();
        lines.add("MODEL " + model.name + " " + (model.integerCount() > 0 ? "relaxation" : "lp") +
                  " objective " + result.objective);
        StringJoiner basis = new StringJoiner(" ");
        for (int column : tableau.basic)
            basis.add(form.columnNames.get(column));
        lines.add("BASIS " + basis);
        lines.add("DEGENERACY primal " + primal + " dual " + dualDegeneracy);
        lines.add("DUAL objective " + dualObjective);
        for (int i = 0; i < dual.length; i++)
            lines.add("CONSTRAINT " + model.constraints.get(i).name() + " price " + dual[i] +
                      " rhs " + model.rhs[i] + " range " + rhsRange(model, result, i));
        for (int j = 0; j < model.variables.size(); j++)
            lines.add("VARIABLE " + model.variables.get(j) + " " + variableStatus(form, basic, j) +
                      " value " + result.solution[j] + " reduced " + variableReduced[j] + " cost " +
                      model.costs[j] + " range " +
                      objectiveRange(model, result, j, reduced, nonbasic));
        return lines;
    }
    static BranchBound.Result solveModel(Model model, int level, int limit) {
        BranchBound.Solver solver =
            (lower, upper, number) -> solveLp(model, lower, upper, number, level);
        if (model.integerCount() > 0)
            return BranchBound.search(model, limit, solver);
        LpResult result = solver.solve(model.lower, model.upper, 1);
        return new BranchBound.Result(result.status, result.objective,
                                      result.status.equals("OPTIMAL") ? result.solution : null,
                                      List.of(result), result, List.of(), 1);
    }
    static int pivots(BranchBound.Result result) {
        int total = 0;
        for (LpResult lp : result.solves())
            total += lp.pivots();
        return total;
    }
    static List<String> solutionLines(Model model, BranchBound.Result result) {
        LpResult root = result.root();
        int integer = model.integerCount();
        List<String> lines = new ArrayList<>();
        lines.add("MODEL " + model.name + " " + model.direction + " variables " +
                  model.variables.size() + " constraints " + model.constraints.size() +
                  " integers " + integer);
        lines.add(statisticsLine(model));
        lines.add("STATUS " + result.status());
        if (result.solution() != null)
            lines.add("OBJECTIVE " + result.objective() + " approx " +
                      result.objective().approximate());
        if (integer > 0 && root.status.equals("OPTIMAL"))
            lines.add("RELAXATION " + root.objective + " approx " + root.objective.approximate());
        if (root.status.equals("INFEASIBLE")) {
            lines.add("INFEASIBILITY " + root.infeasibility);
            Rational[] multipliers = farkas(root);
            for (int i = 0; i < multipliers.length; i++)
                lines.add("FARKAS " + root.form.rowNames.get(i) + " " + multipliers[i]);
        }
        Rational[] values = result.status().equals("UNBOUNDED") ? root.solution : result.solution();
        if (values != null)
            for (int j = 0; j < values.length; j++)
                lines.add("VALUE " + model.variables.get(j) + " " + values[j]);
        if (result.status().equals("UNBOUNDED")) {
            Rational[] ray = unboundedRay(root);
            for (int j = 0; j < ray.length; j++)
                lines.add("RAY " + model.variables.get(j) + " " + ray[j]);
            lines.add("RATE " + dot(model.costs, ray));
        }
        if (result.solution() != null)
            for (int i = 0; i < model.constraints.size(); i++) {
                Rational value = dot(model.matrix[i], result.solution()),
                         margin = model.comparisons[i].equals("<=") ? model.rhs[i].subtract(value)
                                                                    : value.subtract(model.rhs[i]);
                lines.add("ROW " + model.constraints.get(i).name() + " " + value + " " + margin);
            }
        if (integer > 0)
            lines.add("NODES " + result.nodes());
        lines.add("PIVOTS " + pivots(result));
        return lines;
    }
    static final class Reports {
        List<String> iterations = new ArrayList<>(), solutions = new ArrayList<>(),
                     sensitivity = new ArrayList<>(), tree = new ArrayList<>(),
                     summary = new ArrayList<>(
                         List.of("model,status,objective,approx,relaxation,nodes,pivots"));
        Map<String, Integer> statuses = new HashMap<>();
        int solves, phase1, phase2, drives, analyzed, integerModels, integerNodes, limitedModels;
        void error(Model model) {
            statuses.merge("ERROR", 1, Integer::sum);
            iterations.add("MODEL " + model.name + " error");
            solutions.add("MODEL " + model.name);
            solutions.add("STATUS ERROR line " + model.error.line() + " " + model.error.message());
            sensitivity.add("MODEL " + model.name + " skipped ERROR");
            summary.add(model.name + ",ERROR,-,-,-,0,0");
        }
        void valid(Model model, BranchBound.Result result, int level, int limit) {
            statuses.merge(result.status(), 1, Integer::sum);
            iterations.add("MODEL " + model.name + " level " + level);
            for (LpResult lp : result.solves()) {
                iterations.addAll(lp.lines);
                solves++;
                phase1 += lp.phase1;
                phase2 += lp.phase2;
                drives += lp.drives;
            }
            solutions.addAll(solutionLines(model, result));
            if (result.root().status.equals("OPTIMAL")) {
                analyzed++;
                sensitivity.addAll(sensitivityLines(model, result.root()));
            } else
                sensitivity.add("MODEL " + model.name + " skipped " + result.root().status);
            if (model.integerCount() > 0) {
                integerModels++;
                integerNodes += result.nodes();
                if (result.status().equals("NODE_LIMIT"))
                    limitedModels++;
                tree.add("MODEL " + model.name + " " + model.direction + " integers " +
                         model.integerCount() + " node_limit " + limit);
                tree.addAll(result.lines());
            }
            String objective = result.objective() == null ? "-" : result.objective().toString(),
                   approx = result.objective() == null ? "-" : result.objective().approximate(),
                   relaxation =
                       result.root().objective == null ? "-" : result.root().objective.toString();
            summary.add(model.name + "," + result.status() + "," + objective + "," + approx + "," +
                        relaxation + "," + result.solves().size() + "," + pivots(result));
        }
        void finish() throws Exception {
            int models = 0;
            for (int count : statuses.values())
                models += count;
            iterations.add("TOTAL solves " + solves + " phase1 " + phase1 + " phase2 " + phase2 +
                           " drives " + drives + " pivots " + (phase1 + phase2 + drives));
            solutions.add("SUMMARY models " + models + " optimal " +
                          statuses.getOrDefault("OPTIMAL", 0) + " infeasible " +
                          statuses.getOrDefault("INFEASIBLE", 0) + " unbounded " +
                          statuses.getOrDefault("UNBOUNDED", 0) + " node_limit " +
                          statuses.getOrDefault("NODE_LIMIT", 0) + " error " +
                          statuses.getOrDefault("ERROR", 0));
            sensitivity.add("SUMMARY analyzed " + analyzed + " skipped " + (models - analyzed));
            tree.add("SUMMARY models " + integerModels + " nodes " + integerNodes + " node_limit " +
                     limitedModels);
            Files.createDirectories(Path.of("output"));
            write("iterations.txt", iterations);
            write("solutions.txt", solutions);
            write("sensitivity.txt", sensitivity);
            write("bnb_tree.txt", tree);
            write("summary.csv", summary);
        }
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        LpParser.Settings settings = LpParser.settings();
        Reports reports = new Reports();
        for (LpParser.Parsed parsed : LpParser.models()) {
            Model model = contentCheck(parsed);
            if (model.error != null) {
                reports.error(model);
                continue;
            }
            int level = settings.logs().getOrDefault(model.name, settings.level()),
                limit = settings.limits().getOrDefault(model.name, settings.limit());
            BranchBound.Result result = solveModel(model, level, limit);
            reports.valid(model, result, level, limit);
        }
        reports.finish();
    }
}
