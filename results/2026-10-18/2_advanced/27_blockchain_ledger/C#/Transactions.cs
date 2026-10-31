using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Reference(string txid, int index) : IComparable<Reference> {
    public int CompareTo(Reference other) {
        int order = string.CompareOrdinal(txid, other.txid);
        return order != 0 ? order : index.CompareTo(other.index);
    }
    public override string ToString() {
        return txid + ":" + index;
    }
}
sealed record Payment(string address, int amount) {
    public override string ToString() {
        return address + ":" + amount;
    }
}
sealed record Coin(string address, int amount, int height, bool coinbase) {
    public bool Mature(int at, int maturity) {
        return !coinbase || height == 0 || at >= height + maturity;
    }
}
sealed record Check(string reason, int fee);

sealed class Transaction {
    public readonly string text, txid, body;
    public readonly List<Reference> inputs;
    public readonly List<Payment> outputs;
    public readonly List<string> signatures;
    public readonly int? coinbaseHeight;
    public Transaction(string text, List<Reference> inputs, List<Payment> outputs, List<string> signatures,
                       int? height) {
        this.text = text;
        this.txid = Hashing.Digest(text);
        this.inputs = inputs;
        this.outputs = outputs;
        this.signatures = signatures;
        coinbaseHeight = height;
        body = height == null ? text.Substring(0, text.IndexOf(";sig=")) : "";
    }
    public bool Coinbase() {
        return coinbaseHeight != null;
    }
    public int Size() {
        return text.Length;
    }
    public int Total() {
        int total = 0;
        foreach (Payment output in outputs)
            total += output.amount;
        return total;
    }
}

static class Transactions {
    public static Transaction Parse(string text) {
        string[] fields = text.Split(";");
        List<Payment> outputs = new();
        foreach (string item in fields[1].Substring(4).Split(",")) {
            string[] pair = item.Split(":");
            outputs.Add(new Payment(pair[0], int.Parse(pair[1])));
        }
        if (fields[0].StartsWith("cb="))
            return new Transaction(text, [], outputs, [], int.Parse(fields[0].Substring(3)));
        List<Reference> inputs = new();
        foreach (string item in fields[0].Substring(3).Split(",")) {
            string[] pair = item.Split(":");
            inputs.Add(new Reference(pair[0], int.Parse(pair[1])));
        }
        return new Transaction(text, inputs, outputs, fields[2].Substring(4).Split(",").ToList(), null);
    }
    public static string OutputsText(List<Payment> outputs) {
        return string.Join(",", outputs.Select(output => output.ToString()));
    }
    public static Transaction Create(List<Reference> inputs, List<Payment> outputs, string secret) {
        string body = "in=" + string.Join(",", inputs.Select(reference => reference.ToString())) +
                      ";out=" + OutputsText(outputs);
        List<string> signatures = new();
        for (int i = 0; i < inputs.Count; i++)
            signatures.Add(Wallets.Sign(secret, i, body));
        return new Transaction(body + ";sig=" + string.Join(",", signatures), inputs.ToList(), outputs,
                               signatures, null);
    }
    public static Transaction Coinbase(int height, List<Payment> outputs) {
        return new Transaction("cb=" + height + ";out=" + OutputsText(outputs), [], outputs, [], height);
    }
    public static Check Check(Transaction transaction, Dictionary<Reference, Coin> utxo,
                              HashSet<Reference> spent, int height, Dictionary<string, Wallet> owners,
                              int maturity) {
        foreach (Payment output in transaction.outputs)
            if (!owners.ContainsKey(output.address) || output.amount == 0)
                return new Check("bad-output", 0);
        HashSet<Reference> seen = new();
        int total = 0;
        for (int i = 0; i < transaction.inputs.Count; i++) {
            Reference reference = transaction.inputs[i];
            if (spent.Contains(reference) || seen.Contains(reference))
                return new Check("double-spend", 0);
            utxo.TryGetValue(reference, out Coin coin);
            if (coin == null)
                return new Check("missing-input", 0);
            if (!coin.Mature(height, maturity))
                return new Check("immature", 0);
            if (!transaction.signatures[i].Equals(
                    Wallets.Sign(owners[coin.address].secret, i, transaction.body)))
                return new Check("bad-sig", 0);
            seen.Add(reference);
            total += coin.amount;
        }
        return total < transaction.Total() ? new Check("overspend", 0)
                                           : new Check(null, total - transaction.Total());
    }
    public static void Apply(Dictionary<Reference, Coin> utxo, Transaction transaction, int height) {
        foreach (Reference reference in transaction.inputs)
            utxo.Remove(reference);
        for (int i = 0; i < transaction.outputs.Count; i++) {
            Payment output = transaction.outputs[i];
            utxo[new Reference(transaction.txid, i)] =
                new Coin(output.address, output.amount, height, transaction.Coinbase());
        }
    }
}
