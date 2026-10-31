import java.util.*;
final class Relocator {
    enum Type { ABS32, REL32, ABS16, HI16, LO16, GPREL16, CALL24 }
    static int width(Type type) {
        return switch (type) {
            case ABS32, REL32 -> 4;
            case CALL24 -> 3;
            default -> 2;
        };
    }
    static boolean inRange(Type type, long value) {
        return switch (type) {
            case ABS32, HI16 -> value >= -(1L << 31) && value < (1L << 32);
            case REL32 -> value >= -(1L << 31) && value < (1L << 31);
            case ABS16 -> value >= -(1L << 15) && value < (1L << 16);
            case GPREL16 -> value >= -(1L << 15) && value < (1L << 15);
            case CALL24 -> value >= -(1L << 25) && value < (1L << 25);
            case LO16 -> true;
        };
    }
    static boolean unpaired(List<ObjectParser.Relocation> relocations, int index) {
        ObjectParser.Relocation current = relocations.get(index);
        if (current.type != Type.HI16)
            return false;
        if (index + 1 == relocations.size())
            return true;
        ObjectParser.Relocation following = relocations.get(index + 1);
        return following.type != Type.LO16 || following.symbol != current.symbol ||
            following.addend != current.addend;
    }
    record Calculation(long value, long field, boolean inRange) {}
    static Calculation calculate(Type type, long symbol, long addend, long place, long gp) {
        long value = symbol + addend;
        if (type == Type.REL32 || type == Type.CALL24)
            value -= place;
        else if (type == Type.GPREL16)
            value -= gp;
        long field;
        if (type == Type.HI16)
            field = ((Math.floorMod(value, 1L << 32) + 32768) / 65536) % 65536;
        else if (type == Type.CALL24)
            field = Math.floorMod(Math.floorDiv(value, 4), 1L << 24);
        else
            field = Math.floorMod(value, 1L << (8 * width(type)));
        return new Calculation(value, field, inRange(type, value));
    }
}
