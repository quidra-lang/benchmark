import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        int[] coins = {1, 5, 6, 9};
        for (int amount : new int[]{8, 11, 15, 22, 33, 40}) {
            int[] minimum = new int[amount + 1], ways = new int[amount + 1];
            Arrays.fill(minimum, amount + 1);
            minimum[0] = 0;
            ways[0] = 1;
            for (int value = 1; value <= amount; value++) {
                for (int coin : coins) {
                    if (coin <= value) {
                        minimum[value] = Math.min(minimum[value], minimum[value - coin] + 1);
                    }
                }
            }
            for (int coin : coins) {
                for (int value = coin; value <= amount; value++) {
                    ways[value] += ways[value - coin];
                }
            }
            int remaining = amount, greedy = 0;
            for (int i = coins.length - 1; i >= 0; i--) {
                while (remaining >= coins[i]) {
                    remaining -= coins[i];
                    greedy++;
                }
            }
            System.out.println(amount + ": min=" + minimum[amount] + " greedy=" + greedy + " ways=" + ways[amount]);
        }
    }
}
