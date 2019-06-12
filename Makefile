elm_js := public/elm.js
css := public/elm-doc-preview.css
cli_js := cli.js
main := src/Main.elm

css_files := public/style.css public/highlight/styles/default.css public/spinner.css

all: clean elm_js fix_identity minify $(css)

elm_js:
	npx elm make --output=$(elm_js) --optimize $(main)

fix_identity:
	# Work around elm bug https://github.com/elm/compiler/issues/1836
	# (to be removed once Elm > 0.19.0 is released and used)
	@grep '^var elm$$browser$$Browser$$Dom$$NotFound = ' $(elm_js) > public/fix.js
	@grep -v '^var elm$$browser$$Browser$$Dom$$NotFound = ' $(elm_js) >> public/fix.js
	@grep -A 2 '^var elm$$core$$Basics$$identity = function' public/fix.js > $(elm_js)
	@grep -vA 2 '^var elm$$core$$Basics$$identity = function' public/fix.js >> $(elm_js)
	@rm -f public/fix.js

$(css): $(css_files)
	cat $^ | npx csso -o $@

minify:
	npx elm-minify $(elm_js) --overwrite

watch:
	npx elm-live $(main) -d public -u -- --output=$(elm_js) --debug

clean:
	rm -f $(elm_js) $(css)
