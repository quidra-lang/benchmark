object Masks {
    fun matches(inputMask: String,inputValue: String): Boolean {
        val mask=Protocol.fold(inputMask);
        val value=Protocol.fold(inputValue);
        var pattern=0;
        var position=0;
        var star=-1;
        var restart=0;
        while(position<value.length) {
            if(pattern<mask.length&&mask[pattern]=='*') {
                star=pattern;
                pattern++;
                restart=position
            } else if(pattern<mask.length&&(mask[pattern]=='?'||mask[pattern]==value[position])) {
                pattern++;
                position++
            } else if(star>=0) {
                restart++;
                position=restart;
                pattern=star+1
            } else return false
        };
        while(pattern<mask.length&&mask[pattern]=='*')pattern++;
        return pattern==mask.length
    }
    fun normalize(argument: String)=when {
        '!' in argument&&'@' in argument->argument;
        '@' in argument->"*!$argument";
        '!' in argument->"$argument@*";
        '.' in argument->"*!*@$argument";
        else->"$argument!*@*"
    }
}
