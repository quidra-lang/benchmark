import java.util.*;

final class Block {
    final int height, timestamp, difficulty, nonce;
    final String previous, merkle, hash;
    final List<Transaction> transactions;
    Block(int height, String previous, String merkle, int timestamp, int difficulty, int nonce,
          List<Transaction> transactions) {
        this.height = height;
        this.previous = previous;
        this.merkle = merkle;
        this.timestamp = timestamp;
        this.difficulty = difficulty;
        this.nonce = nonce;
        this.transactions = transactions;
        hash = Hashing.digest(Blocks.header(height, previous, merkle, timestamp, difficulty, nonce));
    }
    int size() {
        int size = 0;
        for (Transaction transaction : transactions.subList(1, transactions.size()))
            size += transaction.size();
        return size;
    }
    List<String> txids() {
        return transactions.stream().map(transaction -> transaction.txid).toList();
    }
}

final class Blocks {
    static String header(int height, String previous, String merkle, int timestamp, int difficulty,
                         int nonce) {
        return height + "|" + previous + "|" + merkle + "|" + timestamp + "|" + difficulty + "|" + nonce;
    }
    static Block parse(String[] fields, List<String> texts) {
        return new Block(Integer.parseInt(fields[3]), fields[4], fields[5], Integer.parseInt(fields[6]),
                         Integer.parseInt(fields[7]), Integer.parseInt(fields[8]),
                         texts.stream().map(Transactions::parse).toList());
    }
    static Block mine(int height, String previous, List<Transaction> transactions, int timestamp,
                      int difficulty) {
        String merkle = Hashing.merkle(transactions.stream().map(transaction -> transaction.txid).toList());
        int nonce = 0;
        while (!Hashing.digest(header(height, previous, merkle, timestamp, difficulty, nonce))
                    .startsWith("0".repeat(difficulty)))
            nonce++;
        return new Block(height, previous, merkle, timestamp, difficulty, nonce, transactions);
    }
    static String error(Block block, int maximum) {
        if (!block.hash.startsWith("0".repeat(block.difficulty)))
            return "bad-pow";
        if (!Hashing.merkle(block.txids()).equals(block.merkle))
            return "bad-merkle";
        Transaction first = block.transactions.getFirst();
        if (!first.coinbase() || first.coinbaseHeight != block.height)
            return "bad-structure";
        for (Transaction transaction : block.transactions.subList(1, block.transactions.size()))
            if (transaction.coinbase())
                return "bad-structure";
        return block.size() > maximum ? "too-large" : null;
    }
}
