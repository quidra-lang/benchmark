import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Topology {
    record Prefix(long address, int length) implements Comparable<Prefix> {
        public int compareTo(Prefix other) {
            int c = Long.compare(address, other.address);
            return c != 0 ? c : Integer.compare(length, other.length);
        }
        public String toString() { return addressText(address) + "/" + length; }
        boolean contains(long value) {
            int shift = 32 - length;
            return address >> shift == value >> shift;
        }
    }
    static long addressValue(String text) {
        long value = 0;
        for (String octet : text.split("\\."))
            value = (value << 8) + Integer.parseInt(octet);
        return value;
    }
    static String addressText(long value) {
        return ((value >> 24) & 255) + "." + ((value >> 16) & 255) + "." + ((value >> 8) & 255) +
            "." + (value & 255);
    }
    static Prefix prefix(String text) {
        String[] f = text.split("/");
        return new Prefix(addressValue(f[0]), Integer.parseInt(f[1]));
    }
    static final class Link {
        int number, first, second, delay, mrai, downCount;
        String name, relationship;
        boolean up = true;
        Link(int number, String[] f) {
            this.number = number;
            name = f[1];
            first = Integer.parseInt(f[2]);
            second = Integer.parseInt(f[3]);
            relationship = f[4];
            delay = Integer.parseInt(f[5]);
            mrai = Integer.parseInt(f[6]);
        }
        int other(int owner) { return owner == first ? second : first; }
        String role(int owner) {
            return relationship.equals("P2P") ? "peer" : owner == first ? "customer" : "provider";
        }
        char direction(int owner) {
            return switch (role(owner)) {
                case "customer" -> 'D';
                case "peer" -> 'P';
                default -> 'U';
            };
        }
    }
    record Initial(int owner, Prefix prefix, String origin, List<Policy.Community> communities) {}
    Map<Integer, Long> routerIds = new TreeMap<>();
    List<Link> links = new ArrayList<>();
    Map<String, Link> byName = new HashMap<>();
    Map<Integer, List<Link>> atAs = new TreeMap<>();
    List<Initial> initial = new ArrayList<>();
    Topology() throws Exception {
        for (String line :
             Files.readAllLines(Path.of("input/topology.txt"), StandardCharsets.US_ASCII)) {
            String[] f = line.split(" ");
            if (f[0].equals("AS"))
                routerIds.put(Integer.parseInt(f[1]), addressValue(f[2]));
            else if (f[0].equals("LINK")) {
                Link link = new Link(links.size(), f);
                links.add(link);
                byName.put(link.name, link);
            } else
                initial.add(new Initial(Integer.parseInt(f[1]), prefix(f[2]), f[3],
                                        Policy.communities(Arrays.asList(f).subList(4, f.length))));
        }
        for (int owner : routerIds.keySet())
            atAs.put(owner, new ArrayList<>());
        for (Link link : links) {
            atAs.get(link.first).add(link);
            atAs.get(link.second).add(link);
        }
    }
    Link connecting(int first, int second) {
        for (Link link : atAs.get(first))
            if (link.other(first) == second)
                return link;
        throw new IllegalStateException();
    }
}
