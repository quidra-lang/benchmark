object Protocol {
    const val SPECIAL="[]\\`_^{}|"
    data class Message(val command: String,val parameters: List<String>)
    fun fold(value: String)=buildString {
        for(c in value)append(if(c in 'A'..'Z')c+32 else when(c) {
            '['->'{';
            ']'->'}';
            '\\'->'|';
            '^'->'~';
            else->c
        })
    }
    fun letter(c: Char)=c in 'A'..'Z'||c in 'a'..'z'
    fun digits(value: String)=value.isNotEmpty()&&value.all {
        it in '0'..'9'
    }
    fun validNickname(value: String)=value.isNotEmpty()&&(letter(value[0])||value[0] in SPECIAL)&&value.drop(1).all {
        letter(it)||it in SPECIAL||it in '0'..'9'||it=='-'
    }
    fun validChannel(value: String,maximum: Int)=value.length in 2..maximum&&value.startsWith('#')&&':' !in value
    fun parse(raw: String): Message {
        var position=0;
        if(raw.startsWith(':')) {
            position=raw.indexOf(' ');
            if(position<0)return Message("",emptyList())
        };
        while(position<raw.length&&raw[position]==' ')position++;
        var start=position;
        while(position<raw.length&&raw[position]!=' ')position++;
        val command=raw.substring(start,position).uppercase();
        val parameters=mutableListOf<String>();
        while(position<raw.length) {
            while(position<raw.length&&raw[position]==' ')position++;
            if(position==raw.length)break;
            if(raw[position]==':') {
                parameters.add(raw.substring(position+1));
                break
            };
            if(parameters.size==14) {
                parameters.add(raw.substring(position));
                break
            };
            start=position;
            while(position<raw.length&&raw[position]!=' ')position++;
            parameters.add(raw.substring(start,position))
        };
        return Message(command,parameters)
    }
}
