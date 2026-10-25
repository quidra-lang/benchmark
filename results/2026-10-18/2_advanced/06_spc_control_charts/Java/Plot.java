import java.util.Arrays;

final class Plot {
    private static void place(char[] band, double position, char symbol) { band[(int)Math.clamp(position, 0, 60)] = symbol; }
    private static char[] newBand() { char[] band = new char[61]; Arrays.fill(band, '.'); return band; }
    private static char[] framed(double center) {
        char[] band = newBand(); place(band, 0, ':'); place(band, 60, ':'); place(band, center, '|'); return band;
    }
    static String limitsBand(Limits limits, double value, boolean signalled) {
        double span = limits.ucl() - limits.lcl();
        char[] band = framed(Math.floor(60 * ((limits.cl() - limits.lcl()) / span) + 0.5));
        place(band, Math.floor(60 * ((value - limits.lcl()) / span) + 0.5), signalled ? '*' : 'o');
        return new String(band);
    }
    static String cusumBand(double upper, double lower, double threshold, boolean upperSignal, boolean lowerSignal) {
        char[] band = framed(30);
        if (lower > 0) place(band, 30 - Math.min(30, Math.floor(30 * (lower / threshold) + 0.5)), lowerSignal ? '*' : '-');
        if (upper > 0) place(band, 30 + Math.min(30, Math.floor(30 * (upper / threshold) + 0.5)), upperSignal ? '*' : '+');
        return new String(band);
    }
    static String widthBand(double scale, double width, double value, double center, boolean signalled) {
        char[] band = newBand();
        double edge = Math.min(30, Math.floor(30 * (width / scale) + 0.5));
        place(band, 30, '|'); place(band, 30 - edge, ':'); place(band, 30 + edge, ':');
        double deviation = (value - center) / scale;
        place(band, 30 + Math.floor(30 * deviation + 0.5), signalled ? '*' : 'o');
        return new String(band);
    }
    static String standardBand(double z, boolean ok) {
        char[] band = framed(30); place(band, 30 + Math.floor(10 * z + 0.5), ok ? 'o' : '*'); return new String(band);
    }
}
