import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

record Wallet(String name, String secret, String address) {}

final class Wallets {
    static String address(String secret) {
        return Hashing.digest("addr:" + secret).substring(0, 16);
    }
    static String sign(String secret, int index, String body) {
        return Hashing.digest(secret + ":" + index + ":" + body).substring(0, 16);
    }
    static List<Wallet> read() throws IOException {
        List<Wallet> wallets = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input/wallets.txt"), StandardCharsets.US_ASCII)) {
            String[] fields = line.split(" ");
            wallets.add(new Wallet(fields[0], fields[1], address(fields[1])));
        }
        return wallets;
    }
}
