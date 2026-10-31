import java.util.*;
import java.util.function.UnaryOperator;
final class Simplex {
    record Result(int iterations, Integer unbounded, List<String> lines) {}
    static Result run(Tableau tableau, Rational[] costs, List<Integer> candidates,
                      UnaryOperator<Rational> objective) {
        int iterations = 0;
        List<String> lines = new ArrayList<>();
        List<Integer> ordered = new ArrayList<>(candidates);
        ordered.sort(Integer::compare);
        while (true) {
            Rational[] reduced = tableau.reduced(costs);
            int entering = -1;
            for (int column : ordered)
                if (reduced[column].sign() < 0) {
                    entering = column;
                    break;
                }
            if (entering < 0)
                return new Result(iterations, null, lines);
            int leaving = -1;
            Rational ratio = null;
            for (int row = 0; row < tableau.values.length; row++)
                if (tableau.values[row][entering].sign() > 0) {
                    Rational value = tableau.rhs[row].divide(tableau.values[row][entering]);
                    if (ratio == null || value.compareTo(ratio) < 0 ||
                        value.equals(ratio) && tableau.basic[row] < tableau.basic[leaving]) {
                        ratio = value;
                        leaving = row;
                    }
                }
            if (leaving < 0)
                return new Result(iterations, entering, lines);
            Rational before = reduced[entering];
            int oldBasic = tableau.basic[leaving];
            tableau.pivot(leaving, entering);
            iterations++;
            Rational value = objective.apply(tableau.phaseValue(costs));
            lines.add("PIVOT " + iterations + " enter " + tableau.columnNames.get(entering) +
                      " reduced " + before + " leave " + tableau.columnNames.get(oldBasic) +
                      " row " + tableau.rowNames.get(leaving) + " ratio " + ratio + " objective " +
                      value);
        }
    }
}
