import java.util.*;
import java.math.*;

public class Main {
    static int mergeSort(int[] values, int l, int r) {
        if (l == r) return 0;
        int m = (l + r) / 2;
        int inversions = mergeSort(values,l,m);
        inversions += mergeSort(values,m + 1,r);
        int[] merged = new int[r - l + 1];
        int i = l, j = m + 1, k = 0;
        while (i <= m && j <= r) {
            if (values[i] < values[j]) merged[k++] = values[i++];
            else {
                merged[k++] = values[j++];
                inversions += m - i + 1;
            }
        }
        while (i <= m) merged[k++] = values[i++];
        while (j <= r) merged[k++] = values[j++];
        System.arraycopy(merged,0,values,l,merged.length);
        System.out.println("merge [" + l + ".." + r + "]: " +
            String.join(" ", Arrays.stream(merged).mapToObj(String::valueOf).toList()));
        return inversions;
    }
    public static void main(String[] args) {
        int[] values = {47,12,85,33,6,71,29,58,90,14};
        int inversions = mergeSort(values,0,values.length - 1);
        System.out.println("sorted: " + String.join(" ", Arrays.stream(values).mapToObj(String::valueOf).toList()));
        System.out.println("inversions: " + inversions);
    }
}
