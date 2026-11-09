public class Main {
    static int determinant(int[][] matrix) {
        int n = matrix.length;
        if (n == 1) {
            return matrix[0][0];
        }
        int result = 0;
        for (int column = 0; column < n; column++) {
            int[][] minor = new int[n - 1][n - 1];
            for (int r = 1; r < n; r++) {
                int index = 0;
                for (int c = 0; c < n; c++) {
                    if (c != column) {
                        minor[r - 1][index++] = matrix[r][c];
                    }
                }
            }
            int term = matrix[0][column] * determinant(minor);
            result += column % 2 == 0 ? term : -term;
        }
        return result;
    }

    public static void main(String[] args) {
        int[][][] matrices = {
            {{2, -3, 1}, {5, 4, -2}, {-1, 6, 3}},
            {{3, 0, -2, 5}, {1, 4, 7, -3}, {-6, 2, 1, 8}, {9, -5, 3, 2}},
            {{4, -1, 7, 0, -3}, {2, 8, -5, 6, 1}, {-9, 3, 2, -4, 5}, {6, 0, -7, 3, -2}, {1, -6, 4, 9, 8}}};
        for (int[][] matrix : matrices) {
            System.out.println("det(" + matrix.length + "x" + matrix.length + ") = " + determinant(matrix));
        }
    }
}
