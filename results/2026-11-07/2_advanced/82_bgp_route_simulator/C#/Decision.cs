using System;
using System.Collections.Generic;
using System.Linq;
public static class Decision {
    public sealed class Attribute : IEquatable<Attribute> {
        public List<int> path;
        public string origin;
        public int med;
        public List<Policy.Community> communities;
        public Attribute(List<int> path, string origin, int med,
                         List<Policy.Community> communities) {
            this.path = new(path);
            this.origin = origin;
            this.med = med;
            this.communities = new(communities);
        }
        public bool Equals(Attribute other) =>
            other != null && origin == other.origin && med == other.med
            && path.SequenceEqual(other.path) && communities.SequenceEqual(other.communities);
        public override bool Equals(object other) => other is Attribute attribute &&
                                                     Equals(attribute);
        public override int GetHashCode() {
            HashCode hash = new();
            hash.Add(origin);
            hash.Add(med);
            foreach (int owner in path)
                hash.Add(owner);
            foreach (Policy.Community community in communities)
                hash.Add(community);
            return hash.ToHashCode();
        }
    }
    public sealed class Route : IEquatable<Route> {
        public List<int> path;
        public string origin;
        public int med;
        public List<Policy.Community> communities;
        public int? localPref;
        public Topology.Link link;
        public Route(List<int> path, string origin, int med, List<Policy.Community> communities,
                     int? localPref, Topology.Link link) {
            this.path = new(path);
            this.origin = origin;
            this.med = med;
            this.communities = new(communities);
            this.localPref = localPref;
            this.link = link;
        }
        public bool Local() => link == null;
        public int Neighbor() => path[0];
        public static Route Originated(string origin, List<Policy.Community> communities) =>
            new(new(), origin, 0, communities, null, null);
        public bool Equals(Route other) =>
            other != null && origin == other.origin && med == other.med
            && localPref == other.localPref &&
            ReferenceEquals(link, other.link) && path.SequenceEqual(other.path) &&
            communities.SequenceEqual(other.communities);
        public override bool Equals(object other) => other is Route route && Equals(route);
        public override int GetHashCode() {
            HashCode hash = new();
            hash.Add(origin);
            hash.Add(med);
            hash.Add(localPref);
            hash.Add(link);
            foreach (int owner in path)
                hash.Add(owner);
            foreach (Policy.Community community in communities)
                hash.Add(community);
            return hash.ToHashCode();
        }
    }
    public record Selection(Route route, string reason);
    public static Selection Best(List<Route> candidates, SortedDictionary<int, long> routerIds) {
        List<Route> remaining = new(candidates);
        if (remaining.Count == 1)
            return new(remaining[0], "ONLY");
        foreach (string reason in new[] { "LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID",
                                          "LINK" }) {
            if (reason == "MED") {
                Dictionary<int, int> minimum =
                    remaining.GroupBy(route => route.Neighbor())
                        .ToDictionary(group => group.Key, group => group.Min(route => route.med));
                remaining.RemoveAll(route => route.med != minimum[route.Neighbor()]);
            } else {
                Func<Route, long> key =
                    reason switch { "LOCALPREF" => route => -(long)route.localPref.Value,
                                    "ASPATH" => route => route.path.Count,
                                    "ORIGIN" => route => route.origin == "IGP"   ? 0
                                                         : route.origin == "EGP" ? 1
                                                                                 : 2,
                                    "ROUTERID" => route => routerIds[route.Neighbor()],
                                    _ => route => route.link.number };
                long minimum = remaining.Min(key);
                remaining.RemoveAll(route => key(route) != minimum);
            }
            if (remaining.Count == 1)
                return new(remaining[0], reason);
        }
        throw new InvalidOperationException();
    }
}
