import java.util.*;

final class Transient {
    record Step(double[] field, double[] intermediate) {}
    static double flow(Main.Thermal s, double[] x, int p, int first, int last) {
        double sum = 0;
        for (int f = first; f <= last; f++) {
            Main.Face face = s.faces[p][f];
            if (face.neighbor >= 0)
                sum += face.g * (x[face.neighbor] - x[p]);
            else if (face.boundary)
                sum += face.g * (face.theta - x[p]);
        }
        return sum;
    }
    static double[] thomas(double[] lower, double[] diagonal, double[] upper, double[] rhs) {
        int n = diagonal.length;
        double[] u = new double[n], v = new double[n], x = new double[n];
        u[0] = upper[0] / diagonal[0];
        v[0] = rhs[0] / diagonal[0];
        for (int i = 1; i < n; i++) {
            double pivot = diagonal[i] - lower[i] * u[i - 1];
            u[i] = upper[i] / pivot;
            v[i] = (rhs[i] - lower[i] * v[i - 1]) / pivot;
        }
        x[n - 1] = v[n - 1];
        for (int i = n - 2; i >= 0; i--)
            x[i] = v[i] - u[i] * x[i + 1];
        return x;
    }
    static double[] sweep(Main.Thermal s, double tau, double[] rhs, boolean horizontal) {
        Mesh m = s.mesh;
        int lines = horizontal ? m.height : m.width, length = horizontal ? m.width : m.height,
            first = horizontal ? 0 : 2;
        double[] field = new double[m.count];
        for (int line = 0; line < lines; line++) {
            double[] lower = new double[length], diagonal = new double[length], upper = new double[length],
                     right = new double[length];
            int[] cells = new int[length];
            for (int i = 0; i < length; i++) {
                int p = horizontal ? m.cell(line, i) : m.cell(i, line);
                cells[i] = p;
                Main.Face a = s.faces[p][first], b = s.faces[p][first + 1];
                lower[i] = a.neighbor >= 0 ? -a.g : 0;
                upper[i] = b.neighbor >= 0 ? -b.g : 0;
                diagonal[i] = s.capacity[p] / tau + a.g + b.g;
                double value = rhs[p];
                if (a.boundary)
                    value += a.g * a.theta;
                if (b.boundary)
                    value += b.g * b.theta;
                right[i] = value;
            }
            double[] solved = thomas(lower, diagonal, upper, right);
            for (int i = 0; i < length; i++)
                field[cells[i]] = solved[i];
        }
        return field;
    }
    static Step advance(String method, Main.Thermal s, double[] field, double[] source, double dt) {
        int n = s.mesh.count;
        double[] rhs = new double[n];
        if (method.equals("ftcs")) {
            for (int p = 0; p < n; p++)
                rhs[p] = field[p] + dt * (flow(s, field, p, 0, 3) + source[p]) / s.capacity[p];
            return new Step(rhs, null);
        }
        boolean backward = method.equals("backward_euler");
        double tau = backward ? dt : dt / 2;
        double[] vertical = new double[n];
        for (int p = 0; p < n; p++) {
            vertical[p] = flow(s, field, p, 2, 3);
            rhs[p] = s.capacity[p] / tau * field[p] + vertical[p] + source[p];
        }
        double[] middle = sweep(s, tau, rhs, true);
        for (int p = 0; p < n; p++)
            rhs[p] = backward ? s.capacity[p] / dt * middle[p] - vertical[p]
                              : s.capacity[p] / tau * middle[p] + flow(s, middle, p, 0, 1) + source[p];
        return new Step(sweep(s, tau, rhs, false), middle);
    }
}
