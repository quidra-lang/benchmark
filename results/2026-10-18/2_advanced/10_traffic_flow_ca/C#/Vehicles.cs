sealed record VehicleClass(string Name, int Vmax, long Weight, bool Overtakes, bool Stops);
sealed class Vehicle(int number, VehicleClass kind, string source, int arrival)
{
    public int Number = number, Arrival = arrival, Inserted, Exited, Lane, Cell, Speed, Dwell;
    public VehicleClass Kind = kind;
    public string Source = source, Sink = "";
    public Segment? Segment;
    public Turn? Turn;
    public List<string> Route = [];
    public HashSet<string> CompletedStops = [];
    public long Steps, Distance, StoppedSteps, StopCount, LaneChanges;
    public int MaxSpeed => Math.Min(Kind.Vmax,Segment!.Limit);
    public bool HeadingForStop => Segment is not null && Kind.Stops && Segment.Stop is not null && !CompletedStops.Contains(Segment.Id) && Cell <= Segment.Stop.Cell;
    public int TravelTime => Exited - Inserted + 1;
    public void Place(Segment target, int lane, int cell)
    {
        Segment?.Put(Lane,Cell,0); target.Put(lane,cell,Number); Segment = target; Lane = lane; Cell = cell;
    }
    public void Leave() { Segment!.Put(Lane,Cell,0); Segment = null; }
    public static int Slowdown(int speed, int previous, long draw, int dawdle, int stopped) => speed > 0 && draw % 1000 < (previous == 0 ? stopped : dawdle) ? speed - 1 : speed;
}
