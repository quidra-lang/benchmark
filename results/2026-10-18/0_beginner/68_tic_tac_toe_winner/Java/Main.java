import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        String[][] boards = {{"XXX","OO.","O.X"}, {"X.O",".X.","O.."}, {"XO.",".OX","XO."},
            {"XOX","XOO","OXX"}, {"X.O","XO.","O.X"}, {"XOX","OXO","OXX"}};
        int[][] lines = {{0,1,2},{3,4,5},{6,7,8},{0,3,6},{1,4,7},{2,5,8},{0,4,8},{2,4,6}};
        for (int i = 0; i < boards.length; i++) {
            String cells = String.join("",boards[i]);
            String result = Arrays.stream(lines)
                    .filter(line -> cells.charAt(line[0]) != '.' && cells.charAt(line[0]) == cells.charAt(line[1]) &&
                            cells.charAt(line[0]) == cells.charAt(line[2]))
                    .findFirst().map(line -> cells.charAt(line[0]) + " wins")
                    .orElse(cells.contains(".") ? "in progress" : "draw");
            System.out.println("board " + (i + 1) + ": " + result);
        }
    }
}
