all:
	npx elm make --output=public/elm.js --optimize src/Main.elm
	npx elm-minify public/elm.js --replace
	cat public/style.css public/highlight/styles/default.css | npx csso -o public/elm-doc-preview.css


watch:
	npx elm-live src/Main.elm -d public -u -- --output=public/elm.js

clean:
	rm -f public/elm.js
	rm -f public/elm-doc-preview.css
