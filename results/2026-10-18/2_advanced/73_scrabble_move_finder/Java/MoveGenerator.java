import java.util.*;
final class MoveGenerator {
    static final String LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    static boolean[][] anchors(char[][] board) {
        boolean[][] result = new boolean[15][15];
        if (Board.tiles(board).isEmpty()) {
            result[7][7] = true;
            return result;
        }
        for (int r = 0; r < 15; r++)
            for (int c = 0; c < 15; c++)
                if (board[r][c] == '.')
                    for (Board.Cell neighbor : Board.neighbors(r, c))
                        if (board[neighbor.row()][neighbor.column()] != '.')
                            result[r][c] = true;
        return result;
    }
    static int[][] checks(char[][] board, DictionaryTrie trie) {
        int[][] result = new int[15][15];
        for (int[] row : result)
            Arrays.fill(row, -1);
        for (int r = 0; r < 15; r++)
            for (int c = 0; c < 15; c++)
                if (board[r][c] == '.') {
                    int first = r, last = r;
                    while (first > 0 && board[first - 1][c] != '.')
                        first--;
                    while (last + 1 < 15 && board[last + 1][c] != '.')
                        last++;
                    if (first == last)
                        continue;
                    StringBuilder prefix = new StringBuilder(), suffix = new StringBuilder();
                    for (int i = first; i < r; i++)
                        prefix.append(Character.toUpperCase(board[i][c]));
                    for (int i = r + 1; i <= last; i++)
                        suffix.append(Character.toUpperCase(board[i][c]));
                    int mask = 0;
                    for (int i = 0; i < 26; i++)
                        if (trie.contains(prefix.toString() + (char)('A' + i) + suffix))
                            mask |= 1 << i;
                    result[r][c] = mask;
                }
        return result;
    }
    static final class Search {
        char[][] board;
        DictionaryTrie trie;
        boolean[][] anchors;
        int[][] checks;
        int[] counts = new int[128];
        List<Board.Move> result = new ArrayList<>();
        int row, anchor;
        Search(char[][] board, String rack, DictionaryTrie trie, boolean[][] anchors,
               int[][] checks) {
            this.board = board;
            this.trie = trie;
            this.anchors = anchors;
            this.checks = checks;
            for (char c : rack.toCharArray())
                counts[c]++;
        }
        void extend(DictionaryTrie.Node node, int column, String word, int start) {
            boolean empty = column == 15 || board[row][column] == '.';
            if (empty && column > anchor && node.terminal)
                result.add(new Board.Move(row, start, 0, word));
            if (column == 15)
                return;
            if (!empty) {
                char letter = board[row][column];
                DictionaryTrie.Node child = node.children[Character.toUpperCase(letter) - 'A'];
                if (child != null)
                    extend(child, column + 1, word + letter, start);
                return;
            }
            for (int i = 0; i < 26; i++)
                if (node.children[i] != null &&
                    (checks[row][column] == -1 || (checks[row][column] & (1 << i)) != 0)) {
                    char letter = (char)('A' + i);
                    for (int blank = 0; blank < 2; blank++) {
                        char tile = blank == 0 ? letter : '?',
                             written = blank == 0 ? letter : Character.toLowerCase(letter);
                        if (counts[tile] > 0) {
                            counts[tile]--;
                            extend(node.children[i], column + 1, word + written, start);
                            counts[tile]++;
                        }
                    }
                }
        }
        void left(DictionaryTrie.Node node, String prefix, int remaining) {
            extend(node, anchor, prefix, anchor - prefix.length());
            if (remaining == 0)
                return;
            for (int i = 0; i < 26; i++)
                if (node.children[i] != null) {
                    char letter = (char)('A' + i);
                    for (int blank = 0; blank < 2; blank++) {
                        char tile = blank == 0 ? letter : '?',
                             written = blank == 0 ? letter : Character.toLowerCase(letter);
                        if (counts[tile] > 0) {
                            counts[tile]--;
                            left(node.children[i], prefix + written, remaining - 1);
                            counts[tile]++;
                        }
                    }
                }
        }
        List<Board.Move> generate() {
            for (row = 0; row < 15; row++)
                for (anchor = 0; anchor < 15; anchor++)
                    if (anchors[row][anchor]) {
                        if (anchor > 0 && board[row][anchor - 1] != '.') {
                            int first = anchor - 1;
                            while (first > 0 && board[row][first - 1] != '.')
                                first--;
                            String prefix = new String(board[row], first, anchor - first);
                            DictionaryTrie.Node node = trie.prefix(prefix.toUpperCase(Locale.ROOT));
                            if (node != null)
                                extend(node, anchor, prefix, first);
                        } else {
                            int first = anchor - 1;
                            while (first >= 0 && board[row][first] == '.' && !anchors[row][first])
                                first--;
                            left(trie.root, "", anchor - first - 1);
                        }
                    }
            return result;
        }
    }
    static List<Board.Move> generate(char[][] board, String rack, DictionaryTrie trie) {
        boolean[][] anchors = anchors(board);
        List<Board.Move> across =
            new Search(board, rack, trie, anchors, checks(board, trie)).generate();
        char[][] transposed = Board.transpose(board);
        boolean[][] downAnchors = new boolean[15][15];
        for (int r = 0; r < 15; r++)
            for (int c = 0; c < 15; c++)
                downAnchors[r][c] = anchors[c][r];
        List<Board.Move> down =
            new Search(transposed, rack, trie, downAnchors, checks(transposed, trie)).generate();
        for (Board.Move move : down)
            across.add(new Board.Move(move.column(), move.row(), 1, move.word()));
        Map<List<Board.Tile>, Board.Move> distinct = new LinkedHashMap<>();
        for (Board.Move move : across) {
            List<Board.Tile> tiles = Scoring.placement(board, move);
            if (tiles.size() == 1 && move.direction() == 1) {
                Board.Tile tile = tiles.getFirst();
                if (Board.run(Scoring.apply(board, tiles), tile.row(), tile.column(), 0)
                        .word()
                        .length() >= 2)
                    continue;
            }
            tiles.sort(
                Comparator.comparingInt(Board.Tile::row).thenComparingInt(Board.Tile::column));
            distinct.put(List.copyOf(tiles), move);
        }
        return new ArrayList<>(distinct.values());
    }
}
