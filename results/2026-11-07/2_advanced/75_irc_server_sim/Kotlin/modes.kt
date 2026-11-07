object Modes {
    data class Item(val sign: Char,val character: Char,val argument: String?)
    fun channelItems(mode: String,arguments: List<String>): List<Item> {
        val items=mutableListOf<Item>();
        var sign='+';
        var position=0;
        for(c in mode) {
            if(c=='+'||c=='-') {
                sign=c;
                continue
            };
            var argument: String?=null;
            if(c in "ovbk"||c=='l'&&sign=='+')if(position<arguments.size)argument=arguments[position++];
            if(c=='k'&&sign=='-')argument="*" else if(c=='l'&&sign=='+') {
                if(argument==null||!Protocol.digits(argument)||argument.length>4||argument.toInt()<1)argument=null
            };
            items.add(Item(sign,c,argument))
        };
        return items
    }
    fun changeString(changes: List<Item>): String {
        val mode=StringBuilder();
        val arguments=mutableListOf<String>();
        var previous='\u0000';
        for(item in changes) {
            if(item.sign!=previous) {
                mode.append(item.sign);
                previous=item.sign
            };
            mode.append(item.character);
            item.argument?.let {
                arguments.add(it)
            }
        };
        for(argument in arguments)mode.append(' ').append(argument);
        return mode.toString()
    }
}
