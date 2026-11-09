#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

static class Groups
{
    public static readonly Dictionary<string, string> Descriptors = Table(
        "MI|shallow|BC|patches|PR|partial|DR|low drifting|BL|blowing|SH|showers|TS|thunderstorm|FZ|freezing");
    public static readonly Dictionary<string, string> Phenomena = Table(
        "DZ|drizzle|RA|rain|SN|snow|SG|snow grains|IC|ice crystals|PL|ice pellets|GR|hail|GS|small hail|UP|unknown precipitation|BR|mist|FG|fog|FU|smoke|VA|volcanic ash|DU|dust|SA|sand|HZ|haze|PY|spray|PO|dust whirls|SQ|squalls|FC|funnel cloud|SS|sandstorm|DS|duststorm");
    public static readonly HashSet<string> Precipitation = new() { "DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP" };
    public static readonly Dictionary<string, string> Amounts = Table("FEW|few|SCT|scattered|BKN|broken|OVC|overcast");
    public static readonly Dictionary<string, string> Clear = Table("SKC|sky clear|CLR|clear below 12000 ft|NSC|no significant cloud");
    public static readonly Dictionary<string, string> Intensities = Table("-|light|+|heavy|VC|nearby");

    private static Dictionary<string, string> Table(string data)
    {
        var result = new Dictionary<string, string>();
        string[] p = data.Split('|');
        for (int i = 0; i < p.Length; i += 2) result[p[i]] = p[i + 1];
        return result;
    }

    public static long Number(string s) => s.Length == 0 ? 0 : long.Parse(s, CultureInfo.InvariantCulture);

    public static string[]? Match(string pattern, string text)
    {
        Match m = Regex.Match(text, @"\A(?:" + pattern + @")\z", RegexOptions.CultureInvariant);
        return m.Success ? m.Groups.Cast<System.Text.RegularExpressions.Group>().Select(g => g.Value).ToArray() : null;
    }

    public static Value? Format(string kind, string text)
    {
        var v = new Value { Raw = text };
        string[]? m;
        switch (kind)
        {
            case "modifier":
                return text is "AUTO" or "COR" ? v : null;
            case "wind":
                m = Match(@"(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)", text);
                if (m == null) return null;
                v.Variable = m[1] == "VRB";
                v.Calm = m[1] == "000";
                v.Direction = v.Variable ? 0 : Number(m[1]);
                v.Speed = Number(m[2]);
                v.Gust = m[3] == "" ? -1 : Number(m[3]);
                v.Unit = m[4];
                break;
            case "variation":
                m = Match(@"(\d{3})V(\d{3})", text);
                if (m == null) return null;
                v.First = Number(m[1]);
                v.Second = Number(m[2]);
                break;
            case "visibility":
                if (text == "CAVOK")
                {
                    v.Kind = "cavok";
                    v.Meters = 10000;
                    v.Qualifier = "P";
                    break;
                }
                if (Match(@"\d{4}", text) != null)
                {
                    v.Kind = "meter";
                    v.Meters = Number(text);
                    if (v.Meters == 9999) { v.Meters = 10000; v.Qualifier = "P"; }
                    break;
                }
                v.Kind = "mile";
                m = Match(@"(\d) (\d)/(\d{1,2})SM", text);
                if (m != null)
                {
                    v.Whole = Number(m[1]);
                    v.Num = Number(m[2]);
                    v.Den = Number(m[3]);
                    v.Mixed = true;
                    v.Fractional = true;
                    break;
                }
                m = Match(@"([MP]?)(?:(\d{1,2})|(\d)/(\d{1,2}))SM", text);
                if (m == null) return null;
                v.Qualifier = m[1];
                v.Whole = Number(m[2]);
                v.Fractional = m[3] != "";
                if (v.Fractional) { v.Num = Number(m[3]); v.Den = Number(m[4]); }
                break;
            case "rvr":
                m = Match(@"R(\d{2}[LCR]?)/([MP]?)(\d{4})(?:V([MP]?)(\d{4}))?(FT)?([UDN])?", text);
                if (m == null) return null;
                v.Runway = m[1];
                v.Qualifier = m[2];
                v.First = Number(m[3]);
                v.HasSecond = m[5] != "";
                v.Qualifier2 = m[4];
                v.Second = Number(m[5]);
                v.Unit = m[6] == "" ? "m" : "ft";
                v.Trend = m[7];
                break;
            case "weather":
                if (text == "NSW") { v.Nsw = true; break; }
                string body = text;
                if (body.StartsWith("VC", StringComparison.Ordinal)) { v.Intensity = "VC"; body = body[2..]; }
                else if (body.StartsWith('-') || body.StartsWith('+')) { v.Intensity = body[..1]; body = body[1..]; }
                if (body.Length == 0 || body.Length % 2 != 0) return null;
                for (int i = 0; i < body.Length; i += 2)
                {
                    string code = body.Substring(i, 2);
                    if (!Descriptors.ContainsKey(code) && !Phenomena.ContainsKey(code)) return null;
                    v.Codes.Add(code);
                }
                if (Descriptors.ContainsKey(v.Codes[0]))
                {
                    v.Descriptor = v.Codes[0];
                    v.Codes.RemoveAt(0);
                }
                break;
            case "cloud":
                if (Clear.ContainsKey(text)) { v.Amount = text; break; }
                m = Match(@"(FEW|SCT|BKN|OVC)(\d{3})(CB|TCU)?", text);
                if (m != null)
                {
                    v.Amount = m[1];
                    v.Height = Number(m[2]) * 100;
                    v.Suffix = m[3];
                    break;
                }
                m = Match(@"VV(\d{3})", text);
                if (m == null) return null;
                v.Amount = "VV";
                v.Height = Number(m[1]) * 100;
                break;
            case "temperature":
                m = Match(@"(M?)(\d{2})/(M?)(\d{2})", text);
                if (m == null) return null;
                v.Temp = Number(m[2]) * (m[1] == "" ? 1 : -1);
                v.Dew = Number(m[4]) * (m[3] == "" ? 1 : -1);
                break;
            case "pressure":
                m = Match(@"([AQ])(\d{4})", text);
                if (m == null) return null;
                v.Unit = m[1];
                v.Number = Number(m[2]);
                break;
            case "noTrend":
                return text == "NOSIG" ? v : null;
            default:
                return null;
        }
        return v;
    }

