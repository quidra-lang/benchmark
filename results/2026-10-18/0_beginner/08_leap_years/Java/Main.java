public class Main {
    public static void main(String[] args) {
        int[] years = {1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100};
        for (int year : years) {
            boolean leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
            System.out.println(year + ": " + (leap ? "leap year" : "common year"));
        }
    }
}
