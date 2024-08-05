import 'dart:convert';
import 'package:http/http.dart' as http;

class HttpRequestDS {
  final http.Client _client;

  HttpRequestDS(this._client);

  Future<Map<String, dynamic>> jsonRequest(String url) async {
    http.Response response = await _client
        .get(Uri.parse(url), headers: {"Accept": "application/json"});

    if (response.statusCode != 200) {
      return throw Exception(
          "error fetching STATUS: ${response.statusCode}, Link: $url");
    }
    return jsonDecode(response.body);
  }
}
