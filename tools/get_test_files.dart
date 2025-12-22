import 'dart:async';
import 'dart:convert';

import 'package:http_io/http_io.dart';

typedef JsonMap = Map<String, Object?>;

final uri = Uri(
  scheme: 'https',
  host: 'api.github.com',
  path: 'repos/dart-lang/sdk/contents/tests/standalone/io',
  query: 'ref=stable',
);

Future<void> main() async {
  HttpClient client = HttpClient();

  client.badCertificateCallback = (certificate, host, port) {
    // To pass local proxy. You don't need it.
    return true;
  };

  try {
    HttpClientRequest request = await client.getUrl(uri);
    HttpClientResponse response = await request.close();
    String body = await utf8.decodeStream(response);

    List<Object?> list = json.decode(body) as List<Object?>;
    List<JsonMap> entries = list.cast<JsonMap>();

    for (JsonMap entry in entries) {
      if (entry['type'] != 'file') {
        continue;
      }

      String name = entry['name'] as String;
      String downloadUrl = entry['download_url'] as String;

      if (name.startsWith('socket_')) {
        print(name);

        String content = await read(client, downloadUrl);

        File('test/$name')
          ..createSync()
          ..writeAsStringSync(content);
      }
    }
  } finally {
    client.close();
  }
}

Future<String> read(HttpClient client, String url) async {
  HttpClientRequest request = await client.getUrl(Uri.parse(url));
  HttpClientResponse response = await request.close();
  return await utf8.decodeStream(response);
}
