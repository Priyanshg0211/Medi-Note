import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/patient.dart';

class ApiService {
  static const String baseUrl =
      'https://medinote-backend-production.up.railway.app';
  static const String authToken = 'test-token';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $authToken',
  };
  static Future<String> createSession({
    required String patientId,
    required String userId,
    required String patientName,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/v1/upload-session'),
            headers: _headers,
            body: json.encode({
              'patientId': patientId,
              'userId': userId,
              'patientName': patientName,
              'status': 'recording',
              'startTime': DateTime.now().toIso8601String(),
              'templateId': 'new_patient_visit',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['id'];
      } else {
        throw Exception('Failed to create session: ${response.statusCode}');
      }
    } catch (e) {
      if (e is TimeoutException ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out')) {
        throw Exception(
          'Request timed out. The server may be experiencing issues. Please try again later.',
        );
      }
      rethrow;
    }
  }

  static Future<PresignedUrlResponse> getPresignedUrl({
    required String sessionId,
    required int chunkNumber,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/get-presigned-url'),
        headers: _headers,
        body: json.encode({
          'sessionId': sessionId,
          'chunkNumber': chunkNumber,
          'mimeType': 'audio/wav',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PresignedUrlResponse.fromJson(data);
      } else {
        throw Exception('Failed to get presigned URL: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> uploadChunk({
    required String presignedUrl,
    required Uint8List audioData,
  }) async {
    try {
      final response = await http.put(
        Uri.parse(presignedUrl),
        headers: {'Content-Type': 'audio/wav'},
        body: audioData,
      );

      if (response.statusCode == 200) {
        return;
      } else {
        throw Exception('Failed to upload chunk: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> notifyChunkUploaded({
    required String sessionId,
    required String gcsPath,
    required int chunkNumber,
    required bool isLast,
    required int totalChunks,
    required String publicUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/notify-chunk-uploaded'),
        headers: _headers,
        body: json.encode({
          'sessionId': sessionId,
          'gcsPath': gcsPath,
          'chunkNumber': chunkNumber,
          'isLast': isLast,
          'totalChunksClient': totalChunks,
          'publicUrl': publicUrl,
          'mimeType': 'audio/wav',
          'selectedTemplate': 'default',
          'selectedTemplateId': 'template_123',
          'model': 'whisper',
        }),
      );

      if (response.statusCode == 200) {
        return;
      } else {
        throw Exception(
          'Failed to notify chunk upload: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<Patient>> getPatients({required String userId}) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/v1/patients?userId=$userId'),
            headers: {'Authorization': 'Bearer $authToken'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> patientsJson = data['patients'];
        return patientsJson.map((json) => Patient.fromJson(json)).toList();
      } else {
        throw Exception('Failed to get patients: ${response.statusCode}');
      }
    } catch (e) {
      if (e is TimeoutException ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out')) {
        throw Exception(
          'Request timed out. The server may be experiencing issues. Please try again later.',
        );
      }
      rethrow;
    }
  }

  static Future<Patient> addPatient({
    required String name,
    required String userId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/v1/patients/add-patient-ext'),
            headers: _headers,
            body: json.encode({'name': name, 'userId': userId}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);

        Map<String, dynamic> patientJson;
        if (data.containsKey('patient')) {
          patientJson = data['patient'];
        } else if (data.containsKey('data')) {
          patientJson = data['data'];
        } else {
          patientJson = data;
        }

        return Patient(
          id: patientJson['id'] ?? patientJson['_id'] ?? '',
          name: patientJson['name'] ?? '',
          email: patientJson['email'] ?? '',
          phone: patientJson['phone'] ?? '',
          createdAt: DateTime.now(),
        );
      } else {
        throw Exception(
          'Failed to add patient: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (e is TimeoutException ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out')) {
        return Patient(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          email: '',
          phone: '',
          createdAt: DateTime.now(),
        );
      }
      rethrow;
    }
  }
}

class PresignedUrlResponse {
  final String url;
  final String gcsPath;
  final String publicUrl;

  PresignedUrlResponse({
    required this.url,
    required this.gcsPath,
    required this.publicUrl,
  });

  factory PresignedUrlResponse.fromJson(Map<String, dynamic> json) {
    return PresignedUrlResponse(
      url: json['url'],
      gcsPath: json['gcsPath'],
      publicUrl: json['publicUrl'],
    );
  }
}

// Patient model moved to lib/models/patient.dart
