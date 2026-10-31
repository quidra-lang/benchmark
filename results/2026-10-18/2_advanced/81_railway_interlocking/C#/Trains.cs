using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
public static class Trains {
    public record PathPart(string section, int start);
    public record Request(int time, string train, string route);
    public record Plans(Dictionary<string, Train> trains, List<Request> requests);
    public sealed class Stop {
        public string kind, section;
        public int dwell, scheduledArrival, scheduledDeparture;
        public int? arrival, departure;
        public Stop(string[] f) {
            kind = f[0];
            section = f[2];
            dwell = int.Parse(f[3]);
            scheduledArrival = int.Parse(f[4]);
            scheduledDeparture = int.Parse(f[5]);
        }
    }
    public sealed class Train {
        public string name, entry, exit, state = "WAITING", direction, boundary;
        public char symbol;
        public int length, acceleration, deceleration, maxSpeed, entryTime, entrySpeed,
            scheduledExit, stopIndex, head, speed, boundaryCoordinate, distance, maximumSpeed,
            standing, passes;
        public int? entered, exited;
        public bool dwelling, emergency;
        public Stop awaitingDeparture;
        public List<Stop> stops = new();
        public List<PathPart> path = new();
        public Train(string[] f, char symbol) {
            name = f[1];
            this.symbol = symbol;
            length = int.Parse(f[2]);
            acceleration = int.Parse(f[3]);
            deceleration = int.Parse(f[4]);
            maxSpeed = int.Parse(f[5]);
            entry = f[6];
            entryTime = int.Parse(f[7]);
            entrySpeed = int.Parse(f[8]);
        }
        public Stop NextStop() => stopIndex < stops.Count ? stops[stopIndex] : null;
    }
    public static Plans ReadTrains() {
        Dictionary<string, Train> trains = new();
        List<Request> requests = new();
        foreach (string line in File.ReadAllLines("input/trains.txt", Encoding.ASCII)) {
            string[] f = line.Split(' ');
            switch (f[0]) {
            case "TRAIN": {
                Train train = new(f, (char)('a' + trains.Count));
                trains[train.name] = train;
                break;
            }
            case "REQUEST":
                requests.Add(new(int.Parse(f[3]), f[1], f[2]));
                break;
            case "STOP":
            case "TURN":
                trains[f[1]].stops.Add(new(f));
                break;
            case "EXIT":
                trains[f[1]].exit = f[2];
                trains[f[1]].scheduledExit = int.Parse(f[3]);
                break;
            }
        }
        return new(trains, requests);
    }
    public static int BrakingDistance(int speed, int deceleration) {
        int count = speed / deceleration;
        return count * speed - deceleration * count * (count + 1) / 2;
    }
    public static int SelectSpeed(Train train, int? distance) {
        int low = Math.Max(train.speed - train.deceleration, 0);
        if (!train.emergency)
            for (int speed = Math.Min(train.speed + train.acceleration, train.maxSpeed);
                 speed >= low; speed--)
                if (distance == null ||
                    speed + BrakingDistance(speed, train.deceleration) <= distance.Value)
                    return speed;
        return low;
    }
}
