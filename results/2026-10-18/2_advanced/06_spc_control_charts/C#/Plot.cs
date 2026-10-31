static class Plot
{
    static void Place(char[] band, double position, char symbol) => band[(int)Math.Clamp(position, 0, 60)] = symbol;
    static char[] NewBand() => new string('.', 61).ToCharArray();
    static char[] Framed(double center)
    {
        char[] band = NewBand(); Place(band, 0, ':'); Place(band, 60, ':'); Place(band, center, '|'); return band;
    }
    public static string LimitsBand(Limits limits, double value, bool signalled)
    {
        double span = limits.Ucl - limits.Lcl;
        char[] band = Framed(Math.Floor(60 * ((limits.Cl - limits.Lcl) / span) + 0.5));
        Place(band, Math.Floor(60 * ((value - limits.Lcl) / span) + 0.5), signalled ? '*' : 'o');
        return new(band);
    }
    public static string CusumBand(double upper, double lower, double threshold, bool upperSignal, bool lowerSignal)
    {
        char[] band = Framed(30);
        if (lower > 0) Place(band, 30 - Math.Min(30, Math.Floor(30 * (lower / threshold) + 0.5)), lowerSignal ? '*' : '-');
        if (upper > 0) Place(band, 30 + Math.Min(30, Math.Floor(30 * (upper / threshold) + 0.5)), upperSignal ? '*' : '+');
        return new(band);
    }
    public static string WidthBand(double scale, double width, double value, double center, bool signalled)
    {
        char[] band = NewBand();
        double edge = Math.Min(30, Math.Floor(30 * (width / scale) + 0.5));
        Place(band, 30, '|'); Place(band, 30 - edge, ':'); Place(band, 30 + edge, ':');
        double deviation = (value - center) / scale;
        Place(band, 30 + Math.Floor(30 * deviation + 0.5), signalled ? '*' : 'o');
        return new(band);
    }
    public static string StandardBand(double z, bool ok)
    {
        char[] band = Framed(30); Place(band, 30 + Math.Floor(10 * z + 0.5), ok ? 'o' : '*'); return new(band);
    }
}
