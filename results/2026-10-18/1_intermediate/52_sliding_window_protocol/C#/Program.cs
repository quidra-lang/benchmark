using System;
using System.Collections.Generic;
using System.Linq;

class Program
{
    static readonly string[] Keys = { "PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY", "INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION", "UNSAFE", "TRACE", "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT" };
    static readonly List<string> Output = new();
    static int Mod(int a, int b) => (a % b + b) % b;
    static string Fixed(long numerator, long denominator, int digits)
    {
        long scale = digits == 2 ? 100 : 10;
        long value = denominator == 0 ? 0 : numerator * scale / denominator;
        return (value / scale) + "." + (value % scale).ToString(digits == 2 ? "D2" : "D1");
    }
    static string Tick(int tick) => tick < 0 ? "-" : tick.ToString();
    class Config
    {
        public string Name = "", Protocol = "", Trace = "ALL";
        public int N, W, K, T, Delay, Interval, Limit = 1000, Dupack;
        public bool Nak, Backoff, Congestion, Unsafe, Random;
        public long Seed;
        public int Loss, Corruption;
        public HashSet<int> LostData = new(), LostControl = new(), CorruptData = new(), CorruptControl = new(), Snapshots = new();
        public Dictionary<int, int> DelayData = new(), DelayControl = new();
    }
    static string Validate(Config c, List<string[]> lines)
    {
        Dictionary<string, string[]> values = new();
        foreach (string[] line in lines)
        {
            string key = line[0];
            int index = Array.IndexOf(Keys, key), count = line.Length - 1;
            if (index < 0) return "unknown key " + key;
            if (values.ContainsKey(key)) return "duplicate key " + key;
            if (key == "RANDOM" ? count != 3 : index >= 15 ? count < 1 : count != 1)
                return "wrong number of values for " + key;
            values[key] = line.Skip(1).ToArray();
        }
        for (int i = 0; i < 6; ++i) if (!values.ContainsKey(Keys[i])) return "missing key " + Keys[i];
        foreach (string key in Keys)
        {
            if (!values.TryGetValue(key, out string[] v)) continue;
            int index = Array.IndexOf(Keys, key);
            bool valid = true;
            if (key == "PROTOCOL") valid = new[] { "SW", "GBN", "SR" }.Contains(v[0]);
            else if (index >= 9 && index <= 12) valid = v[0] == "ON" || v[0] == "OFF";
            else if (key == "TRACE") valid = new[] { "ALL", "SENDER", "RECEIVER", "NONE" }.Contains(v[0]);
            else if (key == "RANDOM")
            {
                long seed = long.Parse(v[0]); int loss = int.Parse(v[1]), corruption = int.Parse(v[2]);
                valid = seed >= 1 && seed <= 2147483646 && loss >= 0 && corruption >= 0 && (long)loss + corruption <= 100;
            }
            else if (index >= 15)
            {
                HashSet<int> seen = new();
                foreach (string value in v)
                {
                    string[] parts = value.Split(':'); int number = int.Parse(parts[0]);
                    int lower = key == "SNAPSHOT" ? 0 : 1, upper = key == "SNAPSHOT" ? 2000 : 9999;
                    if (number < lower || number > upper || !seen.Add(number)) valid = false;
                    if (index == 19 || index == 20)
                    {
                        int extra = int.Parse(parts[1]); if (extra < 1 || extra > 50) valid = false;
                    }
                }
            }
            else
            {
                int number = int.Parse(v[0]);
                int lower = key == "INTERVAL" ? 0 : 1;
                int upper = key switch { "FRAMES" => 60, "WINDOW" => 32, "SEQBITS" => 6, "TIMEOUT" => 50, "DELAY" => 10, "INTERVAL" => 10, "MAXTICKS" => 2000, _ => 10 };
                valid = number >= lower && number <= upper;
            }
            if (!valid) return "bad value for " + key;
        }
        string Get(string key, string fallback) => values.TryGetValue(key, out string[] v) ? v[0] : fallback;
        c.Protocol = Get("PROTOCOL", ""); c.N = int.Parse(Get("FRAMES", "0")); c.W = int.Parse(Get("WINDOW", "0"));
        c.K = int.Parse(Get("SEQBITS", "0")); c.T = int.Parse(Get("TIMEOUT", "0")); c.Delay = int.Parse(Get("DELAY", "0"));
        c.Interval = int.Parse(Get("INTERVAL", "0")); c.Limit = int.Parse(Get("MAXTICKS", "1000")); c.Dupack = int.Parse(Get("DUPACK", "0"));
        c.Nak = Get("NAK", "OFF") == "ON"; c.Backoff = Get("BACKOFF", "OFF") == "ON"; c.Congestion = Get("CONGESTION", "OFF") == "ON";
        c.Unsafe = Get("UNSAFE", "OFF") == "ON"; c.Trace = Get("TRACE", "ALL");
        if (c.Protocol == "SR" && values.ContainsKey("DUPACK")) return "DUPACK not supported for SR";
        int limit = c.Protocol == "SW" ? 1 : c.Protocol == "GBN" ? (1 << c.K) - 1 : 1 << (c.K - 1);
        if (c.W > limit && !(c.Unsafe && c.Protocol != "SW")) return $"window {c.W} exceeds limit {limit} for {c.Protocol}";
        if (values.TryGetValue("RANDOM", out string[] random))
        {
            c.Random = true; c.Seed = long.Parse(random[0]); c.Loss = int.Parse(random[1]); c.Corruption = int.Parse(random[2]);
        }
        HashSet<int> Set(string key) => values.TryGetValue(key, out string[] v) ? v.Select(int.Parse).ToHashSet() : new();
        Dictionary<int, int> Delays(string key) => values.TryGetValue(key, out string[] v) ? v.Select(x => x.Split(':')).ToDictionary(x => int.Parse(x[0]), x => int.Parse(x[1])) : new();
        c.LostData = Set("LOSEDATA"); c.LostControl = Set("LOSECTRL"); c.CorruptData = Set("CORRUPTDATA"); c.CorruptControl = Set("CORRUPTCTRL");
        c.Snapshots = Set("SNAPSHOT"); c.DelayData = Delays("DELAYDATA"); c.DelayControl = Delays("DELAYCTRL");
        int conflict = c.LostData.Intersect(c.CorruptData).DefaultIfEmpty(-1).Min();
        if (conflict >= 0) return $"data #{conflict} both lost and corrupted";
        conflict = c.LostControl.Intersect(c.CorruptControl).DefaultIfEmpty(-1).Min();
        return conflict >= 0 ? $"control #{conflict} both lost and corrupted" : null;
    }
    record Transmission(int Arrival, int Number, int Value, int Outcome, bool Nak);
    class Result
    {
        public Config Config;
        public string Status;
        public int Delivered, Data, Completion;
        public Result(Config c, string status) { Config = c; Status = status; }
    }
    class Simulation
    {
        readonly Config c;
        readonly bool sr;
        readonly int modulus;
        readonly List<Transmission> dataEvents = new(), controlEvents = new();
        readonly List<int> queue = new();
        readonly Dictionary<int, int> buffer = new();
        readonly bool[] acknowledged;
        readonly int[] timers, tx, first, deliveredAt, ackedAt;
        int tick, baseFrame, high, next, duration, timer = -1, duplicates, receiver, cwnd = 1, threshold, credit;
        int data, control, resent, naks, timeouts, fast, lostData, lostControl, corruptData, corruptControl;
        int delivered, errors, discarded, maxBuffer, latency;
        bool nakSent;
        long random;
        public Simulation(Config config)
        {
            c = config; sr = c.Protocol == "SR"; modulus = 1 << c.K; duration = c.T; threshold = c.W; random = c.Seed;
            acknowledged = new bool[c.N]; timers = Enumerable.Repeat(-1, c.N).ToArray(); tx = new int[c.N];
            first = Enumerable.Repeat(-1, c.N).ToArray(); deliveredAt = Enumerable.Repeat(-1, c.N).ToArray(); ackedAt = Enumerable.Repeat(-1, c.N).ToArray();
        }
        int Effective => c.Congestion ? Math.Min(c.W, cwnd) : c.W;
        void Log(string side, string text)
        {
            if (c.Trace == "ALL" || c.Trace == side || side == "ALWAYS") Output.Add(tick + " " + text);
        }
        int Outcome(bool isData, int number)
        {
            int outcome = 0;
            if (c.Random)
            {
                random = random * 48271 % 2147483647; int value = (int)(random % 100);
                outcome = value < c.Loss ? 1 : value < c.Loss + c.Corruption ? 2 : 0;
            }
            if ((isData ? c.LostData : c.LostControl).Contains(number)) outcome = 1;
            if ((isData ? c.CorruptData : c.CorruptControl).Contains(number)) outcome = 2;
            return outcome;
        }
        void SendControl(bool nak, int value)
        {
            ++control; if (nak) ++naks;
            Log("RECEIVER", $"{(nak ? "NAK" : "ACK")} a={value} #{control}");
            controlEvents.Add(new Transmission(tick + c.Delay + c.DelayControl.GetValueOrDefault(control), control, value, Outcome(false, control), nak));
        }
        void Deliver(int payload)
        {
            if (payload == receiver)
            {
                Log("RECEIVER", $"DELIVER f={receiver}"); ++delivered;
                if (deliveredAt[payload] < 0) deliveredAt[payload] = tick;
                latency += tick - first[payload];
            }
            else { Log("RECEIVER", $"DELIVER f={receiver} wrong={payload}"); ++errors; }
            ++receiver; nakSent = false;
        }
        void Discard(int sequence) { ++discarded; Log("RECEIVER", $"DISCARD seq={sequence}"); }
        void Receive(Transmission e)
        {
            if (e.Outcome != 0)
            {
                if (e.Outcome == 1) ++lostData; else ++corruptData;
                Log("RECEIVER", $"{(e.Outcome == 1 ? "LOST" : "CORRUPT")} data #{e.Number}"); return;
            }
            int sequence = e.Value % modulus;
            Log("RECEIVER", $"RECV seq={sequence} #{e.Number}");
            if (!sr)
            {
                if (sequence == receiver % modulus) { Deliver(e.Value); SendControl(false, sequence); }
                else
                {
                    Discard(sequence);
                    if (c.Nak && !nakSent) { SendControl(true, receiver % modulus); nakSent = true; }
                    else if (receiver > 0) SendControl(false, (receiver - 1) % modulus);
                }
                return;
            }
            int offset = Mod(sequence - receiver, modulus), position = receiver + offset;
            if (offset < c.W)
            {
                if (buffer.ContainsKey(position)) { Discard(sequence); SendControl(false, sequence); }
                else if (offset == 0)
                {
                    Deliver(e.Value);
                    while (buffer.Remove(receiver, out int payload)) Deliver(payload);
                    SendControl(false, sequence);
                }
                else
                {
                    buffer[position] = e.Value; maxBuffer = Math.Max(maxBuffer, buffer.Count);
                    Log("RECEIVER", $"BUFFER f={position}"); SendControl(false, sequence);
                    if (c.Nak && !nakSent) { SendControl(true, receiver % modulus); nakSent = true; }
                }
            }
            else
            {
                Discard(sequence);
                if (Mod(receiver - sequence, modulus) <= c.W) SendControl(false, sequence);
            }
        }
        void GoBack() { next = baseFrame; timer = -1; duplicates = 0; }
        void Increase(int count)
        {
            if (!c.Congestion) return;
            for (int i = 0; i < count && cwnd < c.W; ++i)
            {
                if (cwnd < threshold) ++cwnd;
                else if (++credit == cwnd) { ++cwnd; credit = 0; }
            }
        }
        void Decrease(bool timeout)
        {
            if (!c.Congestion) return;
            threshold = Math.Max(cwnd / 2, 1); cwnd = timeout ? 1 : threshold; credit = 0;
        }
        void Cwnd(int oldWindow, int oldThreshold)
        {
            if (c.Congestion && (oldWindow != cwnd || oldThreshold != threshold)) Log("SENDER", $"CWND {cwnd} ssthresh={threshold}");
        }
        void Control(Transmission e)
        {
            string kind = e.Nak ? "NAK" : "ACK";
            if (e.Outcome != 0)
            {
                if (e.Outcome == 1) ++lostControl; else ++corruptControl;
                Log("SENDER", $"{(e.Outcome == 1 ? "LOST" : "CORRUPT")} {kind.ToLowerInvariant()} #{e.Number}"); return;
            }
            int oldWindow = cwnd, oldThreshold = threshold, oldBase = baseFrame;
            int frame = baseFrame + Mod(e.Value - baseFrame, modulus);
            bool accepted = sr ? frame < high && !acknowledged[frame] : e.Nak ? frame <= high : frame < high;
            if (accepted)
            {
                if (sr)
                {
                    timers[frame] = -1;
                    if (e.Nak) { if (!queue.Contains(frame)) queue.Add(frame); }
                    else
                    {
                        acknowledged[frame] = true; queue.Remove(frame); if (ackedAt[frame] < 0) ackedAt[frame] = tick;
                        while (baseFrame < high && acknowledged[baseFrame]) ++baseFrame;
                        Increase(1);
                    }
                }
                else
                {
                    baseFrame = frame + (e.Nak ? 0 : 1);
                    Increase(baseFrame - oldBase);
                    for (int f = oldBase; f < baseFrame; ++f) if (ackedAt[f] < 0) ackedAt[f] = tick;
                }
                if (baseFrame > oldBase) { duration = c.T; duplicates = 0; }
                if (!sr)
                {
                    if (e.Nak) GoBack();
                    else { next = Math.Max(next, baseFrame); timer = baseFrame == next ? -1 : tick + duration; }
                }
                if (e.Nak) Decrease(false);
                Log("SENDER", $"GOT{kind} a={e.Value} #{e.Number} base={baseFrame}");
            }
            else
            {
                Log("SENDER", $"OLD{kind} a={e.Value} #{e.Number}");
                if (!sr && !e.Nak && c.Dupack > 0 && baseFrame >= 1 && e.Value == (baseFrame - 1) % modulus)
                {
                    ++duplicates;
                    if (duplicates == c.Dupack) { ++fast; Log("SENDER", $"FASTRETX f={baseFrame}"); GoBack(); Decrease(false); }
                }
            }
            Cwnd(oldWindow, oldThreshold);
        }
        void Timeout(int frame)
        {
            int oldWindow = cwnd, oldThreshold = threshold;
            ++timeouts; Log("SENDER", $"TIMEOUT f={frame}");
            if (sr) { timers[frame] = -1; if (!queue.Contains(frame)) queue.Add(frame); } else GoBack();
            if (c.Backoff) duration = Math.Min(duration * 2, c.T * 8);
            Decrease(true); Cwnd(oldWindow, oldThreshold);
        }
        void Send(int frame)
        {
            ++data;
            bool retry = tx[frame] > 0;
            if (retry) ++resent; else first[frame] = tick;
            ++tx[frame]; Log("SENDER", $"{(retry ? "RESEND" : "SEND")} f={frame} seq={frame % modulus} #{data}");
            dataEvents.Add(new Transmission(tick + c.Delay + c.DelayData.GetValueOrDefault(data), data, frame, Outcome(true, data), false));
            if (sr) timers[frame] = tick + duration; else if (timer < 0) timer = tick + duration;
        }
        void Snapshot()
        {
            char[] sender = new char[c.N], receiving = new char[c.N];
            for (int f = 0; f < c.N; ++f)
            {
                sender[f] = (sr ? acknowledged[f] : f < baseFrame) ? 'A' : (sr ? queue.Contains(f) : next <= f && f < high) ? 'R' : (sr ? f < high : f < next) ? 'O' : f < baseFrame + Effective ? 'W' : '.';
                receiving[f] = f < receiver ? 'D' : sr && buffer.ContainsKey(f) ? 'B' : (sr ? f < receiver + c.W : f == receiver) ? 'W' : '.';
            }
            Log("ALWAYS", $"SNAPSHOT sender={new string(sender)} receiver={new string(receiving)}");
        }
        public Result Run()
        {
            Output.Add($"config: {c.Protocol} n={c.N} w={c.W} k={c.K} T={c.T} d={c.Delay}");
            string On(bool value) => value ? "on" : "off";
            Output.Add($"options: interval={c.Interval} limit={c.Limit} dupack={(c.Dupack == 0 ? "off" : c.Dupack.ToString())} nak={On(c.Nak)} backoff={On(c.Backoff)} congestion={On(c.Congestion)} unsafe={On(c.Unsafe)} trace={c.Trace.ToLowerInvariant()} random={(c.Random ? $"{c.Seed}/{c.Loss}/{c.Corruption}" : "off")}");
            bool complete = false;
            for (tick = 0; tick <= c.Limit; ++tick)
            {
                foreach (Transmission e in dataEvents.Where(e => e.Arrival == tick).OrderBy(e => e.Number).ToArray()) Receive(e);
                foreach (Transmission e in controlEvents.Where(e => e.Arrival == tick).OrderBy(e => e.Number).ToArray()) Control(e);
                complete = baseFrame == c.N;
                if (!complete)
                {
                    if (sr) { for (int f = baseFrame; f < high; ++f) if (timers[f] == tick) Timeout(f); }
                    else if (timer == tick) Timeout(baseFrame);
                    if (sr)
                    {
                        if (queue.Count > 0) { int frame = queue[0]; queue.RemoveAt(0); Send(frame); }
                        else if (high < c.N && high < baseFrame + Effective && high * c.Interval <= tick) { int frame = high++; Send(frame); }
                    }
                    else if (next < c.N && next < baseFrame + Effective && (next < high || next * c.Interval <= tick))
                    {
                        int frame = next++; high = Math.Max(high, next); Send(frame);
                    }
                }
                if (c.Snapshots.Contains(tick)) Snapshot();
                if (complete || tick == c.Limit) { Log("ALWAYS", complete ? "DONE" : "ABORT"); break; }
            }
            for (int f = 0; f < c.N; ++f) Output.Add($"frame {f}: seq={f % modulus} tx={tx[f]} first={Tick(first[f])} delivered={Tick(deliveredAt[f])} acked={Tick(ackedAt[f])}");
            Output.Add($"totals: data={data} resent={resent} control={control} nak={naks} timeouts={timeouts} fastretx={fast}");
            Output.Add($"channel: lost_data={lostData} lost_ctrl={lostControl} corrupt_data={corruptData} corrupt_ctrl={corruptControl}");
            Output.Add($"receiver: delivered={delivered} errors={errors} discarded={discarded} max_buffer={maxBuffer}");
            Output.Add($"result: completion={(complete ? tick.ToString() : "-")} goodput={(complete ? Fixed(delivered, tick, 2) : "-")} efficiency={Fixed(delivered * 100L, data, 1)}% utilization={Fixed(data * 100L, tick + 1, 1)}% latency={(delivered == 0 ? "-" : Fixed(latency, delivered, 2))}");
            return new Result(c, complete ? "complete" : "aborted") { Delivered = delivered, Data = data, Completion = tick };
        }
    }
    static void Main()
    {
        int count = int.Parse(Console.ReadLine()); List<Result> results = new();
        for (int i = 0; i < count; ++i)
        {
            Config config = new() { Name = Console.ReadLine().Split(' ')[1] };
            List<string[]> lines = new(); string line;
            while ((line = Console.ReadLine()) != "END") lines.Add(line.Split(' '));
            Output.Add("== " + config.Name + " ==");
            string error = Validate(config, lines);
            if (error != null) { Output.Add("error: " + error); results.Add(new Result(config, "invalid")); }
            else results.Add(new Simulation(config).Run());
        }
        Output.Add("== ranking ==");
        List<Result> completed = results.Where(r => r.Status == "complete").ToList();
        completed.Sort((a, b) =>
        {
            int order = ((long)b.Delivered * a.Completion).CompareTo((long)a.Delivered * b.Completion);
            if (order == 0) order = ((long)b.Delivered * a.Data).CompareTo((long)a.Delivered * b.Data);
            return order != 0 ? order : results.IndexOf(a).CompareTo(results.IndexOf(b));
        });
        for (int i = 0; i < completed.Count; ++i)
        {
            Result r = completed[i]; Output.Add($"{i + 1}. {r.Config.Name} {r.Config.Protocol} goodput={Fixed(r.Delivered, r.Completion, 2)} efficiency={Fixed(r.Delivered * 100L, r.Data, 1)}%");
        }
        foreach (Result r in results.Where(r => r.Status != "complete")) Output.Add($"- {r.Config.Name} {r.Status}");
        Output.Add("== protocols ==");
        foreach (string protocol in new[] { "SW", "GBN", "SR" })
        {
            List<Result> runs = completed.Where(r => r.Config.Protocol == protocol).ToList();
            if (runs.Count == 0) continue;
            long delivered = runs.Sum(r => (long)r.Delivered), ticks = runs.Sum(r => (long)r.Completion), data = runs.Sum(r => (long)r.Data);
            Output.Add($"{protocol}: runs={runs.Count} goodput={Fixed(delivered, ticks, 2)} efficiency={Fixed(delivered * 100, data, 1)}%");
        }
        Console.WriteLine(string.Join("\n", Output));
    }
}
