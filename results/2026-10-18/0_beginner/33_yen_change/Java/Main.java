import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        int[] denominations = {10000,5000,1000,500,100,50,10,5,1};
        for (int amount : new int[]{3780,15420,99999,506,48263}) {
            int remaining = amount, total = 0; List<String> parts = new ArrayList<>();
            for (int face : denominations) {
                int count = remaining / face; remaining %= face; total += count;
                if (count > 0) parts.add(face + "x" + count);
            }
            System.out.println(amount + " yen: " + String.join(" ", parts) + " (" + total + " pieces)");
        }
    }
}
