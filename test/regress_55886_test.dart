// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Regression test for https://dartbug.com/55886: [HttpResponse.addStream]
// should cancel subscription to the stream which is being added if
// [HttpResponse] itself is being closed.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOSink;

import 'package:http_io/http_io.dart';

import 'async_helper.dart';
import 'expect.dart';

Future<void> pipeStream(Stream<List<int>> from, IOSink to) async {
  bool wasCancelled = false;

  StreamSubscription<List<int>>? subscription;
  late StreamController<List<int>> streamController;
  streamController = StreamController<List<int>>(
    onPause: () {
      subscription?.pause();
    },
    onResume: () {
      subscription?.resume();
    },
    onCancel: () {
      wasCancelled = true;
      subscription?.cancel();
      subscription = null;
    },
    onListen: () {
      subscription = from.listen(
        (data) {
          streamController.add(data);
        },
        onDone: () {
          streamController.close();
          subscription?.cancel();
          subscription = null;
        },
        onError: (Object e, StackTrace st) {
          streamController.addError(e, st);
          subscription?.cancel();
          subscription = null;
        },
      );
    },
  );

  await streamController.stream.pipe(to);
  Expect.isTrue(wasCancelled);
}

Stream<List<int>> generateSlowly() async* {
  for (var i = 0; i < 100; i++) {
    yield utf8.encode('item $i');
    await Future<void>.delayed(Duration(milliseconds: 100));
  }
}

Future<void> serve(HttpServer server) async {
  await for (var rq in server) {
    rq.response.bufferOutput = false;
    await pipeStream(generateSlowly(), rq.response);
    break;
  }
}

void main() async {
  asyncStart();

  var server = await HttpServer.bind('localhost', 0);
  serve(server).then((_) => asyncEnd());

  // Send request and then cancel response stream subscription after
  // the first chunk. This should cause server to close the connection
  // and cancel subscription to the stream which is being piped into
  // the response.
  var client = HttpClient();
  var rq = await client.get('localhost', server.port, '/');
  var rs = await rq.close();
  late StreamSubscription<String> sub;
  sub = rs.map(utf8.decode).listen((msg) {
    sub.cancel();
  });
}
