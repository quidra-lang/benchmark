using System.Collections.Generic;

static class Morphology
{
    public static readonly List<Pixel> NEIGHBORS = [new(0, -1), new(1, -1), new(1, 0), new(1, 1), new(0, 1), new(-1, 1), new(-1, 0), new(-1, -1)];
    public static bool occupied(bool[][] mask, int x, int y) => y >= 0 && y < mask.Length && x >= 0 && x < mask[0].Length && mask[y][x];
    static bool[][] empty(bool[][] mask)
    {
        bool[][] result = new bool[mask.Length][];
        for (int y = 0; y < result.Length; y++) result[y] = new bool[mask[0].Length];
        return result;
    }
    public static bool[][] erode(bool[][] mask, List<Pixel> offsets)
    {
        bool[][] result = empty(mask);
        for (int y = 0; y < mask.Length; y++) for (int x = 0; x < mask[0].Length; x++)
        {
            bool all = true;
            foreach (Pixel offset in offsets) if (!occupied(mask, x + offset.x, y + offset.y)) { all = false; break; }
            result[y][x] = all;
        }
        return result;
    }
    public static bool[][] dilate(bool[][] mask, List<Pixel> offsets)
    {
        bool[][] result = empty(mask);
        for (int y = 0; y < mask.Length; y++) for (int x = 0; x < mask[0].Length; x++)
            foreach (Pixel offset in offsets) if (occupied(mask, x - offset.x, y - offset.y)) { result[y][x] = true; break; }
        return result;
    }
    public static bool[][] opening(bool[][] mask, List<Pixel> offsets) => dilate(erode(mask, offsets), offsets);
    public static bool[][] closing(bool[][] mask, List<Pixel> offsets) => erode(dilate(mask, offsets), offsets);
    public static bool[] bits(HashSet<Pixel> pixels, Pixel point)
    {
        bool[] bits = new bool[8];
        for (int i = 0; i < 8; i++) { Pixel offset = NEIGHBORS[i]; bits[i] = pixels.Contains(new Pixel(point.x + offset.x, point.y + offset.y)); }
        return bits;
    }
    public static int transitions(bool[] bits)
    {
        int count = 0;
        for (int i = 0; i < 8; i++) if (!bits[i] && bits[(i + 1) % 8]) count++;
        return count;
    }
    public static int crossing(HashSet<Pixel> pixels, Pixel point) => transitions(bits(pixels, point));
    static bool removable(bool[] bits, bool first)
    {
        int count = 0;
        foreach (bool bit in bits) if (bit) count++;
        if (count < 2 || count > 6 || transitions(bits) != 1) return false;
        bool p2 = bits[0], p4 = bits[2], p6 = bits[4], p8 = bits[6];
        return first ? !(p2 && p4 && p6) && !(p4 && p6 && p8) : !(p2 && p4 && p8) && !(p2 && p6 && p8);
    }
    static bool thinningStep(HashSet<Pixel> skeleton, bool first)
    {
        var removed = new List<Pixel>();
        foreach (Pixel point in skeleton) if (removable(bits(skeleton, point), first)) removed.Add(point);
        skeleton.ExceptWith(removed);
        return removed.Count > 0;
    }
    public static HashSet<Pixel> thin(List<Pixel> pixels)
    {
        var skeleton = new HashSet<Pixel>(pixels);
        while (true)
        {
            bool first = thinningStep(skeleton, true), second = thinningStep(skeleton, false);
            if (!first && !second) return skeleton;
        }
    }
}
