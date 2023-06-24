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

function add_vspace (){
    if ( !skip_newlines ) {
        skip_newlines = 1
        column = 0
        return RS RS
    }
}

function force_vspace() {
    skip_newlines = 1
    column = 0
    return RS RS
}

function render_text ( text ) {
        gsub(/ä/,"ae", text)
        gsub(/ö/,"oe", text)
        gsub(/ü/,"ue", text)
        text = decode_entities(text)
        pre_mode = 0
        column = 0
        output = ""
        skip_newlines = 1

        nr = split(text, lines, /\n/)

        for (i=1; i<nr; i++ ) {
            line = lines[i]

            if ( match(line, /^h[0-9]\([^)]+\)\./ )) {
                sub(/\([^)]+\)/, "", line)
            }

            if ( match( line, /^h[0-9]./ )) {
                output = output add_vspace() bold line normal force_vspace()
                continue
            }

            if ( match( line, /<pre>/))
                pre_mode = 1

            if ( match( line, /<\/pre>/)) {
                pre_mode = 0
                output = output line RS RS
                skip_newlines = 1
                column = 0
                continue
            }

            if ( pre_mode ) {
                output = output line RS
                continue
            }

            if ( match( line, /^$/)) {
                if ( !skip_newlines ) {
                    output = output RS RS
                    skip_newlines = 1
                    column = 0
                }
                continue
            }
            else {
                skip_newlines = 0
            }

            nf = split(line, fields)

            for(j=1; j<=nf; j++) {
                word = fields[j]
                len = length(word)
                if ( len + column + 1 > width ) {
                    output = output RS
                    column = 0
                }
                if (column == 0) {
                    output = output word
                    column += len
                } else {
                    output = output " " word
                    column += len + 1
                }
            }
        }
        return output RS
}

function get( page, filter,  text ) {
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

function upload_page( page, file ) {
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

function get_titles (titles) {
    text = get("index", "jq -r '.wiki_pages|.[]|.title'")
    return split(text, titles, /\n/)
}

function edit_page (page) {
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
