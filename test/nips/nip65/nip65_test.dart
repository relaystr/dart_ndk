import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip65/nip65.dart';
import 'package:dart_ndk/nips/nip65/read_write_marker.dart';
import 'package:dart_ndk/read_write.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nip65', () {
    test('fromEvent', () {
      final event = Nip01Event(
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pubKey: 'pubkeyUser1',
        kind: Nip65.KIND,
        content: "",
        tags: [
          ['r', 'wss://example.com', 'read'],
          ['r', 'wss://example.org', 'write'],
          ['r', 'wss://example.net'],
          ['invalid'],
        ],
      );
      final nip65 = Nip65.fromEvent(event);
      expect(nip65.relaysMap(), {
        'wss://example.com': ReadWriteMarker.readOnly,
        'wss://example.org': ReadWriteMarker.writeOnly,
        'wss://example.net': ReadWriteMarker.readWrite,
      });
    });

    test('fromEvent - identity (trailing /)', () {
      final event = Nip01Event(
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pubKey: 'pubkeyUser1',
        kind: Nip65.KIND,
        content: "",
        tags: [
          ['r', 'wss://example.com', 'read'],
          ['r', 'wss://example.com/', 'read'],
          ['r', 'wss://example.org/', 'write'],
          ['r', 'wss://example.net'],
          ['invalid'],
        ],
      );
      final nip65 = Nip65.fromEvent(event);
      expect(nip65.relaysMap(), {
        'wss://example.com': ReadWriteMarker.readOnly,
        'wss://example.org': ReadWriteMarker.writeOnly,
        'wss://example.net': ReadWriteMarker.readWrite,
      });
    });

    test('toEvent', () {
      String pubKey = 'pubKey123';
      final nip65 = Nip65.fromMap(pubKey, {
        'wss://example.com': ReadWriteMarker.readWrite,
        'wss://example.org': ReadWriteMarker.readOnly,
        'wss://example.net': ReadWriteMarker.writeOnly,
      });
      final myEvent = nip65.toEvent();
      expect(myEvent.pubKey, equals(pubKey));
      expect(myEvent.kind, equals(Nip65.KIND));
      expect(
          myEvent.tags,
          equals([
            [
              'r',
              'wss://example.com',
            ],
            ['r', 'wss://example.org', 'read'],
            ['r', 'wss://example.net', 'write'],
          ]));
      expect(myEvent.content, equals(''));
      expect(myEvent.createdAt, equals(nip65.createdAt));
    });
  });

  group('ReadWriteMarker', () {
    test('from', () {
      expect(ReadWriteMarker.from(read: true, write: true),
          ReadWriteMarker.readWrite);
      expect(() => ReadWriteMarker.from(read: false, write: false),
          throwsException);
    });

    test('isRead', () {
      expect(ReadWriteMarker.readOnly.isRead, true);
      expect(ReadWriteMarker.readWrite.isRead, true);
      expect(ReadWriteMarker.writeOnly.isRead, false);
    });
    test('isWrite', () {
      expect(ReadWriteMarker.readOnly.isWrite, false);
      expect(ReadWriteMarker.readWrite.isWrite, true);
      expect(ReadWriteMarker.writeOnly.isWrite, true);
    });
    test('matchesMarker', () {
      ReadWriteMarker r = ReadWriteMarker.readOnly;
      ReadWriteMarker w = ReadWriteMarker.writeOnly;
      ReadWriteMarker rw = ReadWriteMarker.readWrite;

      RelayDirection read = RelayDirection.inbox;
      RelayDirection write = RelayDirection.outbox;

      expect(read.matchesMarker(r), true);
      expect(write.matchesMarker(w), true);
      expect(read.matchesMarker(rw), true);
      expect(write.matchesMarker(rw), true);
      expect(read.matchesMarker(w), false);
      expect(write.matchesMarker(r), false);
    });
  });
}
