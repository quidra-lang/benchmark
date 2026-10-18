using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Globalization;

class Program {
    static readonly string BASES="ACGT", SYMBOLS="ACGTRYSWKMBDHVN", COMPLEMENTS="TGCAYRSWMKVHDBN", HEX="0123456789ABCDEF";
    static readonly int[] MASKS={1,2,4,8,5,10,6,9,12,3,14,13,11,7,15};
    static readonly string AMINO="ACDEFGHIKLMNPQRSTVWY";
    static readonly int[] RESIDUES={71079,103139,115089,129116,147177,57052,137141,113160,128174,113160,131193,114104,97117,128131,156188,87078,101105,99133,186213,163176};
    static readonly int[] BASE_MASS={331222,307197,347221,322208};
    static readonly Dictionary<string,char> GENETIC=new();
    static readonly string[] ENZYMES={"EcoRI","BamHI","HindIII","PstI","SmaI","KpnI","XbaI","NotI","EcoRV","HaeIII","AluI","TaqI","Sau3AI","HincII","AvaI"};
    static readonly string[] SITES={"GAATTC","GGATCC","AAGCTT","CTGCAG","CCCGGG","GGTACC","TCTAGA","GCGGCCGC","GATATC","GGCC","AGCT","TCGA","GATC","GTYRAC","CYCGRG"};
    static readonly int[] CUTS={1,1,1,5,3,5,1,2,3,2,2,1,0,3,1};
    static Program() {
        string[] groups={"A GCT GCC GCA GCG",
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
        foreach (string group in groups) {
            string[] t=group.Split(' ');
            for (int i=1;i<t.Length;i++) GENETIC[t[i]]=t[0][0];
        }
    }
    class Fault : Exception { public Fault(string reason) : base(reason) {} }
    static void error(bool condition, string reason) { if (condition) throw new Fault(reason); }
    static int number(string s, int low, int high) {
        error(!matches(s,"-?[0-9]{1,6}"),"invalid number "+s);
        int n=int.Parse(s);
        error(n<low || n>high,"invalid number "+s);
        return n;
    }
    static string reverse(string s) { return new string(s.Reverse().ToArray()); }
    static string complement(string s) {
        StringBuilder result=new StringBuilder();
        foreach (char c in s.ToCharArray()) result.Append(COMPLEMENTS[SYMBOLS.IndexOf(c)]);
        return result.ToString();
    }
    static string revcomp(string s) { return reverse(complement(s)); }
    static int gc(string s) { return (int)s.Count(c => c=='G' || c=='C'); }
    static string formatFixed(int n, int divisor, int width) {
        string fraction=Convert.ToString(n%divisor);
        return n/divisor+"."+new string('0',width-fraction.Length)+fraction;
    }
    static string pct(int a, int b) { return formatFixed(10000*a/b,100,2); }
    static string milli(int n) { return formatFixed(n,1000,3); }
    static string list(System.Collections.IEnumerable values) { return values.Cast<object>().Any() ? string.Join(" ",values.Cast<object>()) : "none"; }
    static List<string> makeCodons(string s, int frame) {
        string strand=frame>0 ? s : revcomp(s);
        List<string> result=new();
        for (int i=Math.Abs(frame)-1;i+3<=s.Length;i+=3) result.Add(strand.Substring(i,3));
        return result;
    }
    static string translation(List<string> codons) {
        StringBuilder result=new StringBuilder();
        foreach (string c in codons) result.Append(GENETIC[c]);
        return result.ToString();
    }
    static Dictionary<string,int> wordCounts(IEnumerable<string> words) {
        Dictionary<string,int> result=new();
        foreach (string word in words) result[word]=result.GetValueOrDefault(word)+1;
        return result;
    }
    static List<string> frequency(Dictionary<string,int> counts) {
        List<string> result=new(counts.Keys);
        result=result.OrderByDescending(s => counts[s]).ThenBy(s => s,StringComparer.Ordinal).ToList();
        return result;
    }
    static List<int> occurrences(string s, string motif) {
        List<int> result=new();
        for (int i=0;i+motif.Length<=s.Length;i++) {
            bool matches=true;
            for (int j=0;j<motif.Length;j++) {
                if ((MASKS[SYMBOLS.IndexOf(motif[j])] & (1<<BASES.IndexOf(s[i+j])))==0) {
                    matches=false;
                    break;
                }
            }
            if (matches) result.Add(i+1);
        }
        return result;
    }
    static bool transition(char a, char b) { return a!=b && ("AG".IndexOf(a)>=0 && "AG".IndexOf(b)>=0 || "CT".IndexOf(a)>=0 && "CT".IndexOf(b)>=0); }
    static int repeatCount(string s, int i, int u) {
        string unit=s.Substring(i,u);
        int count=1;
        while (i+(count+1)*u<=s.Length && s.Substring(i+count*u,u).Equals(unit)) count++;
        return count;
    }
    static bool primitive(string s) {
        for (int d=1;d<s.Length;d++) if (s.Length%d==0 && string.Concat(Enumerable.Repeat(s.Substring(0,d),s.Length/d)).Equals(s)) return false;
        return true;
    }
    static char complementBase(char c) { return BASES[3-BASES.IndexOf(c)]; }
    static int selfcomp(string s) {
        int maximum=0;
        for (int center=1;center<s.Length;center++) {
            int left=center-1,right=center;
            while (left>=0 && right<s.Length && complementBase(s[left])==s[right]) {
                maximum=Math.Max(maximum,right-left+1);
                left--;
                right++;
            }
        }
        return maximum;
    }
    static int tm(string s) {
        int n=s.Length,g=gc(s);
        return n<14 ? 10*(2*(n-g)+4*g) : (649*n+410*g-6724)/n;
    }
    static int mass(string s) {
        int result=-(s.Length-1)*18015;
        foreach (char c in s.ToCharArray()) result+=BASE_MASS[BASES.IndexOf(c)];
        return result;
    }
    static int properOverlap(string a, string b) {
        string joined=b+"#"+a;
        int[] prefix=new int[joined.Length];
        for (int i=1;i<joined.Length;i++) {
            int j=prefix[i-1];
            while (j>0 && joined[i]!=joined[j]) j=prefix[j-1];
            if (joined[i]==joined[j]) j++;
            prefix[i]=j;
        }
        int result=prefix[^1], limit=Math.Min(a.Length,b.Length);
        while (result>=limit) result=prefix[result-1];
        return result;
    }
    record Orf(int frame, int left, int right, string protein);
    record Repeat(int start, int end, int unitLength, string unit, int count);
    class Toolkit {
        public SortedDictionary<string,string> registry=new(StringComparer.Ordinal);
        public Dictionary<string,string[]> schemas=new();
        public Dictionary<string,int[]> arities=new();
        public List<string> output;
        public Toolkit() {
            schema("SEQ",2,2,"NEW","SEQ");
            schema("SLICE",4,4,"NAME","POS","POS","NEW");
            schema("JOIN",3,9,"NEW","NAME");
            schema("MUTATE",3,3,"NAME","POS","BASE");
            foreach (string c in new string[]{"DEL","REVCOMP","COMPLEMENT","REVERSE","TRANSCRIBE","GC","SKEW","TM","MASS","PRIMER","PACK"}) schema(c,1,1,"NAME");
            schema("LIST",0,0);
            foreach (string c in new string[]{"TRANSLATE","CODONS","PROTEIN"}) schema(c,2,2,"NAME","FRAME");
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
        public void schema(string c, int low, int high, params string[] args) {
            schemas[c]=args;
            arities[c]=new int[]{low,high};
        }
        public void emit(string s) { output.Add(s); }
        public void store(string name, string sequence) {
            error(sequence.Length>500,"too long");
            bool replacing=registry.ContainsKey(name);
            registry[name]=sequence;
            emit((replacing ? "replaced " : "stored ")+name+" "+sequence.Length+" nt");
        }
        public void validate(string command, string[] a, int[] nums, string[] sequences) {
            error(!schemas.ContainsKey(command),"unknown command "+command);
            int[] count=arities[command];
            error(a.Length<count[0] || a.Length>count[1],"wrong argument count");
            string[] schema=schemas[command];
            HashSet<string> enzymes=new();
            for (int i=0;i<a.Length;i++) {
                string kind=schema[Math.Min(i,schema.Length-1)], value=a[i];
                switch (kind) {
                    case "NAME":
                        error(!registry.ContainsKey(value),"unknown sequence "+value);
                        sequences[i]=registry[value];
                        break;
                    case "NEW":
                        error(!matches(value,"[a-z][a-z0-9]{0,9}"),"invalid name "+value);
                        break;
                    case "SEQ":
                        for (int j=0;j<value.Length;j++) error(BASES.IndexOf(value[j])<0,"invalid base "+value[j]+" at "+(j+1));
                        break;
                    case "BASE":
                        error(value.Length!=1 || BASES.IndexOf(value[0])<0,"invalid base "+value);
                        break;
                    case "MOTIF":
                        error(!matches(value,"[ACGTRYSWKMBDHVN]{1,30}"),"invalid motif "+value);
                        break;
                    case "ENZYME":
                        error(!ENZYMES.Contains(value),"unknown enzyme "+value);
                        error(!enzymes.Add(value),"duplicate enzyme "+value);
                        break;
                    case "MODE":
                        error(!value.Equals("GLOBAL") && !value.Equals("LOCAL"),"invalid mode "+value);
                        break;
                    case "HEX":
                        error(value.Length!=2*((nums[1]+3)/4) || !matches(value,"[0-9A-F]+"),"invalid hex");
                        break;
                    case "FRAME":
                        nums[i]=number(value,-3,3);
                        error(nums[i]==0,"invalid number "+value);
                        break;
                    case "POS":
                        nums[i]=number(value,1,sequences[0].Length);
                        break;
                    default:
                        string[] bounds=kind.Split(':');
                        nums[i]=number(value,int.Parse(bounds[0]),int.Parse(bounds[1]));
                        break;
                }
            }
        }
        public void align(string a, string b, bool local, int match, int mismatch, int gap) {
            int m=a.Length,n=b.Length;
            int[][] h=Matrix(m+1,n+1);
            if (!local) {
                for (int i=0;i<=m;i++) h[i][0]=i*gap;
                for (int j=0;j<=n;j++) h[0][j]=j*gap;
            }
            int best=0,bi=0,bj=0;
            for (int i=1;i<=m;i++) {
                for (int j=1;j<=n;j++) {
                    int value=Math.Max(h[i-1][j-1]+(a[i-1]==b[j-1] ? match : mismatch),Math.Max(h[i-1][j]+gap,h[i][j-1]+gap));
                    h[i][j]=local ? Math.Max(0,value) : value;
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
                emit("score 0");
                return;
            }
            int traceI=bi,traceJ=bj;
            StringBuilder x=new StringBuilder(),y=new StringBuilder();
            while (local ? h[traceI][traceJ]!=0 : traceI!=0 || traceJ!=0) {
                if (traceI>0 && traceJ>0 && h[traceI][traceJ]==h[traceI-1][traceJ-1]+(a[traceI-1]==b[traceJ-1] ? match : mismatch)) {
                    x.Append(a[--traceI]);
                    y.Append(b[--traceJ]);
                } else if (traceI>0 && h[traceI][traceJ]==h[traceI-1][traceJ]+gap) {
                    x.Append(a[--traceI]);
                    y.Append('-');
                } else {
                    x.Append('-');
                    y.Append(b[--traceJ]);
                }
            }
            string left=reverse(x.ToString()),right=reverse(y.ToString());
            StringBuilder middle=new StringBuilder();
            int identity=0,gaps=0;
            for (int k=0;k<left.Length;k++) {
                char c=left[k]=='-' || right[k]=='-' ? '-' : left[k]==right[k] ? '|' : '*';
                middle.Append(c);
                if (c=='|') identity++;
                if (c=='-') gaps++;
            }
            emit("score "+best+" a "+(traceI+1)+"-"+bi+" b "+(traceJ+1)+"-"+bj+" identity "+identity+"/"+left.Length+" gaps "+gaps);
            emit(left);
            emit(middle.ToString());
            emit(right);
        }
        public bool pair(char a, char b) { return complementBase(a)==b || a=='G' && b=='T' || a=='T' && b=='G'; }
        public int value(int[][] f, int i, int j) { return i>j ? 0 : f[i][j]; }
        public void fold(string s, int loop) {
            int n=s.Length;
            error(n>100,"too long");
            int[][] f=Matrix(n,n);
            for (int length=1;length<=n;length++) {
                for (int i=0;i+length<=n;i++) {
                    int j=i+length-1;
                    f[i][j]=value(f,i,j-1);
                    for (int k=i;k<=j-loop-1;k++) if (pair(s[k],s[j])) f[i][j]=Math.Max(f[i][j],value(f,i,k-1)+1+value(f,k+1,j-1));
                }
            }
            char[] structure=new char[n];
            Array.Fill(structure,'.');
            Stack<int[]> intervals=new();
            intervals.Push(new int[]{0,n-1});
            while (intervals.Count!=0) {
                int[] interval=intervals.Pop();
                int i=interval[0],j=interval[1];
                if (value(f,i,j)==0) continue;
                if (f[i][j]==value(f,i,j-1)) intervals.Push(new int[]{i,j-1});
                else {
                    for (int k=i;k<=j-loop-1;k++) {
                        if (pair(s[k],s[j]) && value(f,i,k-1)+1+value(f,k+1,j-1)==f[i][j]) {
                            structure[k]='(';
                            structure[j]=')';
                            intervals.Push(new int[]{i,k-1});
                            intervals.Push(new int[]{k+1,j-1});
                            break;
                        }
                    }
                }
            }
            emit(new string(structure));
            emit("pairs "+f[0][n-1]);
        }
        public void primer(string s) {
            int n=s.Length,g=gc(s),temperature=tm(s),clamp=gc(s.Substring(Math.Max(0,n-5))),run=1,bestRun=1,repeats=0;
            for (int i=1;i<n;i++) {
                run=s[i]==s[i-1] ? run+1 : 1;
                bestRun=Math.Max(bestRun,run);
            }
            for (int i=0;i+1<n;i++) if (s[i]!=s[i+1]) repeats=Math.Max(repeats,repeatCount(s,i,2));
            int self=selfcomp(s);
            string[] names={"length","gc","tm","clamp","run","repeat","selfcomp"};
            string[] values={Convert.ToString(n),pct(g,n),formatFixed(temperature,10,1),Convert.ToString(clamp),Convert.ToString(bestRun),Convert.ToString(repeats),Convert.ToString(self)};
            bool[] ok={n>=18 && n<=25,40*n<=100*g && 100*g<=60*n,temperature>=520 && temperature<=620,clamp>=1 && clamp<=3,bestRun<=4,repeats<=4,self<=6};
            List<string> failed=new();
            for (int i=0;i<7;i++) {
                emit(names[i]+" "+values[i]+" "+(ok[i] ? "OK" : "FAIL"));
                if (!ok[i]) failed.Add(names[i]);
            }
            emit(failed.Count==0 ? "PASS" : "FAIL "+list(failed));
        }
        public void assemble(string name, int minimum, string[] sequences) {
            List<string> unique=new();
            foreach (string sequence in sequences.Skip(2)) {
                if (!unique.Contains(sequence)) unique.Add(sequence);
            }
            List<string> fragments=new();
            foreach (string s in unique) if (!unique.Any(t => !t.Equals(s) && t.Contains(s))) fragments.Add(s);
            while (fragments.Count>=2) {
                int best=-1,bx=0,by=0;
                for (int x=0;x<fragments.Count;x++) {
                    for (int y=0;y<fragments.Count;y++) {
                        if (x==y) continue;
                        string a=fragments[x],b=fragments[y];
                        int overlap=properOverlap(a,b);
                        if (overlap>best) {
                            best=overlap;
                            bx=x;
                            by=y;
                        }
                    }
                }
                if (best<minimum) break;
                string merged=fragments[bx]+fragments[by].Substring(best);
                fragments[bx]=merged;
                fragments.RemoveAt(by);
                int keep=bx-(by<bx ? 1 : 0);
                for (int i=fragments.Count-1;i>=0;i--) {
                    if (i!=keep && merged.Contains(fragments[i])) {
                        fragments.RemoveAt(i);
                        if (i<keep) keep--;
                    }
                }
            }
            string longest=fragments[0];
            foreach (string s in fragments) if (s.Length>longest.Length) longest=s;
            error(longest.Length>500,"too long");
            emit("contigs "+fragments.Count);
            foreach (string s in fragments) emit(s.Length+" "+s);
            store(name,longest);
        }
        public void execute(string line) {
            string[] t=line.Split(' '),a=t.Skip(1).ToArray();
            int[] nums=new int[a.Length];
            string[] sequences=new string[a.Length];
            string command=t[0];
            validate(command,a,nums,sequences);
            string s=a.Length==0 ? "" : sequences[0];
            int n=s==null ? 0 : s.Length;
            switch (command) {
                case "SEQ":
                    store(a[0],a[1]);
                    break;
                case "SLICE": {
                    int left=Math.Min(nums[1],nums[2]),right=Math.Max(nums[1],nums[2]);
                    string part=s.Substring(left-1,right-left+1);
                    store(a[3],nums[1]<=nums[2] ? part : revcomp(part));
                    break;
                }
                case "JOIN":
                    store(a[0],string.Join("",sequences.Skip(1)));
                    break;
                case "MUTATE": {
                    char old=s[nums[1]-1],next=a[2][0];
                    error(old==next,"no change");
                    registry[a[0]]=s.Substring(0,nums[1]-1)+next+s.Substring(nums[1]);
                    emit(a[0]+" "+old+nums[1]+next+" "+(transition(old,next) ? "transition" : "transversion"));
                    break;
                }
                case "DEL":
                    registry.Remove(a[0]);
                    emit("deleted "+a[0]);
                    break;
                case "LIST":
                    if (registry.Count==0) emit("no sequences");
                    else foreach (string name in registry.Keys) emit(name+" "+registry[name].Length+" nt");
                    break;
                case "REVCOMP":
                    emit(revcomp(s));
                    break;
                case "COMPLEMENT":
                    emit(complement(s));
                    break;
                case "REVERSE":
                    emit(reverse(s));
                    break;
                case "TRANSCRIBE":
                    emit(s.Replace('T','U'));
                    break;
                case "TRANSLATE": {
                    string protein=translation(makeCodons(s,nums[1]));
                    emit(protein.Length==0 ? "none" : protein);
                    break;
                }
                case "CODONS": {
                    Dictionary<string,int> counts=wordCounts(makeCodons(s,nums[1]));
                    if (counts.Count==0) emit("none");
                    foreach (string c in frequency(counts)) emit(c+" "+GENETIC[c]+" "+counts[c]);
                    break;
                }
                case "PROTEIN": {
                    string protein=translation(makeCodons(s,nums[1])).Split('*')[0];
                    error(protein.Length==0,"empty protein");
                    int mass=18015,charge=0;
                    List<string> letters=new();
                    foreach (char c in protein.ToCharArray()) {
                        mass+=RESIDUES[AMINO.IndexOf(c)];
                        charge+="KR".IndexOf(c)>=0 ? 1 : "DE".IndexOf(c)>=0 ? -1 : 0;
                        letters.Add(c.ToString());
                    }
                    Dictionary<string,int> counts=wordCounts(letters);
                    emit(protein);
                    emit("length "+protein.Length+" mass "+milli(mass)+" charge "+(charge>0 ? "+" : "")+charge);
                    emit(string.Join(" ",frequency(counts).Select(c => c+"="+counts[c])));
                    break;
                }
                case "ORFS": {
                    List<Orf> found=new();
                    foreach (int frame in new int[]{1,2,3,-1,-2,-3}) {
                        List<string> codons=makeCodons(s,frame);
                        int start=-1;
                        for (int i=0;i<codons.Count;i++) {
                            if (start<0 && codons[i].Equals("ATG")) start=i;
                            else if (start>=0 && GENETIC[codons[i]]=='*') {
                                if (i-start>=nums[1]) {
                                    int left=Math.Abs(frame)-1+3*start,right=Math.Abs(frame)-1+3*(i+1)-1;
                                    found.Add(new Orf(frame,frame>0 ? left+1 : n-right,frame>0 ? right+1 : n-left,translation(codons.GetRange(start,i-start))));
                                }
                                start=-1;
                            }
                        }
                    }
                    found=found.OrderBy(o => o.left).ToList();
                    if (found.Count==0) emit("none");
                    foreach (Orf o in found) emit((o.frame>0 ? "+" : "")+o.frame+" "+o.left+" "+o.right+" "+o.protein.Length+" "+o.protein);
                    break;
                }
                case "GC": {
                    string lineOut="";
                    foreach (char c in BASES.ToCharArray()) lineOut+=(lineOut.Length==0 ? "" : " ")+c+"="+s.Count(x => x==c);
                    emit(lineOut+" GC="+pct(gc(s),n)+"%");
                    break;
                }
                case "GCWINDOW":
                    error(nums[1]>n,"window too large");
                    for (int i=0;i+nums[1]<=n;i+=nums[2]) emit((i+1)+"-"+(i+nums[1])+" "+pct(gc(s.Substring(i,nums[1])),nums[1])+"%");
                    break;
                case "SKEW": {
                    int[] skew=new int[n+1];
                    for (int i=0;i<n;i++) skew[i+1]=skew[i]+(s[i]=='G' ? 1 : s[i]=='C' ? -1 : 0);
                    foreach (bool minimum in new bool[]{true,false}) {
                        int v=minimum ? skew.Min() : skew.Max();
                        List<int> at=new();
                        for (int i=0;i<=n;i++) if (skew[i]==v) at.Add(i);
                        emit((minimum ? "min " : "max ")+v+" at "+list(at));
                    }
                    break;
                }
                case "KMERS": {
                    error(nums[1]>n,"k too large");
                    List<string> words=new();
                    for (int i=0;i+nums[1]<=n;i++) words.Add(s.Substring(i,nums[1]));
                    Dictionary<string,int> counts=wordCounts(words);
                    emit(words.Count+" windows "+counts.Count+" distinct");
                    List<string> order=frequency(counts);
                    for (int i=0;i<Math.Min(nums[2],order.Count);i++) emit(order[i]+" "+counts[order[i]]);
                    break;
                }
                case "FIND":
                    emit("forward "+list(occurrences(s,a[1])));
                    emit("reverse "+list(occurrences(s,revcomp(a[1]))));
                    break;
                case "RESTRICT": {
                    SortedSet<int> cuts=new();
                    for (int i=1;i<a.Length;i++) {
                        int e=Array.IndexOf(ENZYMES,a[i]);
                        List<int> found=new();
                        foreach (int p in occurrences(s,SITES[e])) {
                            int c=p+CUTS[e]-1;
                            if (c>=1 && c<n) {
                                found.Add(c);
                                cuts.Add(c);
                            }
                        }
                        emit(a[i]+" "+list(found));
                    }
                    List<string> fragments=new();
                    List<int> sizes=new(),ends=new(cuts);
                    ends.Add(n);
                    int previous=0;
                    foreach (int end in ends) {
                        fragments.Add((previous+1)+"-"+end);
                        sizes.Add(end-previous);
                        previous=end;
                    }
                    sizes.Sort((leftSize,rightSize) => rightSize.CompareTo(leftSize));
                    emit("fragments "+list(fragments));
                    emit("sizes "+list(sizes));
                    break;
                }
                case "PALINDROMES": {
                    error(nums[1]>nums[2],"invalid range");
                    int count=0;
                    for (int i=0;i<n;i++) {
                        for (int length=nums[1];length<=nums[2] && i+length<=n;length++) {
                            string part=s.Substring(i,length);
                            if (part.Equals(revcomp(part))) {
                                emit((i+1)+" "+length+" "+part);
                                count++;
                            }
                        }
                    }
                    if (count==0) emit("none");
                    break;
                }
                case "REPEATS": {
                    error(nums[1]>nums[2],"invalid range");
                    List<Repeat> found=new();
                    for (int u=nums[1];u<=nums[2];u++) {
                        int i=0;
                        while (i+u<=n) {
                            string unit=s.Substring(i,u);
                            int count=repeatCount(s,i,u);
                            if (primitive(unit) && count>=nums[3]) {
                                found.Add(new Repeat(i+1,i+count*u,u,unit,count));
                                i+=count*u;
                            } else i++;
                        }
                    }
                    found=found.OrderBy(r => r.start).ThenBy(r => r.unitLength).ToList();
                    if (found.Count==0) emit("none");
                    foreach (Repeat r in found) emit(r.start+"-"+r.end+" "+r.unit+"x"+r.count);
                    break;
                }
                case "HAMMING": {
                    string b=sequences[1];
                    error(n!=b.Length,"length mismatch");
                    int distance=0,transitions=0;
                    for (int i=0;i<n;i++) {
                        if (s[i]!=b[i]) {
                            distance++;
                            if (transition(s[i],b[i])) transitions++;
                        }
                    }
                    emit("distance "+distance+" transitions "+transitions+" transversions "+(distance-transitions));
                    break;
                }
                case "ALIGN":
                    align(s,sequences[1],a[2].Equals("LOCAL"),nums[3],nums[4],nums[5]);
                    break;
                case "CONSENSUS": {
                    foreach (string sequence in sequences) error(sequence.Length!=n,"length mismatch");
                    int[][] profile=Matrix(4,n);
                    StringBuilder consensus=new StringBuilder(),iupac=new StringBuilder();
                    for (int i=0;i<n;i++) {
                        foreach (string sequence in sequences) profile[BASES.IndexOf(sequence[i])][i]++;
                        int maximum=0,mask=0;
                        for (int b=0;b<4;b++) maximum=Math.Max(maximum,profile[b][i]);
                        bool chosen=false;
                        for (int b=0;b<4;b++) {
                            if (profile[b][i]==maximum) {
                                mask|=1<<b;
                                if (!chosen) {
                                    consensus.Append(BASES[b]);
                                    chosen=true;
                                }
                            }
                        }
                        for (int j=0;j<MASKS.Length;j++) if (MASKS[j]==mask) iupac.Append(SYMBOLS[j]);
                    }
                    for (int b=0;b<4;b++) {
                        List<int> row=new();
                        foreach (int count in profile[b]) row.Add(count);
                        emit(BASES[b]+" "+list(row));
                    }
                    emit("consensus "+consensus);
                    emit("iupac "+iupac);
                    break;
                }
                case "TM":
                    emit("Tm "+formatFixed(tm(s),10,1)+" "+(n<14 ? "wallace" : "gc"));
                    break;
                case "MASS":
                    emit("ss "+milli(mass(s))+" ds "+milli(mass(s)+mass(revcomp(s))));
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
                        for (int j=0;j<4;j++) value=4*value+(i+j<n ? BASES.IndexOf(s[i+j]) : 0);
                        hex.Append(HEX[value/16]).Append(HEX[value%16]);
                    }
                    emit(n+" "+hex);
                    break;
                }
                case "UNPACK": {
                    StringBuilder decoded=new StringBuilder();
                    for (int i=0;i<a[2].Length;i+=2) {
                        int value=16*HEX.IndexOf(a[2][i])+HEX.IndexOf(a[2][i+1]);
                        foreach (int shift in new int[]{6,4,2,0}) decoded.Append(BASES[value>>shift&3]);
                    }
                    for (int i=nums[1];i<decoded.Length;i++) error(decoded[i]!='A',"invalid padding");
                    store(a[0],decoded.ToString(0,nums[1]));
                    break;
                }
            }
        }
        public List<string> process(string line) {
            output=new();
            try { execute(line); }
            catch (Fault fault) {
                output.Clear();
                emit("ERROR "+fault.Message);
            }
            return output;
        }
    }
    static bool matches(string s, string pattern) => Regex.IsMatch(s,"\\A(?:"+pattern+")\\z",RegexOptions.CultureInvariant);
    static int[][] Matrix(int rows, int columns) => Enumerable.Range(0,rows).Select(_ => new int[columns]).ToArray();
    static void Main() {
        CultureInfo.CurrentCulture=CultureInfo.InvariantCulture;
        Toolkit toolkit=new();
        int n=int.Parse(Console.ReadLine()!);
        for (int i=0;i<n;i++) {
            foreach (string line in toolkit.process(Console.ReadLine()!)) Console.WriteLine(line);
        }
    }
}
