using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Wallet(string name, string secret, string address);

static class Wallets {
    public static string Address(string secret) {
        return Hashing.Digest("addr:" + secret).Substring(0, 16);
    }
    public static string Sign(string secret, int index, string body) {
        return Hashing.Digest(secret + ":" + index + ":" + body).Substring(0, 16);
    }
    public static List<Wallet> Read() {
        List<Wallet> wallets = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input/wallets.txt"), Encoding.ASCII)) {
            string[] fields = line.Split(" ");
            wallets.Add(new Wallet(fields[0], fields[1], Address(fields[1])));
        }
        return wallets;
    }
}
