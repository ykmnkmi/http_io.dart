// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'http.dart';

const String _dartSessionId = 'DARTSESSID';

// A _HttpSession is a node in a double-linked list, with _next and _prev being
// the previous and next pointers.
class _HttpSession implements HttpSession {
  // Destroyed marked. Used by the http connection to see if a session is valid.
  bool _destroyed = false;
  bool _isNew = true;
  DateTime _lastSeen;
  void Function()? _timeoutCallback;
  final _HttpSessionManager _sessionManager;
  // Pointers in timeout queue.
  _HttpSession? _prev;
  _HttpSession? _next;
  @override
  final String id;

  final Map<Object?, Object?> _data = HashMap<Object?, Object?>();

  _HttpSession(this._sessionManager, this.id) : _lastSeen = DateTime.now();

  @override
  void destroy() {
    assert(!_destroyed);
    _destroyed = true;
    _sessionManager._removeFromTimeoutQueue(this);
    _sessionManager._sessions.remove(id);
  }

  // Mark the session as seen. This will reset the timeout and move the node to
  // the end of the timeout queue.
  void _markSeen() {
    _lastSeen = DateTime.now();
    _sessionManager._bumpToEnd(this);
  }

  DateTime get lastSeen => _lastSeen;

  @override
  bool get isNew => _isNew;

  @override
  set onTimeout(void Function()? callback) {
    _timeoutCallback = callback;
  }

  // Map implementation:
  @override
  bool containsValue(value) => _data.containsValue(value);
  @override
  bool containsKey(key) => _data.containsKey(key);
  @override
  dynamic operator [](key) => _data[key];
  @override
  void operator []=(key, value) {
    _data[key] = value;
  }

  @override
  dynamic putIfAbsent(key, ifAbsent) => _data.putIfAbsent(key, ifAbsent);
  @override
  void addAll(Map<Object?, Object?> other) => _data.addAll(other);
  @override
  dynamic remove(key) => _data.remove(key);
  @override
  void clear() {
    _data.clear();
  }

  @override
  void forEach(void Function(dynamic key, dynamic value) f) {
    _data.forEach(f);
  }

  @override
  Iterable<MapEntry<Object?, Object?>> get entries => _data.entries;

  @override
  void addEntries(Iterable<MapEntry<Object?, Object?>> entries) {
    _data.addEntries(entries);
  }

  @override
  Map<K, V> map<K, V>(
          MapEntry<K, V> Function(dynamic key, dynamic value) transform) =>
      _data.map(transform);

  @override
  void removeWhere(bool Function(dynamic key, dynamic value) test) {
    _data.removeWhere(test);
  }

  @override
  Map<K, V> cast<K, V>() => _data.cast<K, V>();
  @override
  dynamic update(key, dynamic Function(dynamic value) update,
          {dynamic Function()? ifAbsent}) =>
      _data.update(key, update, ifAbsent: ifAbsent);

  @override
  void updateAll(dynamic Function(dynamic key, dynamic value) update) {
    _data.updateAll(update);
  }

  @override
  Iterable<Object?> get keys => _data.keys;
  @override
  Iterable<Object?> get values => _data.values;
  @override
  int get length => _data.length;
  @override
  bool get isEmpty => _data.isEmpty;
  @override
  bool get isNotEmpty => _data.isNotEmpty;

  @override
  String toString() => 'HttpSession id:$id $_data';
}

// Private class used to manage all the active sessions. The sessions are stored
// in two ways:
//
//  * In a map, mapping from ID to HttpSession.
//  * In a linked list, used as a timeout queue.
class _HttpSessionManager {
  final Map<String, _HttpSession> _sessions;
  int _sessionTimeout = 20 * 60; // 20 mins.
  _HttpSession? _head;
  _HttpSession? _tail;
  Timer? _timer;

  _HttpSessionManager() : _sessions = {};

  String createSessionId() {
    const int keyLength = 16; // 128 bits.
    var data = _CryptoUtils.getRandomBytes(keyLength);
    return _CryptoUtils.bytesToHex(data);
  }

  _HttpSession? getSession(String id) => _sessions[id];

  _HttpSession createSession() {
    var id = createSessionId();
    // TODO(ajohnsen): Consider adding a limit and throwing an exception.
    // Should be very unlikely however.
    while (_sessions.containsKey(id)) {
      id = createSessionId();
    }
    var session = _sessions[id] = _HttpSession(this, id);
    _addToTimeoutQueue(session);
    return session;
  }

  set sessionTimeout(int timeout) {
    _sessionTimeout = timeout;
    _stopTimer();
    _startTimer();
  }

  void close() {
    _stopTimer();
  }

  void _bumpToEnd(_HttpSession session) {
    _removeFromTimeoutQueue(session);
    _addToTimeoutQueue(session);
  }

  void _addToTimeoutQueue(_HttpSession session) {
    if (_head == null) {
      assert(_tail == null);
      _tail = _head = session;
      _startTimer();
    } else {
      assert(_timer != null);
      var tail = _tail!;
      // Add to end.
      tail._next = session;
      session._prev = tail;
      _tail = session;
    }
  }

  void _removeFromTimeoutQueue(_HttpSession session) {
    var next = session._next;
    var prev = session._prev;
    session._next = session._prev = null;
    next?._prev = prev;
    prev?._next = next;
    if (_tail == session) {
      _tail = prev;
    }
    if (_head == session) {
      _head = next;
      // We removed the head element, start new timer.
      _stopTimer();
      _startTimer();
    }
  }

  void _timerTimeout() {
    _stopTimer(); // Clear timer.
    var session = _head!;
    session.destroy(); // Will remove the session from timeout queue and map.
    session._timeoutCallback?.call();
  }

  void _startTimer() {
    assert(_timer == null);
    var head = _head;
    if (head != null) {
      int seconds = DateTime.now().difference(head.lastSeen).inSeconds;
      _timer =
          Timer(Duration(seconds: _sessionTimeout - seconds), _timerTimeout);
    }
  }

  void _stopTimer() {
    var timer = _timer;
    if (timer != null) {
      timer.cancel();
      _timer = null;
    }
  }
}
