using System;
using System.Collections.Generic;
using System.Linq;

readonly record struct Position(int X, int Y);
readonly record struct RoomCell(int Room, int X, int Y);
sealed record Room(int X, int Y, int Width, int Height) {
    public Position Center() => new(X + Width / 2, Y + Height / 2);
}
sealed class Region {
    public readonly int X, Y, Width, Height;
    public Region First, Second;
    public int Leaf = -1;
    public Region(int x, int y, int width, int height) { X = x; Y = y; Width = width; Height = height; }
}
sealed class Level {
    public readonly int Depth, Width, Height;
    public readonly char[][] Terrain, Memory;
    public readonly List<Room> Rooms = new();
    public Position Arrival, Target;
    public int ArrivalRoom, MonstersCreated, ItemsPlaced, Kills, Picked;
    public readonly List<Monster> Monsters = new();
    public readonly List<Item> Items = new();
    public Level(int depth, int width, int height) {
        Depth = depth; Width = width; Height = height;
        Terrain = Enumerable.Range(0, height).Select(_ => Enumerable.Repeat(' ', width).ToArray()).ToArray();
        Memory = Enumerable.Range(0, height).Select(_ => Enumerable.Repeat(' ', width).ToArray()).ToArray();
    }
    public Monster MonsterAt(int x, int y) => Monsters.FirstOrDefault(monster => monster.X == x && monster.Y == y);
    public Item ItemAt(int x, int y) => Items.FirstOrDefault(item => item.X == x && item.Y == y);
    public Position DrawInterior(Minstd rng, int index) {
        Room room = Rooms[index];
        int x = room.X + 1 + rng.Rnd(room.Width - 2), y = room.Y + 1 + rng.Rnd(room.Height - 2);
        return new Position(x, y);
    }
    public RoomCell DrawRoom(Minstd rng) {
        int room = rng.Rnd(Rooms.Count);
        Position cell = DrawInterior(rng, room);
        return new RoomCell(room, cell.X, cell.Y);
    }
}
sealed class DungeonGen {
    readonly Minstd rng;
    readonly int minSize, maxSplit, roomMin, roomMax;
    public DungeonGen(Minstd rng, int minSize, int maxSplit, int roomMin, int roomMax) { this.rng = rng; this.minSize = minSize; this.maxSplit = maxSplit; this.roomMin = roomMin; this.roomMax = roomMax; }
    public Level Generate(int depth, int width, int height) {
        Level level = new(depth, width, height);
        Region root = new(0, 0, width, height);
        List<Region> leaves = new();
        Split(root, 0, leaves);
        foreach (Region leaf in leaves) level.Rooms.Add(MakeRoom(level, leaf));
        Connect(level, root); ChooseStairs(level);
        return level;
    }
    void Split(Region region, int depth, List<Region> leaves) {
        bool cv = region.Width >= 2 * minSize, ch = region.Height >= 2 * minSize;
        if (depth == maxSplit || !(cv || ch)) { region.Leaf = leaves.Count; leaves.Add(region); return; }
        bool vertical;
        if (cv && ch) {
            if (4 * region.Width >= 5 * region.Height) vertical = true;
            else if (4 * region.Height >= 5 * region.Width) vertical = false;
            else vertical = rng.Draw() % 2 == 0;
        } else vertical = cv;
        if (vertical) {
            int cut = minSize + rng.Rnd(region.Width - 2 * minSize + 1);
            region.First = new Region(region.X, region.Y, cut, region.Height); region.Second = new Region(region.X + cut, region.Y, region.Width - cut, region.Height);
        } else {
            int cut = minSize + rng.Rnd(region.Height - 2 * minSize + 1);
            region.First = new Region(region.X, region.Y, region.Width, cut); region.Second = new Region(region.X, region.Y + cut, region.Width, region.Height - cut);
        }
        Split(region.First, depth + 1, leaves); Split(region.Second, depth + 1, leaves);
    }
    Room MakeRoom(Level level, Region region) {
        int width = roomMin + rng.Rnd(Math.Min(roomMax, region.Width - 1) - roomMin + 1);
        int height = roomMin + rng.Rnd(Math.Min(roomMax, region.Height - 1) - roomMin + 1);
        int x = region.X + rng.Rnd(region.Width - width), y = region.Y + rng.Rnd(region.Height - height);
        for (int row = y; row < y + height; row++) for (int column = x; column < x + width; column++) level.Terrain[row][column] = row == y || row == y + height - 1 ? '-' : column == x || column == x + width - 1 ? '|' : '.';
        return new Room(x, y, width, height);
    }
    List<int> Connect(Level level, Region region) {
        if (region.Leaf >= 0) return [region.Leaf];
        List<int> first = Connect(level, region.First), second = Connect(level, region.Second);
        int bestA = -1, bestB = -1, bestDistance = 0;
        foreach (int a in first) foreach (int b in second) {
            Position start = level.Rooms[a].Center(), end = level.Rooms[b].Center();
            int distance = Math.Abs(start.X - end.X) + Math.Abs(start.Y - end.Y);
            if (bestA < 0 || distance < bestDistance) { bestA = a; bestB = b; bestDistance = distance; }
        }
        bool horizontalFirst = rng.Draw() % 2 == 0;
        Dig(level, level.Rooms[bestA].Center(), level.Rooms[bestB].Center(), horizontalFirst);
        first.AddRange(second);
        return first;
    }
    void Dig(Level level, Position start, Position end, bool horizontalFirst) {
        List<Position> path = new();
        int sx = end.X >= start.X ? 1 : -1, sy = end.Y >= start.Y ? 1 : -1;
        if (horizontalFirst) {
            for (int x = start.X; ; x += sx) { path.Add(new Position(x, start.Y)); if (x == end.X) break; }
            for (int y = start.Y; ; y += sy) { path.Add(new Position(end.X, y)); if (y == end.Y) break; }
        } else {
            for (int y = start.Y; ; y += sy) { path.Add(new Position(start.X, y)); if (y == end.Y) break; }
            for (int x = start.X; ; x += sx) { path.Add(new Position(x, end.Y)); if (x == end.X) break; }
        }
        foreach (Position point in path) {
            char terrain = level.Terrain[point.Y][point.X];
            if (terrain == ' ') level.Terrain[point.Y][point.X] = '#';
            else if (terrain is '-' or '|') level.Terrain[point.Y][point.X] = '+';
        }
    }
    void ChooseStairs(Level level) {
        RoomCell drawn = level.DrawRoom(rng);
        level.ArrivalRoom = drawn.Room; level.Arrival = new Position(drawn.X, drawn.Y); level.Terrain[drawn.Y][drawn.X] = '<';
        int other = rng.Rnd(level.Rooms.Count - 1);
        if (other >= drawn.Room) other++;
        level.Target = level.DrawInterior(rng, other);
    }
}
