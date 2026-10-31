import java.util.*;

final class Eigen {
    record Result(double[] values, double[][] vectors, int sweeps) {}
    static double off(double[][] a) {
        double sum = 0;
        for (int p = 0; p < a.length - 1; p++)
            for (int q = p + 1; q < a.length; q++)
                sum += a[p][q] * a[p][q];
        return sum;
    }
    static void rotate(double[][] a, double[][] v, int p, int q) {
        double apq = a[p][q];
        if (apq == 0)
            return;
        double theta = (a[q][q] - a[p][p]) / (2 * apq),
               t = 1 / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
        if (theta < 0)
            t = -t;
        double c = 1 / Math.sqrt(t * t + 1), s = t * c;
        for (int r = 0; r < a.length; r++)
            if (r != p && r != q) {
                double arp = a[r][p], arq = a[r][q];
                a[r][p] = a[p][r] = c * arp - s * arq;
                a[r][q] = a[q][r] = s * arp + c * arq;
            }
        a[p][p] -= t * apq;
        a[q][q] += t * apq;
        a[p][q] = a[q][p] = 0;
        for (int r = 0; r < v.length; r++) {
            double first = v[r][p], second = v[r][q];
            v[r][p] = c * first - s * second;
            v[r][q] = s * first + c * second;
        }
    }
    static Result jacobi(double[][] matrix) {
        int n = matrix.length;
        double[][] a = Matrix.copy(matrix), v = Matrix.identity(n);
        double initial = off(a);
        int count = 0;
        if (initial > 0)
            for (int sweep = 1; sweep <= 100; sweep++) {
                for (int p = 0; p < n - 1; p++)
                    for (int q = p + 1; q < n; q++)
                        rotate(a, v, p, q);
                double current = off(a);
                if (count == 0 && current < 1e-16 * initial)
                    count = sweep;
                if (current < 1e-22 * initial)
                    break;
            }
        List<Integer> order = new ArrayList<>();
        for (int k = 0; k < n; k++)
            order.add(k);
        order.sort((left, right) -> {
            int comparison = Double.compare(a[right][right], a[left][left]);
            return comparison != 0 ? comparison : Integer.compare(left, right);
        });
        double[] values = new double[n];
        double[][] vectors = new double[n][];
        for (int k = 0; k < n; k++) {
            int index = order.get(k);
            values[k] = a[index][index];
            vectors[k] = Matrix.column(v, index);
            Matrix.normalize(vectors[k]);
            Matrix.orient(vectors[k]);
        }
        return new Result(values, vectors, count);
    }
    record Power(double value, double[] vector, int agreement) {}
    static List<Power> power(double[][] matrix, double[][] reference) {
        int n = matrix.length;
        double[][] b = Matrix.copy(matrix);
        List<Power> result = new ArrayList<>();
        for (int k = 0; k < n; k++) {
            double[] x = new double[n];
            Arrays.fill(x, 1);
            int agreement = 0;
            for (int iteration = 1; iteration <= 1000; iteration++) {
                x = Matrix.multiply(b, x);
                Matrix.normalize(x);
                double positive = 0, negative = 0;
                for (int j = 0; j < n; j++) {
                    positive = Math.max(positive, Math.abs(x[j] - reference[k][j]));
                    negative = Math.max(negative, Math.abs(x[j] + reference[k][j]));
                }
                if (agreement == 0 && Math.min(positive, negative) < 0.000001)
                    agreement = iteration;
            }
            double value = Matrix.dot(x, Matrix.multiply(b, x));
            Matrix.normalize(x);
            Matrix.orient(x);
            result.add(new Power(value, x, agreement));
            Matrix.deflate(b, value, x);
        }
        return result;
    }
}
