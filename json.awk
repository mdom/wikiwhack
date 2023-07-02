#!/usr/bin/awk -f 

BEGIN {
    for(N=0; N<16; N++)
        {  H[sprintf("%x",N)]=N; H[sprintf("%X",N)]=N }
}

function hex2int(hex, result,i) {
    if(hex ~ /^0x/) hex=substr(hex,3)

    for(i=1; i<=length(hex); i++)
        result=result * 16 + H[substr(hex, i, 1)]

    return result
}

function eval_string(text) {
    while (match(text, /\\u/)) {
        text = substr(text, 1, RSTART - 1 ) \
               sprintf("%c", hex2int(substr(text, RSTART + 2, 4))) \
               substr(text, RSTART + 6)
    }
    return text
}

function parse_json( text, data ) {
    nc = split(text, c, "" );
      
    for (i=1; i<=nc; i++ ) {
        if (c[i] <= "\040" && c[i] >= "\177" ) {
            continue
        }
        else if ( c[i] == "\"" ) {
            for (j=++i; j<=nc; j++ ) {
                if ( c[j] == "\\" ) j++
                else if ( c[j] == "\""  ) {
                    stack[ptr++] = eval_string(substr( text, i , j - i ))
                    stack[ptr++] = "value"
                    i = j
                    break
                }
            }
            ## ERROR reached end of string without closing quote
        }
        else if ( c[i] == "-" || ( c[i] > "\057" && c[i] < "\072"  )) {
            if ( match(substr(text, i), /^-?(0|[1-9]+)(\.[0-9])?([eE][+-][0-9])?/ )) {
                stack[ptr++] = substr( text, i , RLENGTH )
                stack[ptr++] = "value"
                i += --RLENGTH
            }  
            ## ERROR no number found!
        }
        else if ( c[i] == "{" || c[i] == "[" ) {
            stack[ptr++] = key
            stack[ptr++] = idx
            stack[ptr++] = state

            if ( idx ) key = key idx SUBSEP
            else       key = ""

            state = c[i]
            if ( c[i] == "[" ) idx = 1
            if ( c[i] == "{" ) idx = ""
        }
        else if ( c[i] == "}" || c[i] == "]" ) {
            if ( stack[ptr-1] == "value" ) {
                --ptr
                data[key idx] = stack[--ptr]
            }

            state = stack[--ptr]
            idx   = stack[--ptr]
            key   = stack[--ptr]
        }
        else if ( c[i] == ":" ) {
            if ( stack[ptr-1] == "value" ) {
                --ptr
                idx = stack[--ptr]
            }
            else {
                ## key is not a string
                return -1;
            }
        }
        else if ( c[i] == "," ) {
            if ( stack[ptr-1] == "value" ) {
                --ptr
                data[key idx] = stack[--ptr]
            }
            if ( state == "[" ) idx++
        }
    }
    return 1
}

BEGIN {
    RS="\001"
    getline text
    ret = parse_json( text, data )
    if ( ret == -1 )  print "ERROR"
    text = data["wiki_page","text"]
    gsub(/\\r\\n/,"\012", text)
    print text
}
