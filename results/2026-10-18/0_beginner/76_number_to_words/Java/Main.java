import java.util.*;
import java.math.*;

public class Main {
    static String underThousand(int n) {
        String[] ones = {"zero","one","two","three","four","five","six","seven","eight","nine",
            "ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen"};
        String[] tens = {"", "", "twenty","thirty","forty","fifty","sixty","seventy","eighty","ninety"};
        List<String> parts = new ArrayList<>();
        if (n >= 100) parts.add(ones[n / 100] + " hundred");
        int remainder = n % 100;
        if (remainder >= 20) parts.add(tens[remainder / 10] + (remainder % 10 > 0 ? "-" + ones[remainder % 10] : ""));
        else if (remainder > 0) parts.add(ones[remainder]);
        return String.join(" ",parts);
    }
    public static void main(String[] args) {
        for (int n : new int[]{0,13,40,100,568,71000,300019,999999}) {
            List<String> parts = new ArrayList<>();
            if (n == 0) parts.add("zero");
            if (n >= 1000) parts.add(underThousand(n / 1000) + " thousand");
            if (n % 1000 > 0) parts.add(underThousand(n % 1000));
            System.out.println(n + ": " + String.join(" ",parts));
        }
    }
}
