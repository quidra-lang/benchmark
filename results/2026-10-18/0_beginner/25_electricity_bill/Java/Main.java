public class Main {
    public static void main(String[] args) {
        String[] names = {"Sato","Suzuki","Takahashi","Tanaka","Ito","Watanabe"};
        int[] usages = {85,120,254,300,438,176};
        int total = 0;
        for (int i = 0; i < names.length; i++) {
            int u = usages[i], bill = 900 + Math.min(u, 120) * 30 + Math.min(Math.max(u - 120, 0), 180) * 36 + Math.max(u - 300, 0) * 40;
            total += bill;
            System.out.println(names[i] + ": " + u + " kWh, " + bill + " yen");
        }
        System.out.println("total: " + total + " yen");
    }
}
