public class Main {
    static void permute(String prefix, boolean[] used, int[] count) {
        if (prefix.length() == 4) {
            System.out.println(++count[0] + ": " + prefix);
            return;
        }
        for (int i = 0; i < 4; i++) {
            if (!used[i]) {
                used[i] = true;
                permute(prefix + "ABCD".charAt(i), used, count);
                used[i] = false;
            }
        }
    }

    public static void main(String[] args) {
        permute("", new boolean[4], new int[1]);
    }
}
