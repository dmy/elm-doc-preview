# elm-doc-preview

This is an Elm 0.19 documentation previewer for **packages**, **applications**
and their **dependencies**.


It aims at rendering documentation exactly like the
[official package website](https://package.elm-lang.org) to avoid
any surprise when releasing a package.

Note that applications documentation is
[not yet supported by Elm](https://github.com/elm/compiler/issues/1835#issuecomment-440080525),
so only the `README` and dependencies are supported for those at the moment.

<p align="center">
  <img src="https://raw.githubusercontent.com/dmy/elm-doc-preview/master/screenshots/regex.png" width="360" />
  <img src="https://raw.githubusercontent.com/dmy/elm-doc-preview/master/screenshots/elm-doc-preview.png" width="360" />
  <img src="https://raw.githubusercontent.com/dmy/elm-doc-preview/master/screenshots/compilation.png" width="360" />
  <img src="https://raw.githubusercontent.com/dmy/elm-doc-preview/master/screenshots/term.png" width="360" />
</p>

# Features

- **Packages** full support with **hot reloading**
- **Offline dependencies documentation** for packages and applications
- **Regex filtering** for focused documentation
- **Compilation errors display** (packages only)
- **Online documentations sharing** for reviews (using the
[online version](#online-version))

# Installation

```sh
$ npm install -g elm-doc-preview
```

# Usage

```sh
Usage: edp|elm-doc-preview [options] [path_to_package_or_application]

Options:
  -V, --version      output the version number
  -p, --port <port>  the server listening port (default: 8000)
  -h, --help         output usage information

Environment variables:
  ELM_HOME           Elm home directory (cache)
```

For example, from the directory where your package `elm.json` is:

```sh
$ elm-doc-preview
```

or

```
$ edp
```

or from anywhere:

```sh
$ elm-doc-preview path/to/package_or_application
```

# Online version

There is also an online version supporting documentations loading from github
to share them for online reviews:

https://elm-doc-preview.netlify.com

It does not support hot-reloading or dependencies documentation though.

# API
```javascript
const DocServer = require('elm-doc-preview');

// constructor(path_to_elm_json = ".")
const server = new DocServer();

// Optionaly exit cleanly on SIGINT to let temporary files be removed
process.on("SIGINT", () => { process.exit(0); });

// listen(port = 8000)
server.listen();
```

# Credits

- Documentation rendering from [package.elm-lang.org](https://github.com/elm/package.elm-lang.org) by Evan Czaplicki.
- Markdown rendering from [Marked.js](https://github.com/markedjs/marked) by Christopher Jeffrey.
- Code highlighting from [highlight.js](https://github.com/highlightjs/highlight.js) by Ivan Sagalaev.
- Code highlighting theme from [Solarized](ethanschoonover.com/solarized) by Jeremy Hull.
- CSS spinner from [SpinKit](https://github.com/tobiasahlin/SpinKit) by Tobias Ahlin.
