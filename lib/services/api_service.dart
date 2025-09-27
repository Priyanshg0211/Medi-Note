import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/patient.dart';

class ApiService {
  // Backend URL - Using deployed Railway backend
  static const String baseUrl =
      'https://medinote-backend-production.up.railway.app';
  // For local development: 'http://localhost:3000'
  // For device testing: 'http://YOUR_COMPUTER_IP:3000'

  static const String authToken = 'test-token';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $authToken',
  };

  // Create a new recording session
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
      print('Error creating session: $e');
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

  // Get presigned URL for chunk upload
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
      print('Error getting presigned URL: $e');
      rethrow;
    }
  }

  // Upload audio chunk to presigned URL
  static Future<void> uploadChunk({
    required String presignedUrl,
    required Uint8List audioData,
  }) async {
    try {
      print('Uploading chunk to: $presignedUrl (${audioData.length} bytes)');

      final response = await http.put(
        Uri.parse(presignedUrl),
        headers: {'Content-Type': 'audio/wav'},
        body: audioData,
      );

      if (response.statusCode == 200) {
        print('Chunk upload successful');
      } else {
        throw Exception('Failed to upload chunk: ${response.statusCode}');
      }
    } catch (e) {
      print('Error uploading chunk: $e');
      rethrow;
    }
  }

  // Notify backend that chunk was uploaded
  static Future<void> notifyChunkUploaded({
    required String sessionId,
    required String gcsPath,
    required int chunkNumber,
    required bool isLast,
    required int totalChunks,
    required String publicUrl,
  }) async {
    try {
      print(
        'Notifying chunk upload: session=$sessionId, chunk=$chunkNumber, isLast=$isLast',
      );

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
        print('Chunk notification successful');
      } else {
        throw Exception(
          'Failed to notify chunk upload: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error notifying chunk upload: $e');
      rethrow;
    }
  }

  // Get patients list
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
      print('Error getting patients: $e');
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

  // Create a new patient and return it
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

      print('Add patient response status: ${response.statusCode}');
      print('Add patient response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Parsed response data: $data');

        // Try different possible response structures
        Map<String, dynamic> patientJson;
        if (data.containsKey('patient')) {
          patientJson = data['patient'];
        } else if (data.containsKey('data')) {
          patientJson = data['data'];
        } else {
          // Assume the response is the patient data directly
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
      print('Error adding patient: $e');
      if (e is TimeoutException ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out')) {
        // Create a local patient when server is unavailable
        print('Server unavailable, creating local patient');
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
