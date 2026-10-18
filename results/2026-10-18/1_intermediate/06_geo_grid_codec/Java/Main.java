import java.io.*;
import java.util.*;

public class Main {
    static final String GH="0123456789bcdefghjkmnpqrstuvwxyz", L24="ABCDEFGHJKLMNPQRSTUVWXYZ",
        PLUS="23456789CFGHJMPQRVWX", G25="ABCDEFGHJKLMNOPQRSTUVWXYZ", BANDS="CDEFGHJKLMNPQRSTUVWX",
        MROWS="ABCDEFGHJKLMNPQRSTUV";
    static final Map<String,int[]> PRECISIONS = Map.of(
        "GEOHASH",new int[]{1,2,3,4,5,6,7,8,9},"MAIDENHEAD",new int[]{2,4,6,8},
        "PLUSCODE",new int[]{2,4,6,8,10,11},"GARS",new int[]{5,6,7},
        "GEOREF",new int[]{2,4,8,10,12},"MESH",new int[]{4,6,8,9,10,11});
    static final long[] MESH_SCALE={1,8,80,160,320,640};
    static final String[] MAIDEN={"ABCDEFGHIJKLMNOPQR","0123456789","abcdefghijklmnopqrstuvwx","0123456789"};
    static final Map<String,Integer> counts=Map.ofEntries(Map.entry("ENCODE",4),Map.entry("DECODE",2),Map.entry("NEIGHBORS",2),
            Map.entry("PARENT",2),Map.entry("CHILDREN",2),Map.entry("COMMON",3),Map.entry("CONTAINS",4),
            Map.entry("COVER",6),Map.entry("CONVERT",5),Map.entry("STEPS",3),Map.entry("PATH",3),Map.entry("RELATE",4),
            Map.entry("SIZE",2),Map.entry("SHORTEN",3),Map.entry("RECOVER",3));
    record Cell(String system, int level, long x, long y, long w, long h) {}
    static class Invalid extends RuntimeException {}
    static void require(boolean condition) { if (!condition) throw new Invalid(); }
    static long integer(String s) {
        require(s.matches("-?[0-9]{1,9}"));
        return Long.parseLong(s);
    }
    static long range(String s, long low, long high) {
        long value = integer(s);
        require(value >= low && value <= high);
        return value;
    }
    static long coordinate(String s, boolean latitude) {
        require(s.matches("-?[0-9]{1,3}(\\.[0-9]{1,6})?"));
        boolean negative = s.startsWith("-");
        String[] pieces = (negative ? s.substring(1) : s).split("\\.");
        long value = Long.parseLong(pieces[0])*1000000;
        if (pieces.length == 2) value += Long.parseLong(pieces[1]+"0".repeat(6-pieces[1].length()));
        if (negative) value = -value;
        require(latitude ? value >= -90000000 && value <= 90000000 : value >= -180000000 && value < 180000000);
        return value;
    }
    static int[] precisions(String system) {
        int[] result = PRECISIONS.get(system);
        require(result != null);
        return result;
    }
    static int level(String system, long precision) {
        int result = Arrays.binarySearch(precisions(system),(int)precision);
        require(result >= 0);
        return result;
    }
    static Cell grid(String system, int level, long x, long y) {
        int p = precisions(system)[level];
        long w, h;
        switch (system) {
            case "GEOHASH" -> {
                w=1L<<((5*p+1)/2);
                h=1L<<(5*p/2);
            }
            case "MAIDENHEAD" -> {
                w=(new long[]{18,180,4320,43200})[level];
                h=w;
            }
            case "PLUSCODE" -> {
                w=(new long[]{18,360,7200,144000,2880000,11520000})[level];
                h=(new long[]{9,180,3600,72000,1440000,7200000})[level];
            }
            case "GARS" -> {
                w=(new long[]{720,1440,4320})[level];
                h=(new long[]{360,720,2160})[level];
            }
            case "GEOREF" -> {
                w=(new long[]{24,360,21600,216000,2160000})[level];
                h=(new long[]{12,180,10800,108000,1080000})[level];
            }
            default -> {
                w=360*MESH_SCALE[level];
                h=270*MESH_SCALE[level];
            }
        }
        return new Cell(system,level,x,y,w,h);
    }
    static Cell point(String system, int level, long latitude, long longitude) {
        Cell g = grid(system,level,0,0);
        return grid(system,level,(longitude+180000000)*g.w()/360000000,
            Math.min((latitude+90000000)*g.h()/180000000,g.h()-1));
    }
    static int digit(char c, String alphabet) {
        int value = alphabet.indexOf(c);
        require(value >= 0);
        return value;
    }
    static long digits(String s) {
        require(!s.isEmpty() && s.chars().allMatch(c -> c >= '0' && c <= '9'));
        return Long.parseLong(s);
    }
    static String pad(long n, int width) { return String.format(Locale.ROOT,"%0"+width+"d",n); }
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
    static String code(Cell c) {
        String system = c.system();
        int p = precisions(system)[c.level()];
        long x = c.x(), y = c.y();
        StringBuilder result = new StringBuilder();
        switch (system) {
            case "GEOHASH": {
                int ax=(5*p+1)/2, ay=5*p/2, group=0;
                for (int bit = 0; bit < 5*p; bit++) {
                    int b = bit%2 == 0 ? (int)(x>>(--ax)&1) : (int)(y>>(--ay)&1);
                    group = group*2+b;
                    if (bit%5 == 4) {
                        result.append(GH.charAt(group));
                        group=0;
                    }
                }
                return result.toString();
            }
            case "MAIDENHEAD": {
                int count=p/2;
                long[] a=radix(x,new long[]{18,10,24,10},count), b=radix(y,new long[]{18,10,24,10},count);
                for (int i=0;i<count;i++) result.append(MAIDEN[i].charAt((int)a[i])).append(MAIDEN[i].charAt((int)b[i]));
                return result.toString();
            }
            case "PLUSCODE": {
                int extra = p == 11 ? (int)(4*(y%5)+x%4) : -1;
                if (p == 11) {
                    x/=4;
                    y/=5;
                }
                int count=Math.min(p,10)/2;
                long[] a=radix(x,new long[]{18,20,20,20,20},count), b=radix(y,new long[]{9,20,20,20,20},count);
                for (int i=0;i<count;i++) result.append(PLUS.charAt((int)b[i])).append(PLUS.charAt((int)a[i]));
                if (extra >= 0) result.append(PLUS.charAt(extra));
                String text=result.toString();
                return p < 8 ? text+"0".repeat(8-p)+"+" : text.substring(0,8)+"+"+text.substring(8);
            }
            case "GARS": {
                long scale=c.level()==0 ? 1 : c.level()==1 ? 2 : 6;
                long bx=x/scale, by=y/scale;
                result.append(pad(bx+1,3)).append(L24.charAt((int)(by/24))).append(L24.charAt((int)(by%24)));
                if (p>=6) {
                    long divisor=p==7 ? 3 : 1;
                    result.append(1+x/divisor%2+2*(1-y/divisor%2));
                }
                if (p==7) result.append(1+x%3+3*(2-y%3));
                return result.toString();
            }
            case "GEOREF": {
                if (p==2) return ""+L24.charAt((int)x)+L24.charAt((int)y);
                int m=(p-4)/2;
                long scale=p==4 ? 1 : 6*power(m-1), bx=x/scale, by=y/scale;
                result.append(L24.charAt((int)(bx/15))).append(L24.charAt((int)(by/15)))
                    .append(L24.charAt((int)(bx%15))).append(L24.charAt((int)(by%15)));
                if (p>=8) result.append(pad(x%scale,m)).append(pad(y%scale,m));
                return result.toString();
            }
            default: {
                long scale=MESH_SCALE[c.level()], u=x-280*scale, v=y-135*scale;
                if (u<0 || u>=80*scale || v<0 || v>=100*scale) return null;
                int count=c.level()+1;
                long[] a=radix(u,new long[]{80,8,10,2,2,2},count), b=radix(v,new long[]{100,8,10,2,2,2},count);
                result.append(pad(b[0],2)).append(pad(a[0],2));
                for (int i=1;i<count;i++) {
                    if (i<=2) result.append(b[i]).append(a[i]);
                    else result.append(1+a[i]+2*b[i]);
                }
                return result.toString();
            }
        }
    }
    static Cell decode(String system, String text) {
        precisions(system);
        int p=text.length();
        long x=0,y=0;
        switch (system) {
            case "GEOHASH": {
                require(p>=1 && p<=9);
                int bit=0;
                for (char ch:text.toCharArray()) {
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
                    x=x*MAIDEN[i].length()+digit(text.charAt(2*i),MAIDEN[i]);
                    y=y*MAIDEN[i].length()+digit(text.charAt(2*i+1),MAIDEN[i]);
                }
                break;
            }
            case "PLUSCODE": {
                require(p>=9 && text.indexOf('+')==8 && text.lastIndexOf('+')==8);
                int firstZero=text.substring(0,8).indexOf('0');
                int before=firstZero<0 ? 8 : firstZero, after=p-9;
                require(before==2 || before==4 || before==6 || before==8);
                require(before==8 ? after==0 || after==2 || after==3 : after==0);
                for (int i=before;i<8;i++) require(text.charAt(i)=='0');
                String sequence=text.substring(0,before)+text.substring(9);
                p=sequence.length();
                require(digit(sequence.charAt(0),PLUS)<=8 && digit(sequence.charAt(1),PLUS)<=17);
                for (int i=0;i<Math.min(p,10);i+=2) {
                    y=y*20+digit(sequence.charAt(i),PLUS);
                    x=x*20+digit(sequence.charAt(i+1),PLUS);
                }
                if (p==11) {
                    int d=digit(sequence.charAt(10),PLUS);
                    x=x*4+d%4;
                    y=y*5+d/4;
                }
                break;
            }
            case "GARS": {
                require(p>=5 && p<=7);
                long e=digits(text.substring(0,3));
                require(e>=1 && e<=720);
                x=e-1;
                y=digit(text.charAt(3),L24.substring(0,15))*24+digit(text.charAt(4),L24);
                if (p>=6) {
                    int q=digit(text.charAt(5),"1234");
                    x=x*2+q%2;
                    y=y*2+1-q/2;
                }
                if (p==7) {
                    int q=digit(text.charAt(6),"123456789");
                    x=x*3+q%3;
                    y=y*3+2-q/3;
                }
                break;
            }
            case "GEOREF": {
                level(system,p);
                x=digit(text.charAt(0),L24);
                y=digit(text.charAt(1),L24.substring(0,12));
                if (p>=4) {
                    x=x*15+digit(text.charAt(2),L24.substring(0,15));
                    y=y*15+digit(text.charAt(3),L24.substring(0,15));
                }
                if (p>=8) {
                    int m=(p-4)/2;
                    long scale=6*power(m-1), a=digits(text.substring(4,4+m)), b=digits(text.substring(4+m));
                    require(a<scale && b<scale);
                    x=x*scale+a;
                    y=y*scale+b;
                }
                break;
            }
            default: {
                int l=level(system,p);
                digits(text);
                long v=digits(text.substring(0,2)), u=digits(text.substring(2,4));
                require(u<80);
                if (p>=6) {
                    v=v*8+digit(text.charAt(4),"01234567");
                    u=u*8+digit(text.charAt(5),"01234567");
                }
                if (p>=8) {
                    v=v*10+digit(text.charAt(6),"0123456789");
                    u=u*10+digit(text.charAt(7),"0123456789");
                }
                for (int i=8;i<p;i++) {
                    int q=digit(text.charAt(i),"1234");
                    v=v*2+q/2;
                    u=u*2+q%2;
                }
                x=u+280*MESH_SCALE[l];
                y=v+135*MESH_SCALE[l];
                break;
            }
        }
        Cell result=grid(system,level(system,p),x,y);
        require(text.equals(code(result)));
        return result;
    }
    static Cell ancestor(Cell c, int level) {
        Cell g=grid(c.system(),level,0,0);
        return grid(c.system(),level,c.x()*g.w()/c.w(),c.y()*g.h()/c.h());
    }
    static String shown(Cell c) { String result=code(c); return result==null ? "-" : result; }
    static String coordinateFormat(long n) { return (n<0 ? "-" : "")+Math.abs(n)/1000000+"."+pad(Math.abs(n)%1000000,6); }
    static long boundary(Cell c, boolean latitude, int offset, boolean center) {
        long extent=latitude ? 180000000 : 360000000, total=latitude ? c.h() : c.w(), value=latitude ? c.y() : c.x();
        return -extent/2+(center ? extent*(2*value+1)/(2*total) : extent*(value+offset)/total);
    }
    static int compare(long a, long ad, long b, long bd) { return Long.compare(a*bd,b*ad); }
    static boolean inside(Cell a, Cell b) {
        return compare(a.x(),a.w(),b.x(),b.w())>=0 && compare(a.x()+1,a.w(),b.x()+1,b.w())<=0 &&
            compare(a.y(),a.h(),b.y(),b.h())>=0 && compare(a.y()+1,a.h(),b.y()+1,b.h())<=0;
    }
    static long[] steps(Cell a, Cell b) {
        long dx=Math.floorMod(b.x()-a.x(),a.w());
        if (dx>a.w()/2) dx-=a.w();
        return new long[]{dx,b.y()-a.y()};
    }
    static long[] detail(String a, String b) {
        require(a.matches("[0-9]{1,5}") && b.matches("[0-9]{1,5}") && a.length()==b.length());
        long size=power(5-a.length());
        return new long[]{digits(a)*size,digits(b)*size,size};
    }
    static String columns(long zone) { return zone%3==1 ? "ABCDEFGH" : zone%3==2 ? "JKLMNPQR" : "STUVWXYZ"; }
    static String auxiliary(String[] t) {
        String command=t[0];
        int n=t.length-1;
        switch (command) {
            case "UTMZONE": {
                require(n==2);
                long lat=coordinate(t[1],true), lon=coordinate(t[2],false);
                if (lat< -80000000 || lat>=84000000) return "NONE";
                char band=BANDS.charAt((int)Math.min((lat+80000000)/8000000,19));
                long zone=(lon+180000000)/6000000+1;
                if (band=='V' && lon>=3000000 && lon<12000000) zone=32;
                if (band=='X') {
                    if (lon>=0 && lon<9000000) zone=31;
                    else if (lon>=9000000 && lon<21000000) zone=33;
                    else if (lon>=21000000 && lon<33000000) zone=35;
                    else if (lon>=33000000 && lon<42000000) zone=37;
                }
                return zone+String.valueOf(band);
            }
            case "OSGB": {
                require(n==3);
                long e=range(t[1],0,699999), north=range(t[2],0,1299999);
                int d=(int)range(t[3],0,5);
                String letters=""+G25.charAt((int)((3-north/500000)*5+2+e/500000))+G25.charAt((int)((4-north/100000%5)*5+e/100000%5));
                return letters+(d==0 ? "" : " "+pad(e%100000,5).substring(0,d)+" "+pad(north%100000,5).substring(0,d));
            }
            case "UNOSGB": {
                require(n==1 || n==3);
                require(t[1].length()==2);
                int a=digit(t[1].charAt(0),G25), b=digit(t[1].charAt(1),G25);
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
                require(t[2].length()==1);
                digit(t[2].charAt(0),BANDS);
                int d=(int)range(t[5],0,5), offset=zone%2==0 ? 5 : 0;
                String square=""+columns(zone).charAt((int)(e/100000-1))+MROWS.charAt((int)((north/100000+offset)%20));
                return zone+t[2]+" "+square+(d==0 ? "" : " "+pad(e%100000,5).substring(0,d)+" "+pad(north%100000,5).substring(0,d));
            }
            case "UNMGRS": {
                require(n==2 || n==4);
                require(t[1].matches("[1-9][0-9]?[CDEFGHJKLMNPQRSTUVWX]"));
                long zone=Long.parseLong(t[1].substring(0,t[1].length()-1));
                require(zone<=60 && t[2].length()==2);
                int a=digit(t[2].charAt(0),columns(zone)), b=digit(t[2].charAt(1),MROWS), offset=zone%2==0 ? 5 : 0;
                long e=100000*(a+1), north=100000*Math.floorMod(b-offset,20), size=100000;
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
                for (int i=z-1;i>=0;i--) result.append((x>>i&1)+2*(y>>i&1));
                return result.toString();
            }
            case "UNQUADKEY": {
                require(n==1 && t[1].matches("[0-3]{1,23}"));
                long x=0,y=0;
                for (char c:t[1].toCharArray()) {
                    int d=c-'0';
                    x=x*2+d%2;
                    y=y*2+d/2;
                }
                return "x="+x+" y="+y+" z="+t[1].length();
            }
            default: throw new Invalid();
        }
    }
    static String execute(String line) {
        String[] t=line.split(" ");
        String command=t[0];
        if (!counts.containsKey(command) && !command.equals("COMPACT")) return auxiliary(t);
        if (command.equals("COMPACT")) require(t.length>=3 && t.length<=102);
        else require(t.length==counts.get(command)+1);
        if (command.equals("SHORTEN") || command.equals("RECOVER")) {
            long lat=coordinate(t[2],true), lon=coordinate(t[3],false);
            if (command.equals("SHORTEN")) {
                Cell c=decode("PLUSCODE",t[1]);
                require(precisions(c.system())[c.level()]>=8);
                long yn= -90000000*2*c.h()+180000000*(2*c.y()+1), xn= -180000000*2*c.w()+360000000*(2*c.x()+1);
                if (Math.abs(yn-lat*2*c.h())<15000*2*c.h() && Math.abs(xn-lon*2*c.w())<15000*2*c.w()) return t[1].substring(6);
                if (Math.abs(yn-lat*2*c.h())<300000*2*c.h() && Math.abs(xn-lon*2*c.w())<300000*2*c.w()) return t[1].substring(4);
                return t[1];
            }
            int plus=t[1].indexOf('+');
            require(plus==2 || plus==4);
            require(t[1].lastIndexOf('+')==plus);
            int tail=t[1].length()-plus-1;
            require(tail==0 || tail==2 || tail==3);
            for (char ch:t[1].replace("+","").toCharArray()) digit(ch,PLUS);
            int missing=8-plus;
            String prefix=code(point("PLUSCODE",4,lat,lon)).substring(0,missing);
            Cell c=decode("PLUSCODE",prefix+t[1]);
            long d=missing==4 ? 1000000 : 50000, x=c.x(), y=c.y();
            long yn= -90000000*2*c.h()+180000000*(2*y+1), xn= -180000000*2*c.w()+360000000*(2*x+1);
            long my=d*c.h()/180000000, mx=d*c.w()/360000000;
            if ((lat+d/2)*2*c.h()<yn && yn-d*2*c.h()>= -90000000*2*c.h()) y-=my;
            else if ((lat-d/2)*2*c.h()>yn && yn+d*2*c.h()<=90000000*2*c.h()) y+=my;
            if ((lon+d/2)*2*c.w()<xn) x=Math.floorMod(x-mx,c.w());
            else if ((lon-d/2)*2*c.w()>xn) x=Math.floorMod(x+mx,c.w());
            return code(grid("PLUSCODE",c.level(),x,y));
        }
        String system=t[1];
        precisions(system);
        if (command.equals("ENCODE")) {
            Cell c=point(system,level(system,integer(t[4])),coordinate(t[2],true),coordinate(t[3],false));
            String code=code(c);
            return code==null ? "OUT OF AREA" : code;
        }
        if (command.equals("SIZE")) {
            int l=level(system,integer(t[2]));
            Cell c=grid(system,l,0,0);
            long count=system.equals("MESH") ? 8000*MESH_SCALE[l]*MESH_SCALE[l] : c.w()*c.h();
            return "w="+coordinateFormat(360000000/c.w())+" h="+coordinateFormat(180000000/c.h())+" cells="+count;
        }
        if (command.equals("COVER")) {
            int l=level(system,integer(t[2]));
            long lat1=coordinate(t[3],true), lon1=coordinate(t[4],false), lat2=coordinate(t[5],true), lon2=coordinate(t[6],false);
            require(lat1<=lat2);
            Cell a=point(system,l,lat1,lon1), b=point(system,l,lat2,lon2);
            long columns=lon1<=lon2 ? b.x()-a.x()+1 : Math.min(a.w(),b.x()-a.x()+1+a.w());
            if (columns*(b.y()-a.y()+1)>100) return "TOO MANY";
            List<String> result=new ArrayList<>();
            for (long y=b.y();y>=a.y();y--) {
                for (long i=0;i<columns;i++) result.add(shown(grid(system,l,(a.x()+i)%a.w(),y)));
            }
            return String.join(" ",result);
        }
        if (command.equals("COMPACT")) {
            Set<Cell> cells=new HashSet<>();
            for (int i=2;i<t.length;i++) cells.add(decode(system,t[i]));
            List<Cell> covered = cells.stream().filter(c -> cells.stream()
                .anyMatch(a -> a.level()<c.level() && ancestor(c,a.level()).equals(a))).toList();
            cells.removeAll(covered);
            boolean changed=true;
            while (changed) {
                changed=false;
                for (Cell child:new ArrayList<>(cells)) {
                    if (child.level()==0) continue;
                    Cell parent=ancestor(child,child.level()-1), g=grid(system,child.level(),0,0);
                    long rx=g.w()/parent.w(), ry=g.h()/parent.h();
                    if (rx*ry>cells.size()) continue;
                    Set<Cell> siblings=new HashSet<>();
                    for (long j=0;j<ry;j++) {
                        for (long i=0;i<rx;i++) siblings.add(grid(system,child.level(),parent.x()*rx+i,parent.y()*ry+j));
                    }
                    if (cells.containsAll(siblings)) {
                        cells.removeAll(siblings);
                        cells.add(parent);
                        changed=true;
                        break;
                    }
                }
            }
            List<Cell> result=new ArrayList<>(cells);
            result.sort(Comparator.comparingInt(Cell::level).thenComparing(Comparator.comparingLong(Cell::y).reversed()).thenComparingLong(Cell::x));
            return String.join(" ",result.stream().map(Main::code).toList());
        }
        Cell a=decode(system,t[2]);
        switch (command) {
            case "DECODE": return "sw="+coordinateFormat(boundary(a,true,0,false))+","+coordinateFormat(boundary(a,false,0,false))+
                " ne="+coordinateFormat(boundary(a,true,1,false))+","+coordinateFormat(boundary(a,false,1,false))+
                " c="+coordinateFormat(boundary(a,true,0,true))+","+coordinateFormat(boundary(a,false,0,true));
            case "NEIGHBORS": {
                int[] dx={0,1,1,1,0,-1,-1,-1}, dy={1,1,0,-1,-1,-1,0,1};
                List<String> result=new ArrayList<>();
                for (int i=0;i<8;i++) result.add(a.y()+dy[i]<0 || a.y()+dy[i]>=a.h() ? "-" : shown(grid(system,a.level(),Math.floorMod(a.x()+dx[i],a.w()),a.y()+dy[i])));
                return String.join(" ",result);
            }
            case "PARENT": return a.level()==0 ? "NONE" : code(ancestor(a,a.level()-1));
            case "CHILDREN": {
                if (a.level()+1==precisions(system).length) return "NONE";
                Cell g=grid(system,a.level()+1,0,0);
                long rx=g.w()/a.w(), ry=g.h()/a.h();
                if (rx*ry>100) return "TOO MANY";
                List<String> result=new ArrayList<>();
                for (long j=ry-1;j>=0;j--) {
                    for (long i=0;i<rx;i++) result.add(shown(grid(system,g.level(),a.x()*rx+i,a.y()*ry+j)));
                }
                return String.join(" ",result);
            }
            case "COMMON": {
                Cell b=decode(system,t[3]);
                for (int l=Math.min(a.level(),b.level());l>=0;l--) {
                    Cell parent=ancestor(a,l);
                    if (parent.equals(ancestor(b,l))) return code(parent);
                }
                return "NONE";
            }
            case "CONTAINS": return a.equals(point(system,a.level(),coordinate(t[3],true),coordinate(t[4],false))) ? "YES" : "NO";
            case "CONVERT": {
                require(t[3].equals("TO"));
                Cell g=grid(t[4],level(t[4],integer(t[5])),0,0);
                String result=code(grid(g.system(),g.level(),(2*a.x()+1)*g.w()/(2*a.w()),(2*a.y()+1)*g.h()/(2*a.h())));
                return result==null ? "OUT OF AREA" : result;
            }
            case "STEPS", "PATH": {
                Cell b=decode(system,t[3]);
                if (a.level()!=b.level()) return "MISMATCH";
                long[] delta=steps(a,b);
                if (command.equals("STEPS")) return "dx="+delta[0]+" dy="+delta[1];
                long n=Math.max(Math.abs(delta[0]),Math.abs(delta[1]));
                if (n+1>100) return "TOO MANY";
                List<String> result=new ArrayList<>();
                for (long i=0;i<=n;i++) {
                    long dx=n==0 ? 0 : Math.floorDiv(2*i*delta[0]+n,2*n), dy=n==0 ? 0 : Math.floorDiv(2*i*delta[1]+n,2*n);
                    result.add(shown(grid(system,a.level(),Math.floorMod(a.x()+dx,a.w()),a.y()+dy)));
                }
                return String.join(" ",result);
            }
            case "RELATE": {
                Cell b=decode(t[3],t[4]);
                boolean ab=inside(a,b), ba=inside(b,a);
                if (ab && ba) return "EQUAL";
                if (ab) return "INSIDE";
                if (ba) return "CONTAINS";
                int ew=compare(a.x()+1,a.w(),b.x(),b.w()), we=compare(b.x()+1,b.w(),a.x(),a.w());
                int ns=compare(a.y()+1,a.h(),b.y(),b.h()), sn=compare(b.y()+1,b.h(),a.y(),a.h());
                if (ew>0 && we>0 && ns>0 && sn>0) return "OVERLAP";
                boolean dateline=a.x()+1==a.w() && b.x()==0 || b.x()+1==b.w() && a.x()==0;
                return ns>=0 && sn>=0 && (ew>=0 && we>=0 || dateline) ? "TOUCH" : "DISJOINT";
            }
            default: throw new Invalid();
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output=new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n=Integer.parseInt(input.readLine());
        for (int i=0;i<n;i++) {
            try { output.println(execute(input.readLine())); }
            catch (Invalid invalid) { output.println("INVALID"); }
        }
        output.flush();
    }
}
