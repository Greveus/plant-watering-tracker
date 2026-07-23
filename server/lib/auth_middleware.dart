import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Prüft den Header `Authorization: Bearer <token>` gegen [expectedToken].
/// `/health` bleibt bewusst auth-frei (Liveness-Check für Docker-Healthcheck
/// und den "Verbindung testen"-Button in der App).
Middleware authMiddleware({required String expectedToken}) {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.url.path == 'health') {
        return innerHandler(request);
      }

      final header = request.headers['authorization'];
      if (header != 'Bearer $expectedToken') {
        return Response.forbidden(
          jsonEncode({'error': 'invalid_token'}),
          headers: {'content-type': 'application/json'},
        );
      }

      return innerHandler(request);
    };
  };
}
