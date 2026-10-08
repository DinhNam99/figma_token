import 'dart:convert';
import 'dart:io';

import 'package:figma/figma.dart';

import '../model/raw_models.dart';

/// Thrown when the Figma API cannot be reached or rejects the request.
class FigmaApiException implements Exception {
  const FigmaApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'FigmaApiException${statusCode == null ? '' : '($statusCode)'}: $message';
}

/// Thin client for `GET /v1/files/:file_key/variables/local`.
///
/// Auth: header `X-Figma-Token: <personal access token>`. The token must carry
/// the `file_variables:read` scope (the endpoint is available to full members
/// of Enterprise organisations).
class FigmaVariablesApi {
  FigmaVariablesApi({required String token, bool useHttp2 = false})
    : _client = FigmaClient(token, useHttp2: useHttp2);

  final FigmaClient _client;

  static const String _path = '/variables/local';

  /// Fetches and decodes the local variables document for [fileKey].
  Future<RawVariablesDocument> fetchLocalVariables(String fileKey) async {
    final url = 'https://api.figma.com/v1/files/$fileKey$_path';
    final Map<String, dynamic> json;
    try {
      json = await _client.authenticatedGet(url);
    } on FigmaException catch (error) {
      throw FigmaApiException(_explain(error), statusCode: error.code);
    } on SocketException catch (error) {
      throw FigmaApiException('Network error: ${error.message}');
    }

    final document = RawVariablesDocument.fromJson(json);
    if (document.variables.isEmpty && document.collections.isEmpty) {
      throw const FigmaApiException(
        'The file returned no variables. Check that the file key is correct '
        'and that the file actually contains Variables.',
      );
    }
    return RawVariablesDocument(
      collections: document.collections,
      variables: document.variables,
      fileKey: fileKey,
    );
  }

  static String _explain(FigmaException error) {
    final body = error.message ?? '';
    String message = body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        message = (decoded['message'] ?? decoded['err'] ?? body).toString();
      }
    } catch (_) {
      // Not a JSON body: keep the raw text.
    }
    if (error.code == 403 && message.contains('file_variables:read')) {
      return '$message\n'
          'Create a Personal Access Token with the `file_variables:read` '
          'scope (Figma -> Settings -> Security -> Personal access tokens) '
          'and update your .env.';
    }
    if (error.code == 401) {
      return 'Invalid Figma token (401). Check FIGMA_TOKEN in your .env.';
    }
    return message;
  }
}
