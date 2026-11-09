import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Simulator {
    record Message(int serial, int sender, int receiver, Topology.Link link, Topology.Prefix prefix,
                   Decision.Attribute content, int arrival) {}
    static final Comparator<Message> ORDER = Comparator.comparingInt(Message::arrival)
                                                 .thenComparingInt(Message::receiver)
                                                 .thenComparingInt(Message::sender)
                                                 .thenComparingInt(Message::serial);
    static final class MessageQueue {
        PriorityQueue<Message> queue = new PriorityQueue<>(ORDER);
        int serial;
        Message send(int time, int sender, int receiver, Topology.Link link, Topology.Prefix prefix,
                     Decision.Attribute content) {
            Message message =
                new Message(++serial, sender, receiver, link, prefix, content, time + link.delay);
            queue.add(message);
            return message;
        }
        Integer nextTime() { return queue.isEmpty() ? null : queue.peek().arrival(); }
        Message take() { return queue.remove(); }
        List<Message> ordered() {
            List<Message> result = new ArrayList<>(queue);
            result.sort(ORDER);
            return result;
        }
        List<Message> removeLink(Topology.Link link) {
            List<Message> removed = new ArrayList<>();
            for (Message message : ordered())
                if (message.link() == link)
                    removed.add(message);
            queue.removeIf(message -> message.link() == link);
            return removed;
        }
    }
    record Event(int time, String text, String[] fields, String kind) {
        Event(int time, String text) { this(time, text, text.split(" "), kind(text)); }
        static String kind(String text) {
            String[] f = text.split(" ");
            return f[0].equals("LINK") || f[0].equals("POLICY") ? f[0] + "_" + f[1] : f[0];
        }
    }
    record Trace(int source, String address, long value) {}
    record Params(Map<String, Integer> defaults, int stepcap, List<Trace> traces) {}
    static List<Event> events() throws Exception {
        List<Event> events = new ArrayList<>();
        events.add(new Event(0, "INITIAL"));
        for (String line :
             Files.readAllLines(Path.of("input/events.txt"), StandardCharsets.US_ASCII)) {
            int separator = line.indexOf(' ');
            events.add(new Event(Integer.parseInt(line.substring(0, separator)),
                                 line.substring(separator + 1)));
        }
        return events;
    }
    static Params params() throws Exception {
        List<String> lines =
            Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII);
        String[] f = lines.get(0).split(" ");
        Map<String, Integer> defaults =
            Map.of("customer", Integer.parseInt(f[1]), "peer", Integer.parseInt(f[2]), "provider",
                   Integer.parseInt(f[3]));
        int stepcap = Integer.parseInt(lines.get(1).split(" ")[1]);
        List<Trace> traces = new ArrayList<>();
        for (String line : lines.subList(2, lines.size())) {
            String[] t = line.split(" ");
            traces.add(new Trace(Integer.parseInt(t[1]), t[2], Topology.addressValue(t[2])));
        }
        return new Params(defaults, stepcap, traces);
    }
}
