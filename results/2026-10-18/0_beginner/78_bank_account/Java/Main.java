import java.util.Map;
import java.util.TreeMap;

public class Main {
    public static void main(String[] args) {
        String[] transactions = {"deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000",
            "withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000",
            "withdraw Emma 300", "deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800"};
        Map<String, Integer> balances = new TreeMap<>(Map.of("Nina", 12000, "Leo", 3500, "Emma", 800));
        for (int i = 0; i < transactions.length; i++) {
            String[] parts = transactions[i].split(" ");
            String name = parts[1];
            int amount = Integer.parseInt(parts[parts.length - 1]);
            boolean success = parts[0].equals("deposit") || balances.get(name) >= amount;
            if (success) {
                if (parts[0].equals("deposit")) {
                    balances.put(name, balances.get(name) + amount);
                } else {
                    balances.put(name, balances.get(name) - amount);
                    if (parts[0].equals("transfer")) {
                        balances.put(parts[2], balances.get(parts[2]) + amount);
                    }
                }
            }
            System.out.println("op " + (i + 1) + ": " + transactions[i]
                    + (success ? " ok" : " failed (insufficient funds)"));
        }
        for (var entry : balances.entrySet()) {
            System.out.println(entry.getKey() + ": " + entry.getValue());
        }
    }
}
