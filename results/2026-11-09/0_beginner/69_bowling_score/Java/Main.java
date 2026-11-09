import java.util.ArrayList;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        int[][] games = {{8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2},
            {3, 4, 5, 2, 7, 1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5},
            {5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7, 4, 6, 1, 9, 7, 3, 5},
            {10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10},
            {10, 9, 1, 10, 10, 7, 2, 0, 0, 10, 8, 1, 10, 6, 4, 10}};
        for (int game = 0; game < games.length; game++) {
            int[] rolls = games[game];
            int index = 0, total = 0;
            List<String> cumulative = new ArrayList<>();
            for (int frame = 1; frame <= 10; frame++) {
                if (frame == 10) {
                    while (index < rolls.length) {
                        total += rolls[index++];
                    }
                } else if (rolls[index] == 10) {
                    total += 10 + rolls[index + 1] + rolls[index + 2];
                    index++;
                } else {
                    int pins = rolls[index] + rolls[index + 1];
                    total += pins;
                    if (pins == 10) {
                        total += rolls[index + 2];
                    }
                    index += 2;
                }
                cumulative.add(Integer.toString(total));
            }
            System.out.println("game " + (game + 1) + ": " + String.join(" ", cumulative));
        }
    }
}
