.PHONY: all doc_server elm_js fix_identity minify clean

elm_js := static/js/elm.js
css := static/css/elm-doc-preview.css
cli_js := cli.js
main := src/Main.elm
doc_server := lib/elm-doc-server.js

css_files := static/css/style.css static/highlight/styles/default.css static/css/spinner.css

all: clean $(doc_server) elm_js fix_identity minify $(css)

$(doc_server): lib/elm-doc-server.ts
	npx tsc

elm_js:
	npx elm make --output=$(elm_js) --optimize $(main)

fix_identity:
	# Work around elm bug https://github.com/elm/compiler/issues/1836
	# (to be removed once Elm > 0.19.0 is released and used)
	@grep '^var elm$$browser$$Browser$$Dom$$NotFound = ' $(elm_js) > static/js/fix.js
	@grep -v '^var elm$$browser$$Browser$$Dom$$NotFound = ' $(elm_js) >> static/js/fix.js
	@grep -A 2 '^var elm$$core$$Basics$$identity = function' static/js/fix.js > $(elm_js)
	@grep -vA 2 '^var elm$$core$$Basics$$identity = function' static/js/fix.js >> $(elm_js)
	@rm -f static/js/fix.js

$(css): $(css_files)
	cat $^ | npx csso -o $@

minify:
	npx elm-minify $(elm_js) --overwrite

clean:
	rm -f $(elm_js) $(css)
