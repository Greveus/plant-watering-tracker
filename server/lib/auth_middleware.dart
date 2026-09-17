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
        // Bewusst protokolliert: logRequests() zeigt nur den 403, nicht die
        // Ursache. Ohne diese Zeile sieht man in `docker compose logs` nicht,
        // ob ein Gerät mit falschem Token anklopft oder der Header ganz fehlt
        // – die beiden häufigsten Einrichtungsfehler.
        // ignore: avoid_print
        print('auth: Anfrage an ${request.url.path} abgelehnt '
            '(${header == null ? 'kein Authorization-Header' : 'falscher Token'})');
        return Response.forbidden(
          jsonEncode({'error': 'invalid_token'}),
          headers: {'content-type': 'application/json'},
        );
      }

      return innerHandler(request);
    };
  };
}
