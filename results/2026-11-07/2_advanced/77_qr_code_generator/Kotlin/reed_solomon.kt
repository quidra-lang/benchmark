object ReedSolomon {
    val exp=IntArray(255);
    val log=IntArray(256);
    private val generators=mutableMapOf<Int,IntArray>()
    init {
        exp[0]=1;
        for(i in 1 until 255) {
            val value=2*exp[i-1];
            exp[i]=if(value>=256)value xor 285 else value
        };
        for(i in 0 until 255)log[exp[i]]=i
    }
    data class Correction(val syndromes: IntArray,val corrected: IntArray?,val positions: List<Int>)
    fun multiply(a: Int,b: Int)=if(a==0||b==0)0 else exp[(log[a]+log[b])%255]
    fun divide(a: Int,b: Int)=if(a==0)0 else exp[(log[a]-log[b]+255)%255]
    fun generator(degree: Int): IntArray=generators.getOrPut(degree) {
        var coefficients=intArrayOf(1);
        for(power in 0 until degree) {
            val product=IntArray(coefficients.size+1);
            for(j in coefficients.indices) {
                product[j]=product[j] xor coefficients[j];
                product[j+1]=product[j+1] xor multiply(coefficients[j],exp[power])
            };
            coefficients=product
        };
        coefficients
    }
    fun parity(data: IntArray,degree: Int): IntArray {
        val dividend=data.copyOf(data.size+degree);
        val generator=generator(degree);
        for(i in data.indices) {
            val leading=dividend[i];
            if(leading!=0)for(j in generator.indices)dividend[i+j]=dividend[i+j] xor multiply(leading,generator[j])
        };
        return dividend.copyOfRange(data.size,dividend.size)
    }
    fun syndromes(words: IntArray,degree: Int): IntArray {
        val values=IntArray(degree);
        for(j in 0 until degree)for(word in words)values[j]=multiply(values[j],exp[j]) xor word;
        return values
    }
    fun evaluate(coefficients: IntArray,x: Int): Int {
        var value=0;
        for(i in coefficients.lastIndex downTo 0)value=multiply(value,x) xor coefficients[i];
        return value
    }
    fun correct(received: IntArray,degree: Int): Correction {
        val syndromes=syndromes(received,degree);
        if(syndromes.all {
            it==0
        })return Correction(syndromes,received.copyOf(),emptyList());
        var locator=IntArray(degree+1);
        var previous=IntArray(degree+1);
        locator[0]=1;
        previous[0]=1;
        var length=0;
        var shift=1;
        var beta=1;
        for(q in 0 until degree) {
            var discrepancy=syndromes[q];
            for(i in 1..length)discrepancy=discrepancy xor multiply(locator[i],syndromes[q-i]);
            if(discrepancy==0) {
                shift++;
                continue
            };
            val saved=locator.copyOf();
            val multiplier=divide(discrepancy,beta);
            for(i in 0..degree-shift)locator[i+shift]=locator[i+shift] xor multiply(multiplier,previous[i]);
            if(2*length<=q) {
                length=q+1-length;
                previous=saved;
                beta=discrepancy;
                shift=1
            }else shift++
        };
        if(length>degree/2)return Correction(syndromes,null,emptyList());
        locator=locator.copyOf(length+1);
        val roots=received.indices.filter {
            evaluate(locator,exp[(255-(received.size-1-it))%255])==0
        };
        if(roots.size!=length)return Correction(syndromes,null,emptyList());
        val omega=IntArray(degree);
        val derivative=IntArray(length);
        for(i in 0 until degree)for(j in 0 until minOf(locator.size,degree-i))omega[i+j]=omega[i+j] xor multiply(syndromes[i],
            locator[j]);
        for(h in 1..length step 2)derivative[h-1]=locator[h];
        val corrected=received.copyOf();
        for(i in roots) {
            val x=exp[(received.size-1-i)%255];
            val z=exp[(255-(received.size-1-i))%255];
            val denominator=evaluate(derivative,z);
            if(denominator==0)return Correction(syndromes,null,emptyList());
            corrected[i]=corrected[i] xor multiply(x,divide(evaluate(omega,z),denominator))
        };
        if(ReedSolomon.syndromes(corrected,degree).any {
            it!=0
        })return Correction(syndromes,null,emptyList());
        return Correction(syndromes,corrected,received.indices.filter {
            received[it]!=corrected[it]
        })
    }
}
