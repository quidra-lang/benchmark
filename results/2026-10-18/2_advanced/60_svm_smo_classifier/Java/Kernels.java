import java.util.*;

final class Kernels {
    record Point(double x, double y) {}
    record Kernel(String name, String kind, int degree, double gamma, double offset) {
        double value(Point a, Point b) {
            if (kind.equals("linear"))
                return a.x() * b.x() + a.y() * b.y();
            if (kind.equals("poly")) {
                double s = gamma * (a.x() * b.x() + a.y() * b.y()) + offset, value = 1;
                for (int i = 0; i < degree; i++)
                    value *= s;
                return value;
            }
            double e1 = a.x() - b.x(), e2 = a.y() - b.y();
            return Math.exp(-gamma * (e1 * e1 + e2 * e2));
        }
        String description() {
            return kind.equals("linear") ? "linear"
            : kind.equals("poly")        ? "poly degree " + degree + " gamma " + Evaluation.fixed(gamma, 4) +
                                               " coef0 " + Evaluation.fixed(offset, 4)
                                         : "rbf gamma " + Evaluation.fixed(gamma, 4);
        }
        double[][] matrix(List<Point> points) {
            int n = points.size();
            double[][] matrix = new double[n][n];
            for (int i = 0; i < n; i++)
                for (int j = 0; j < n; j++)
                    matrix[i][j] = value(points.get(i), points.get(j));
            return matrix;
        }
    }
    static double[][] submatrix(double[][] matrix, List<Integer> indices) {
        int n = indices.size();
        double[][] result = new double[n][n];
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                result[i][j] = matrix[indices.get(i)][indices.get(j)];
        return result;
    }
}
