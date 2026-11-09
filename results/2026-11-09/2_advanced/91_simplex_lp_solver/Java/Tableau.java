import java.util.*;
import java.util.function.UnaryOperator;
final class Tableau {
    List<String> rowNames, columnNames;
    Rational[][] values;
    Rational[] rhs;
    int[] basic;
    Tableau(List<String> rowNames, List<String> columnNames, Rational[][] matrix, Rational[] rhs,
            int[] initial) {
        this.rowNames = rowNames;
        this.columnNames = columnNames;
        values = new Rational[matrix.length][];
        for (int i = 0; i < matrix.length; i++)
            values[i] = matrix[i].clone();
        this.rhs = rhs.clone();
        basic = initial.clone();
    }
    void pivot(int row, int column) {
        Rational divisor = values[row][column];
        for (int k = 0; k < columnNames.size(); k++)
            values[row][k] = values[row][k].divide(divisor);
        rhs[row] = rhs[row].divide(divisor);
        for (int other = 0; other < values.length; other++)
            if (other != row) {
                Rational factor = values[other][column];
                for (int k = 0; k < columnNames.size(); k++)
                    values[other][k] = values[other][k].subtract(factor.multiply(values[row][k]));
                rhs[other] = rhs[other].subtract(factor.multiply(rhs[row]));
            }
        basic[row] = column;
    }
    Rational[] reduced(Rational[] costs) {
        Rational[] reduced = costs.clone();
        for (int k = 0; k < costs.length; k++)
            for (int row = 0; row < values.length; row++)
                reduced[k] = reduced[k].subtract(costs[basic[row]].multiply(values[row][k]));
        return reduced;
    }
    Rational phaseValue(Rational[] costs) {
        Rational value = Rational.ZERO;
        for (int i = 0; i < rhs.length; i++)
            value = value.add(costs[basic[i]].multiply(rhs[i]));
        return value;
    }
    static String joined(Rational[] values) {
        StringJoiner text = new StringJoiner(" ");
        for (Rational value : values)
            text.add(value.toString());
        return text.toString();
    }
    List<String> display(String heading, Rational[] costs, UnaryOperator<Rational> objective) {
        List<String> lines = new ArrayList<>();
        lines.add("TABLEAU " + heading);
        lines.add("COLUMNS " + String.join(" ", columnNames));
        for (int i = 0; i < values.length; i++)
            lines.add("ROW " + rowNames.get(i) + " " + columnNames.get(basic[i]) + " " +
                      joined(values[i]) + " | " + rhs[i]);
        lines.add("COST " + joined(reduced(costs)) + " | " + objective.apply(phaseValue(costs)));
        return lines;
    }
}
