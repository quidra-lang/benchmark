sealed class Turn(Segment target, long weight)
{
    public Segment Target = target;
    public long Weight = weight, Vehicles;
}
sealed class BusStop(Segment segment, int cell, int dwell)
{
    public Segment Segment = segment;
    public int Cell = cell, Dwell = dwell;
    public long Buses;
}
sealed class Segment(string id, string start, string end, int length, int lanes, int limit)
{
    public string Id = id, Start = start, End = end;
    public int Length = length, Lanes = lanes, Limit = limit;
    public int[][] Cells = Enumerable.Range(0,lanes).Select(_ => new int[length]).ToArray();
    public Junction? Junction;
    public BusStop? Stop;
    public List<Turn> Turns = [];
    public long Entered, VehicleSum, SpeedSum, MaxVehicles, GreenSteps, QueueSum, MaxQueue, Failures, Passed, Blocked;
    public long[] Changes = new long[3];
    public bool Empty(int lane, int cell) => Cells[lane - 1][cell] == 0;
    public void Put(int lane, int cell, int value) => Cells[lane - 1][cell] = value;
    public int Free(int lane, int cell, int cap)
    {
        int count = 0; while (count < cap && cell + count + 1 < Length && Empty(lane,cell + count + 1)) count++; return count;
    }
    public int First(int lane) { for (int cell = 0; cell < Length; cell++) if (!Empty(lane,cell)) return cell; return Length; }
    public bool Safe(int lane, int cell) { for (int x = Math.Max(0,cell - Limit); x <= cell; x++) if (!Empty(lane,x)) return false; return true; }
    public IEnumerable<int> Numbers(int lane) => Cells[lane - 1].Where(x => x > 0);
    public string Text(int lane, List<Vehicle> vehicles) => new(Cells[lane - 1].Select(x => x == 0 ? '.' : x < 0 ? '#' : (char)('0' + vehicles[x - 1].Speed)).ToArray());
}
sealed class Incident(Segment segment, int lane, int cell, long start, long end)
{
    public Segment Segment = segment;
    public int Lane = lane, Cell = cell, ActiveStart, ActiveEnd;
    public long Start = start, End = end;
    string state = "planned";
    public string Update(int step)
    {
        string result = "";
        if (state == "active" && step > End) { state = "cleared"; Segment.Put(Lane,Cell,0); result = "INCIDENT_END"; }
        else if (state == "planned" && step > End) state = "cancelled";
        else if (state == "planned" && step >= Start && Segment.Empty(Lane,Cell)) { state = "active"; Segment.Put(Lane,Cell,-1); ActiveStart = step; result = "INCIDENT_START"; }
        if (state == "active") ActiveEnd = step; return result;
    }
}
