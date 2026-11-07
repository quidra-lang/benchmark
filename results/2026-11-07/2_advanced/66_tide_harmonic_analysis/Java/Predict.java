import java.util.*;
final class Predict {
    static final class Extremum {
        boolean high;
        double minute, height;
        int rounded;
        String label;
        Extremum(boolean high, double minute, double height) {
            this.high = high;
            this.minute = minute;
            this.height = height;
        }
    }
    static double height(HarmonicFit.Model m, double t) {
        double value = m.coefficients()[0];
        for (int k = 0; k < m.selected().size(); k++) {
            double angle = HarmonicFit.angle(m.selected().get(k).speed(), t);
            HarmonicFit.Constant c = m.constants().get(k);
            value += c.a() * Math.cos(angle) + c.b() * Math.sin(angle);
        }
        return value;
    }
    static double[] hours(HarmonicFit.Model m, int start, int count) {
        double[] values = new double[count + 1];
        for (int i = 0; i <= count; i++)
            values[i] = height(m, start + i);
        return values;
    }
    static List<Extremum> extrema(HarmonicFit.Model m, int start, int hours, int grid) {
        int count = hours * 60 / grid;
        double[] values = new double[count + 1];
        for (int j = 0; j <= count; j++)
            values[j] = height(m, (60 * start + j * grid) / 60.0);
        List<Extremum> result = new ArrayList<>();
        for (int j = 1; j < count; j++) {
            double left = values[j - 1], center = values[j], right = values[j + 1];
            boolean high = left < center && center > right, low = left > center && center < right;
            if (!high && !low)
                continue;
            double delta = (left - right) / (2 * (left - 2 * center + right)),
                   minute = 60 * start + j * grid + delta * grid,
                   z = center - (left - right) * delta / 4;
            result.add(new Extremum(high, minute, z));
        }
        return result;
    }
}
