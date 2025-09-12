import 'dart:async';
import 'dart:io';
import 'dart:io' as io show exitCode;

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
      List<String> arguments = <String>[entity.path];
      int exitCode = await run(arguments);

      if (exitCode != 0) {
        io.exitCode = exitCode;
        break parent;
      }
    } else {
      for (List<String> options in vmOptions) {
        List<String> arguments = <String>[...options, entity.path];
        int exitCode = await run(arguments);

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

Future<int> run(List<String> arguments) async {
  stdout.writeln('dart ${arguments.join(' ')}');

  Process process = await Process.start(Platform.executable, arguments);
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
  return exitCode;
}
