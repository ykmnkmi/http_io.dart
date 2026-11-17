import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String http = 'http.dart';

final Uri git = Uri.parse(
  'https://raw.githubusercontent.com'
  '/dart-lang/sdk/stable/sdk/lib/_http/',
);

Future<void> main() async {
  List<FileSystemEntity> entities = Directory('lib/src/http').listSync();

  HttpClient client = HttpClient();

  for (FileSystemEntity entity in entities) {
    if (entity is! File) {
      continue;
    }

    print(entity.uri);

    Uri fileUri = git.resolve(entity.uri.pathSegments.last);
    HttpClientRequest request = await client.getUrl(fileUri);
    HttpClientResponse response = await request.close();
    String content = await utf8.decoder.bind(response).join();
    entity.writeAsStringSync(content.replaceAll('dart:_http', http));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  client.close();
}
