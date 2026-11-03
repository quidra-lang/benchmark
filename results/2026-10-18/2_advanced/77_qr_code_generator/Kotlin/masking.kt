object Masking {
    data class Penalty(val n1: Int,val n2: Int,val n3: Int,val n4: Int) {
        fun total()=n1+n2+n3+n4
    }
    fun condition(mask: Int,x: Int,y: Int)=when(mask) {
        0->(y+x)%2==0;
        1->y%2==0;
        2->x%3==0;
        3->(y+x)%3==0;
        4->(y/2+x/3)%2==0;
        5->(y*x)%2+(y*x)%3==0;
        6->((y*x)%2+(y*x)%3)%2==0;
        else->((y+x)%2+(y*x)%3)%2==0
    }
    fun apply(symbol: Array<IntArray>,order: List<Matrix.Point>,mask: Int): Array<IntArray> {
        val result=Matrix.copy(symbol);
        for(p in order)if(condition(mask,p.x,p.y))result[p.y][p.x]=result[p.y][p.x] xor 1;
        return result
    }
    fun penalties(symbol: Array<IntArray>): Penalty {
        val size=symbol.size;
        var n1=0;
        var n2=0;
        var n3=0;
        var dark=0;
        for(orientation in 0..1)for(line in 0 until size) {
            var previous=-1;
            var run=0;
            var window=0;
            for(i in 0 until size) {
                val value=if(orientation==0)symbol[line][i] else symbol[i][line];
                if(value==previous)run++ else {
                    if(run>=5)n1+=run-2;
                    previous=value;
                    run=1
                };
                window=((window shl 1) or value) and 2047;
                if(i>=10&&(window==0b10111010000||window==0b00001011101))n3+=40
            };
            if(run>=5)n1+=run-2
        };
        for(y in 0 until size)for(x in 0 until size) {
            dark+=symbol[y][x];
            if(y+1<size&&x+1<size&&symbol[y][x]==symbol[y+1][x]&&symbol[y][x]==symbol[y][x+1]&&symbol[y][x]==symbol[y+1][x+1])n2+=3
        };
        return Penalty(n1,n2,n3,10*(kotlin.math.abs(20*dark-10*size*size)/(size*size)))
    }
}
