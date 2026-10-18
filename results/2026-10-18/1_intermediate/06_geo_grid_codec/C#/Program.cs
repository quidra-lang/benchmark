using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

class Program {
    static readonly string GH="0123456789bcdefghjkmnpqrstuvwxyz", L24="ABCDEFGHJKLMNPQRSTUVWXYZ",
        PLUS="23456789CFGHJMPQRVWX", G25="ABCDEFGHJKLMNOPQRSTUVWXYZ", BANDS="CDEFGHJKLMNPQRSTUVWX",
        MROWS="ABCDEFGHJKLMNPQRSTUV";
    static readonly Dictionary<string,int[]> PRECISIONS = new() {
        ["GEOHASH"] = new[]{1,2,3,4,5,6,7,8,9}, ["MAIDENHEAD"] = new[]{2,4,6,8},
        ["PLUSCODE"] = new[]{2,4,6,8,10,11}, ["GARS"] = new[]{5,6,7},
        ["GEOREF"] = new[]{2,4,8,10,12}, ["MESH"] = new[]{4,6,8,9,10,11}
    };
    static readonly long[] MESH_SCALE={1,8,80,160,320,640};
    static readonly string[] MAIDEN={"ABCDEFGHIJKLMNOPQR","0123456789","abcdefghijklmnopqrstuvwx","0123456789"};
    record Cell(string system, int level, long x, long y, long w, long h);
    class Invalid : Exception {}
    static void require(bool condition) { if (!condition) throw new Invalid(); }
    static long integer(string s) {
        require(matches(s,"-?[0-9]{1,9}"));
        return long.Parse(s);
    }
    static long range(string s, long low, long high) {
        long value = integer(s);
        require(value >= low && value <= high);
        return value;
    }
    static long coordinate(string s, bool latitude) {
        require(matches(s,"-?[0-9]{1,3}(\\.[0-9]{1,6})?"));
        bool negative = s.StartsWith("-");
        string[] pieces = (negative ? s.Substring(1) : s).Split('.');
        long value = long.Parse(pieces[0])*1000000;
        if (pieces.Length == 2) value += long.Parse(pieces[1]+new string('0',6-pieces[1].Length));
        if (negative) value = -value;
        require(latitude ? value >= -90000000 && value <= 90000000 : value >= -180000000 && value < 180000000);
        return value;
    }
    static int[] precisions(string system) {
        int[] result = PRECISIONS.GetValueOrDefault(system);
        require(result != null);
        return result;
    }
    static int level(string system, long precision) {
        int[] values = precisions(system);
        for (int i = 0; i < values.Length; i++) if (values[i] == precision) return i;
        throw new Invalid();
    }
    static Cell grid(string system, int level, long x, long y) {
        int p = precisions(system)[level];
        long w, h;
        switch (system) {
            case "GEOHASH":
                w=1L<<((5*p+1)/2);
                h=1L<<(5*p/2);
                break;
            case "MAIDENHEAD":
                w=new long[]{18,180,4320,43200}[level];
                h=w;
                break;
            case "PLUSCODE":
                w=new long[]{18,360,7200,144000,2880000,11520000}[level];
                h=new long[]{9,180,3600,72000,1440000,7200000}[level];
                break;
            case "GARS":
                w=new long[]{720,1440,4320}[level];
                h=new long[]{360,720,2160}[level];
                break;
            case "GEOREF":
                w=new long[]{24,360,21600,216000,2160000}[level];
                h=new long[]{12,180,10800,108000,1080000}[level];
                break;
            default:
                w=360*MESH_SCALE[level];
                h=270*MESH_SCALE[level];
                break;
        }
        return new Cell(system,level,x,y,w,h);
    }
    static Cell point(string system, int level, long latitude, long longitude) {
        Cell g = grid(system,level,0,0);
        return grid(system,level,(longitude+180000000)*g.w/360000000,
            Math.Min((latitude+90000000)*g.h/180000000,g.h-1));
    }
    static int digit(char c, string alphabet) {
        int value = alphabet.IndexOf(c);
        require(value >= 0);
        return value;
    }
    static long digits(string s) {
        require(s.Length != 0 && s.All(c => c >= '0' && c <= '9'));
        return long.Parse(s);
    }
    static string pad(long n, int width) {
        string s = n.ToString();
        return new string('0',Math.Max(0,width-s.Length))+s;
    }
    static long power(int n) {
        long result = 1;
        for (int i = 0; i < n; i++) result *= 10;
        return result;
    }
    static long[] radix(long value, long[] bases, int count) {
        long[] result = new long[count];
        for (int i = count-1; i >= 0; i--) {
            result[i] = value%bases[i];
            value /= bases[i];
        }
        return result;
    }
    static string code(Cell c) {
        string system = c.system;
        int p = precisions(system)[c.level];
        long x = c.x, y = c.y;
        StringBuilder result = new StringBuilder();
        switch (system) {
            case "GEOHASH": {
                int ax=(5*p+1)/2, ay=5*p/2, group=0;
                for (int bit = 0; bit < 5*p; bit++) {
                    int b = bit%2 == 0 ? (int)(x>>(--ax)&1) : (int)(y>>(--ay)&1);
                    group = group*2+b;
                    if (bit%5 == 4) {
                        result.Append(GH[group]);
                        group=0;
                    }
                }
                return result.ToString();
            }
            case "MAIDENHEAD": {
                int count=p/2;
                long[] a=radix(x,new long[]{18,10,24,10},count), b=radix(y,new long[]{18,10,24,10},count);
                for (int i=0;i<count;i++) result.Append(MAIDEN[i][(int)a[i]]).Append(MAIDEN[i][(int)b[i]]);
                return result.ToString();
            }
            case "PLUSCODE": {
                int extra = p == 11 ? (int)(4*(y%5)+x%4) : -1;
                if (p == 11) {
                    x/=4;
                    y/=5;
                }
                int count=Math.Min(p,10)/2;
                long[] a=radix(x,new long[]{18,20,20,20,20},count), b=radix(y,new long[]{9,20,20,20,20},count);
                for (int i=0;i<count;i++) result.Append(PLUS[(int)b[i]]).Append(PLUS[(int)a[i]]);
                if (extra >= 0) result.Append(PLUS[extra]);
                string text=result.ToString();
                return p < 8 ? text+new string('0',8-p)+"+" : text.Substring(0,8)+"+"+text.Substring(8);
            }
            case "GARS": {
                long scale=c.level==0 ? 1 : c.level==1 ? 2 : 6;
                long bx=x/scale, by=y/scale;
                result.Append(pad(bx+1,3)).Append(L24[(int)(by/24)]).Append(L24[(int)(by%24)]);
                if (p>=6) {
                    long divisor=p==7 ? 3 : 1;
                    result.Append(1+x/divisor%2+2*(1-y/divisor%2));
                }
                if (p==7) result.Append(1+x%3+3*(2-y%3));
                return result.ToString();
            }
            case "GEOREF": {
                if (p==2) return ""+L24[(int)x]+L24[(int)y];
                int m=(p-4)/2;
                long scale=p==4 ? 1 : 6*power(m-1), bx=x/scale, by=y/scale;
                result.Append(L24[(int)(bx/15)]).Append(L24[(int)(by/15)])
                    .Append(L24[(int)(bx%15)]).Append(L24[(int)(by%15)]);
                if (p>=8) result.Append(pad(x%scale,m)).Append(pad(y%scale,m));
                return result.ToString();
            }
            default: {
                long scale=MESH_SCALE[c.level], u=x-280*scale, v=y-135*scale;
                if (u<0 || u>=80*scale || v<0 || v>=100*scale) return null;
                int count=c.level+1;
                long[] a=radix(u,new long[]{80,8,10,2,2,2},count), b=radix(v,new long[]{100,8,10,2,2,2},count);
                result.Append(pad(b[0],2)).Append(pad(a[0],2));
                for (int i=1;i<count;i++) {
                    if (i<=2) result.Append(b[i]).Append(a[i]);
                    else result.Append(1+a[i]+2*b[i]);
                }
                return result.ToString();
            }
        }
    }
    static Cell decode(string system, string text) {
        precisions(system);
        int p=text.Length;
        long x=0,y=0;
        switch (system) {
            case "GEOHASH": {
                require(p>=1 && p<=9);
                int bit=0;
                foreach (char ch in text) {
                    int d=digit(ch,GH);
                    for (int i=4;i>=0;i--) {
                        if (bit%2==0) x=x*2+(d>>i&1);
                        else y=y*2+(d>>i&1);
                        bit++;
                    }
                }
                break;
            }
            case "MAIDENHEAD": {
                level(system,p);
                for (int i=0;i<p/2;i++) {
                    x=x*MAIDEN[i].Length+digit(text[2*i],MAIDEN[i]);
                    y=y*MAIDEN[i].Length+digit(text[2*i+1],MAIDEN[i]);
                }
                break;
            }
            case "PLUSCODE": {
                require(p>=9 && text.IndexOf('+')==8 && text.LastIndexOf('+')==8);
                int firstZero=text.Substring(0,8).IndexOf('0');
                int before=firstZero<0 ? 8 : firstZero, after=p-9;
                require(before==2 || before==4 || before==6 || before==8);
                require(before==8 ? after==0 || after==2 || after==3 : after==0);
                for (int i=before;i<8;i++) require(text[i]=='0');
                string sequence=text.Substring(0,before)+text.Substring(9);
                p=sequence.Length;
                require(digit(sequence[0],PLUS)<=8 && digit(sequence[1],PLUS)<=17);
                for (int i=0;i<Math.Min(p,10);i+=2) {
                    y=y*20+digit(sequence[i],PLUS);
                    x=x*20+digit(sequence[i+1],PLUS);
                }
                if (p==11) {
                    int d=digit(sequence[10],PLUS);
                    x=x*4+d%4;
                    y=y*5+d/4;
                }
                break;
            }
            case "GARS": {
                require(p>=5 && p<=7);
                long e=digits(text.Substring(0,3));
                require(e>=1 && e<=720);
                x=e-1;
                y=digit(text[3],L24.Substring(0,15))*24+digit(text[4],L24);
                if (p>=6) {
                    int q=digit(text[5],"1234");
                    x=x*2+q%2;
                    y=y*2+1-q/2;
                }
                if (p==7) {
                    int q=digit(text[6],"123456789");
                    x=x*3+q%3;
                    y=y*3+2-q/3;
                }
                break;
            }
            case "GEOREF": {
                level(system,p);
                x=digit(text[0],L24);
                y=digit(text[1],L24.Substring(0,12));
                if (p>=4) {
                    x=x*15+digit(text[2],L24.Substring(0,15));
                    y=y*15+digit(text[3],L24.Substring(0,15));
                }
                if (p>=8) {
                    int m=(p-4)/2;
                    long scale=6*power(m-1), a=digits(text.Substring(4,m)), b=digits(text.Substring(4+m));
                    require(a<scale && b<scale);
                    x=x*scale+a;
                    y=y*scale+b;
                }
                break;
            }
            default: {
                int l=level(system,p);
                digits(text);
                long v=digits(text.Substring(0,2)), u=digits(text.Substring(2,2));
                require(u<80);
                if (p>=6) {
                    v=v*8+digit(text[4],"01234567");
                    u=u*8+digit(text[5],"01234567");
                }
                if (p>=8) {
                    v=v*10+digit(text[6],"0123456789");
                    u=u*10+digit(text[7],"0123456789");
                }
                for (int i=8;i<p;i++) {
                    int q=digit(text[i],"1234");
                    v=v*2+q/2;
                    u=u*2+q%2;
                }
                x=u+280*MESH_SCALE[l];
                y=v+135*MESH_SCALE[l];
                break;
            }
        }
        Cell result=grid(system,level(system,p),x,y);
        require(text.Equals(code(result)));
        return result;
    }
    static Cell ancestor(Cell c, int level) {
        Cell g=grid(c.system,level,0,0);
        return grid(c.system,level,c.x*g.w/c.w,c.y*g.h/c.h);
    }
    static string shown(Cell c) { string result=code(c); return result==null ? "-" : result; }
    static string coordinateFormat(long n) { return (n<0 ? "-" : "")+Math.Abs(n)/1000000+"."+pad(Math.Abs(n)%1000000,6); }
    static long boundary(Cell c, bool latitude, int offset, bool center) {
        long extent=latitude ? 180000000 : 360000000, total=latitude ? c.h : c.w, value=latitude ? c.y : c.x;
        return -extent/2+(center ? extent*(2*value+1)/(2*total) : extent*(value+offset)/total);
    }
    static int compare(long a, long ad, long b, long bd) { return (a*bd).CompareTo(b*ad); }
    static bool inside(Cell a, Cell b) {
        return compare(a.x,a.w,b.x,b.w)>=0 && compare(a.x+1,a.w,b.x+1,b.w)<=0 &&
            compare(a.y,a.h,b.y,b.h)>=0 && compare(a.y+1,a.h,b.y+1,b.h)<=0;
    }
    static long[] steps(Cell a, Cell b) {
        long dx=mod(b.x-a.x,a.w);
        if (dx>a.w/2) dx-=a.w;
        return new long[]{dx,b.y-a.y};
    }
    static long[] detail(string a, string b) {
        require(matches(a,"[0-9]{1,5}") && matches(b,"[0-9]{1,5}") && a.Length==b.Length);
        long size=power(5-a.Length);
        return new long[]{digits(a)*size,digits(b)*size,size};
    }
    static string columns(long zone) { return zone%3==1 ? "ABCDEFGH" : zone%3==2 ? "JKLMNPQR" : "STUVWXYZ"; }
    static string auxiliary(string[] t) {
        string command=t[0];
        int n=t.Length-1;
        switch (command) {
            case "UTMZONE": {
                require(n==2);
                long lat=coordinate(t[1],true), lon=coordinate(t[2],false);
                if (lat< -80000000 || lat>=84000000) return "NONE";
                char band=BANDS[(int)Math.Min((lat+80000000)/8000000,19)];
                long zone=(lon+180000000)/6000000+1;
                if (band=='V' && lon>=3000000 && lon<12000000) zone=32;
                if (band=='X') {
                    if (lon>=0 && lon<9000000) zone=31;
                    else if (lon>=9000000 && lon<21000000) zone=33;
                    else if (lon>=21000000 && lon<33000000) zone=35;
                    else if (lon>=33000000 && lon<42000000) zone=37;
                }
                return zone+band.ToString();
            }
            case "OSGB": {
                require(n==3);
                long e=range(t[1],0,699999), north=range(t[2],0,1299999);
                int d=(int)range(t[3],0,5);
                string letters=""+G25[(int)((3-north/500000)*5+2+e/500000)]+G25[(int)((4-north/100000%5)*5+e/100000%5)];
                return letters+(d==0 ? "" : " "+pad(e%100000,5).Substring(0,d)+" "+pad(north%100000,5).Substring(0,d));
            }
            case "UNOSGB": {
                require(n==1 || n==3);
                require(t[1].Length==2);
                int a=digit(t[1][0],G25), b=digit(t[1][1],G25);
                long e=500000*(a%5-2)+100000*(b%5), north=500000*(3-a/5)+100000*(4-b/5), size=100000;
                require(e>=0 && e<700000 && north>=0 && north<1300000);
                if (n==3) {
                    long[] values=detail(t[2],t[3]);
                    e+=values[0];
                    north+=values[1];
                    size=values[2];
                }
                return "sw="+e+","+north+" size="+size;
            }
            case "MGRS": {
                require(n==5);
                long zone=range(t[1],1,60), e=range(t[3],100000,899999), north=range(t[4],0,9999999);
                require(t[2].Length==1);
                digit(t[2][0],BANDS);
                int d=(int)range(t[5],0,5), offset=zone%2==0 ? 5 : 0;
                string square=""+columns(zone)[(int)(e/100000-1)]+MROWS[(int)((north/100000+offset)%20)];
                return zone+t[2]+" "+square+(d==0 ? "" : " "+pad(e%100000,5).Substring(0,d)+" "+pad(north%100000,5).Substring(0,d));
            }
            case "UNMGRS": {
                require(n==2 || n==4);
                require(matches(t[1],"[1-9][0-9]?[CDEFGHJKLMNPQRSTUVWX]"));
                long zone=long.Parse(t[1].Substring(0,t[1].Length-1));
                require(zone<=60 && t[2].Length==2);
                int a=digit(t[2][0],columns(zone)), b=digit(t[2][1],MROWS), offset=zone%2==0 ? 5 : 0;
                long e=100000*(a+1), north=100000*mod(b-offset,20), size=100000;
                if (n==4) {
                    long[] values=detail(t[3],t[4]);
                    e+=values[0];
                    north+=values[1];
                    size=values[2];
                }
                return t[1]+" sw="+e+","+north+" size="+size;
            }
            case "QUADKEY": {
                require(n==3);
                int z=(int)range(t[3],1,23);
                long x=range(t[1],0,(1L<<z)-1), y=range(t[2],0,(1L<<z)-1);
                StringBuilder result=new StringBuilder();
                for (int i=z-1;i>=0;i--) result.Append((x>>i&1)+2*(y>>i&1));
                return result.ToString();
            }
            case "UNQUADKEY": {
                require(n==1 && matches(t[1],"[0-3]{1,23}"));
                long x=0,y=0;
                foreach (char c in t[1]) {
                    int d=c-'0';
                    x=x*2+d%2;
                    y=y*2+d/2;
                }
                return "x="+x+" y="+y+" z="+t[1].Length;
            }
            default: throw new Invalid();
        }
    }
    static string execute(string line) {
        string[] t=line.Split(' ');
        string command=t[0];
        Dictionary<string,int> counts = new() {
            ["ENCODE"]=4, ["DECODE"]=2, ["NEIGHBORS"]=2, ["PARENT"]=2, ["CHILDREN"]=2,
            ["COMMON"]=3, ["CONTAINS"]=4, ["COVER"]=6, ["CONVERT"]=5, ["STEPS"]=3,
            ["PATH"]=3, ["RELATE"]=4, ["SIZE"]=2, ["SHORTEN"]=3, ["RECOVER"]=3
        };
        if (!counts.ContainsKey(command) && !command.Equals("COMPACT")) return auxiliary(t);
        if (command.Equals("COMPACT")) require(t.Length>=3 && t.Length<=102);
        else require(t.Length==counts[command]+1);
        if (command.Equals("SHORTEN") || command.Equals("RECOVER")) {
            long lat=coordinate(t[2],true), lon=coordinate(t[3],false);
            if (command.Equals("SHORTEN")) {
                Cell cShort=decode("PLUSCODE",t[1]);
                require(precisions(cShort.system)[cShort.level]>=8);
                long ynShort= -90000000*2*cShort.h+180000000*(2*cShort.y+1), xnShort= -180000000*2*cShort.w+360000000*(2*cShort.x+1);
                if (Math.Abs(ynShort-lat*2*cShort.h)<15000*2*cShort.h && Math.Abs(xnShort-lon*2*cShort.w)<15000*2*cShort.w) return t[1].Substring(6);
                if (Math.Abs(ynShort-lat*2*cShort.h)<300000*2*cShort.h && Math.Abs(xnShort-lon*2*cShort.w)<300000*2*cShort.w) return t[1].Substring(4);
                return t[1];
            }
            int plus=t[1].IndexOf('+');
            require(plus==2 || plus==4);
            require(t[1].LastIndexOf('+')==plus);
            int tail=t[1].Length-plus-1;
            require(tail==0 || tail==2 || tail==3);
            foreach (char ch in t[1].Replace("+","")) digit(ch,PLUS);
            int missing=8-plus;
            string prefix=code(point("PLUSCODE",4,lat,lon)).Substring(0,missing);
            Cell c=decode("PLUSCODE",prefix+t[1]);
            long d=missing==4 ? 1000000 : 50000, x=c.x, y=c.y;
            long yn= -90000000*2*c.h+180000000*(2*y+1), xn= -180000000*2*c.w+360000000*(2*x+1);
            long my=d*c.h/180000000, mx=d*c.w/360000000;
            if ((lat+d/2)*2*c.h<yn && yn-d*2*c.h>= -90000000*2*c.h) y-=my;
            else if ((lat-d/2)*2*c.h>yn && yn+d*2*c.h<=90000000*2*c.h) y+=my;
            if ((lon+d/2)*2*c.w<xn) x=mod(x-mx,c.w);
            else if ((lon-d/2)*2*c.w>xn) x=mod(x+mx,c.w);
            return code(grid("PLUSCODE",c.level,x,y));
        }
        string system=t[1];
        precisions(system);
        if (command.Equals("ENCODE")) {
            Cell c=point(system,level(system,integer(t[4])),coordinate(t[2],true),coordinate(t[3],false));
            string encoded=code(c);
            return encoded==null ? "OUT OF AREA" : encoded;
        }
        if (command.Equals("SIZE")) {
            int l=level(system,integer(t[2]));
            Cell c=grid(system,l,0,0);
            long count=system.Equals("MESH") ? 8000*MESH_SCALE[l]*MESH_SCALE[l] : c.w*c.h;
            return "w="+coordinateFormat(360000000/c.w)+" h="+coordinateFormat(180000000/c.h)+" cells="+count;
        }
        if (command.Equals("COVER")) {
            int l=level(system,integer(t[2]));
            long lat1=coordinate(t[3],true), lon1=coordinate(t[4],false), lat2=coordinate(t[5],true), lon2=coordinate(t[6],false);
            require(lat1<=lat2);
            Cell a=point(system,l,lat1,lon1), b=point(system,l,lat2,lon2);
            long columns=lon1<=lon2 ? b.x-a.x+1 : Math.Min(a.w,b.x-a.x+1+a.w);
            if (columns*(b.y-a.y+1)>100) return "TOO MANY";
            List<string> result=new();
            for (long y=b.y;y>=a.y;y--) {
                for (long i=0;i<columns;i++) result.Add(shown(grid(system,l,(a.x+i)%a.w,y)));
            }
            return string.Join(" ",result);
        }
        if (command.Equals("COMPACT")) {
            HashSet<Cell> cells=new();
            for (int i=2;i<t.Length;i++) cells.Add(decode(system,t[i]));
            HashSet<Cell> covered = new();
            foreach (Cell c in cells) {
                foreach (Cell a in cells) {
                    if (a.level<c.level && ancestor(c,a.level).Equals(a)) covered.Add(c);
                }
            }
            cells.ExceptWith(covered);
            bool changed=true;
            while (changed) {
                changed=false;
                foreach (Cell child in cells.ToList()) {
                    if (child.level==0) continue;
                    Cell parent=ancestor(child,child.level-1), g=grid(system,child.level,0,0);
                    long rx=g.w/parent.w, ry=g.h/parent.h;
                    if (rx*ry>cells.Count) continue;
                    HashSet<Cell> siblings=new();
                    for (long j=0;j<ry;j++) {
                        for (long i=0;i<rx;i++) siblings.Add(grid(system,child.level,parent.x*rx+i,parent.y*ry+j));
                    }
                    if (cells.IsSupersetOf(siblings)) {
                        cells.ExceptWith(siblings);
                        cells.Add(parent);
                        changed=true;
                        break;
                    }
                }
            }
            List<Cell> result=new(cells);
            result = result.OrderBy(c => c.level).ThenByDescending(c => c.y).ThenBy(c => c.x).ToList();
            return string.Join(" ",result.Select(code));
        }
        Cell primary=decode(system,t[2]);
        switch (command) {
            case "DECODE": return "sw="+coordinateFormat(boundary(primary,true,0,false))+","+coordinateFormat(boundary(primary,false,0,false))+
                " ne="+coordinateFormat(boundary(primary,true,1,false))+","+coordinateFormat(boundary(primary,false,1,false))+
                " c="+coordinateFormat(boundary(primary,true,0,true))+","+coordinateFormat(boundary(primary,false,0,true));
            case "NEIGHBORS": {
                int[] dx={0,1,1,1,0,-1,-1,-1}, dy={1,1,0,-1,-1,-1,0,1};
                List<string> result=new();
                for (int i=0;i<8;i++) result.Add(primary.y+dy[i]<0 || primary.y+dy[i]>=primary.h ? "-" : shown(grid(system,primary.level,mod(primary.x+dx[i],primary.w),primary.y+dy[i])));
                return string.Join(" ",result);
            }
            case "PARENT": return primary.level==0 ? "NONE" : code(ancestor(primary,primary.level-1));
            case "CHILDREN": {
                if (primary.level+1==precisions(system).Length) return "NONE";
                Cell g=grid(system,primary.level+1,0,0);
                long rx=g.w/primary.w, ry=g.h/primary.h;
                if (rx*ry>100) return "TOO MANY";
                List<string> result=new();
                for (long j=ry-1;j>=0;j--) {
                    for (long i=0;i<rx;i++) result.Add(shown(grid(system,g.level,primary.x*rx+i,primary.y*ry+j)));
                }
                return string.Join(" ",result);
            }
            case "COMMON": {
                Cell b=decode(system,t[3]);
                for (int l=Math.Min(primary.level,b.level);l>=0;l--) {
                    Cell parent=ancestor(primary,l);
                    if (parent.Equals(ancestor(b,l))) return code(parent);
                }
                return "NONE";
            }
            case "CONTAINS": return primary.Equals(point(system,primary.level,coordinate(t[3],true),coordinate(t[4],false))) ? "YES" : "NO";
            case "CONVERT": {
                require(t[3].Equals("TO"));
                Cell g=grid(t[4],level(t[4],integer(t[5])),0,0);
                string result=code(grid(g.system,g.level,(2*primary.x+1)*g.w/(2*primary.w),(2*primary.y+1)*g.h/(2*primary.h)));
                return result==null ? "OUT OF AREA" : result;
            }
            case "STEPS":
            case "PATH": {
                Cell b=decode(system,t[3]);
                if (primary.level!=b.level) return "MISMATCH";
                long[] delta=steps(primary,b);
                if (command.Equals("STEPS")) return "dx="+delta[0]+" dy="+delta[1];
                long n=Math.Max(Math.Abs(delta[0]),Math.Abs(delta[1]));
                if (n+1>100) return "TOO MANY";
                List<string> result=new();
                for (long i=0;i<=n;i++) {
                    long dx=n==0 ? 0 : floor(2*i*delta[0]+n,2*n), dy=n==0 ? 0 : floor(2*i*delta[1]+n,2*n);
                    result.Add(shown(grid(system,primary.level,mod(primary.x+dx,primary.w),primary.y+dy)));
                }
                return string.Join(" ",result);
            }
            case "RELATE": {
                Cell b=decode(t[3],t[4]);
                bool ab=inside(primary,b), ba=inside(b,primary);
                if (ab && ba) return "EQUAL";
                if (ab) return "INSIDE";
                if (ba) return "CONTAINS";
                int ew=compare(primary.x+1,primary.w,b.x,b.w), we=compare(b.x+1,b.w,primary.x,primary.w);
                int ns=compare(primary.y+1,primary.h,b.y,b.h), sn=compare(b.y+1,b.h,primary.y,primary.h);
                if (ew>0 && we>0 && ns>0 && sn>0) return "OVERLAP";
                bool dateline=primary.x+1==primary.w && b.x==0 || b.x+1==b.w && primary.x==0;
                return ns>=0 && sn>=0 && (ew>=0 && we>=0 || dateline) ? "TOUCH" : "DISJOINT";
            }
            default: throw new Invalid();
        }
    }
    static bool matches(string s, string pattern) => Regex.IsMatch(s,"\\A(?:"+pattern+")\\z",RegexOptions.CultureInvariant);
    static long mod(long a, long n) => (a%n+n)%n;
    static long floor(long a, long n) => a/n-(a%n<0 ? 1 : 0);
    static void Main() {
        CultureInfo.CurrentCulture=CultureInfo.InvariantCulture;
        int n=int.Parse(Console.ReadLine()!);
        for (int i=0;i<n;i++) {
            try { Console.WriteLine(execute(Console.ReadLine()!)); }
            catch (Invalid) { Console.WriteLine("INVALID"); }
        }
    }
}
