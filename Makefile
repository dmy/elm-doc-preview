elm_js := public/elm.js
css := public/elm-doc-preview.css
cli_js := cli.js
main := src/Main.elm

css_files := public/style.css public/highlight/styles/default.css public/spinner.css

all: clean elm_js minify $(css)

elm_js:
	npx elm make --output=$(elm_js) --optimize $(main)

$(css): $(css_files)
	cat $^ | npx csso -o $@

minify:
	npx elm-minify $(elm_js) --overwrite

watch:
	npx elm-live $(main) -d public -u -- --output=$(elm_js) --debug

clean:
	rm -f $(elm_js) $(css)
