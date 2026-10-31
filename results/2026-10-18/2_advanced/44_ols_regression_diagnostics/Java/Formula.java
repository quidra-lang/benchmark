import java.util.*;

final class Formula {
    record Factor(String name, String column, int power, boolean categorical) {}
    static Factor factor(String name) {
        if (name.startsWith("C("))
            return new Factor(name, name.substring(2, name.length() - 1), 1, true);
        if (name.startsWith("I(")) {
            int caret = name.indexOf('^');
            return new Factor(name, name.substring(2, caret),
                              Integer.parseInt(name.substring(caret + 1, caret + 2)), false);
        }
        return new Factor(name, name, 1, false);
    }
    static final class Term {
        String name;
        List<Factor> factors;
        Set<String> names = new HashSet<>();
        Term(List<String> words) {
            factors = new ArrayList<>();
            for (String word : words) {
                factors.add(factor(word));
                names.add(word);
            }
            name = String.join(":", words);
        }
    }
    static boolean contained(Term a, Term b) {
        return a.names.size() < b.names.size() && b.names.containsAll(a.names);
    }
    static final class Model {
        String response, weight, original;
        List<Term> terms = new ArrayList<>();
        Set<String> variables = new LinkedHashSet<>();
        Set<String> factorColumns = new LinkedHashSet<>();
    }
    static void add(Model model, List<String> factors) {
        Term term = new Term(factors);
        for (Term old : model.terms)
            if (old.names.equals(term.names))
                return;
        model.terms.add(term);
    }
    static Model parse(String line) {
        Model model = new Model();
        int weighted = line.indexOf(" weights=");
        model.original = weighted < 0 ? line : line.substring(0, weighted);
        model.weight = weighted < 0 ? null : line.substring(weighted + 9);
        int split = model.original.indexOf(" ~ ");
        model.response = model.original.substring(0, split);
        for (String expression : model.original.substring(split + 3).split(" \\+ ")) {
            if (!expression.contains("*"))
                add(model, Arrays.asList(expression.split(":")));
            else {
                List<String> factors = Arrays.asList(expression.split("\\*"));
                for (int size = 1; size <= factors.size(); size++)
                    for (int mask = 1; mask < (1 << factors.size()); mask++)
                        if (Integer.bitCount(mask) == size) {
                            List<String> selected = new ArrayList<>();
                            for (int i = 0; i < factors.size(); i++)
                                if ((mask & (1 << i)) != 0)
                                    selected.add(factors.get(i));
                            add(model, selected);
                        }
            }
        }
        for (Term term : model.terms)
            for (Factor factor : term.factors)
                model.factorColumns.add(factor.column());
        model.variables.addAll(model.factorColumns);
        model.variables.add(model.response);
        if (model.weight != null)
            model.variables.add(model.weight);
        return model;
    }
    record Component(Factor factor, String name, String level) {
        double value(Dataframe.Row row) {
            if (factor.categorical())
                return row.values().get(factor.column()).equals(level) ? 1 : 0;
            double v = row.numeric(factor.column());
            return factor.power() == 1 ? v : factor.power() == 2 ? v * v : v * v * v;
        }
    }
    static final class Column {
        String name;
        int term;
        List<Component> components;
        Column(String name, int term, List<Component> components) {
            this.name = name;
            this.term = term;
            this.components = components;
        }
        double value(Dataframe.Row row) {
            double product = 1;
            for (Component component : components)
                product *= component.value(row);
            return product;
        }
    }
    static final class Design {
        Model model;
        List<Dataframe.Row> rows = new ArrayList<>();
        Map<String, List<String>> levels = new LinkedHashMap<>();
        List<Column> columns = new ArrayList<>();
        double[] y, w;
        Design(Model model, Dataframe.Frame frame) {
            this.model = model;
            for (Dataframe.Row row : frame.rows) {
                boolean valid = true;
                for (String column : model.variables)
                    if (row.values().get(column) == null)
                        valid = false;
                if (valid)
                    rows.add(row);
            }
            for (Term term : model.terms)
                for (Factor factor : term.factors)
                    if (factor.categorical() && !levels.containsKey(factor.column())) {
                        SortedSet<String> values = new TreeSet<>();
                        for (Dataframe.Row row : rows)
                            values.add(row.values().get(factor.column()));
                        levels.put(factor.column(), new ArrayList<>(values));
                    }
            columns.add(new Column("(Intercept)", -1, new ArrayList<>()));
            for (int t = 0; t < model.terms.size(); t++) {
                Term term = model.terms.get(t);
                List<List<Component>> choices = new ArrayList<>();
                int count = 1;
                for (Factor factor : term.factors) {
                    List<Component> components = new ArrayList<>();
                    if (factor.categorical()) {
                        List<String> values = levels.get(factor.column());
                        for (int i = 1; i < values.size(); i++)
                            components.add(
                                new Component(factor, factor.name() + values.get(i), values.get(i)));
                    } else
                        components.add(new Component(factor, factor.name(), null));
                    choices.add(components);
                    count *= components.size();
                }
                for (int ordinal = 0; ordinal < count; ordinal++) {
                    int rest = ordinal;
                    List<Component> components = new ArrayList<>();
                    List<String> names = new ArrayList<>();
                    for (List<Component> list : choices) {
                        Component component = list.get(rest % list.size());
                        rest /= list.size();
                        components.add(component);
                        names.add(component.name());
                    }
                    columns.add(new Column(String.join(":", names), t, components));
                }
            }
            y = new double[rows.size()];
            w = new double[rows.size()];
            for (int i = 0; i < rows.size(); i++) {
                y[i] = rows.get(i).numeric(model.response);
                w[i] = model.weight == null ? 1 : rows.get(i).numeric(model.weight);
            }
        }
        int[] indices(int mask) {
            List<Integer> result = new ArrayList<>();
            for (int j = 0; j < columns.size(); j++)
                if (columns.get(j).term < 0 || (mask & (1 << columns.get(j).term)) != 0)
                    result.add(j);
            int[] indices = new int[result.size()];
            for (int i = 0; i < indices.length; i++)
                indices[i] = result.get(i);
            return indices;
        }
        double[][] matrix(int[] indices) {
            double[][] result = new double[rows.size()][indices.length];
            for (int i = 0; i < rows.size(); i++)
                for (int j = 0; j < indices.length; j++)
                    result[i][j] = columns.get(indices[j]).value(rows.get(i));
            return result;
        }
        boolean predictable(Dataframe.Row row) {
            for (String name : model.factorColumns) {
                String value = row.values().get(name);
                if (value == null || (levels.containsKey(name) && !levels.get(name).contains(value)))
                    return false;
            }
            return true;
        }
        double[] vector(Dataframe.Row row) {
            double[] result = new double[columns.size()];
            for (int j = 0; j < result.length; j++)
                result[j] = columns.get(j).value(row);
            return result;
        }
    }
    static String display(Model model, int mask) {
        List<String> terms = new ArrayList<>();
        for (int t = 0; t < model.terms.size(); t++)
            if ((mask & (1 << t)) != 0)
                terms.add(model.terms.get(t).name);
        return model.response + " ~ " + (terms.isEmpty() ? "1" : String.join(" + ", terms));
    }
    static boolean removable(Model model, int mask, int term) {
        if ((mask & (1 << term)) == 0)
            return false;
        for (int t = 0; t < model.terms.size(); t++)
            if ((mask & (1 << t)) != 0 && contained(model.terms.get(term), model.terms.get(t)))
                return false;
        return true;
    }
    static boolean hierarchical(Model model, int mask) {
        for (int t = 0; t < model.terms.size(); t++)
            if ((mask & (1 << t)) != 0)
                for (int a = 0; a < model.terms.size(); a++)
                    if (contained(model.terms.get(a), model.terms.get(t)) && (mask & (1 << a)) == 0)
                        return false;
        return true;
    }
}
