# for test env
{{ range ls "bkapps/upstreams/test" }}
upstream {{ .Key }} { 
        {{ with $app := .Value | parseJSON }}
        {{ range $d := $app }} server {{ $d }} max_fails=1 fail_timeout=30s;
        {{ end }} {{ end }} 
}
{{ end }}

# for prod env
{{ range ls "bkapps/upstreams/prod" }}
upstream {{ .Key }} { 
        {{ with $app := .Value | parseJSON }}
        {{ range $d := $app }} server {{ $d }} max_fails=1 fail_timeout=30s;
        {{ end }} {{ end }} 
}
{{ end }}