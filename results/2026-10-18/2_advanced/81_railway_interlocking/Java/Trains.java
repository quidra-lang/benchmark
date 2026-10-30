import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Trains {
    record PathPart(String section, int start) {}
    record Request(int time, String train, String route) {}
    record Plans(Map<String, Train> trains, List<Request> requests) {}
    static final class Stop {
        String kind, section;
        int dwell, scheduledArrival, scheduledDeparture;
        Integer arrival, departure;
        Stop(String[] f) {
            kind = f[0];
            section = f[2];
            dwell = Integer.parseInt(f[3]);
            scheduledArrival = Integer.parseInt(f[4]);
            scheduledDeparture = Integer.parseInt(f[5]);
        }
    }
    static final class Train {
        String name, entry, exit, state = "WAITING", direction, boundary;
        char symbol;
        int length, acceleration, deceleration, maxSpeed, entryTime, entrySpeed, scheduledExit,
            stopIndex, head, speed, boundaryCoordinate, distance, maximumSpeed, standing, passes;
        Integer entered, exited;
        boolean dwelling, emergency;
        Stop awaitingDeparture;
        List<Stop> stops = new ArrayList<>();
        List<PathPart> path = new ArrayList<>();
        Train(String[] f, char symbol) {
            name = f[1];
            this.symbol = symbol;
            length = Integer.parseInt(f[2]);
            acceleration = Integer.parseInt(f[3]);
            deceleration = Integer.parseInt(f[4]);
            maxSpeed = Integer.parseInt(f[5]);
            entry = f[6];
            entryTime = Integer.parseInt(f[7]);
            entrySpeed = Integer.parseInt(f[8]);
        }
        Stop nextStop() { return stopIndex < stops.size() ? stops.get(stopIndex) : null; }
    }
    static Plans readTrains() throws Exception {
        Map<String, Train> trains = new LinkedHashMap<>();
        List<Request> requests = new ArrayList<>();
        for (String line :
             Files.readAllLines(Path.of("input/trains.txt"), StandardCharsets.US_ASCII)) {
            String[] f = line.split(" ");
            switch (f[0]) {
            case "TRAIN": {
                Train train = new Train(f, (char)('a' + trains.size()));
                trains.put(train.name, train);
                break;
            }
            case "REQUEST":
                requests.add(new Request(Integer.parseInt(f[3]), f[1], f[2]));
                break;
            case "STOP":
            case "TURN":
                trains.get(f[1]).stops.add(new Stop(f));
                break;
            case "EXIT":
                trains.get(f[1]).exit = f[2];
                trains.get(f[1]).scheduledExit = Integer.parseInt(f[3]);
                break;
            }
        }
        return new Plans(trains, requests);
    }
    static int brakingDistance(int speed, int deceleration) {
        int count = speed / deceleration;
        return count * speed - deceleration * count * (count + 1) / 2;
    }
    static int selectSpeed(Train train, Integer distance) {
        int low = Math.max(train.speed - train.deceleration, 0);
        if (!train.emergency)
            for (int speed = Math.min(train.speed + train.acceleration, train.maxSpeed);
                 speed >= low; speed--)
                if (distance == null ||
                    speed + brakingDistance(speed, train.deceleration) <= distance)
                    return speed;
        return low;
    }
}
