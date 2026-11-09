import java.io.*;
import java.util.*;
import java.util.stream.IntStream;

public class Main {
    static final String BASES="ACGT", SYMBOLS="ACGTRYSWKMBDHVN", COMPLEMENTS="TGCAYRSWMKVHDBN";
    static final HexFormat HEX_FORMAT=HexFormat.of().withUpperCase();
    static final int[] MASKS={1,2,4,8,5,10,6,9,12,3,14,13,11,7,15};
    static final String AMINO="ACDEFGHIKLMNPQRSTVWY";
    static final int[] RESIDUES={71079,103139,115089,129116,147177,57052,137141,113160,128174,113160,131193,114104,97117,128131,156188,87078,101105,99133,186213,163176};
    static final int[] BASE_MASS={331222,307197,347221,322208};
    static final Map<String,Character> GENETIC=new HashMap<>();
    static final String[] ENZYMES={"EcoRI","BamHI","HindIII","PstI","SmaI","KpnI","XbaI","NotI","EcoRV","HaeIII","AluI","TaqI","Sau3AI","HincII","AvaI"};
    static final String[] SITES={"GAATTC","GGATCC","AAGCTT","CTGCAG","CCCGGG","GGTACC","TCTAGA","GCGGCCGC","GATATC","GGCC","AGCT","TCGA","GATC","GTYRAC","CYCGRG"};
    static final int[] CUTS={1,1,1,5,3,5,1,2,3,2,2,1,0,3,1};
    static {
        String[] groups={"A GCT GCC GCA GCG",
            "C TGT TGC",
            "D GAT GAC",
            "E GAA GAG",
            "F TTT TTC",
            "G GGT GGC GGA GGG",
            "H CAT CAC",
            "I ATT ATC ATA",
            "K AAA AAG",
            "L TTA TTG CTT CTC CTA CTG",
            "M ATG",
            "N AAT AAC",
            "P CCT CCC CCA CCG",
            "Q CAA CAG",
            "R CGT CGC CGA CGG AGA AGG",
            "S TCT TCC TCA TCG AGT AGC",
            "T ACT ACC ACA ACG",
            "V GTT GTC GTA GTG",
            "W TGG",
            "Y TAT TAC",
            "* TAA TAG TGA"};
        for (String group:groups) {
            String[] t=group.split(" ");
            for (int i=1;i<t.length;i++) GENETIC.put(t[i],t[0].charAt(0));
        }
    }
    static class Fault extends RuntimeException { Fault(String reason) { super(reason); } }
    static void error(boolean condition, String reason) { if (condition) throw new Fault(reason); }
    static int number(String s, int low, int high) {
        error(!s.matches("-?[0-9]{1,6}"),"invalid number "+s);
        int n=Integer.parseInt(s);
        error(n<low || n>high,"invalid number "+s);
        return n;
    }
    static String reverse(String s) { return new StringBuilder(s).reverse().toString(); }
    static String complement(String s) {
        StringBuilder out=new StringBuilder();
        for (char c:s.toCharArray()) out.append(COMPLEMENTS.charAt(SYMBOLS.indexOf(c)));
        return out.toString();
    }
    static String revcomp(String s) { return reverse(complement(s)); }
    static int gc(String s) { return (int)s.chars().filter(c -> c=='G' || c=='C').count(); }
    static String fixed(int n, int divisor, int width) {
        return String.format(Locale.ROOT,"%d.%0"+width+"d",n/divisor,n%divisor);
    }
    static String pct(int a, int b) { return fixed(10000*a/b,100,2); }
    static String milli(int n) { return fixed(n,1000,3); }
    static String list(Collection<?> values) { return values.isEmpty() ? "none" : String.join(" ",values.stream().map(Object::toString).toList()); }
    static List<String> codons(String s, int frame) {
        String strand=frame>0 ? s : revcomp(s);
        List<String> result=new ArrayList<>();
        for (int i=Math.abs(frame)-1;i+3<=s.length();i+=3) result.add(strand.substring(i,i+3));
        return result;
    }
    static String translation(List<String> codons) {
        return String.join("",codons.stream().map(c -> GENETIC.get(c).toString()).toList());
    }
    static Map<String,Integer> counts(Collection<String> words) {
        Map<String,Integer> out=new HashMap<>();
        for (String word:words) out.merge(word,1,Integer::sum);
        return out;
    }
    static List<String> frequency(Map<String,Integer> counts) {
        List<String> out=new ArrayList<>(counts.keySet());
        out.sort(Comparator.comparingInt((String s) -> -counts.get(s)).thenComparing(Comparator.naturalOrder()));
        return out;
    }
    static List<Integer> occurrences(String s, String motif) {
        return IntStream.range(0,Math.max(0,s.length()-motif.length()+1))
            .filter(i -> IntStream.range(0,motif.length()).allMatch(j ->
                (MASKS[SYMBOLS.indexOf(motif.charAt(j))] & (1<<BASES.indexOf(s.charAt(i+j))))!=0))
            .map(i -> i+1).boxed().toList();
    }
    static boolean transition(char a, char b) { return a!=b && ("AG".indexOf(a)>=0 && "AG".indexOf(b)>=0 || "CT".indexOf(a)>=0 && "CT".indexOf(b)>=0); }
    static int repeatCount(String s, int i, int u) {
        String unit=s.substring(i,i+u);
        int count=1;
        while (i+(count+1)*u<=s.length() && s.substring(i+count*u,i+(count+1)*u).equals(unit)) count++;
        return count;
    }
    static boolean primitive(String s) {
        for (int d=1;d<s.length();d++) if (s.length()%d==0 && s.substring(0,d).repeat(s.length()/d).equals(s)) return false;
        return true;
    }
    static char complementBase(char c) { return BASES.charAt(3-BASES.indexOf(c)); }
    static int selfcomp(String s) {
        int maximum=0;
        for (int center=1;center<s.length();center++) {
            int left=center-1,right=center;
            while (left>=0 && right<s.length() && complementBase(s.charAt(left))==s.charAt(right)) {
                maximum=Math.max(maximum,right-left+1);
                left--;
                right++;
            }
        }
        return maximum;
    }
    static int tm(String s) {
        int n=s.length(),g=gc(s);
        return n<14 ? 10*(2*(n-g)+4*g) : (649*n+410*g-6724)/n;
    }
    static int mass(String s) {
        return s.chars().map(c -> BASE_MASS[BASES.indexOf(c)]).sum()-(s.length()-1)*18015;
    }
    static int overlap(String a, String b) {
        String joined=b+"#"+a;
        int[] prefix=new int[joined.length()];
        for (int i=1;i<joined.length();i++) {
            int j=prefix[i-1];
            while (j>0 && joined.charAt(i)!=joined.charAt(j)) j=prefix[j-1];
            if (joined.charAt(i)==joined.charAt(j)) j++;
            prefix[i]=j;
        }
        int result=prefix[joined.length()-1], limit=Math.min(a.length(),b.length());
        while (result>=limit) result=prefix[result-1];
        return result;
    }
    record Orf(int frame, int left, int right, String protein) {}
    record Repeat(int start, int end, int unitLength, String unit, int count) {}
    static class Toolkit {
        TreeMap<String,String> registry=new TreeMap<>();
        Map<String,String[]> schemas=new HashMap<>();
        Map<String,int[]> arities=new HashMap<>();
        List<String> output;
        Toolkit() {
            schema("SEQ",2,2,"NEW","SEQ");
            schema("SLICE",4,4,"NAME","POS","POS","NEW");
            schema("JOIN",3,9,"NEW","NAME");
            schema("MUTATE",3,3,"NAME","POS","BASE");
            for (String c:new String[]{"DEL","REVCOMP","COMPLEMENT","REVERSE","TRANSCRIBE","GC","SKEW","TM","MASS","PRIMER","PACK"}) schema(c,1,1,"NAME");
            schema("LIST",0,0);
            for (String c:new String[]{"TRANSLATE","CODONS","PROTEIN"}) schema(c,2,2,"NAME","FRAME");
            schema("ORFS",2,2,"NAME","1:200");
            schema("GCWINDOW",3,3,"NAME","1:500","1:500");
            schema("KMERS",3,3,"NAME","1:12","1:100");
            schema("FIND",2,2,"NAME","MOTIF");
            schema("RESTRICT",2,7,"NAME","ENZYME");
            schema("PALINDROMES",3,3,"NAME","2:20","2:20");
            schema("REPEATS",4,4,"NAME","1:6","1:6","2:50");
            schema("HAMMING",2,2,"NAME","NAME");
            schema("ALIGN",6,6,"NAME","NAME","MODE","1:20","-20:0","-20:-1");
            schema("CONSENSUS",2,10,"NAME");
            schema("FOLD",2,2,"NAME","0:10");
            schema("ASSEMBLE",4,10,"NEW","1:100","NAME");
            schema("UNPACK",3,3,"NEW","1:500","HEX");
        }
        void schema(String c, int low, int high, String... args) {
            schemas.put(c,args);
            arities.put(c,new int[]{low,high});
        }
        void store(String name, String sequence) {
            error(sequence.length()>500,"too long");
            boolean replacing=registry.containsKey(name);
            registry.put(name,sequence);
            output.add((replacing ? "replaced " : "stored ")+name+" "+sequence.length()+" nt");
        }
        void validate(String command, String[] a, int[] nums, String[] sequences) {
            error(!schemas.containsKey(command),"unknown command "+command);
            int[] count=arities.get(command);
            error(a.length<count[0] || a.length>count[1],"wrong argument count");
            String[] schema=schemas.get(command);
            Set<String> enzymes=new HashSet<>();
            for (int i=0;i<a.length;i++) {
                String kind=schema[Math.min(i,schema.length-1)], value=a[i];
                switch (kind) {
                    case "NAME":
                        error(!registry.containsKey(value),"unknown sequence "+value);
                        sequences[i]=registry.get(value);
                        break;
                    case "NEW":
                        error(!value.matches("[a-z][a-z0-9]{0,9}"),"invalid name "+value);
                        break;
                    case "SEQ":
                        for (int j=0;j<value.length();j++) error(BASES.indexOf(value.charAt(j))<0,"invalid base "+value.charAt(j)+" at "+(j+1));
                        break;
                    case "BASE":
                        error(value.length()!=1 || BASES.indexOf(value.charAt(0))<0,"invalid base "+value);
                        break;
                    case "MOTIF":
                        error(!value.matches("[ACGTRYSWKMBDHVN]{1,30}"),"invalid motif "+value);
                        break;
                    case "ENZYME":
                        error(!Arrays.asList(ENZYMES).contains(value),"unknown enzyme "+value);
                        error(!enzymes.add(value),"duplicate enzyme "+value);
                        break;
                    case "MODE":
                        error(!value.equals("GLOBAL") && !value.equals("LOCAL"),"invalid mode "+value);
                        break;
                    case "HEX":
                        error(value.length()!=2*((nums[1]+3)/4) || !value.matches("[0-9A-F]+"),"invalid hex");
                        break;
                    case "FRAME":
                        nums[i]=number(value,-3,3);
                        error(nums[i]==0,"invalid number "+value);
                        break;
                    case "POS":
                        nums[i]=number(value,1,sequences[0].length());
                        break;
                    default:
                        String[] bounds=kind.split(":");
                        nums[i]=number(value,Integer.parseInt(bounds[0]),Integer.parseInt(bounds[1]));
                }
            }
        }
        void align(String a, String b, boolean local, int match, int mismatch, int gap) {
            int m=a.length(),n=b.length();
            int[][] h=new int[m+1][n+1];
            if (!local) {
                for (int i=0;i<=m;i++) h[i][0]=i*gap;
                for (int j=0;j<=n;j++) h[0][j]=j*gap;
            }
            int best=0,bi=0,bj=0;
            for (int i=1;i<=m;i++) {
                for (int j=1;j<=n;j++) {
                    int value=Math.max(h[i-1][j-1]+(a.charAt(i-1)==b.charAt(j-1) ? match : mismatch),Math.max(h[i-1][j]+gap,h[i][j-1]+gap));
                    h[i][j]=local ? Math.max(0,value) : value;
                    if (local && h[i][j]>best) {
                        best=h[i][j];
                        bi=i;
                        bj=j;
                    }
                }
            }
            if (!local) {
                bi=m;
                bj=n;
                best=h[m][n];
            }
            if (local && best==0) {
                output.add("score 0");
                return;
            }
            int i=bi,j=bj;
            StringBuilder x=new StringBuilder(),y=new StringBuilder();
            while (local ? h[i][j]!=0 : i!=0 || j!=0) {
                if (i>0 && j>0 && h[i][j]==h[i-1][j-1]+(a.charAt(i-1)==b.charAt(j-1) ? match : mismatch)) {
                    x.append(a.charAt(--i));
                    y.append(b.charAt(--j));
                } else if (i>0 && h[i][j]==h[i-1][j]+gap) {
                    x.append(a.charAt(--i));
                    y.append('-');
                } else {
                    x.append('-');
                    y.append(b.charAt(--j));
                }
            }
            String left=x.reverse().toString(),right=y.reverse().toString();
            StringBuilder middle=new StringBuilder();
            int identity=0,gaps=0;
            for (int k=0;k<left.length();k++) {
                char c=left.charAt(k)=='-' || right.charAt(k)=='-' ? '-' : left.charAt(k)==right.charAt(k) ? '|' : '*';
                middle.append(c);
                if (c=='|') identity++;
                if (c=='-') gaps++;
            }
            output.add("score "+best+" a "+(i+1)+"-"+bi+" b "+(j+1)+"-"+bj+" identity "+identity+"/"+left.length()+" gaps "+gaps);
            output.add(left);
            output.add(middle.toString());
            output.add(right);
        }
        boolean pair(char a, char b) { return complementBase(a)==b || a=='G' && b=='T' || a=='T' && b=='G'; }
        int value(int[][] f, int i, int j) { return i>j ? 0 : f[i][j]; }
        void fold(String s, int loop) {
            int n=s.length();
            error(n>100,"too long");
            int[][] f=new int[n][n];
            for (int length=1;length<=n;length++) {
                for (int i=0;i+length<=n;i++) {
                    int j=i+length-1;
                    f[i][j]=value(f,i,j-1);
                    for (int k=i;k<=j-loop-1;k++) if (pair(s.charAt(k),s.charAt(j))) f[i][j]=Math.max(f[i][j],value(f,i,k-1)+1+value(f,k+1,j-1));
                }
            }
            char[] structure=new char[n];
            Arrays.fill(structure,'.');
            Deque<int[]> intervals=new ArrayDeque<>();
            intervals.push(new int[]{0,n-1});
            while (!intervals.isEmpty()) {
                int[] interval=intervals.pop();
                int i=interval[0],j=interval[1];
                if (value(f,i,j)==0) continue;
                if (f[i][j]==value(f,i,j-1)) intervals.push(new int[]{i,j-1});
                else {
                    for (int k=i;k<=j-loop-1;k++) {
                        if (pair(s.charAt(k),s.charAt(j)) && value(f,i,k-1)+1+value(f,k+1,j-1)==f[i][j]) {
                            structure[k]='(';
                            structure[j]=')';
                            intervals.push(new int[]{i,k-1});
                            intervals.push(new int[]{k+1,j-1});
                            break;
                        }
                    }
                }
            }
            output.add(new String(structure));
            output.add("pairs "+f[0][n-1]);
        }
        void primer(String s) {
            int n=s.length(),g=gc(s),temperature=tm(s),clamp=gc(s.substring(Math.max(0,n-5))),run=1,bestRun=1,repeats=0;
            for (int i=1;i<n;i++) {
                run=s.charAt(i)==s.charAt(i-1) ? run+1 : 1;
                bestRun=Math.max(bestRun,run);
            }
            for (int i=0;i+1<n;i++) if (s.charAt(i)!=s.charAt(i+1)) repeats=Math.max(repeats,repeatCount(s,i,2));
            int self=selfcomp(s);
            String[] names={"length","gc","tm","clamp","run","repeat","selfcomp"};
            String[] values={Integer.toString(n),pct(g,n),fixed(temperature,10,1),Integer.toString(clamp),Integer.toString(bestRun),Integer.toString(repeats),Integer.toString(self)};
            boolean[] ok={n>=18 && n<=25,40*n<=100*g && 100*g<=60*n,temperature>=520 && temperature<=620,clamp>=1 && clamp<=3,bestRun<=4,repeats<=4,self<=6};
            List<String> failed=new ArrayList<>();
            for (int i=0;i<7;i++) {
                output.add(names[i]+" "+values[i]+" "+(ok[i] ? "OK" : "FAIL"));
                if (!ok[i]) failed.add(names[i]);
            }
            output.add(failed.isEmpty() ? "PASS" : "FAIL "+list(failed));
        }
        void assemble(String name, int minimum, String[] sequences) {
            List<String> unique=new ArrayList<>(new LinkedHashSet<>(Arrays.asList(sequences).subList(2,sequences.length)));
            List<String> fragments=new ArrayList<>();
            for (String s:unique) if (unique.stream().noneMatch(t -> !t.equals(s) && t.contains(s))) fragments.add(s);
            while (fragments.size()>=2) {
                int best=-1,bx=0,by=0;
                for (int x=0;x<fragments.size();x++) {
                    for (int y=0;y<fragments.size();y++) {
                        if (x==y) continue;
                        String a=fragments.get(x),b=fragments.get(y);
                        int overlap=overlap(a,b);
                        if (overlap>best) {
                            best=overlap;
                            bx=x;
                            by=y;
                        }
                    }
                }
                if (best<minimum) break;
                String merged=fragments.get(bx)+fragments.get(by).substring(best);
                fragments.set(bx,merged);
                fragments.remove(by);
                int keep=bx-(by<bx ? 1 : 0);
                for (int i=fragments.size()-1;i>=0;i--) {
                    if (i!=keep && merged.contains(fragments.get(i))) {
                        fragments.remove(i);
                        if (i<keep) keep--;
                    }
                }
            }
            String longest=Collections.max(fragments,Comparator.comparingInt(String::length));
            error(longest.length()>500,"too long");
            output.add("contigs "+fragments.size());
            for (String s:fragments) output.add(s.length()+" "+s);
            store(name,longest);
        }
        void execute(String line) {
            String[] t=line.split(" "),a=Arrays.copyOfRange(t,1,t.length);
            int[] nums=new int[a.length];
            String[] sequences=new String[a.length];
            String command=t[0];
            validate(command,a,nums,sequences);
            String s=a.length==0 ? "" : sequences[0];
            int n=s==null ? 0 : s.length();
            switch (command) {
                case "SEQ":
                    store(a[0],a[1]);
                    break;
                case "SLICE": {
                    int left=Math.min(nums[1],nums[2]),right=Math.max(nums[1],nums[2]);
                    String part=s.substring(left-1,right);
                    store(a[3],nums[1]<=nums[2] ? part : revcomp(part));
                    break;
                }
                case "JOIN":
                    store(a[0],String.join("",Arrays.asList(sequences).subList(1,sequences.length)));
                    break;
                case "MUTATE": {
                    char old=s.charAt(nums[1]-1),next=a[2].charAt(0);
                    error(old==next,"no change");
                    registry.put(a[0],s.substring(0,nums[1]-1)+next+s.substring(nums[1]));
                    output.add(a[0]+" "+old+nums[1]+next+" "+(transition(old,next) ? "transition" : "transversion"));
                    break;
                }
                case "DEL":
                    registry.remove(a[0]);
                    output.add("deleted "+a[0]);
                    break;
                case "LIST":
                    if (registry.isEmpty()) output.add("no sequences");
                    else for (String name:registry.keySet()) output.add(name+" "+registry.get(name).length()+" nt");
                    break;
                case "REVCOMP":
                    output.add(revcomp(s));
                    break;
                case "COMPLEMENT":
                    output.add(complement(s));
                    break;
                case "REVERSE":
                    output.add(reverse(s));
                    break;
                case "TRANSCRIBE":
                    output.add(s.replace('T','U'));
                    break;
                case "TRANSLATE": {
                    String protein=translation(codons(s,nums[1]));
                    output.add(protein.isEmpty() ? "none" : protein);
                    break;
                }
                case "CODONS": {
                    Map<String,Integer> counts=counts(codons(s,nums[1]));
                    if (counts.isEmpty()) output.add("none");
                    for (String c:frequency(counts)) output.add(c+" "+GENETIC.get(c)+" "+counts.get(c));
                    break;
                }
                case "PROTEIN": {
                    String protein=translation(codons(s,nums[1])).split("\\*",-1)[0];
                    error(protein.isEmpty(),"empty protein");
                    int mass=18015+protein.chars().map(c -> RESIDUES[AMINO.indexOf(c)]).sum();
                    long charge=protein.chars().filter(c -> "KR".indexOf(c)>=0).count()
                        -protein.chars().filter(c -> "DE".indexOf(c)>=0).count();
                    Map<String,Integer> counts=counts(protein.chars().mapToObj(Character::toString).toList());
                    output.add(protein);
                    output.add("length "+protein.length()+" mass "+milli(mass)+" charge "+(charge>0 ? "+" : "")+charge);
                    output.add(String.join(" ",frequency(counts).stream().map(c -> c+"="+counts.get(c)).toList()));
                    break;
                }
                case "ORFS": {
                    List<Orf> found=new ArrayList<>();
                    for (int frame:new int[]{1,2,3,-1,-2,-3}) {
                        List<String> codons=codons(s,frame);
                        int start=-1;
                        for (int i=0;i<codons.size();i++) {
                            if (start<0 && codons.get(i).equals("ATG")) start=i;
                            else if (start>=0 && GENETIC.get(codons.get(i))=='*') {
                                if (i-start>=nums[1]) {
                                    int left=Math.abs(frame)-1+3*start,right=Math.abs(frame)-1+3*(i+1)-1;
                                    found.add(new Orf(frame,frame>0 ? left+1 : n-right,frame>0 ? right+1 : n-left,translation(codons.subList(start,i))));
                                }
                                start=-1;
                            }
                        }
                    }
                    found.sort(Comparator.comparingInt(Orf::left));
                    if (found.isEmpty()) output.add("none");
                    for (Orf o:found) output.add((o.frame()>0 ? "+" : "")+o.frame()+" "+o.left()+" "+o.right()+" "+o.protein().length()+" "+o.protein());
                    break;
                }
                case "GC": {
                    String lineOut="";
                    for (char c:BASES.toCharArray()) lineOut+=(lineOut.isEmpty() ? "" : " ")+c+"="+s.chars().filter(x -> x==c).count();
                    output.add(lineOut+" GC="+pct(gc(s),n)+"%");
                    break;
                }
                case "GCWINDOW":
                    error(nums[1]>n,"window too large");
                    for (int i=0;i+nums[1]<=n;i+=nums[2]) output.add((i+1)+"-"+(i+nums[1])+" "+pct(gc(s.substring(i,i+nums[1])),nums[1])+"%");
                    break;
                case "SKEW": {
                    int[] skew=new int[n+1];
                    for (int i=0;i<n;i++) skew[i+1]=skew[i]+(s.charAt(i)=='G' ? 1 : s.charAt(i)=='C' ? -1 : 0);
                    for (boolean minimum:new boolean[]{true,false}) {
                        int v=minimum ? Arrays.stream(skew).min().orElse(0) : Arrays.stream(skew).max().orElse(0);
                        List<Integer> at=IntStream.rangeClosed(0,n).filter(i -> skew[i]==v).boxed().toList();
                        output.add((minimum ? "min " : "max ")+v+" at "+list(at));
                    }
                    break;
                }
                case "KMERS": {
                    error(nums[1]>n,"k too large");
                    List<String> words=IntStream.rangeClosed(0,n-nums[1])
                        .mapToObj(i -> s.substring(i,i+nums[1])).toList();
                    Map<String,Integer> counts=counts(words);
                    output.add(words.size()+" windows "+counts.size()+" distinct");
                    List<String> order=frequency(counts);
                    for (int i=0;i<Math.min(nums[2],order.size());i++) output.add(order.get(i)+" "+counts.get(order.get(i)));
                    break;
                }
                case "FIND":
                    output.add("forward "+list(occurrences(s,a[1])));
                    output.add("reverse "+list(occurrences(s,revcomp(a[1]))));
                    break;
                case "RESTRICT": {
                    TreeSet<Integer> cuts=new TreeSet<>();
                    for (int i=1;i<a.length;i++) {
                        int e=Arrays.asList(ENZYMES).indexOf(a[i]);
                        List<Integer> found=new ArrayList<>();
                        for (int p:occurrences(s,SITES[e])) {
                            int c=p+CUTS[e]-1;
                            if (c>=1 && c<n) {
                                found.add(c);
                                cuts.add(c);
                            }
                        }
                        output.add(a[i]+" "+list(found));
                    }
                    List<String> fragments=new ArrayList<>();
                    List<Integer> sizes=new ArrayList<>(),ends=new ArrayList<>(cuts);
                    ends.add(n);
                    int previous=0;
                    for (int end:ends) {
                        fragments.add((previous+1)+"-"+end);
                        sizes.add(end-previous);
                        previous=end;
                    }
                    sizes.sort(Comparator.reverseOrder());
                    output.add("fragments "+list(fragments));
                    output.add("sizes "+list(sizes));
                    break;
                }
                case "PALINDROMES": {
                    error(nums[1]>nums[2],"invalid range");
                    int count=0;
                    for (int i=0;i<n;i++) {
                        for (int length=nums[1];length<=nums[2] && i+length<=n;length++) {
                            String part=s.substring(i,i+length);
                            if (part.equals(revcomp(part))) {
                                output.add((i+1)+" "+length+" "+part);
                                count++;
                            }
                        }
                    }
                    if (count==0) output.add("none");
                    break;
                }
                case "REPEATS": {
                    error(nums[1]>nums[2],"invalid range");
                    List<Repeat> found=new ArrayList<>();
                    for (int u=nums[1];u<=nums[2];u++) {
                        int i=0;
                        while (i+u<=n) {
                            String unit=s.substring(i,i+u);
                            int count=repeatCount(s,i,u);
                            if (primitive(unit) && count>=nums[3]) {
                                found.add(new Repeat(i+1,i+count*u,u,unit,count));
                                i+=count*u;
                            } else i++;
                        }
                    }
                    found.sort(Comparator.comparingInt(Repeat::start).thenComparingInt(Repeat::unitLength));
                    if (found.isEmpty()) output.add("none");
                    for (Repeat r:found) output.add(r.start()+"-"+r.end()+" "+r.unit()+"x"+r.count());
                    break;
                }
                case "HAMMING": {
                    String b=sequences[1];
                    error(n!=b.length(),"length mismatch");
                    int distance=0,transitions=0;
                    for (int i=0;i<n;i++) {
                        if (s.charAt(i)!=b.charAt(i)) {
                            distance++;
                            if (transition(s.charAt(i),b.charAt(i))) transitions++;
                        }
                    }
                    output.add("distance "+distance+" transitions "+transitions+" transversions "+(distance-transitions));
                    break;
                }
                case "ALIGN":
                    align(s,sequences[1],a[2].equals("LOCAL"),nums[3],nums[4],nums[5]);
                    break;
                case "CONSENSUS": {
                    for (String sequence:sequences) error(sequence.length()!=n,"length mismatch");
                    int[][] profile=new int[4][n];
                    StringBuilder consensus=new StringBuilder(),iupac=new StringBuilder();
                    for (int i=0;i<n;i++) {
                        for (String sequence:sequences) profile[BASES.indexOf(sequence.charAt(i))][i]++;
                        int maximum=0,mask=0;
                        for (int b=0;b<4;b++) maximum=Math.max(maximum,profile[b][i]);
                        boolean chosen=false;
                        for (int b=0;b<4;b++) {
                            if (profile[b][i]==maximum) {
                                mask|=1<<b;
                                if (!chosen) {
                                    consensus.append(BASES.charAt(b));
                                    chosen=true;
                                }
                            }
                        }
                        for (int j=0;j<MASKS.length;j++) if (MASKS[j]==mask) iupac.append(SYMBOLS.charAt(j));
                    }
                    for (int b=0;b<4;b++) output.add(BASES.charAt(b)+" "+list(Arrays.stream(profile[b]).boxed().toList()));
                    output.add("consensus "+consensus);
                    output.add("iupac "+iupac);
                    break;
                }
                case "TM":
                    output.add("Tm "+fixed(tm(s),10,1)+" "+(n<14 ? "wallace" : "gc"));
                    break;
                case "MASS":
                    output.add("ss "+milli(mass(s))+" ds "+milli(mass(s)+mass(revcomp(s))));
                    break;
                case "PRIMER":
                    primer(s);
                    break;
                case "FOLD":
                    fold(s,nums[1]);
                    break;
                case "ASSEMBLE":
                    assemble(a[0],nums[1],sequences);
                    break;
                case "PACK": {
                    StringBuilder hex=new StringBuilder();
                    for (int i=0;i<n;i+=4) {
                        int value=0;
                        for (int j=0;j<4;j++) value=4*value+(i+j<n ? BASES.indexOf(s.charAt(i+j)) : 0);
                        hex.append(HEX_FORMAT.toHexDigits((byte)value));
                    }
                    output.add(n+" "+hex);
                    break;
                }
                case "UNPACK": {
                    StringBuilder decoded=new StringBuilder();
                    for (byte packed:HEX_FORMAT.parseHex(a[2])) {
                        int value=Byte.toUnsignedInt(packed);
                        for (int shift:new int[]{6,4,2,0}) decoded.append(BASES.charAt(value>>shift&3));
                    }
                    for (int i=nums[1];i<decoded.length();i++) error(decoded.charAt(i)!='A',"invalid padding");
                    store(a[0],decoded.substring(0,nums[1]));
                    break;
                }
            }
        }
        List<String> process(String line) {
            output=new ArrayList<>();
            try { execute(line); }
            catch (Fault fault) {
                output.clear();
                output.add("ERROR "+fault.getMessage());
            }
            return output;
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output=new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Toolkit toolkit=new Toolkit();
        int n=Integer.parseInt(input.readLine());
        for (int i=0;i<n;i++) {
            for (String line:toolkit.process(input.readLine())) output.println(line);
        }
        output.flush();
    }
}
