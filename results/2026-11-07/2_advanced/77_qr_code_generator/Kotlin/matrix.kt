object Matrix {
    const val DATA=0;
    const val FUNCTION=1;
    const val FORMAT=2;
    const val VERSION=3
    data class Point(val x: Int,val y: Int)
    data class Positions(val first: List<Point>,val second: List<Point>)
    data class Built(val symbol: Array<IntArray>,val areas: Array<IntArray>,val order: List<Point>)
    fun formatPositions(size: Int): Positions {
        val first=mutableListOf<Point>();
        val second=mutableListOf<Point>();
        for(i in 0 until 15) {
            first.add(when {
                i<6->Point(8,i);
                i==6->Point(8,7);
                i==7->Point(8,8);
                i==8->Point(7,8);
                else->Point(14-i,8)
            });
            second.add(if(i<8)Point(size-1-i,8) else Point(8,size-15+i))
        };
        return Positions(first,second)
    }
    fun versionPositions(size: Int)=Positions((0 until 18).map {
        Point(size-11+it%3,it/3)
    },(0 until 18).map {
        Point(it/3,size-11+it%3)
    })
    fun remainder(initial: Int,divisor: Int): Int {
        var value=initial;
        val degree=31-Integer.numberOfLeadingZeros(divisor);
        while(value!=0&&31-Integer.numberOfLeadingZeros(value)>=degree)value=value xor (divisor shl (31-Integer.numberOfLeadingZeros(value)-degree));
        return value
    }
    fun formatInformation(level: String,mask: Int): Int {
        val indicator=when(level) {
            "L"->1;
            "M"->0;
            "Q"->3;
            else->2
        };
        val shifted=(8*indicator+mask) shl 10;
        return (shifted+remainder(shifted,0x537)) xor 0x5412
    }
    fun versionInformation(version: Int): Int {
        val shifted=version shl 12;
        return shifted+remainder(shifted,0x1F25)
    }
    fun writeValue(symbol: Array<IntArray>,positions: List<Point>,value: Int) {
        for((i,p) in positions.withIndex())symbol[p.y][p.x]=(value ushr i) and 1
    }
    fun readValue(symbol: Array<IntArray>,positions: List<Point>): Int {
        var value=0;
        for((i,p) in positions.withIndex())value=value or (symbol[p.y][p.x] shl i);
        return value
    }
    fun copy(symbol: Array<IntArray>)=Array(symbol.size) {
        symbol[it].copyOf()
    }
    fun build(version: Int,alignments: IntArray): Built {
        val size=17+4*version;
        val symbol=Array(size) {
            IntArray(size)
        };
        val areas=Array(size) {
            IntArray(size)
        };
        for(center in listOf(Point(3,3),Point(size-4,3),Point(3,size-4)))for(dy in -4..4)for(dx in -4..4) {
            val x=center.x+dx;
            val y=center.y+dy;
            if(x !in 0 until size||y !in 0 until size)continue;
            val distance=maxOf(kotlin.math.abs(dx),kotlin.math.abs(dy));
            symbol[y][x]=if(distance==0||distance==1||distance==3)1 else 0;
            areas[y][x]=FUNCTION
        };
        for(i in 8..size-9) {
            val value=if(i%2==0)1 else 0;
            symbol[i][6]=value;
            symbol[6][i]=value;
            areas[i][6]=FUNCTION;
            areas[6][i]=FUNCTION
        };
        for(yi in alignments.indices)for(xi in alignments.indices) {
            if(yi==0&&(xi==0||xi==alignments.lastIndex)||yi==alignments.lastIndex&&xi==0)continue;
            for(dy in -2..2)for(dx in -2..2) {
                val x=alignments[xi]+dx;
                val y=alignments[yi]+dy;
                symbol[y][x]=if(maxOf(kotlin.math.abs(dx),kotlin.math.abs(dy))!=1)1 else 0;
                areas[y][x]=FUNCTION
            }
        };
        symbol[size-8][8]=1;
        areas[size-8][8]=FUNCTION;
        val format=formatPositions(size);
        for(positions in listOf(format.first,format.second))for(p in positions)areas[p.y][p.x]=FORMAT;
        if(version>=7) {
            val information=versionPositions(size);
            for(positions in listOf(information.first,information.second)) {
                for(p in positions)areas[p.y][p.x]=VERSION;
                writeValue(symbol,positions,versionInformation(version))
            }
        };
        return Built(symbol,areas,readingOrder(areas))
    }
    fun readingOrder(areas: Array<IntArray>): List<Point> {
        val size=areas.size;
        val order=mutableListOf<Point>();
        var right=size-1;
        var pair=0;
        while(right>=1) {
            if(right==6)right=5;
            for(i in 0 until size) {
                val y=if(pair%2==0)size-1-i else i;
                for(x in right downTo right-1)if(areas[y][x]==DATA)order.add(Point(x,y))
            };
            pair++;
            right-=2
        };
        return order
    }
}
