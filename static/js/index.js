new ClipboardJS('.copy-to-clipboard');
var app = Elm.Main.init();

document.addEventListener("click", function(e) {
  if (e.button !== 0) {
    return true;
  }

  e.preventDefault();
  var target = e.target;
  // Go up to anchor to get href
  while (target && !(target instanceof HTMLAnchorElement)) {
    target = target.parentNode;
  }
  if (target instanceof HTMLAnchorElement) {
    var href = target.getAttribute("href");
    if (href && href.startsWith("https://package.elm-lang.org/packages/")) {
      href = href.substring(28);
    }
    if (href) {
      app.ports.locationHrefRequested.send(href);
    }
  }
});

var ws = new WebSocket("ws://" + location.hostname + ":" + location.port + "/");

ws.onclose = function (event) {
  if (event.code > 1001) {
    location.reload();
  }
};

ws.onmessage = function (event) {
  var msg = JSON.parse(event.data);
  switch (msg.type) {
    case "readme":
      app.ports.onReadme.send(msg.data);
      break;
    case "manifest":
      console.log(manifest);
      app.ports.onManifest.send(msg.data);
    case "docs":
      app.ports.onDocs.send(msg.data);
      break;
  }
};
