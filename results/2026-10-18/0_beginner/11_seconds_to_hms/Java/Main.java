import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        for (int seconds : new int[]{0, 59, 3725, 45296, 86400, 312047}) {
            System.out.printf(Locale.ROOT, "%d seconds = %02d:%02d:%02d%n",
                    seconds, seconds / 3600, seconds / 60 % 60, seconds % 60);
        }
    }
}
