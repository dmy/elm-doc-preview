all:
	elm make --output=public/elm.js --optimize src/Main.elm
	elm-minify public/elm.js --replace

watch:
	elm-live src/Main.elm -d public -u -- --output=public/elm.js

clean:
	rm -f public/elm.js
