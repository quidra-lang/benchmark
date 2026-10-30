import java.util.*;
final class Clients {
    static final class Client {
        final String identifier, hostname;
        final int connectionTime;
        String nickname, username, realname = "", away = "";
        boolean invisible, registered, active = true;
        int registrationTime = -1, lastReceived, lastSpeaking = -1, pingSent = -1, tokens,
            refillTime = -1, received, sent;
        Deque<String> queue = new ArrayDeque<>();
        List<Channels.Channel> channels = new ArrayList<>(), invites = new ArrayList<>();
        Client(String identifier, String hostname, int time, int capacity) {
            this.identifier = identifier;
            this.hostname = hostname;
            connectionTime = lastReceived = time;
            tokens = capacity;
        }
        String addressee() { return nickname == null ? "*" : nickname; }
        String prefix() { return nickname + "!" + username + "@" + hostname; }
        String mode() { return invisible ? "+i" : "+"; }
        void useToken(int time, int capacity, int interval) {
            if (tokens == capacity)
                refillTime = time + interval;
            tokens--;
        }
        void refill(int time, int capacity, int interval) {
            if (refillTime == time) {
                tokens++;
                refillTime = tokens < capacity ? time + interval : -1;
            }
        }
    }
}
