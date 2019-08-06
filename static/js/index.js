new ClipboardJS('.copy-to-clipboard');
var app = Elm.Main.init();

var ws = new WebSocket("ws://" + location.hostname + ":" + location.port + "/");

ws.onclose = function(event) {
  if (event.code > 1001) {
    location.reload();
  }
};

ws.onmessage = function(event) {
  var msg = JSON.parse(event.data);
  switch (msg.type) {
    case "":
      break;
  }
};
