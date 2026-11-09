import java.util.*;

final class Clocks {
    static void advance(Processes.State p, Main.Event sender) {
        if (sender == null)
            p.lamport++;
        else {
            p.lamport = Math.max(p.lamport, sender.lamport) + 1;
            for (int i = 0; i < p.vector.length; i++)
                p.vector[i] = Math.max(p.vector[i], sender.vector[i]);
        }
        p.vector[p.index]++;
    }
    static boolean lessEqual(int[] a, int[] b) {
        for (int i = 0; i < a.length; i++)
            if (a[i] > b[i])
                return false;
        return true;
    }
    static boolean before(int[] a, int[] b) {
        return !Arrays.equals(a, b) && lessEqual(a, b);
    }
    static String relation(int[] a, int[] b) {
        return before(a, b) ? "->" : before(b, a) ? "<-" : "||";
    }
    static boolean deliverable(Main.Packet c, Processes.State p) {
        int[] stamp = c.message.stamp;
        for (int i = 0; i < stamp.length; i++)
            if (i == c.source ? stamp[i] != p.broadcast[i] + 1 : stamp[i] > p.broadcast[i])
                return false;
        return true;
    }
    static int[] missing(Main.Packet c, Processes.State p) {
        List<Integer> list = new ArrayList<>();
        for (int i = 0; i < p.broadcast.length; i++)
            if (c.message.stamp[i] > p.broadcast[i] + (i == c.source ? 1 : 0))
                list.add(i);
        int[] values = new int[list.size()];
        for (int i = 0; i < values.length; i++)
            values[i] = list.get(i);
        return values;
    }
    static String vector(int[] values) {
        List<String> s = new ArrayList<>();
        for (int value : values)
            s.add(Integer.toString(value));
        return String.join(",", s);
    }
}
