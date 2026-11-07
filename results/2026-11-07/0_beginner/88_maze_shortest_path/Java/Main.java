import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Deque;

public class Main {
    public static void main(String[] args) {
        String[] rows = {
            "#############",
            "#S..#.......#",
            "#.#.#.###.#.#",
            "#.#...#...#.#",
            "#.###.#.###.#",
            "#...#...#...#",
            "###.#####.#.#",
            "#.......#..G#",
            "#############"};
        char[][] maze = Arrays.stream(rows).map(String::toCharArray).toArray(char[][]::new);
        int start = -1, goal = -1;
        for (int r = 0; r < 9; r++) {
            for (int c = 0; c < 13; c++) {
                if (maze[r][c] == 'S') {
                    start = r * 13 + c;
                }
                if (maze[r][c] == 'G') {
                    goal = r * 13 + c;
                }
            }
        }
        int[] parent = new int[117];
        Arrays.fill(parent, -1);
        parent[start] = start;
        Deque<Integer> queue = new ArrayDeque<>();
        queue.add(start);
        int[] dr = {-1, 1, 0, 0}, dc = {0, 0, -1, 1};
        while (!queue.isEmpty()) {
            int cell = queue.remove(), r = cell / 13, c = cell % 13;
            if (cell == goal) {
                break;
            }
            for (int d = 0; d < 4; d++) {
                int nr = r + dr[d], nc = c + dc[d];
                if (nr < 0 || nr >= 9 || nc < 0 || nc >= 13) {
                    continue;
                }
                int next = nr * 13 + nc;
                if (maze[nr][nc] != '#' && parent[next] < 0) {
                    parent[next] = cell;
                    queue.add(next);
                }
            }
        }
        int steps = 0;
        for (int cell = goal; cell != start; cell = parent[cell]) {
            if (cell != goal) {
                maze[cell / 13][cell % 13] = '*';
            }
            steps++;
        }
        System.out.println("steps: " + steps);
        for (char[] row : maze) {
            System.out.println(new String(row));
        }
    }
}
