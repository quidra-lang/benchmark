import java.util.*;

record Reference(String txid, int index) implements Comparable<Reference> {
    public int compareTo(Reference other) {
        int order = txid.compareTo(other.txid);
        return order != 0 ? order : Integer.compare(index, other.index);
    }
    public String toString() {
        return txid + ":" + index;
    }
}
record Payment(String address, int amount) {
    public String toString() {
        return address + ":" + amount;
    }
}
record Coin(String address, int amount, int height, boolean coinbase) {
    boolean mature(int at, int maturity) {
        return !coinbase || height == 0 || at >= height + maturity;
    }
}
record Check(String reason, int fee) {}

final class Transaction {
    final String text, txid, body;
    final List<Reference> inputs;
    final List<Payment> outputs;
    final List<String> signatures;
    final Integer coinbaseHeight;
    Transaction(String text, List<Reference> inputs, List<Payment> outputs, List<String> signatures,
                Integer height) {
        this.text = text;
        this.txid = Hashing.digest(text);
        this.inputs = inputs;
        this.outputs = outputs;
        this.signatures = signatures;
        coinbaseHeight = height;
        body = height == null ? text.substring(0, text.indexOf(";sig=")) : "";
    }
    boolean coinbase() {
        return coinbaseHeight != null;
    }
    int size() {
        return text.length();
    }
    int total() {
        int total = 0;
        for (Payment output : outputs)
            total += output.amount();
        return total;
    }
}

final class Transactions {
    static Transaction parse(String text) {
        String[] fields = text.split(";");
        List<Payment> outputs = new ArrayList<>();
        for (String item : fields[1].substring(4).split(",")) {
            String[] pair = item.split(":");
            outputs.add(new Payment(pair[0], Integer.parseInt(pair[1])));
        }
        if (fields[0].startsWith("cb="))
            return new Transaction(text, List.of(), outputs, List.of(),
                                   Integer.parseInt(fields[0].substring(3)));
        List<Reference> inputs = new ArrayList<>();
        for (String item : fields[0].substring(3).split(",")) {
            String[] pair = item.split(":");
            inputs.add(new Reference(pair[0], Integer.parseInt(pair[1])));
        }
        return new Transaction(text, inputs, outputs, List.of(fields[2].substring(4).split(",")), null);
    }
    static String outputsText(List<Payment> outputs) {
        return String.join(",", outputs.stream().map(Payment::toString).toList());
    }
    static Transaction create(List<Reference> inputs, List<Payment> outputs, String secret) {
        String body = "in=" + String.join(",", inputs.stream().map(Reference::toString).toList()) +
                      ";out=" + outputsText(outputs);
        List<String> signatures = new ArrayList<>();
        for (int i = 0; i < inputs.size(); i++)
            signatures.add(Wallets.sign(secret, i, body));
        return new Transaction(body + ";sig=" + String.join(",", signatures), new ArrayList<>(inputs),
                               outputs, signatures, null);
    }
    static Transaction coinbase(int height, List<Payment> outputs) {
        return new Transaction("cb=" + height + ";out=" + outputsText(outputs), List.of(), outputs, List.of(),
                               height);
    }
    static Check check(Transaction transaction, Map<Reference, Coin> utxo, Set<Reference> spent, int height,
                       Map<String, Wallet> owners, int maturity) {
        for (Payment output : transaction.outputs)
            if (!owners.containsKey(output.address()) || output.amount() == 0)
                return new Check("bad-output", 0);
        Set<Reference> seen = new HashSet<>();
        int total = 0;
        for (int i = 0; i < transaction.inputs.size(); i++) {
            Reference reference = transaction.inputs.get(i);
            if (spent.contains(reference) || seen.contains(reference))
                return new Check("double-spend", 0);
            Coin coin = utxo.get(reference);
            if (coin == null)
                return new Check("missing-input", 0);
            if (!coin.mature(height, maturity))
                return new Check("immature", 0);
            if (!transaction.signatures.get(i).equals(
                    Wallets.sign(owners.get(coin.address()).secret(), i, transaction.body)))
                return new Check("bad-sig", 0);
            seen.add(reference);
            total += coin.amount();
        }
        return total < transaction.total() ? new Check("overspend", 0)
                                           : new Check(null, total - transaction.total());
    }
    static void apply(Map<Reference, Coin> utxo, Transaction transaction, int height) {
        for (Reference reference : transaction.inputs)
            utxo.remove(reference);
        for (int i = 0; i < transaction.outputs.size(); i++) {
            Payment output = transaction.outputs.get(i);
            utxo.put(new Reference(transaction.txid, i),
                     new Coin(output.address(), output.amount(), height, transaction.coinbase()));
        }
    }
}
