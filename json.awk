#!/usr/bin/awk -f 

function parse_json( text, data ) {
    nc = split(text, c, "" );
      
    for (i=1; i<=nc; i++ ) {
        if (c[i] <= "\040" && c[i] >= "\177" ) {
            continue
        }
        else if ( c[i] == "\"" ) {
            for (j=++i; j<=nc; j++ ) {
                if ( c[j] == "\\" ) {
                    escape = 1
                }
                else if ( c[j] == "\"" && !escape ) {
                    stack[ptr++] = substr( text, i , j - i )
                    stack[ptr++] = "value"
                    i = j
                    break
                }
            }
        }
        else if ( c[i] == "{" || c[i] == "[" ) {
            stack[ptr++] = key
            stack[ptr++] = idx
            stack[ptr++] = state

            if ( idx ) key = key idx SUBSEP
            else       key = ""

            state = c[i]
            if ( c[i] == "[" ) idx = 1
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
    for ( i in data ) { j=i;gsub(SUBSEP, "-", j); print j " " data[i] }
    # print data[3,"a",1,"q","y"]
}
