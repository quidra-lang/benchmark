import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        for (int n : new int[]{0,10,255,1000,43981,65535})
            System.out.println(n + ": bin=" + Integer.toBinaryString(n) + " oct=" + Integer.toOctalString(n) + " hex=" + Integer.toHexString(n).toUpperCase(Locale.ROOT));
    }
}
