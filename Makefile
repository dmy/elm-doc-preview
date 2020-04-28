.PHONY: all elm_js minify clean publish

elm_js := static/js/elm.js
css := static/css/elm-doc-preview.css
cli_js := cli.js
main := src/Main.elm
doc_server := lib/elm-doc-server.js

css_files := static/css/style.css static/highlight/styles/default.css static/css/spinner.css

all: clean $(doc_server) elm_js minify $(css)

$(doc_server): lib/elm-doc-server.ts
	npx tsc

elm_js:
	npx elm make --output=$(elm_js) --optimize $(main)

$(css): $(css_files)
	cat $^ | npx csso -o $@

minify:
	npx elm-minify $(elm_js) --overwrite

clean:
	rm -f $(elm_js) $(css)

publish: all
	npm publish
