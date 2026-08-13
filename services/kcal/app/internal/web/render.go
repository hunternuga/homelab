package web

import (
	"embed"
	"html/template"
	"io/fs"
)

//go:embed templates/*.html
var templateFS embed.FS

//go:embed static/*.css
var staticFSRaw embed.FS

func staticFS() fs.FS {
	sub, err := fs.Sub(staticFSRaw, "static")
	if err != nil {
		panic(err)
	}
	return sub
}

// pages lists every content template. Each is parsed together with
// layout.html into its own *template.Template so that every page's
// {{define "content"}} block lives in an isolated namespace — parsing all
// pages into one shared template set would let each page's "content"
// definition silently clobber the others.
var pages = []string{"login.html", "register.html", "dashboard.html", "history.html"}

func loadTemplates() (map[string]*template.Template, error) {
	tmpls := make(map[string]*template.Template, len(pages))
	for _, page := range pages {
		t, err := template.ParseFS(templateFS, "templates/layout.html", "templates/"+page)
		if err != nil {
			return nil, err
		}
		tmpls[page] = t
	}
	return tmpls, nil
}
