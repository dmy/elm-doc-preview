var app = Elm.Main.init({
  flags: {
    readme: localStorage.getItem("readme"),
    docs: localStorage.getItem("docs"),
    online: true
  }
});

app.ports.clearStorage.subscribe(function() {
  localStorage.clear();
});

app.ports.storeReadme.subscribe(function(readme) {
  localStorage.setItem("readme", readme);
});

app.ports.storeDocs.subscribe(function(docs) {
  localStorage.setItem("docs", docs);
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
    app.ports.locationHrefRequested.send(href);
  }
});