    public static bool Valid(string kind, Value v, Section s, Station station)
    {
        switch (kind)
        {
            case "wind":
                if (v.Variable) { if (v.Speed < 1) return false; }
                else if (v.Direction > 360 || v.Direction % 10 != 0 || (v.Direction == 0) != (v.Speed == 0)) return false;
                return v.Gust < 0 || !v.Calm && v.Gust > v.Speed;
            case "variation":
                return v.First >= 10 && v.First <= 360 && v.First % 10 == 0 && v.Second >= 10 && v.Second <= 360
                    && v.Second % 10 == 0 && v.First != v.Second && s.Wind != null && !s.Wind.Variable && !s.Wind.Calm;
            case "visibility":
                if (v.Kind != "mile") return true;
                if (!v.Fractional) return v.Whole >= 1;
                return (v.Den is 2 or 4 or 8 or 16) && v.Num >= 1 && v.Num < v.Den && (!v.Mixed || v.Whole >= 1);
            case "rvr":
                return station.Runways.Any(r => r.Name == v.Runway) && (!v.HasSecond || v.First < v.Second);
            case "weather":
                var accepted = s.Weather ?? new List<Value>();
                if (accepted.Count >= 3 || accepted.Any(w => w.Nsw)) return false;
                if (v.Nsw) return accepted.Count == 0 && (s.Context is "trend" or "change");
                if (!v.Codes.All(Phenomena.ContainsKey) || v.Codes.Distinct().Count() != v.Codes.Count) return false;
                if (v.Codes.Count == 0 && v.Descriptor is not ("TS" or "SH")) return false;
                if ((v.Intensity is "-" or "+") && !v.Codes.Any(Precipitation.Contains)) return false;
                return v.Codes.Count < 2 || v.Codes.All(Precipitation.Contains);
            case "cloud":
                if (s.Cloud == null || s.Cloud.Count == 0) return true;
                var last = s.Cloud[^1];
                return Amounts.ContainsKey(v.Amount) && Amounts.ContainsKey(last.Amount) && v.Height > last.Height;
            case "temperature":
                return v.Dew <= v.Temp;
            case "pressure":
                return v.Unit == "A" ? v.Number >= 2500 && v.Number <= 3150 : v.Number >= 850 && v.Number <= 1070;
            default:
                return true;
        }
    }

    public static void Accept(Section s, string kind, Value v)
    {
        switch (kind)
        {
            case "modifier": s.Modifier = v; break;
            case "wind":
                if (v.Unit == "MPS")
                {
                    v.Speed = Units.Knots(v.Speed);
                    if (v.Gust >= 0) v.Gust = Units.Knots(v.Gust);
                }
                s.Wind = v;
                break;
            case "variation": s.Variation = v; break;
            case "visibility":
                s.Visibility = v;
                if (v.Kind == "cavok") { s.Weather = new(); s.Cloud = new(); }
                break;
            case "rvr": s.Rvr.Add(v); break;
            case "weather": (s.Weather ??= new()).Add(v); break;
            case "cloud": (s.Cloud ??= new()).Add(v); break;
            case "temperature": s.Temperature = v; break;
            case "pressure":
                v.Inches = v.Unit == "A" ? v.Number : Units.InHg(v.Number);
                v.Hecto = v.Unit == "Q" ? v.Number : Units.HPa(v.Number);
                s.Pressure = v;
                break;
            case "noTrend": s.NoTrend = true; break;
        }
    }
}
