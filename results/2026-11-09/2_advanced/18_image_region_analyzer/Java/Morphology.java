import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class Morphology {
    static final List<Pixel> NEIGHBORS = List.of(new Pixel(0, -1), new Pixel(1, -1), new Pixel(1, 0), new Pixel(1, 1), new Pixel(0, 1), new Pixel(-1, 1), new Pixel(-1, 0), new Pixel(-1, -1));
    static boolean occupied(boolean[][] mask, int x, int y) { return y >= 0 && y < mask.length && x >= 0 && x < mask[0].length && mask[y][x]; }
    static boolean[][] erode(boolean[][] mask, List<Pixel> offsets) {
        boolean[][] result = new boolean[mask.length][mask[0].length];
        for (int y = 0; y < mask.length; y++) for (int x = 0; x < mask[0].length; x++) {
            boolean all = true;
            for (Pixel offset : offsets) if (!occupied(mask, x + offset.x(), y + offset.y())) { all = false; break; }
            result[y][x] = all;
        }
        return result;
    }
    static boolean[][] dilate(boolean[][] mask, List<Pixel> offsets) {
        boolean[][] result = new boolean[mask.length][mask[0].length];
        for (int y = 0; y < mask.length; y++) for (int x = 0; x < mask[0].length; x++) {
            for (Pixel offset : offsets) if (occupied(mask, x - offset.x(), y - offset.y())) { result[y][x] = true; break; }
        }
        return result;
    }
    static boolean[][] opening(boolean[][] mask, List<Pixel> offsets) { return dilate(erode(mask, offsets), offsets); }
    static boolean[][] closing(boolean[][] mask, List<Pixel> offsets) { return erode(dilate(mask, offsets), offsets); }
    static boolean[] bits(Set<Pixel> pixels, Pixel point) {
        boolean[] bits = new boolean[8];
        for (int i = 0; i < 8; i++) { Pixel offset = NEIGHBORS.get(i); bits[i] = pixels.contains(new Pixel(point.x() + offset.x(), point.y() + offset.y())); }
        return bits;
    }
    static int transitions(boolean[] bits) {
        int count = 0;
        for (int i = 0; i < 8; i++) if (!bits[i] && bits[(i + 1) % 8]) count++;
        return count;
    }
    static int crossing(Set<Pixel> pixels, Pixel point) { return transitions(bits(pixels, point)); }
    static boolean removable(boolean[] bits, boolean first) {
        int count = 0; for (boolean bit : bits) if (bit) count++;
        if (count < 2 || count > 6 || transitions(bits) != 1) return false;
        boolean p2 = bits[0], p4 = bits[2], p6 = bits[4], p8 = bits[6];
        return first ? !(p2 && p4 && p6) && !(p4 && p6 && p8) : !(p2 && p4 && p8) && !(p2 && p6 && p8);
    }
    static boolean thinningStep(Set<Pixel> skeleton, boolean first) {
        List<Pixel> removed = new ArrayList<>();
        for (Pixel point : skeleton) if (removable(bits(skeleton, point), first)) removed.add(point);
        skeleton.removeAll(removed);
        return !removed.isEmpty();
    }
    static Set<Pixel> thin(List<Pixel> pixels) {
        Set<Pixel> skeleton = new HashSet<>(pixels);
        while (true) {
            boolean first = thinningStep(skeleton, true), second = thinningStep(skeleton, false);
            if (!first && !second) return skeleton;
        }
    }
}
