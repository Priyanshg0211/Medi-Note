import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/patient.dart';

class ApiService {
  // Backend URL - Using deployed Railway backend
  static const String baseUrl = 'https://medinote-backend-production.up.railway.app/api';
  // For local development: 'http://localhost:3000/api'
  // For device testing: 'http://YOUR_COMPUTER_IP:3000/api'

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
      final response = await http.post(
        Uri.parse('$baseUrl/v1/upload-session'),
        headers: _headers,
        body: json.encode({
          'patientId': patientId,
          'userId': userId,
          'patientName': patientName,
          'status': 'recording',
          'startTime': DateTime.now().toIso8601String(),
          'templateId': 'new_patient_visit',
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['id'];
      } else {
        throw Exception('Failed to create session: ${response.statusCode}');
      }
    } catch (e) {
      print('Error creating session: $e');
      rethrow;
    }
  }

  // Get presigned URL for chunk upload
  // NOTE: This endpoint is not available on the deployed backend
  // Keeping for future implementation or alternative approach
  static Future<PresignedUrlResponse> getPresignedUrl({
    required String sessionId,
    required int chunkNumber,
  }) async {
    try {
      // Since /get-presigned-url is not available, we'll return a mock response
      // or implement direct upload to the session endpoint
      print('WARNING: get-presigned-url endpoint not available on deployed backend');
      
      // For now, create a mock response or alternative implementation
      return PresignedUrlResponse(
        url: '$baseUrl/v1/upload-session/$sessionId/chunk/$chunkNumber',
        gcsPath: 'mock-gcs-path',
        publicUrl: 'mock-public-url',
      );
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
      
      // Since we're using mock URLs, we'll skip actual upload for now
      // In a real implementation, this would upload to the session endpoint
      print('WARNING: Using mock upload - actual endpoint not available on deployed backend');
      
      // Mock successful upload
      await Future.delayed(Duration(milliseconds: 100));
      print('Chunk upload simulated successfully');
    } catch (e) {
      print('Error uploading chunk: $e');
      rethrow;
    }
  }

  // Notify backend that chunk was uploaded
  // NOTE: This endpoint is not available on the deployed backend
  static Future<void> notifyChunkUploaded({
    required String sessionId,
    required String gcsPath,
    required int chunkNumber,
    required bool isLast,
    required int totalChunks,
    required String publicUrl,
  }) async {
    try {
      print('Notifying chunk upload: session=$sessionId, chunk=$chunkNumber, isLast=$isLast');
      print('WARNING: notify-chunk-uploaded endpoint not available on deployed backend');
      
      // Since the endpoint doesn't exist, we'll simulate the notification
      // In a real implementation, this might be handled differently by the backend
      await Future.delayed(Duration(milliseconds: 50));
      print('Chunk notification simulated successfully');
    } catch (e) {
      print('Error notifying chunk upload: $e');
      rethrow;
    }
  }

  // Get patients list
  static Future<List<Patient>> getPatients({required String userId}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/v1/patients?userId=$userId'),
        headers: {'Authorization': 'Bearer $authToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> patientsJson = data['patients'];
        return patientsJson.map((json) => Patient.fromJson(json)).toList();
      } else {
        throw Exception('Failed to get patients: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting patients: $e');
      rethrow;
    }
  }

  // Create a new patient and return it
  // NOTE: add-patient-ext endpoint not available, using patients endpoint instead
  static Future<Patient> addPatient({required String name, required String userId}) async {
    try {
      print('WARNING: add-patient-ext endpoint not available, attempting to use patients endpoint');
      
      final response = await http.post(
        Uri.parse('$baseUrl/v1/patients'),
        headers: _headers,
        body: json.encode({
          'name': name,
          'userId': userId,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final patientJson = data['patient'] ?? data;
        return Patient(
          id: patientJson['id'] ?? 'temp_${DateTime.now().millisecondsSinceEpoch}',
          name: patientJson['name'] ?? name,
          email: patientJson['email'] ?? '',
          phone: patientJson['phone'] ?? '',
          createdAt: patientJson['createdAt'] != null
              ? DateTime.tryParse(patientJson['createdAt']) ?? DateTime.now()
              : DateTime.now(),
        );
      } else {
        throw Exception('Failed to add patient: ${response.statusCode}');
      }
    } catch (e) {
      print('Error adding patient: $e');
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
