import java.util.Arrays;

public class Main {
    static int queens(int[] positions, int row, int[] first) {
        if (row == positions.length) {
            if (first[0] == -1) System.arraycopy(positions,0,first,0,positions.length);
            return 1;
        }
        if (row == 0) Arrays.fill(first,-1);
        int count = 0;
        for (int column = 0; column < positions.length; column++) {
            boolean safe = true;
            for (int previous = 0; previous < row; previous++) {
                if (positions[previous] == column || Math.abs(positions[previous] - column) == row - previous) {
                    safe = false;
                    break;
                }
            }
            if (safe) {
                positions[row] = column;
                count += queens(positions,row + 1,first);
            }
        }
        return count;
    }
    public static void main(String[] args) {
        int[] firstEight = new int[8];
        for (int n = 4; n <= 8; n++) {
            int[] positions = new int[n], first = new int[n];
            int solutions = queens(positions,0,first);
            System.out.println("N=" + n + ": " + solutions + " solutions");
            if (n == 8) firstEight = first;
        }
        for (int column : firstEight) System.out.println(".".repeat(column) + "Q" + ".".repeat(7 - column));
    }
}
