var app = Elm.Main.init({
  flags: {
    readme: null,
    docs: null,
    online: false
  }
});

app.ports.clearStorage.subscribe(function() {
});

app.ports.storeReadme.subscribe(function(readme) {
});

app.ports.storeDocs.subscribe(function(docs) {
});

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
    if (href) {
      app.ports.locationHrefRequested.send(href);
    }
  }
});

var ws = new WebSocket("ws://" + location.hostname + ":" + location.port + "/");

ws.onclose = function(event) {
  if (event.code > 1001) {
    location.reload();
  }
};

ws.onmessage = function(event) {
  var msg = JSON.parse(event.data);
  switch (msg.type) {
    case "name":
      app.ports.nameUpdated.send(msg.data);
      break;
    case "compilation":
      app.ports.compilationUpdated.send(msg.data);
      break;
    case "readme":
      app.ports.readmeUpdated.send(msg.data);
      break;
    case "docs":
      app.ports.docsUpdated.send(msg.data);
      break;
    case "deps":
      app.ports.depsUpdated.send(msg.data);
      break;
  }
};
