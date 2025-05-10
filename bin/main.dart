import 'package:http_io/http_io.dart';

void main() {
  print(const bool.fromEnvironment('dart.vm.product'));
  print(HeaderValue.parse('xxx; aaa=bbb; ccc="\\";\\a"; ddd="    "'));
}
