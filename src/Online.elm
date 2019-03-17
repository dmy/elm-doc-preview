module Online exposing (readme, readmeWithModules)


readme : String
readme =
    """
# Elm Documentation Previewer

Open a package `README.md`, `docs.json` (from `elm make --docs=docs.json`) or
both:

> Click **Open Files** on the side or **drag & drop files** anywhere in the
> page.  
> Invalid files will be ignored.

## Sharing documentation

To share some unpublished package documentation (for example for review),
commit `README.md` and `docs.json` (generated with `elm make --docs docs.json`)
to a github repository and use the following query parameters:

**`repo`**
> The github repository, for example `dmy/elm-doc-example`.

**`version`** (optional, `master` by default)
> The branch, tag or commit hash.

Examples with https://github.com/dmy/elm-doc-example:
* https://elm-doc-preview.netlify.com?repo=dmy/elm-doc-example
* https://elm-doc-preview.netlify.com?repo=dmy/elm-doc-example&version=master
* https://elm-doc-preview.netlify.com?repo=dmy/elm-doc-example&version=ba1054
* https://elm-doc-preview.netlify.com/ModuleA?repo=dmy/elm-doc-example
* https://elm-doc-preview.netlify.com/ModuleB?repo=dmy/elm-doc-example#TypeB

Notes:
* Paths to modules and symbols fragments are supported, so links from the
documentation can be copied and shared.
* Files not found or invalid will be ignored.

## Privacy

No data is sent to the server, so you can safely preview private packages
documentation.

Local documentation is stored in the browser local storage to improve
navigation.  
Closing the preview clears it.

## Offline version with hot reloading
When editing a package documentation, it is more convenient to see updates in
real-time. For this you can use the local version that supports hot reloading,
see https://www.npmjs.com/package/elm-doc-preview.

## Credits

* Documentation rendering from [package.elm-lang.org](https://github.com/elm/package.elm-lang.org) by Evan Czaplicki.
* Markdown rendering from [Marked.js](https://github.com/markedjs/marked) by Christopher Jeffrey.
* Code highlighting from [highlight.js](https://github.com/highlightjs/highlight.js) by Ivan Sagalaev.
* Code highlighting theme from [Solarized](https://ethanschoonover.com/solarized) by Jeremy Hull.
* CSS spinner from [SpinKit](https://github.com/tobiasahlin/SpinKit) by Tobias Ahlin.

## Feedback

Report bugs or feature requests at
https://github.com/dmy/elm-doc-preview/issues.
"""


readmeWithModules : String
readmeWithModules =
    """
# Elm Documentation Previewer

Select a module or add a `README.md` file.
"""
