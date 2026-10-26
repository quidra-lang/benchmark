import java.util.Arrays;
import java.util.List;

record Massey(double[] ratings, double homeAdvantage) {}
final class LinearModels {
    static double[] cholesky(double[][] matrix, double[] vector) {
        int size = vector.length; double[][] lower = new double[size][size];
        for (int i = 0; i < size; i++) for (int j = 0; j <= i; j++) {
            double total = 0; for (int k = 0; k < j; k++) total += lower[i][k] * lower[j][k];
            lower[i][j] = j < i ? (matrix[i][j] - total) / lower[j][j] : Math.sqrt(matrix[i][i] - total);
        }
        double[] forward = new double[size];
        for (int i = 0; i < size; i++) { double total = 0; for (int k = 0; k < i; k++) total += lower[i][k] * forward[k]; forward[i] = (vector[i] - total) / lower[i][i]; }
        double[] solution = new double[size];
        for (int i = size - 1; i >= 0; i--) { double total = 0; for (int k = i + 1; k < size; k++) total += lower[k][i] * solution[k]; solution[i] = (forward[i] - total) / lower[i][i]; }
        return solution;
    }
    static double[] gaussian(double[][] matrix, double[] vector) {
        int size = vector.length;
        for (int k = 0; k < size; k++) {
            int pivot = k; for (int row = k + 1; row < size; row++) if (Math.abs(matrix[row][k]) > Math.abs(matrix[pivot][k])) pivot = row;
            double[] swap = matrix[k]; matrix[k] = matrix[pivot]; matrix[pivot] = swap; double value = vector[k]; vector[k] = vector[pivot]; vector[pivot] = value;
            for (int i = k + 1; i < size; i++) { double factor = matrix[i][k] / matrix[k][k]; for (int j = k; j < size; j++) matrix[i][j] -= factor * matrix[k][j]; vector[i] -= factor * vector[k]; }
        }
        double[] solution = new double[size];
        for (int i = size - 1; i >= 0; i--) { double total = 0; for (int j = i + 1; j < size; j++) total += matrix[i][j] * solution[j]; solution[i] = (vector[i] - total) / matrix[i][i]; }
        return solution;
    }
    static double[] colley(int count, List<Match> matches) {
        double[][] matrix = new double[count][count]; int[] balance = new int[count];
        for (int i = 0; i < count; i++) matrix[i][i] = 2;
        for (Match match : matches) {
            int home = match.home(), away = match.away(); matrix[home][home]++; matrix[away][away]++; matrix[home][away]--; matrix[away][home]--;
            if (match.margin() > 0) { balance[home]++; balance[away]--; } else if (match.margin() < 0) { balance[home]--; balance[away]++; }
        }
        double[] vector = new double[count]; for (int i = 0; i < count; i++) vector[i] = 1 + balance[i] / 2.0;
        return cholesky(matrix, vector);
    }
    static Massey massey(int count, List<Match> matches) {
        int size = count + 1; double[][] matrix = new double[size][size]; double[] vector = new double[size];
        for (Match match : matches) {
            int home = match.home(), away = match.away(), margin = match.margin();
            matrix[home][home]++; matrix[away][away]++; matrix[home][away]--; matrix[away][home]--;
            matrix[home][count]++; matrix[count][home]++; matrix[away][count]--; matrix[count][away]--; matrix[count][count]++;
            vector[home] += margin; vector[away] -= margin; vector[count] += margin;
        }
        Arrays.fill(matrix[count - 1], 1); matrix[count - 1][count] = 0; vector[count - 1] = 0;
        double[] solution = gaussian(matrix, vector); return new Massey(Arrays.copyOf(solution, count), solution[count]);
    }
}
