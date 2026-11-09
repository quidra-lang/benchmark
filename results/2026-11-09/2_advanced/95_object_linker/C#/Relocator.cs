using System;
using System.Collections.Generic;
using System.Linq;
static class Relocator {
    public static readonly string[] Types = {
        "ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24"
    };
    public static int Width(string kind) => kind is "ABS32" or "REL32" ? 4 : kind == "CALL24" ? 3 : 2;
    public static long Value(string kind, long symbol, long addend, long position, long gp) => symbol + addend - (kind is "REL32" or "CALL24" ? position : kind == "GPREL16" ? gp : 0);
    public static bool Fits(string kind, long value) => kind switch {
        "ABS32" or "HI16" => value >= -2147483648L && value < 4294967296L, "REL32" => value >= -2147483648L && value < 2147483648L, "ABS16" => value >= -32768 && value < 65536, "GPREL16" => value >= -32768 && value < 32768, "CALL24" => value >= -33554432 && value < 33554432, _ => true
    };
    public static long Field(string kind, long value) => kind switch {
        "HI16" => Layout.Mod((Layout.Mod(value, 4294967296L) + 32768) / 65536, 65536), "CALL24" => Layout.Mod((value - Layout.Mod(value, 4)) / 4, 16777216), "ABS32" or "REL32" => Layout.Mod(value, 4294967296L), _ => Layout.Mod(value, 65536)
    };
    public static bool Unpaired(List<Relocation> relocations, int index) {
        Relocation current = relocations[index];
        if (current.Kind != "HI16") return false;
        if (index + 1 == relocations.Count) return true;
        Relocation next = relocations[index + 1];
        return next.Kind != "LO16" || next.Symbol != current.Symbol || next.Addend != current.Addend;
    }
    public static List<int> Little(long value, int width) => Enumerable.Range(0, width).Select(i => (int)((value >> (8 * i)) & 255)).ToList();
}
