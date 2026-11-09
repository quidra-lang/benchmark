object ColumnarProgram {
    val scanCounts=listOf("row_groups_read","row_groups_skipped","pages_read","pages_skipped","pages_unneeded",
        "dictionary_pages_read","bytes_read","rows_scanned","rows_matched")
    class Counts {
        val values=mutableMapOf<String,Int>();
        fun get(name: String)=values.getOrDefault(name,0);
        fun add(name: String,amount: Int) {
            values[name]=get(name)+amount
        };
        fun text()=scanCounts.joinToString(" ") {
            "$it ${get(it)}"
        }
    }
    class Page {
        var offset=0;
        var kind=0;
        var method=0;
        var values=0;
        var nulls=0;
        var bodySize=0;
        var headerSize=0;
        var bodyOffset=0;
        var size=0;
        var checksum=0L;
        var bounds: Encoding.Bounds?=null
    }
    class Chunk {
        var data=ByteArray(0);
        var offset=0;
        var size=0;
        var pageCount=0;
        var nulls=0;
        var fallback=0;
        var methods: List<Int> = emptyList();
        var hasDictionary=false;
        var bounds: Encoding.Bounds?=null;
        var dictionary: Page?=null;
        val pages=mutableListOf<Page>()
    }
    class RowGroup(val rows: Int,val firstRow: Int) {
        val chunks=mutableListOf<Chunk>()
    }
    data class Built(val data: ByteArray,val report: List<String>)
    data class Store(val data: ByteArray,val version: Int,val columns: List<SchemaIo.Column>,val rows: Int,
        val groups: List<RowGroup>,val footerSize: Int,val footerOffset: Int)
    data class BoundItem(val operation: String,val index: Int)
    data class Plan(val items: List<BoundItem>,val headers: List<String>,val condition: Query.Condition?,
        val group: Int,val order: Int,val descending: Boolean,val limit: Int?,val aggregate: Boolean,
        val needed: List<Int>,val conditionColumns: List<Int>)
    data class Checked(val error: String?,val plan: Plan?)
    data class Zone(val bounds: Encoding.Bounds?,val nulls: Int,val count: Int)
    data class Possibilities(val canTrue: Boolean,val canFalse: Boolean)
    data class Scan(val matched: List<Array<SchemaIo.Value?>>,val counts: Counts,val records: List<String?>)
    data class Result(val kind: String,val matched: Int,val output: List<String>)
    data class QueryReports(val results: List<String>,val statistics: List<String>)
    data class Recovery(val report: List<String>,val rows: List<String>)
    enum class Truth {
        TRUE,FALSE,UNKNOWN
    }
    fun statistics(values: List<SchemaIo.Value?>): Encoding.Bounds? {
        val present=values.filterNotNull();
        if(present.isEmpty())return null;
        val comparator=Comparator<SchemaIo.Value> {
            a,b->SchemaIo.compare(a,b)
        };
        return Encoding.Bounds(present.minWith(comparator),present.maxWith(comparator))
    }
    fun statisticsText(column: SchemaIo.Column,bounds: Encoding.Bounds?)=if(bounds==null)"stats none" else "min ${SchemaIo.valueText(column.kind,bounds.low)} max ${SchemaIo.valueText(column.kind,bounds.high)}"
    fun methodList(methods: Collection<Int>)=methods.joinToString(",") {
        Encoding.methods[it]
    }
    fun columnLine(index: Int,column: SchemaIo.Column)="column $index ${column.name} ${column.kind} "+if(column.nullable)"NULLABLE" else "REQUIRED"
    fun buildPage(column: SchemaIo.Column,kind: Int,method: Int,values: List<SchemaIo.Value?>,dictionary: List<SchemaIo.Value>?): ByteArray {
        val body=Bitstream.Writer();
        var nulls=0;
        var bounds: Encoding.Bounds?=null;
        if(kind==1)body.bytes(Encoding.encodeValues(column.kind,0,values.filterNotNull(),null))else {
            val present=values.filterNotNull();
            val levels=values.map {
                if(it==null)0L else 1L
            };
            nulls=values.size-present.size;
            bounds=statistics(values);
            if(column.nullable) {
                val encoded=Bitstream.hybridEncode(levels,1);
                body.integer(encoded.size.toLong());
                body.bytes(encoded)
            };
            body.bytes(Encoding.encodeValues(column.kind,method,present,dictionary))
        };
        val data=body.value();
        val page=Bitstream.Writer();
        page.byteValue(kind);
        page.byteValue(method);
        page.uleb(values.size.toLong());
        page.uleb(nulls.toLong());
        page.uleb(data.size.toLong());
        page.integer(Bitstream.adler32(data));
        page.bytes(Encoding.encodeStatistics(column.kind,bounds));
        page.bytes(data);
        return page.value()
    }
    fun buildChunk(column: SchemaIo.Column,values: List<SchemaIo.Value?>,method: Int,pageSize: Int,dictionaryLimit: Int): Chunk {
        val pages=values.chunked(pageSize);
        val dictionary=mutableListOf<SchemaIo.Value>();
        var dictionaryPages=0;
        if(method==1) {
            var known=setOf<SchemaIo.Value>();
            var dictionaryBytes=0;
            for(page in pages) {
                val additions=mutableListOf<SchemaIo.Value>();
                val proposed=known.toMutableSet();
                for(value in page)if(value!=null&&proposed.add(value))additions.add(value);
                val size=dictionaryBytes+Encoding.encodeValues(column.kind,0,additions,null).size;
                if(size>dictionaryLimit)break;
                dictionary.addAll(additions);
                known=proposed;
                dictionaryBytes=size;
                dictionaryPages++
            };
            if(dictionary.isEmpty())dictionaryPages=0
        };
        val writer=Bitstream.Writer();
        if(dictionaryPages>0)writer.bytes(buildPage(column,1,0,dictionary,null));
        val methods=sortedSetOf<Int>();
        for((p,page) in pages.withIndex()) {
            val selected=if(method==1) {
                if(p<dictionaryPages)1 else 0
            }else method;
            methods.add(selected);
            writer.bytes(buildPage(column,0,selected,page,dictionary))
        };
        val chunk=Chunk();
        chunk.data=writer.value();
        chunk.size=chunk.data.size;
        chunk.methods=methods.toList();
        chunk.hasDictionary=dictionaryPages>0;
        chunk.pageCount=pages.size;
        chunk.nulls=values.count {
            it==null
        };
        chunk.bounds=statistics(values);
        chunk.fallback=if(method==1)pages.size-dictionaryPages else 0;
        return chunk
    }
    fun buildFile(inputs: SchemaIo.Inputs): Built {
        val columns=inputs.columns;
        val rows=inputs.rows;
        val options=inputs.options;
        val data=Bitstream.Writer();
        data.bytes("MPTC".toByteArray(Charsets.US_ASCII));
        val groups=mutableListOf<RowGroup>();
        val report=mutableListOf("row_group,column,encoding,bytes,fallback_pages,chosen");
        for(first in rows.indices step options.rowGroupSize) {
            val groupRows=rows.subList(first,minOf(first+options.rowGroupSize,rows.size));
            val group=RowGroup(groupRows.size,first);
            val number=groups.size;
            for((index,column) in columns.withIndex()) {
                val values=groupRows.map {
                    it[index]
                };
                val candidates=Encoding.candidates(column.kind).associateWith {
                    buildChunk(column,values,it,options.pageSize,options.dictionaryLimit)
                };
                val requested=options.encodings.getValue(column.name);
                var chosen=if(requested=="AUTO")Encoding.candidates(column.kind).minBy {
                    candidates.getValue(it).size
                } else Encoding.methods.indexOf(requested);
                if(chosen==1&&!candidates.getValue(chosen).hasDictionary)chosen=0;
                for(method in Encoding.candidates(column.kind)) {
                    val candidate=candidates.getValue(method);
                    report.add("$number,${column.name},${Encoding.methods[method]},${candidate.size},${candidate.fallback},"+if(method==chosen)"yes" else "no")
                };
                val chunk=candidates.getValue(chosen);
                chunk.offset=data.size();
                data.bytes(chunk.data);
                group.chunks.add(chunk)
            };
            groups.add(group)
        };
        val footer=Bitstream.Writer();
        footer.uleb(1);
        footer.uleb(columns.size.toLong());
        for(column in columns) {
            footer.uleb(column.name.length.toLong());
            footer.bytes(column.name.toByteArray(Charsets.US_ASCII));
            footer.byteValue(SchemaIo.types.indexOf(column.kind));
            footer.byteValue(if(column.nullable)1 else 0)
        };
        footer.uleb(rows.size.toLong());
        footer.uleb(groups.size.toLong());
        for(group in groups) {
            footer.uleb(group.rows.toLong());
            for((i,column) in columns.withIndex()) {
                val chunk=group.chunks[i];
                footer.uleb(chunk.offset.toLong());
                footer.uleb(chunk.size.toLong());
                footer.uleb(chunk.methods.size.toLong());
                for(method in chunk.methods)footer.byteValue(method);
                footer.byteValue(if(chunk.hasDictionary)1 else 0);
                footer.uleb(chunk.pageCount.toLong());
                footer.uleb(chunk.nulls.toLong());
                footer.bytes(Encoding.encodeStatistics(column.kind,chunk.bounds))
            }
        };
        data.bytes(footer.value());
        data.integer(footer.size().toLong());
        data.bytes("MPTC".toByteArray(Charsets.US_ASCII));
        return Built(data.value(),report)
    }
    fun parseFile(data: ByteArray): Store {
        val footerSize=Bitstream.Reader(data,data.size-8).integer().toInt();
        val footerOffset=data.size-8-footerSize;
        var reader=Bitstream.Reader(data,footerOffset);
        val version=reader.uleb().toInt();
        val columnCount=reader.uleb().toInt();
        val columns=List(columnCount) {
            val name=reader.read(reader.uleb().toInt()).toString(Charsets.US_ASCII);
            SchemaIo.Column(name,SchemaIo.types[reader.byteValue()],reader.byteValue()!=0)
        };
        val rows=reader.uleb().toInt();
        val groupCount=reader.uleb().toInt();
        var firstRow=0;
        val groups=mutableListOf<RowGroup>();
        repeat(groupCount) {
            val group=RowGroup(reader.uleb().toInt(),firstRow);
            for(column in columns) {
                val chunk=Chunk();
                chunk.offset=reader.uleb().toInt();
                chunk.size=reader.uleb().toInt();
                chunk.methods=List(reader.uleb().toInt()) {
                    reader.byteValue()
                };
                chunk.hasDictionary=reader.byteValue()!=0;
                chunk.pageCount=reader.uleb().toInt();
                chunk.nulls=reader.uleb().toInt();
                chunk.bounds=Encoding.decodeStatistics(reader,column.kind);
                group.chunks.add(chunk)
            };
            groups.add(group);
            firstRow+=group.rows
        };
        for(group in groups)for((i,column) in columns.withIndex()) {
            val chunk=group.chunks[i];
            reader=Bitstream.Reader(data,chunk.offset);
            var first=true;
            while(reader.position<chunk.offset+chunk.size) {
                val page=Page();
                page.offset=reader.position;
                page.kind=reader.byteValue();
                page.method=reader.byteValue();
                page.values=reader.uleb().toInt();
                page.nulls=reader.uleb().toInt();
                page.bodySize=reader.uleb().toInt();
                page.checksum=reader.integer();
                page.bounds=Encoding.decodeStatistics(reader,column.kind);
                page.headerSize=reader.position-page.offset;
                page.bodyOffset=reader.position;
                page.size=page.headerSize+page.bodySize;
                reader.position+=page.bodySize;
                if(first&&chunk.hasDictionary)chunk.dictionary=page else chunk.pages.add(page);
                first=false
            }
        };
        return Store(data,version,columns,rows,groups,footerSize,footerOffset)
    }
    fun pageBody(file: Store,page: Page)=file.data.copyOfRange(page.bodyOffset,page.bodyOffset+page.bodySize)
    fun decodeDictionary(file: Store,column: SchemaIo.Column,page: Page)=Encoding.decodeValues(Bitstream.Reader(pageBody(file,
        page)),column.kind,0,page.values,null)
    fun decodePage(file: Store,column: SchemaIo.Column,page: Page,dictionary: List<SchemaIo.Value>?): List<SchemaIo.Value?> {
        val reader=Bitstream.Reader(pageBody(file,page));
        val levels=if(column.nullable)Bitstream.hybridDecode(Bitstream.Reader(reader.read(reader.integer().toInt())),
            1,page.values) else List(page.values) {
            1L
        };
        val values=Encoding.decodeValues(reader,column.kind,page.method,levels.count {
            it==1L
        },dictionary);
        var index=0;
        return levels.map {
            if(it==1L)values[index++] else null
        }
    }
    fun checksum(value: Long)=value.toString(16).padStart(8,'0')
    class Summary {
        var bytes=0;
        var dataPages=0;
        var dictionaryPages=0;
        val methods=sortedSetOf<Int>()
    }
    fun verifyAndDescribe(file: Store,original: List<Array<SchemaIo.Value?>>): List<String> {
        val columns=file.columns;
        val lines=mutableListOf("file bytes ${file.data.size} footer_offset ${file.footerOffset} footer_bytes ${file.footerSize}",
            "table version ${file.version} rows ${file.rows} columns ${columns.size} row_groups ${file.groups.size}");
        val summaries=List(columns.size) {
            Summary()
        };
        for((i,column) in columns.withIndex())lines.add(columnLine(i,column));
        var cells=0;
        var nulls=0;
        var mismatches=0;
        var checksumErrors=0;
        for((g,group) in file.groups.withIndex()) {
            lines.add("row_group $g rows ${group.rows} first_row ${group.firstRow} bytes ${group.chunks.sumOf{it.size}}");
            for((i,column) in columns.withIndex()) {
                val chunk=group.chunks[i];
                val hasDictionary=if(chunk.hasDictionary)"yes" else "no";
                lines.add("chunk $g ${column.name} offset ${chunk.offset} size ${chunk.size} encodings ${methodList(chunk.methods)} dictionary $hasDictionary pages ${chunk.pageCount} nulls ${chunk.nulls} ${statisticsText(column,chunk.bounds)}");
                val summary=summaries[i];
                summary.bytes+=chunk.size;
                summary.dataPages+=chunk.pageCount;
                summary.dictionaryPages+=if(chunk.hasDictionary)1 else 0;
                summary.methods.addAll(chunk.methods);
                var dictionary: List<SchemaIo.Value>?=null;
                val dictionaryPage=chunk.dictionary;
                if(dictionaryPage!=null) {
                    val page=dictionaryPage;
                    if(Bitstream.adler32(pageBody(file,page))!=page.checksum)checksumErrors++;
                    dictionary=decodeDictionary(file,column,page);
                    lines.add("page $g ${column.name} dict offset ${page.offset} header ${page.headerSize} body ${page.bodySize} checksum ${checksum(page.checksum)} entries ${page.values}")
                };
                var rowNumber=group.firstRow;
                for((p,page) in chunk.pages.withIndex()) {
                    if(Bitstream.adler32(pageBody(file,page))!=page.checksum)checksumErrors++;
                    lines.add("page $g ${column.name} $p offset ${page.offset} header ${page.headerSize} body ${page.bodySize} checksum ${checksum(page.checksum)} encoding ${Encoding.methods[page.method]} values ${page.values} nulls ${page.nulls} ${statisticsText(column,page.bounds)}");
                    for(value in decodePage(file,column,page,dictionary)) {
                        cells++;
                        if(value==null)nulls++;
                        if(value!=original[rowNumber][i])mismatches++;
                        rowNumber++
                    }
                }
            }
        };
        for((i,column) in columns.withIndex()) {
            val summary=summaries[i];
            lines.add("summary ${column.name} bytes ${summary.bytes} data_pages ${summary.dataPages} dictionary_pages ${summary.dictionaryPages} encodings ${methodList(summary.methods)}")
        };
        val status=if(mismatches==0&&checksumErrors==0)"ok" else "failed";
        lines.add("roundtrip $status cells $cells nulls $nulls mismatches $mismatches checksum_errors $checksumErrors");
        return lines
    }
    fun conditionLeaves(tree: Query.Condition?): List<Query.Comparison> =when(tree) {
        null->emptyList();
        is Query.Comparison->listOf(tree);
        is Query.Logical->conditionLeaves(tree.first)+conditionLeaves(tree.second)
    }
    fun itemHeader(item: Query.Item)=when(item.operation) {
        "COLUMN"->item.name!!;
        "COUNT_DISTINCT"->"COUNT(DISTINCT ${item.name})";
        else->"${item.operation}(${item.name?:"*"})"
    }
    fun checkQuery(raw: Query.Raw,columns: List<SchemaIo.Column>): Checked {
        val indices=columns.withIndex().associate {
            it.value.name to it.index
        };
        val items=raw.items?:columns.map {
            Query.Item("COLUMN",it.name)
        };
        val leaves=conditionLeaves(raw.condition);
        val names=items.mapNotNull {
            it.name
        }+leaves.map {
            it.name
        }+listOfNotNull(raw.group,raw.order);
        if(names.any {
            it !in indices
        })return Checked("unknown_column",null);
        for(leaf in leaves) {
            val kind=columns[indices.getValue(leaf.name)].kind;
            val expected=if(kind=="DATE")"STRING" else kind;
            if(leaf.literals.any {
                it.kind!=expected
            })return Checked("type_mismatch",null)
        };
        if(items.any {
            it.operation in listOf("SUM","AVG")&&columns[indices.getValue(it.name!!)].kind!="INT"
        })return Checked("bad_aggregate",null);
        val aggregate=raw.group!=null||items.any {
            it.operation!="COLUMN"
        };
        if(aggregate&&items.any {
            it.operation=="COLUMN"&&it.name!=raw.group
        })return Checked("not_grouped",null);
        if(aggregate&&raw.order!=null)return Checked("bad_order",null);
        val needed=names.map {
            indices.getValue(it)
        }.toSortedSet().toList();
        val conditionColumns=leaves.map {
            indices.getValue(it.name)
        }.toSortedSet().toList();
        for(leaf in leaves) {
            leaf.index=indices.getValue(leaf.name);
            leaf.values=leaf.literals.map {
                if(columns[leaf.index].kind=="DATE")SchemaIo.NumberValue(SchemaIo.dayNumber((it.value as SchemaIo.TextValue).value).toLong()) else it.value
            }
        };
        val bound=items.map {
            BoundItem(it.operation,it.name?.let {
                n->indices.getValue(n)
            }?:-1)
        };
        return Checked(null,Plan(bound,items.map {
            itemHeader(it)
        },raw.condition,raw.group?.let {
            indices.getValue(it)
        }?:-1,raw.order?.let {
            indices.getValue(it)
        }?:-1,raw.descending,raw.limit,aggregate,needed,conditionColumns))
    }
    fun logicalNot(value: Truth)=when(value) {
        Truth.UNKNOWN->Truth.UNKNOWN;
        Truth.TRUE->Truth.FALSE;
        Truth.FALSE->Truth.TRUE
    }
    fun logicalPair(operation: String,first: Truth,second: Truth): Truth {
        if(operation=="AND") {
            if(first==Truth.FALSE||second==Truth.FALSE)return Truth.FALSE;
            return if(first==Truth.UNKNOWN||second==Truth.UNKNOWN)Truth.UNKNOWN else Truth.TRUE
        };
        if(first==Truth.TRUE||second==Truth.TRUE)return Truth.TRUE;
        return if(first==Truth.UNKNOWN||second==Truth.UNKNOWN)Truth.UNKNOWN else Truth.FALSE
    }
    fun compareValue(leaf: Query.Comparison,value: SchemaIo.Value?): Truth {
        if(leaf.operation=="IS_NULL")return if(value==null)Truth.TRUE else Truth.FALSE;
        if(leaf.operation=="IS_NOT_NULL")return if(value!=null)Truth.TRUE else Truth.FALSE;
        if(value==null)return Truth.UNKNOWN;
        val matches=when(leaf.operation) {
            "BETWEEN"->SchemaIo.compare(leaf.values[0],value)<=0&&SchemaIo.compare(value,leaf.values[1])<=0;
            "IN"->value in leaf.values;
            else-> {
                val compared=SchemaIo.compare(value,leaf.values.first());
                when(leaf.operation) {
                    "="->compared==0;
                    "<>"->compared!=0;
                    "<"->compared<0;
                    "<="->compared<=0;
                    ">"->compared>0;
                    else->compared>=0
                }
            }
        };
        return if(matches)Truth.TRUE else Truth.FALSE
    }
    fun evaluate(tree: Query.Condition?,row: Array<SchemaIo.Value?>): Truth=when(tree) {
        null->Truth.TRUE;
        is Query.Comparison->compareValue(tree,row[tree.index]);
        is Query.Logical-> {
            val first=evaluate(tree.first,row);
            if(tree.operation=="NOT")logicalNot(first) else logicalPair(tree.operation,first,evaluate(tree.second,row))
        }
    }
    fun rangePossibilities(leaf: Query.Comparison,bounds: Encoding.Bounds): Possibilities {
        val low=bounds.low;
        val high=bounds.high;
        val literals=leaf.values;
        val operation=leaf.operation;
        if(operation=="BETWEEN") {
            val first=literals[0];
            val last=literals[1];
            return Possibilities(SchemaIo.compare(low,last)<=0&&SchemaIo.compare(high,first)>=0&&SchemaIo.compare(first,
                last)<=0,SchemaIo.compare(low,first)<0||SchemaIo.compare(high,last)>0)
        };
        if(operation=="IN")return Possibilities(literals.any {
            SchemaIo.compare(low,it)<=0&&SchemaIo.compare(it,high)<=0
        },!(low==high&&low in literals));
        val value=literals.first();
        val lo=SchemaIo.compare(low,value);
        val hi=SchemaIo.compare(high,value);
        return when(operation) {
            "="->Possibilities(lo<=0&&hi>=0,!(lo==0&&hi==0));
            "<>"->Possibilities(!(lo==0&&hi==0),lo<=0&&hi>=0);
            "<"->Possibilities(lo<0,hi>=0);
            "<="->Possibilities(lo<=0,hi>0);
            ">"->Possibilities(hi>0,lo<=0);
            else->Possibilities(hi>=0,lo<0)
        }
    }
    fun zoneValues(tree: Query.Condition,zones: Map<Int,Zone>): Set<Truth> {
        if(tree is Query.Logical) {
            val first=zoneValues(tree.first,zones);
            return if(tree.operation=="NOT")first.map {
                logicalNot(it)
            }.toSet() else first.flatMap {
                left->zoneValues(tree.second!!,zones).map {
                    right->logicalPair(tree.operation,left,right)
                }
            }.toSet()
        };
        val leaf=tree as Query.Comparison;
        val zone=zones.getValue(leaf.index);
        val values=mutableSetOf<Truth>();
        if(leaf.operation=="IS_NULL"||leaf.operation=="IS_NOT_NULL") {
            if(zone.nulls>0)values.add(if(leaf.operation=="IS_NULL")Truth.TRUE else Truth.FALSE);
            if(zone.nulls<zone.count)values.add(if(leaf.operation=="IS_NOT_NULL")Truth.TRUE else Truth.FALSE);
            return values
        };
        if(zone.nulls>0)values.add(Truth.UNKNOWN);
        val bounds=zone.bounds;
        if(bounds!=null) {
            val possible=rangePossibilities(leaf,bounds);
            if(possible.canTrue)values.add(Truth.TRUE);
            if(possible.canFalse)values.add(Truth.FALSE)
        };
        return values
    }
    data class PageKey(val group: Int,val column: Int)
    fun readScanPage(file: Store,g: Int,index: Int,p: Int,dictionaries: MutableMap<PageKey,List<SchemaIo.Value>>,
        counts: Counts): List<SchemaIo.Value?> {
        val column=file.columns[index];
        val chunk=file.groups[g].chunks[index];
        val page=chunk.pages[p];
        var dictionary: List<SchemaIo.Value>?=null;
        if(page.method==1) {
            val key=PageKey(g,index);
            dictionary=dictionaries.getOrPut(key) {
                val dictionaryPage=chunk.dictionary!!;
                counts.add("dictionary_pages_read",1);
                counts.add("bytes_read",dictionaryPage.size);
                decodeDictionary(file,column,dictionaryPage)
            }
        };
        counts.add("pages_read",1);
        counts.add("bytes_read",page.size);
        return decodePage(file,column,page,dictionary)
    }
    fun scan(file: Store,plan: Plan): Scan {
        val counts=Counts();
        val records=mutableListOf<String?>();
        val matched=mutableListOf<Array<SchemaIo.Value?>>();
        val dictionaries=mutableMapOf<PageKey,List<SchemaIo.Value>>();
        val remaining=plan.needed.filter {
            it !in plan.conditionColumns
        };
        val condition=plan.condition;
        for((g,group) in file.groups.withIndex()) {
            var zones=plan.conditionColumns.associateWith {
                val chunk=group.chunks[it];
                Zone(chunk.bounds,chunk.nulls,group.rows)
            };
            if(condition!=null&&Truth.TRUE !in zoneValues(condition,zones)) {
                counts.add("row_groups_skipped",1);
                records.add(null);
                continue
            };
            counts.add("row_groups_read",1);
            if(plan.needed.isEmpty()) {
                counts.add("rows_scanned",group.rows);
                repeat(group.rows) {
                    matched.add(arrayOfNulls<SchemaIo.Value>(file.columns.size))
                };
                records.add("-");
                continue
            };
            val record=StringBuilder();
            for(p in 0 until group.chunks.first().pageCount) {
                zones=plan.conditionColumns.associateWith {
                    val page=group.chunks[it].pages[p];
                    Zone(page.bounds,page.nulls,page.values)
                };
                if(condition!=null&&Truth.TRUE !in zoneValues(condition,zones)) {
                    counts.add("pages_skipped",plan.needed.size);
                    record.append('s');
                    continue
                };
                val rowCount=group.chunks.first().pages[p].values;
                counts.add("rows_scanned",rowCount);
                val rows=List(rowCount) {
                    arrayOfNulls<SchemaIo.Value>(file.columns.size)
                };
                for(index in plan.conditionColumns) {
                    val values=readScanPage(file,g,index,p,dictionaries,counts);
                    for(i in 0 until rowCount)rows[i][index]=values[i]
                };
                val selected=rows.indices.filter {
                    evaluate(condition,rows[it])==Truth.TRUE
                };
                if(selected.isEmpty()&&remaining.isNotEmpty()) {
                    counts.add("pages_unneeded",remaining.size);
                    record.append('u');
                    continue
                };
                for(index in remaining) {
                    val values=readScanPage(file,g,index,p,dictionaries,counts);
                    for(i in 0 until rowCount)rows[i][index]=values[i]
                };
                for(index in selected)matched.add(rows[index]);
                record.append('r')
            };
            records.add(record.toString())
        };
        counts.add("rows_matched",matched.size);
        return Scan(matched,counts,records)
    }
    fun gcd(initial: Long,divisor: Long): Long {
        var a=kotlin.math.abs(initial);
        var b=divisor;
        while(b!=0L) {
            val next=a%b;
            a=b;
            b=next
        };
        return a
    }
    fun aggregateItem(columns: List<SchemaIo.Column>,item: BoundItem,rows: List<Array<SchemaIo.Value?>>,
        key: SchemaIo.Value?): String {
        val op=item.operation;
        val index=item.index;
        if(op=="COLUMN")return SchemaIo.valueText(columns[index].kind,key);
        if(op=="COUNT"&&index<0)return rows.size.toString();
        val values=rows.mapNotNull {
            it[index]
        };
        if(op=="COUNT")return values.size.toString();
        if(op=="COUNT_DISTINCT")return values.toSet().size.toString();
        if(values.isEmpty())return "NULL";
        if(op=="SUM"||op=="AVG") {
            val total=values.sumOf {
                (it as SchemaIo.NumberValue).value
            };
            if(op=="SUM")return total.toString();
            val divisor=gcd(total,values.size.toLong());
            val numerator=total/divisor;
            val denominator=values.size/divisor;
            return if(denominator==1L)numerator.toString() else "$numerator/$denominator"
        };
        val comparator=Comparator<SchemaIo.Value> {
            a,b->SchemaIo.compare(a,b)
        };
        val best=if(op=="MIN")values.minWith(comparator) else values.maxWith(comparator);
        return SchemaIo.valueText(columns[index].kind,best)
    }
    fun buildResult(columns: List<SchemaIo.Column>,plan: Plan,matched: List<Array<SchemaIo.Value?>>): Result {
        val kind: String;
        var output: List<String>;
        if(!plan.aggregate) {
            kind="rows";
            val arranged=if(plan.order<0)matched else matched.sortedWith(Comparator {
                a,b->(if(plan.descending)-1 else 1)*SchemaIo.compare(a[plan.order],b[plan.order])
            });
            output=arranged.map {
                row->plan.items.joinToString(",") {
                    SchemaIo.valueText(columns[it.index].kind,row[it.index])
                }
            }
        }else if(plan.group<0) {
            kind="aggregate";
            output=listOf(plan.items.joinToString(",") {
                aggregateItem(columns,it,matched,null)
            })
        }else {
            kind="grouped";
            val groups=sortedMapOf<SchemaIo.Value?,MutableList<Array<SchemaIo.Value?>>>(Comparator {
                a,b->SchemaIo.compare(a,b)
            });
            for(row in matched)groups.getOrPut(row[plan.group]) {
                mutableListOf()
            }.add(row);
            output=groups.entries.map {
                (key,rows)->plan.items.joinToString(",") {
                    aggregateItem(columns,it,rows,key)
                }
            }
        };
        val limit=plan.limit;
        if(limit!=null)output=output.take(limit);
        return Result(kind,matched.size,output)
    }
    fun executeQueries(file: Store,originals: List<Array<SchemaIo.Value?>>,queries: List<String>): QueryReports {
        val results=mutableListOf<String>();
        val statistics=mutableListOf<String>();
        val totals=Counts();
        var errors=0;
        var checksOk=0;
        for((i,text) in queries.withIndex()) {
            val number=i+1;
            val checked=checkQuery(Query.Parser(text).parse(),file.columns);
            val error=checked.error;
            if(error!=null) {
                val line="query $number error $error";
                results.add(line);
                statistics.add(line);
                errors++;
                continue
            };
            val plan=checked.plan!!;
            val scan=scan(file,plan);
            val result=buildResult(file.columns,plan,scan.matched);
            val reference=originals.filter {
                evaluate(plan.condition,it)==Truth.TRUE
            };
            val check=if(result==buildResult(file.columns,plan,reference))"ok" else "mismatch";
            if(check=="ok")checksOk++;
            results.add("query $number ${result.kind} matched ${result.matched} output ${result.output.size}");
            results.add("columns "+plan.headers.joinToString(","));
            results.addAll(result.output);
            val needed=plan.needed.joinToString(",") {
                file.columns[it].name
            }.ifEmpty {
                "-"
            };
            statistics.add("query $number columns $needed ${scan.counts.text()} check $check");
            for((g,record) in scan.records.withIndex())statistics.add("query $number row_group $g "+if(record==null)"skipped" else "pages $record");
            for(name in scanCounts)totals.add(name,scan.counts.get(name))
        };
        statistics.add("total queries ${queries.size} errors $errors ${totals.text()} checks_ok $checksOk");
        return QueryReports(results,statistics)
    }
    fun recover(data: ByteArray): Recovery {
        val file=parseFile(data);
        val columns=file.columns;
        val rows=Array(file.rows) {
            Array<SchemaIo.Value?>(columns.size) {
                SchemaIo.Unknown
            }
        };
        val lines=mutableListOf("file bytes ${data.size} rows ${file.rows} columns ${columns.size} row_groups ${file.groups.size}");
        for((i,column) in columns.withIndex())lines.add(columnLine(i,column));
        var pagesExamined=0;
        var damagedCount=0;
        var lostPages=0;
        var lostCells=0;
        for((g,group) in file.groups.withIndex())for((i,column) in columns.withIndex()) {
            val chunk=group.chunks[i];
            var dictionary: List<SchemaIo.Value>?=null;
            var dictionaryDamaged=false;
            val pages=listOfNotNull(chunk.dictionary)+chunk.pages;
            var rowNumber=group.firstRow;
            var p=0;
            for(page in pages) {
                pagesExamined++;
                val computed=Bitstream.adler32(pageBody(file,page));
                val damaged=computed!=page.checksum;
                val label=if(page.kind==1)"dict" else p.toString();
                if(damaged) {
                    damagedCount++;
                    lines.add("damaged $g ${column.name} $label offset ${page.offset} stored ${checksum(page.checksum)} computed ${checksum(computed)}")
                };
                if(page.kind==1) {
                    dictionaryDamaged=damaged;
                    if(!damaged)dictionary=decodeDictionary(file,column,page);
                    continue
                };
                val reason=when {
                    damaged->"checksum";
                    page.method==1&&dictionaryDamaged->"dictionary";
                    else->null
                };
                if(reason!=null) {
                    lostPages++;
                    lostCells+=page.values;
                    lines.add("lost $g ${column.name} $p rows ${page.values} reason $reason")
                }else {
                    val values=decodePage(file,column,page,dictionary);
                    for((j,value) in values.withIndex())rows[rowNumber+j][i]=value
                };
                rowNumber+=page.values;
                p++
            }
        };
        lines.add("summary pages $pagesExamined damaged $damagedCount lost_pages $lostPages lost_cells $lostCells recovered_cells ${file.rows*columns.size-lostCells}");
        val recovered=mutableListOf(columns.joinToString(",") {
            it.name
        });
        for(row in rows)recovered.add(columns.indices.joinToString(",") {
            i->if(row[i]===SchemaIo.Unknown)"?" else SchemaIo.valueText(columns[i].kind,row[i],"")
        });
        return Recovery(lines,recovered)
    }
    fun run() {
        val inputs=SchemaIo.readInputs();
        val built=buildFile(inputs);
        val file=parseFile(built.data);
        val metadata=verifyAndDescribe(file,inputs.rows);
        val queries=executeQueries(file,inputs.rows,inputs.queries);
        val recovery=recover(inputs.damaged);
        val hex=built.data.toList().chunked(32).map {
            part->part.joinToString("") {
                (it.toInt() and 255).toString(16).padStart(2,'0')
            }
        };
        SchemaIo.writeOutputs(linkedMapOf("file.hex" to hex,"metadata.txt" to metadata,"encoding_report.csv" to built.report,
            "query_results.txt" to queries.results,"query_stats.txt" to queries.statistics,"recovery.txt" to recovery.report,
            "recovered.csv" to recovery.rows))
    }
}
fun main() {
    ColumnarProgram.run()
}
