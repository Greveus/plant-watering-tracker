import 'dart:convert';

import 'package:shelf/shelf.dart';

Response handleHealth(Request request) {
  return Response.ok(
    jsonEncode({'status': 'ok'}),
    headers: {'content-type': 'application/json'},
  );
}
