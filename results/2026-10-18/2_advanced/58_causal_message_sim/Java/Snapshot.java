import java.util.*;

final class Snapshot {
    record LocalRecord(int time, String reason, int balance, int lamport, int[] vector,
                       List<Main.Packet> pending) {}
    record Ignored(int process, int time) {}
    static final class State {
        String name;
        int start, complete, finished;
        LocalRecord[] records;
        List<List<List<Main.Packet>>> channels = new ArrayList<>();
        int[][] sent, accepted;
        List<Ignored> ignored = new ArrayList<>();
        State(String name, int time, int size) {
            this.name = name;
            start = time;
            records = new LocalRecord[size];
            sent = new int[size][size];
            accepted = new int[size][size];
            for (int i = 0; i < size; i++) {
                Arrays.fill(sent[i], -1);
                Arrays.fill(accepted[i], -1);
                List<List<Main.Packet>> row = new ArrayList<>();
                for (int j = 0; j < size; j++)
                    row.add(new ArrayList<>());
                channels.add(row);
            }
        }
        void recordState(Processes.State p, int time, String reason) {
            records[p.index] = new LocalRecord(time, reason, p.balance, p.lamport, p.vector.clone(),
                                               new ArrayList<>(p.hold));
        }
        void accept(int source, int destination, int time) {
            accepted[source][destination] = time;
            finished++;
            if (finished == records.length * (records.length - 1))
                complete = time;
        }
        int[] cut() {
            int[] c = new int[records.length];
            for (int i = 0; i < c.length; i++)
                c[i] = records[i].vector()[i];
            return c;
        }
    }
    static final class Cut {
        List<Main.Packet> orphans = new ArrayList<>(), transit = new ArrayList<>();
        int balances, money;
    }
    static Cut inspect(int[] cut, Main.Simulation sim) {
        Cut result = new Cut();
        for (Main.Packet c : sim.copies) {
            boolean sent = c.message.send.local <= cut[c.source],
                    received = c.recv != null && c.recv.local <= cut[c.destination];
            if (received && !sent)
                result.orphans.add(c);
            if (sent && !received)
                result.transit.add(c);
        }
        for (int i = 0; i < cut.length; i++)
            result.balances += sim.processes.get(i).balanceAt(cut[i]);
        result.money = result.balances;
        for (Main.Packet c : result.transit)
            result.money += c.message.amount;
        return result;
    }
    static boolean match(List<Main.Packet> recorded, List<Main.Packet> transit) {
        if (recorded.size() != transit.size())
            return false;
        Map<Main.Packet, Integer> counts = new HashMap<>();
        for (Main.Packet c : recorded)
            counts.put(c, counts.getOrDefault(c, 0) + 1);
        for (Main.Packet c : transit) {
            int value = counts.getOrDefault(c, 0);
            if (value == 0)
                return false;
            counts.put(c, value - 1);
        }
        return true;
    }
}
