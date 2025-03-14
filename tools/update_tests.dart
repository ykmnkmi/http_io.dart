import 'dart:async';
import 'dart:convert';
import 'dart:io';

final RegExp spaceRE = RegExp(r'\s+');

final RegExp optionsRE = RegExp(r'^// VMOptions=(.*)$', multiLine: true);

final Uri git = Uri.parse(
  'https://raw.githubusercontent.com/dart-lang/sdk/refs/tags/3.7.1/tests/standalone/io/',
);

Future<void> main() async {
  List<FileSystemEntity> entities = Directory('test').listSync();

  HttpClient client = HttpClient();

  for (FileSystemEntity entity in entities) {
    if (entity is! File || !entity.path.endsWith('_test.dart')) {
      continue;
    }

    print(entity.path);

    Uri fileUri = git.resolve(entity.path.substring(5));
    HttpClientRequest request = await client.openUrl('GET', fileUri);
    HttpClientResponse response = await request.close();
    String content = await utf8.decoder.bind(response).join();
    entity.writeAsStringSync(
      content.replaceAll('dart:io', 'http_io/http_io.dart'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  client.close();
}

List<String> extractVMOptions(RegExpMatch match) {
  String options = match[1] ?? '';

  if (options.isEmpty) {
    return <String>[];
  }

  return options.split(spaceRE);
}
