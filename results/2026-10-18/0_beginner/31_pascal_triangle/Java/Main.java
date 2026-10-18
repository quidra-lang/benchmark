import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        int[] row = {1};
        for (int n = 0; n < 12; n++) {
            System.out.println(String.join(" ", Arrays.stream(row).mapToObj(String::valueOf).toList()));
            int[] next = new int[row.length + 1];
            next[0] = next[next.length - 1] = 1;
            for (int k = 1; k < row.length; k++) next[k] = row[k - 1] + row[k];
            row = next;
        }
    }
}
