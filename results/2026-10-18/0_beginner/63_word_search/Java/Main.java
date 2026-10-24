public class Main {
    public static void main(String[] args) {
        String[] board = {"MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN",
            "KUVNGSBPRO", "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR"};
        String[] directions = {"E", "SE", "S", "SW", "W", "NW", "N", "NE"};
        int[] dr = {0,1,1,1,0,-1,-1,-1}, dc = {1,1,0,-1,-1,-1,0,1};
        for (String word : new String[]{"TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"}) {
            String result = "not found";
            search: for (int r = 0; r < 10; r++) {
                for (int c = 0; c < 10; c++) {
                    for (int d = 0; d < 8; d++) {
                        boolean match = true;
                        for (int k = 0; k < word.length(); k++) {
                            int nr = r + k * dr[d], nc = c + k * dc[d];
                            if (nr < 0 || nr >= 10 || nc < 0 || nc >= 10 || board[nr].charAt(nc) != word.charAt(k)) {
                                match = false;
                                break;
                            }
                        }
                        if (match) {
                            result = "(" + r + ", " + c + ") " + directions[d];
                            break search;
                        }
                    }
                }
            }
            System.out.println(word + ": " + result);
        }
    }
}
