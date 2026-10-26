import java.util.ArrayList;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        int[] values = {3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77};
        for (int target : new int[]{42, 3, 77, 31, 50, 1}) {
            int lo = 0, hi = 15, found = -1;
            List<String> probes = new ArrayList<>();
            while (lo <= hi) {
                int mid = (lo + hi) / 2;
                probes.add(Integer.toString(mid));
                if (values[mid] == target) {
                    found = mid;
                    break;
                }
                if (values[mid] < target) {
                    lo = mid + 1;
                } else {
                    hi = mid - 1;
                }
            }
            System.out.println(target + ": probes " + String.join(" ", probes)
                    + " -> " + (found >= 0 ? "index " + found : "not found"));
        }
    }
}
