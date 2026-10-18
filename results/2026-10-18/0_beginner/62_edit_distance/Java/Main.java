import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        String[][] pairs = {{"kitten", "sitting"}, {"flaw", "lawn"}, {"listen", "silent"},
            {"intention", "execution"}, {"algorithm", "altruistic"}};
        for (String[] pair : pairs) {
            String a = pair[0], b = pair[1];
            int[][] dp = new int[a.length() + 1][b.length() + 1];
            for (int i = 0; i <= a.length(); i++) dp[i][0] = i;
            for (int j = 0; j <= b.length(); j++) dp[0][j] = j;
            for (int i = 1; i <= a.length(); i++) {
                for (int j = 1; j <= b.length(); j++) {
                    int cost = a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1;
                    dp[i][j] = Math.min(dp[i - 1][j] + 1,
                        Math.min(dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost));
                }
            }
            System.out.println(a + " -> " + b + ": " + dp[a.length()][b.length()]);
        }
    }
}
