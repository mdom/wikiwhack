#!/usr/bin/awk -f

function decode_entities ( text ) {
   while ( match(text, /&#[0-9]+;/) != 0 ) {
       text = substr(text, 0, RSTART - 1) \
              sprintf("%c", 0+substr(text, RSTART + 2, RLENGTH - 3 )) \
              substr(text, RSTART + RLENGTH)
   }
   gsub(/&quot;/, quote, text)
   return text
}

function render_text (text,  nr,ol,lines,line,nf,pre_mode,output,result ) {

        gsub(/\015/, "\012", text)

        text = decode_entities(text)
        pre_mode = 0

        nr = split(text, lines, /\n/)
        ol = 1

        for (i=1; i<nr; i++ ) {
            line = lines[i]

            if ( match(line, /^h[0-9]\([^)]+\)\./ )) {
                sub(/\([^)]+\)/, "", line)
            }

            if ( match( line, /^h[0-9]./ )) {
                output[++ol] =  ""
                output[++ol] =  bold line normal
                output[++ol] =  ""
                continue
            }

            if ( match( line, /<pre>/))
                pre_mode = 1

            if ( pre_mode ) {
                output[++ol] = line
                continue
            }

            if ( match( line, /<\/pre>/)) {
                pre_mode = 0
                continue
            }

            if ( match( line, /^[ \t]*$/)) {
                output[++ol] = ""
                continue
            }

            nf = split(line, fields)

            for(j=1; j<=nf; j++) {
                word = fields[j]
                len = length(word)
                if ( len + length(output[ol]) + 1 > width ) {
                    ol++
                }
                if (output[ol] == "")
                    output[ol] = word
                else 
                    output[ol] = output[ol] " " word
            }
        }

        ## Remove empty lines from end
        while (output[ol] == "") ol--

        last   = ""
        for (i=1;i<=ol;i++) {
            if ( !(last == "" && output[i] == "" )) {
                if (result)
                    result = result RS output[i]
                else
                    result = result output[i]
                last = output[i]
            }
        }
        return result RS
}

function get( page, filter,  text, cmd ) {
    gsub(/'/,"%27", page)
    cmd = curl "'" base_url "/wiki/" page ".json?key=" ENVIRON["REDMINE_APIKEY"] "'"
    if ( filter ) cmd = cmd "|" filter
    while ( cmd | getline line > 0 ) {
        if (text) text = text RS line
        else text = line
    }
    close(cmd)
    return text
}

function upload_page( page, file,  json, url, cmd ) {
    cmd = "jq --slurp -R '{\"wiki_page\": { \"text\": . }}' " file 
    while ( cmd | getline line > 0 ) {
        json = json RS line    
    }
    close(cmd)

    url = "'" base_url "/wiki/" page ".json?key=" ENVIRON["REDMINE_APIKEY"] "'"
    cmd = curl " --request PUT --data-binary @- " url
    print json | cmd
    close(cmd)
}

function get_titles (titles,  text) {
    text = get("index", "jq -r '.wiki_pages|.[]|.title'")
    return split(text, titles, /\n/)
}

function edit_page (page,  tmp, tmp_) {
    text = get_text(page)
    tmp = tmpfile()
    tmp_ = tmpfile()
    print text > tmp
    print text > tmp_
    system(editor " " tmp " </dev/tty")
    if (system("cmp -s " tmp " " tmp_) == 1) {
        upload_page(page, tmp)
    }
    close(tmp)
    close(tmp_)
}

function tmpfile(,file) {
    file = sprintf("/tmp/wikiwhack.%s", rand())
    TEMPFILES[TEMPFILESC++] = file
    return file
}

function get_text (page) {
    return get(page, "jq -r '.wiki_page|.text'")
}

function read_config (,  file) {
    if ( ENVIRON["XDG_CONFIG_HOME"] ) 
        file = ENVIRON["XDG_CONFIG_HOME"] "/wikiwhack/wikiwackrc"
    else
        file = ENVIRON["HOME"] "/.wikiwhackrc"
    while ( getline < file > 0 ) {
        config[$1] = $2
    }
    close(file)
}

function die (msg) {
    print prog ": " msg > "/dev/stderr"
    exit 1
}

function basename (file,  parts) {
    n = split(file, parts, "/")
    return parts[n]
}

BEGIN {
    prog = ENVIRON["_"]
    if ( !prog ) prog = "wikiwack"

    read_config()

    if ( !config["base_url"] ) {
        die("Configuration setting base_url not set.")
    }

    base_url = config["base_url"]

    curl = "exec curl -sS -H 'Content-Type: application/json' "
    fzf  = "exec fzf " \
        "--preview='$0 cat {}' " \
        "--bind=enter:toggle-preview " \
        "--bind='alt-s:reload#$0 search {q}#+clear-query' " \
        "--bind='alt-c:execute#$0 edit {q}#+reload:$0 titles' " \
        "--bind='alt-e:execute:$0 edit {}' " \
        "--bind='alt-v:execute:$0 view {}' " \
        "--bind=alt-j:preview-half-page-down " \
        "--bind=alt-k:preview-half-page-up " \
        "--bind=alt-q:abort " \
        "--color=header:reverse " \
        "--info=inline "  \
        "--ansi " \
        "--preview-window=hidden " \
        "--header='M-e:edit M-s:search M-v:less ENTER:preview M-q:quit' "

    gsub(/\$0/, prog, fzf)

    editor = ENVIRON["EDITOR"]
    if (!editor) editor = "vi"

    width = ENVIRON["FZF_PREVIEW_COLUMNS"]
    if ( !width ) width = 70
    width -= 10

    escape = ""
    bold   = escape "[1m"
    normal = escape "[0m"
    quote  = sprintf("%c", 39);
    current = 0
    output_index = 0

    srand()

    mode = ARGV[1]

    if ( mode == "" ) {
        n = get_titles(titles)
        for (i=1; i<=n; i++)
            print titles[i] | fzf
    }
    else if ( mode == "titles" ) {
        n = get_titles(titles)
        for (i=1; i<=n; i++)
            print titles[i]
    }
    else if ( mode == "cat" ) {
        page = ARGV[2]
        text = render_text(get_text(page))
        if (text) printf "%s", text
    }
    else if ( mode == "view" ) {
        page = ARGV[2]
        text = render_text(get_text(page))
        cmd = "less -R"
        if (text) printf "%s", text  | cmd
        close(cmd)
    }
    else if ( mode == "edit" ) {
        page = ARGV[2]
        edit_page(page)
    }

    for (idx in TEMPFILES)
        system("rm " TEMPFILES[idx])
}
