import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        String[] names = {"tent", "stove", "lantern", "rope", "camera", "blanket", "water"};
        int[] weights = {10,3,2,3,5,5,6}, values = {120,65,45,20,90,85,100};
        int[][] dp = new int[8][21];
        for (int i = 1; i <= 7; i++) {
            for (int capacity = 0; capacity <= 20; capacity++) {
                dp[i][capacity] = dp[i - 1][capacity];
                if (weights[i - 1] <= capacity) {
                    dp[i][capacity] = Math.max(dp[i][capacity], dp[i - 1][capacity - weights[i - 1]] + values[i - 1]);
                }
            }
        }
        boolean[] chosen = new boolean[7];
        int capacity = 20, totalWeight = 0;
        for (int i = 7; i >= 1; i--) {
            if (dp[i][capacity] != dp[i - 1][capacity]) {
                chosen[i - 1] = true;
                capacity -= weights[i - 1];
                totalWeight += weights[i - 1];
            }
        }
        List<String> items = new ArrayList<>();
        for (int i = 0; i < 7; i++) {
            if (chosen[i]) items.add(names[i]);
        }
        System.out.println("max value: " + dp[7][20]);
        System.out.println("total weight: " + totalWeight);
        System.out.println("items: " + String.join(" ",items));
    }
}
