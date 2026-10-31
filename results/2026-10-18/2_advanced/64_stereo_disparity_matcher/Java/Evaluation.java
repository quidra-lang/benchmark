import java.util.*;
final class Evaluation {
    static final String[] REGIONS = {"nonocc", "all", "disc"};
    record Regions(List<Integer> nonocc, List<Integer> all, List<Integer> disc,
                   List<Integer> occluded) {
        List<Integer> at(int i) { return i == 0 ? nonocc : i == 1 ? all : disc; }
    }
    record Metrics(int pixels, int valid, int bad1, int bad2, long error, int exact) {
        String mae() { return valid == 0 ? "-" : Refinement.two(error, valid); }
    }
    static Regions regions(int[] truth, int w, int h) {
        List<Integer> all = new ArrayList<>(), visible = new ArrayList<>(),
                      hidden = new ArrayList<>(), disc = new ArrayList<>();
        for (int p = 0; p < truth.length; p++)
            if (truth[p] != 0) {
                all.add(p);
                int x = p % w, y = p / w, g = truth[p], target = x - g;
                boolean occluded = target < 0;
                for (int x2 = 0; x2 < w && !occluded; x2++)
                    if (truth[y * w + x2] > g && x2 - truth[y * w + x2] == target)
                        occluded = true;
                if (occluded)
                    hidden.add(p);
                else
                    visible.add(p);
            }
        for (int p : visible) {
            int x = p % w, y = p / w;
            boolean edge = false;
            for (int yy = Math.max(0, y - 1); yy <= Math.min(h - 1, y + 1); yy++)
                for (int xx = Math.max(0, x - 1); xx <= Math.min(w - 1, x + 1); xx++) {
                    int q = yy * w + xx;
                    if (q != p && truth[q] != 0 && Math.abs(truth[q] - truth[p]) >= 2)
                        edge = true;
                }
            if (edge)
                disc.add(p);
        }
        return new Regions(visible, all, disc, hidden);
    }
    static Metrics evaluate(int[] image, int[] truth, List<Integer> region) {
        int valid = 0, bad1 = 0, bad2 = 0, exact = 0;
        long error = 0;
        for (int p : region)
            if (image[p] == 0) {
                bad1++;
                bad2++;
            } else {
                valid++;
                int e = Math.abs(image[p] - truth[p]);
                error += e;
                if (e > 1)
                    bad1++;
                if (e > 2)
                    bad2++;
                if (e == 0)
                    exact++;
            }
        return new Metrics(region.size(), valid, bad1, bad2, error, exact);
    }
    static long gcd(long a, long b) {
        while (b != 0) {
            long t = a % b;
            a = b;
            b = t;
        }
        return a;
    }
    static String ratio(long a, long b) {
        if (b == 0)
            return "0/1 0.00";
        long divisor = gcd(a, b);
        return a / divisor + "/" + b / divisor + " " + Refinement.two(100 * a, b);
    }
}
