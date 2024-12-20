// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: unused_element, unused_field

part of 'io.dart';

@pragma('vm:external-name', 'IOService_NewServicePort')
external SendPort _newServicePort();

class _IOService {
  // This list must be kept in sync with the list in runtime/bin/io_service.h
  static const int fileExists = 0;
  static const int fileCreate = 1;
  static const int fileDelete = 2;
  static const int fileRename = 3;
  static const int fileCopy = 4;
  static const int fileOpen = 5;
  static const int fileResolveSymbolicLinks = 6;
  static const int fileClose = 7;
  static const int filePosition = 8;
  static const int fileSetPosition = 9;
  static const int fileTruncate = 10;
  static const int fileLength = 11;
  static const int fileLengthFromPath = 12;
  static const int fileLastAccessed = 13;
  static const int fileSetLastAccessed = 14;
  static const int fileLastModified = 15;
  static const int fileSetLastModified = 16;
  static const int fileFlush = 17;
  static const int fileReadByte = 18;
  static const int fileWriteByte = 19;
  static const int fileRead = 20;
  static const int fileReadInto = 21;
  static const int fileWriteFrom = 22;
  static const int fileCreateLink = 23;
  static const int fileDeleteLink = 24;
  static const int fileRenameLink = 25;
  static const int fileLinkTarget = 26;
  static const int fileType = 27;
  static const int fileIdentical = 28;
  static const int fileStat = 29;
  static const int fileLock = 30;
  static const int fileCreatePipe = 31;
  static const int socketLookup = 32;
  static const int socketListInterfaces = 33;
  static const int socketReverseLookup = 34;
  static const int directoryCreate = 35;
  static const int directoryDelete = 36;
  static const int directoryExists = 37;
  static const int directoryCreateTemp = 38;
  static const int directoryListStart = 39;
  static const int directoryListNext = 40;
  static const int directoryListStop = 41;
  static const int directoryRename = 42;
  static const int sslProcessFilter = 43;

  static final SendPort _port = _newServicePort();

  static RawReceivePort? _receivePort;
  static late SendPort _replyToPort;
  static final HashMap<int, Completer<Object?>> _messageMap =
      HashMap<int, Completer<Object?>>();
  static int _id = 0;

  static Future<Object?> _dispatch(int request, List<dynamic> data) {
    int id;
    do {
      id = _getNextId();
    } while (_messageMap.containsKey(id));
    Completer<Object?> completer = Completer<Object?>();
    try {
      _ensureInitialize();
      _messageMap[id] = completer;
      _port.send(<dynamic>[id, _replyToPort, request, data]);
    } catch (error) {
      _messageMap.remove(id)!.complete(error);
      if (_messageMap.isEmpty) {
        _finalize();
      }
    }
    return completer.future;
  }

  static void _ensureInitialize() {
    if (_receivePort == null) {
      _receivePort = RawReceivePort(null, 'IO Service');
      _replyToPort = _receivePort!.sendPort;
      _receivePort!.handler = (List<Object?> data) {
        assert(data.length == 2);
        _messageMap.remove(data[0])!.complete(data[1]);
        if (_messageMap.isEmpty) {
          _finalize();
        }
      };
    }
  }

  static void _finalize() {
    _id = 0;
    _receivePort!.close();
    _receivePort = null;
  }

  static int _getNextId() {
    if (_id == 0x7FFFFFFF) {
      _id = 0;
    }
    return _id++;
  }
}
