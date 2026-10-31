import java.util.*;
final class Channels {
    static final class Member {
        Clients.Client client;
        boolean op, voice;
        Member(Clients.Client client, boolean op) {
            this.client = client;
            this.op = op;
        }
        String status() { return op ? "@" : voice ? "+" : ""; }
        String display() { return status() + client.nickname; }
    }
    record Ban(String mask, String setter, int time) {}
    static final class Channel {
        String name, topic = "", topicSetter, key = "";
        int created, topicTime = -1, limit, peak, messages;
        List<Member> members = new ArrayList<>();
        List<Ban> bans = new ArrayList<>();
        Set<Character> flags = new HashSet<>(Set.of('n', 't'));
        Channel(String name, int time) {
            this.name = name;
            created = time;
        }
        Member member(Clients.Client client) {
            for (Member member : members)
                if (member.client == client)
                    return member;
            return null;
        }
        Member add(Clients.Client client, boolean op) {
            Member member = new Member(client, op);
            members.add(member);
            client.channels.add(this);
            peak = Math.max(peak, members.size());
            return member;
        }
        void remove(Clients.Client client) {
            members.remove(member(client));
            client.channels.remove(this);
        }
        String nameList(Clients.Client viewer) {
            boolean inside = member(viewer) != null;
            List<String> names = new ArrayList<>();
            for (Member member : members)
                if (inside || !member.client.invisible)
                    names.add(member.display());
            return String.join(" ", names);
        }
        boolean banned(Clients.Client client) {
            for (Ban ban : bans)
                if (Masks.matches(ban.mask(), client.prefix()))
                    return true;
            return false;
        }
        boolean canSpeak(Clients.Client client) {
            Member member = member(client);
            boolean privileged = member != null && (member.op || member.voice);
            return (member != null || !flags.contains('n')) &&
                (!flags.contains('m') || privileged) && (privileged || !banned(client));
        }
        String modeDisplay(boolean includeKey) {
            StringBuilder mode = new StringBuilder("+");
            for (char c : "iklmnt".toCharArray())
                if (c == 'k' ? !key.isEmpty() : c == 'l' ? limit != 0 : flags.contains(c))
                    mode.append(c);
            if (includeKey && !key.isEmpty())
                mode.append(" ").append(key);
            if (limit != 0)
                mode.append(" ").append(limit);
            return mode.toString();
        }
    }
}
