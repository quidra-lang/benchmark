import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        for (long n : new long[]{0,7,999,1000,-456789,3141592,9876543210L}) System.out.printf(Locale.US, "%,d%n", n);
    }
}
