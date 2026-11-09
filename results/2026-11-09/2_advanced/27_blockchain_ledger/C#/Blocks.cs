using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class Block {
    public readonly int height, timestamp, difficulty, nonce;
    public readonly string previous, merkle, hash;
    public readonly List<Transaction> transactions;
    public Block(int height, string previous, string merkle, int timestamp, int difficulty, int nonce,
                 List<Transaction> transactions) {
        this.height = height;
        this.previous = previous;
        this.merkle = merkle;
        this.timestamp = timestamp;
        this.difficulty = difficulty;
        this.nonce = nonce;
        this.transactions = transactions;
        hash = Hashing.Digest(Blocks.Header(height, previous, merkle, timestamp, difficulty, nonce));
    }
    public int Size() {
        int size = 0;
        foreach (Transaction transaction in transactions.GetRange(1, transactions.Count - (1)))
            size += transaction.Size();
        return size;
    }
    public List<string> Txids() {
        return transactions.Select(transaction => transaction.txid).ToList();
    }
}

static class Blocks {
    public static string Header(int height, string previous, string merkle, int timestamp, int difficulty,
                                int nonce) {
        return height + "|" + previous + "|" + merkle + "|" + timestamp + "|" + difficulty + "|" + nonce;
    }
    public static Block Parse(string[] fields, List<string> texts) {
        return new Block(int.Parse(fields[3]), fields[4], fields[5], int.Parse(fields[6]),
                         int.Parse(fields[7]), int.Parse(fields[8]),
                         texts.Select(Transactions.Parse).ToList());
    }
    public static Block Mine(int height, string previous, List<Transaction> transactions, int timestamp,
                             int difficulty) {
        string merkle = Hashing.Merkle(transactions.Select(transaction => transaction.txid).ToList());
        int nonce = 0;
        while (!Hashing.Digest(Header(height, previous, merkle, timestamp, difficulty, nonce))
                    .StartsWith(new string('0', difficulty)))
            nonce++;
        return new Block(height, previous, merkle, timestamp, difficulty, nonce, transactions);
    }
    public static string Error(Block block, int maximum) {
        if (!block.hash.StartsWith(new string('0', block.difficulty)))
            return "bad-pow";
        if (!Hashing.Merkle(block.Txids()).Equals(block.merkle))
            return "bad-merkle";
        Transaction first = block.transactions[0];
        if (!first.Coinbase() || first.coinbaseHeight != block.height)
            return "bad-structure";
        foreach (Transaction transaction in block.transactions.GetRange(1, block.transactions.Count - (1)))
            if (transaction.Coinbase())
                return "bad-structure";
        return block.Size() > maximum ? "too-large" : null;
    }
}
