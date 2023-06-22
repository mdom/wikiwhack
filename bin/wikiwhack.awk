#!/usr/bin/awk -f

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
}

function tmpfile(,file) {
    file = sprintf("/tmp/wikiwhack.%s", rand())
    TEMPFILES[TEMPFILESC++] = file
    return file
}

function get_text (page) {
    return get(page, "jq -r '.wiki_page|.text'")
}

BEGIN {
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

    editor = ENVIRON["EDITOR"]
    if (!editor) editor = "vi"

    srand()

    gsub(/\$0/,"wikiwhack",fzf)

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
        text = get_text(page)
        if (text) printf "%s", text
    }
    else if ( mode == "edit" ) {
        page = ARGV[2]
        edit_page(page)
    }

    for (idx in TEMPFILES)
        system("rm " TEMPFILES[idx])
}
