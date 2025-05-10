import 'dart:async';

import 'package:http_io/http_io.dart';

void main() {
  HttpServer.bind(InternetAddress.loopbackIPv4, 3000).then<void>(onServer);
}

void onServer(HttpServer server) {
  server.listen(onRequest);

  StreamSubscription<ProcessSignal> subscription = ProcessSignal.sigterm
      .watch()
      .listen(null);

  void onSignal(ProcessSignal signal) {
    subscription.cancel();
    server.close();
  }

  subscription.onData(onSignal);
}

void onRequest(HttpRequest request) {
  if (request.uri.path == '/') {
    request.response.headers.contentType = ContentType.text;
    request.response.write(request.requestedUri);
  } else {
    request.response.statusCode = 404;
  }

  request.response.close();
}
