import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class BidsIo {
    record Item(String name, long reserve) {}
    record Bid(int number, int bidder, int bundle, long amount, boolean xor) {
        int size() { return Integer.bitCount(bundle); }
    }
    record Participant(String name, long value, long bid) {}
    record BidderLine(String name, String language, List<String> bids) {}
    static final class RawAuction {
        String name;
        List<String> items;
        List<BidderLine> lines = new ArrayList<>();
        RawAuction(String name, List<String> items) {
            this.name = name;
            this.items = items;
        }
    }
    static final class Group {
        String kind, name;
        List<String> arguments;
        List<Participant> participants = new ArrayList<>();
        Group(String[] f) {
            kind = f[0];
            name = f[1];
            arguments = Arrays.asList(f).subList(2, f.length);
        }
    }
    List<Item> items = new ArrayList<>();
    Map<String, RawAuction> auctions = new LinkedHashMap<>();
    List<Group> groups = new ArrayList<>();
    List<String> runs;
    Map<String, Long> params = new HashMap<>();
    static List<String> lines(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    BidsIo() throws Exception {
        for (String line : lines("items.txt")) {
            String[] f = line.split(" ");
            items.add(new Item(f[0], Long.parseLong(f[1])));
        }
        RawAuction auction = null;
        for (String line : lines("bids.txt")) {
            String[] f = line.split(" ");
            if (f[0].equals("auction")) {
                auction = new RawAuction(f[1], List.copyOf(Arrays.asList(f).subList(2, f.length)));
                auctions.put(f[1], auction);
            } else
                auction.lines.add(
                    new BidderLine(f[1], f[2], List.copyOf(Arrays.asList(f).subList(3, f.length))));
        }
        Group group = null;
        for (String line : lines("single_item.txt")) {
            String[] f = line.split(" ");
            if (f[0].equals("lot") || f[0].equals("slots")) {
                group = new Group(f);
                groups.add(group);
            } else
                group.participants.add(
                    new Participant(f[1], Long.parseLong(f[2]), Long.parseLong(f[3])));
        }
        for (String line : lines("params.txt")) {
            String[] f = line.split(" ");
            if (f[0].equals("run"))
                runs = List.copyOf(Arrays.asList(f).subList(1, f.length));
            else
                params.put(f[0], Long.parseLong(f[1]));
        }
    }
}
