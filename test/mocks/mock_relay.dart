import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/domain_layer/entities/filter.dart';
import 'package:dart_ndk/shared/nips/nip01/key_pair.dart';
import 'package:dart_ndk/domain_layer/entities/nip_65.dart';
import 'package:flutter_test/flutter_test.dart';

class MockRelay {
  String name;
  int? port;
  HttpServer? server;
  WebSocket? webSocket;
  Map<KeyPair, Nip65>? nip65s;
  Map<KeyPair, Nip01Event>? textNotes;
  bool signEvents;

  static int startPort = 4044;

  String get url => "ws://localhost:$port";

  MockRelay({
    required this.name,
    this.nip65s,
    this.signEvents = true,
    int? explicitPort,
  }) {
    if (explicitPort != null) {
      port = explicitPort;
    } else {
      port = startPort;
      startPort++;
    }
  }

  Future<void> startServer(
      {Map<KeyPair, Nip65>? nip65s,
      Map<KeyPair, Nip01Event>? textNotes}) async {
    var myPromise = Completer<void>();

    if (nip65s != null) {
      this.nip65s = nip65s;
    }
    if (textNotes != null) {
      this.textNotes = textNotes;
    }

    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, port!);

    this.server = server;

    var stream = server.transform(WebSocketTransformer());

    stream.listen((webSocket) {
      this.webSocket = webSocket;
      webSocket.listen((message) {
        if (message == "ping") {
          webSocket.add("pong");
          return;
        }
        var eventJson = json.decode(message);
        if (eventJson[0] == "REQ") {
          String requestId = eventJson[1];
          log('Received: $eventJson');
          Filter filter = Filter.fromMap(eventJson[2]);
          if (filter.kinds != null && filter.authors != null) {
            if (filter.kinds!.contains(Nip65.KIND) && nip65s != null) {
              _respondeNip65(filter.authors!, requestId);
            }
            if (filter.kinds!.contains(Nip01Event.TEXT_NODE_KIND) &&
                textNotes != null) {
              _respondeTextNote(filter.authors!, requestId);
            }
            // todo: other
          }
          List<dynamic> eose = [];
          eose.add("EOSE");
          eose.add(requestId);
          webSocket.add(jsonEncode(eose));
        }
      });
    }, onError: (error) {
      log(' error: $error');
    });

    log('Listening on localhost:${server.port}');
    myPromise.complete();

    return myPromise.future;
  }

  void _respondeNip65(List<String> authors, String requestId) {
    for (var author in authors) {
      KeyPair key = nip65s!.keys.where((key) => key.publicKey == author).first;
      Nip65? nip65 = nip65s![key];
      if (nip65 != null && nip65.relays.isNotEmpty) {
        List<dynamic> json = [];
        json.add("EVENT");
        json.add(requestId);

        Nip01Event event = nip65.toEvent();
        if (signEvents) {
          event.sign(key.privateKey!);
        }
        json.add(event.toJson());
        webSocket!.add(jsonEncode(json));
      }
    }
  }

  void _respondeTextNote(List<String> authors, String requestId) {
    for (var author in authors) {
      List<KeyPair> keys =
          textNotes!.keys.where((key) => key.publicKey == author).toList();
      if (keys.isNotEmpty) {
        KeyPair key = keys.first;
        Nip01Event? textNote = Nip01Event.fromJson(textNotes![key]!.toJson());
        List<dynamic> json = [];
        json.add("EVENT");
        json.add(requestId);

        if (signEvents) {
          textNote.sign(key.privateKey!);
        }
        json.add(textNote.toJson());
        webSocket!.add(jsonEncode(json));
      }
    }
  }

  Future<void> stopServer() async {
    if (server != null) {
      log('closing server on localhost:$url');
      return await server!.close();
    }
  }
}
