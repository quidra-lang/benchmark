import java.nio.file.*;
import java.util.*;

final class Network {
    static final class Generator {
        long state;
        int draws;
        Generator(int seed) {
            state = seed;
        }
        int draw() {
            state = 48271 * state % 2147483647;
            draws++;
            return (int)state;
        }
    }
    static final class Channel {
        int source, destination, a, b, sequence, lastArrival, messages, markers, buffered, maxDelay, entries;
        boolean fifo;
        int[] previous;
        String delay() {
            return a == b ? Integer.toString(a) : a + "-" + b;
        }
        void dispatch(Main.Packet packet, int time, Generator generator) {
            packet.source = source;
            packet.destination = destination;
            packet.sequence = ++sequence;
            packet.dispatch = time;
            int delay = a == b ? a : a + generator.draw() % (b - a + 1);
            int arrival = time + delay;
            if (fifo)
                arrival = Math.max(arrival, lastArrival);
            lastArrival = Math.max(lastArrival, arrival);
            packet.arrival = arrival;
            maxDelay = Math.max(maxDelay, arrival - time);
            if (packet.message == null)
                markers++;
            else {
                messages++;
                int[] vector = packet.message.send.vector;
                for (int i = 0; i < previous.length; i++)
                    if (previous[i] != vector[i])
                        entries++;
                previous = vector.clone();
            }
        }
    }
    List<String> names;
    Channel[][] channels;
    Network() throws Exception {
        List<String> lines = Files.readAllLines(Path.of("input/topology.txt"));
        String[] header = lines.get(0).split(" ");
        names = new ArrayList<>(Arrays.asList(header).subList(1, header.length));
        int n = names.size();
        channels = new Channel[n][n];
        for (String line : lines.subList(1, lines.size())) {
            String[] w = line.split(" ");
            Channel c = new Channel();
            c.source = names.indexOf(w[1]);
            c.destination = names.indexOf(w[2]);
            c.fifo = w[3].equals("FIFO");
            c.a = Integer.parseInt(w[4]);
            c.b = w.length == 6 ? Integer.parseInt(w[5]) : c.a;
            c.previous = new int[n];
            channels[c.source][c.destination] = c;
        }
    }
}
