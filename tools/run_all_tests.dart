import 'dart:async';
import 'dart:io' hide exitCode;
import 'dart:io' as io show exitCode;
import 'dart:isolate';

final RegExp spaceRE = RegExp(r'\s+');

final RegExp optionsRE = RegExp(r'^// VMOptions=(.*)$', multiLine: true);

Future<void> main() async {
  List<FileSystemEntity> entities = Directory('test').listSync();

  parent:
  for (FileSystemEntity entity in entities) {
    if (entity is! File || !entity.path.endsWith('_test.dart')) {
      continue;
    }

    await Future.delayed(const Duration(milliseconds: 10));

    String content = entity.readAsStringSync();

    List<List<String>> vmOptions = optionsRE
        .allMatches(content)
        .map<List<String>>(extractVMOptions)
        .toList();

    if (vmOptions.isEmpty) {
      stdout.writeln('dart ${entity.path}');

      ReceivePort receivePort = ReceivePort();

      try {
        SendPort sendPort = receivePort.sendPort;

        Isolate isolate = await Isolate.spawnUri(
          Directory.current.uri.resolveUri(entity.uri),
          <String>[],
          null,
          onExit: sendPort,
          onError: sendPort,
        );

        Object? message = await receivePort.first;
        isolate.kill(priority: Isolate.immediate);

        if (message is List) {
          stderr.writeln(message[0]);
          stderr.writeln(message[1]);
          break parent;
        }
      } catch (error, stackTrace) {
        stderr.writeln(error);
        stderr.writeln(stackTrace);
      } finally {
        receivePort.close();
      }
    } else {
      for (List<String> options in vmOptions) {
        options = <String>[...options, entity.path];
        stdout.writeln('dart ${options.join(' ')}');

        Process process = await Process.start(Platform.executable, options);
        StreamSubscription<List<int>> out = process.stdout.listen(stdout.add);
        StreamSubscription<List<int>> err = process.stderr.listen(stderr.add);

        int exitCode = await process.exitCode.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            process.kill(ProcessSignal.sigterm);
            return process.exitCode;
          },
        );

        out.cancel();
        err.cancel();

        if (exitCode != 0) {
          io.exitCode = exitCode;
          break parent;
        }
      }
    }
  }
}

List<String> extractVMOptions(RegExpMatch match) {
  String options = match[1] ?? '';

  if (options.isEmpty) {
    return <String>[];
  }

  return options.split(spaceRE);
}
