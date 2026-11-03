using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public sealed class Interlocking {
    public record Requirement(string point, string position);
    public record PointLock(string route, string position);
    public static List<string> Names(string text) => text == "-" ? new() : text.Split(',').ToList();
    public static List<Requirement>
    ParseRequirements(string text) => Names(text)
                                          .Select(item => {
                                              string[] f = item.Split(':');
                                              return new Requirement(f[0], f[1]);
                                          })
                                          .ToList();
    public sealed class Route {
        public string name, start, finish, direction, state;
        public List<Requirement> points, flank, requirements;
        public List<string> sections, overlap, conflicts;
        public int approachTime, overlapCounter, requests, grants, uses, cancels, wait, maxwait,
            lockedSeconds;
        public int? releaseTime;
        public HashSet<string> passed = new();
        public bool overlapLocked;
        public Route(string[] f, Layout layout) {
            name = f[1];
            start = f[2];
            finish = f[3];
            points = ParseRequirements(f[4]);
            sections = Names(f[5]);
            overlap = Names(f[6]);
            flank = ParseRequirements(f[7]);
            conflicts = Names(f[8]);
            approachTime = int.Parse(f[9]);
            direction = layout.signals[start].direction;
            requirements = points.Concat(flank).ToList();
        }
    }
    public Layout layout;
    public Dictionary<string, Route> routes = new();
    public Interlocking(Layout layout) {
        this.layout = layout;
        foreach (string line in File.ReadAllLines("input/routes.txt", Encoding.ASCII)) {
            Route route = new(line.Split(' '), layout);
            routes[route.name] = route;
        }
    }
    public void Lock(Route route) {
        route.state = "LOCKED";
        route.releaseTime = null;
        route.passed.Clear();
        route.overlapLocked = true;
        route.overlapCounter = 0;
        foreach (string name in route.sections)
            layout.sections[name].routeLock = route.name;
        foreach (string name in route.overlap)
            layout.sections[name].overlapLocks.Add(route.name);
        foreach (Requirement requirement in route.requirements)
            layout.points[requirement.point].locks.Add(new(route.name, requirement.position));
    }
    public void UnlockPoints(Route route, HashSet<string> sections) {
        foreach (Layout.Point point in layout.points.Values)
            if (sections == null || sections.Contains(point.common))
                point.locks.RemoveWhere(pointLock => pointLock.route == route.name);
    }
    public void UnlockSection(Route route, string name) {
        Layout.Section section = layout.sections[name];
        if (section.routeLock == route.name)
            section.routeLock = null;
        UnlockPoints(route, new() { name });
    }
    public void UnlockOverlap(Route route) {
        foreach (string name in route.overlap)
            layout.sections[name].overlapLocks.Remove(route.name);
        UnlockPoints(route, new(route.overlap));
        route.overlapLocked = false;
    }
    public void Release(Route route) {
        foreach (string name in route.sections)
            if (layout.sections[name].routeLock == route.name)
                layout.sections[name].routeLock = null;
        if (route.overlapLocked)
            UnlockOverlap(route);
        UnlockPoints(route, null);
        route.state = null;
        route.releaseTime = null;
    }
}
