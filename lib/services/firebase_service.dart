import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient.dart';
import '../models/recording_session.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _patientsCollection = 'patients';
  static const String _recordingSessionsCollection = 'recording_sessions';

  // Initialize Firebase
  static Future<void> initialize() async {
    // Firebase is automatically initialized when the app starts
    // This method can be used for any additional setup if needed
  }

  // Add a new patient to Firestore
  static Future<Patient> addPatient({
    required String name,
    required String userId,
  }) async {
    try {
      final patientData = {
        'name': name,
        'userId': userId,
        'email': '',
        'phone': '',
        'createdAt': FieldValue.serverTimestamp(),
      };

      final docRef = await _firestore
          .collection(_patientsCollection)
          .add(patientData);

      // Get the created document to return the patient with ID
      final doc = await docRef.get();
      final data = doc.data() as Map<String, dynamic>;

      return Patient(
        id: doc.id,
        name: data['name'] ?? name,
        email: data['email'],
        phone: data['phone'],
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    } catch (e) {
      // print('Error adding patient to Firebase: $e');
      // Return a local patient if Firebase fails
      return Patient(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        email: '',
        phone: '',
        createdAt: DateTime.now(),
      );
    }
  }

  // Get all patients for a user
  static Future<List<Patient>> getPatients({required String userId}) async {
    try {
      final querySnapshot =
          await _firestore
              .collection(_patientsCollection)
              .where('userId', isEqualTo: userId)
              .orderBy('createdAt', descending: true)
              .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return Patient(
          id: doc.id,
          name: data['name'] ?? '',
          email: data['email'],
          phone: data['phone'],
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      // print('Error getting patients from Firebase: $e');
      return [];
    }
  }

  // Update a patient
  static Future<void> updatePatient({
    required String patientId,
    required String name,
    String? email,
    String? phone,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'name': name,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (email != null) updateData['email'] = email;
      if (phone != null) updateData['phone'] = phone;

      await _firestore
          .collection(_patientsCollection)
          .doc(patientId)
          .update(updateData);
    } catch (e) {
      // print('Error updating patient in Firebase: $e');
      throw Exception('Failed to update patient: $e');
    }
  }

  // Delete a patient
  static Future<void> deletePatient({required String patientId}) async {
    try {
      await _firestore.collection(_patientsCollection).doc(patientId).delete();
    } catch (e) {
      // print('Error deleting patient from Firebase: $e');
      throw Exception('Failed to delete patient: $e');
    }
  }

  // Recording Session Management
  static Future<String> createRecordingSession({
    required String patientId,
    required String patientName,
    required String userId,
  }) async {
    try {
      final sessionData = {
        'patientId': patientId,
        'patientName': patientName,
        'userId': userId,
        'startTime': FieldValue.serverTimestamp(),
        'status': 'recording',
        'totalChunks': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };

      final docRef = await _firestore
          .collection(_recordingSessionsCollection)
          .add(sessionData);

      return docRef.id;
    } catch (e) {
      // print('Error creating recording session in Firebase: $e');
      throw Exception('Failed to create recording session: $e');
    }
  }

  static Future<void> updateRecordingSession({
    required String sessionId,
    required String status,
    int? totalChunks,
    String? endTime,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (totalChunks != null) updateData['totalChunks'] = totalChunks;
      if (endTime != null) updateData['endTime'] = FieldValue.serverTimestamp();

      await _firestore
          .collection(_recordingSessionsCollection)
          .doc(sessionId)
          .update(updateData);
    } catch (e) {
      // print('Error updating recording session in Firebase: $e');
      throw Exception('Failed to update recording session: $e');
    }
  }

  static Future<List<RecordingSession>> getRecordingSessions({
    required String userId,
    String? patientId,
  }) async {
    try {
      Query query = _firestore
          .collection(_recordingSessionsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true);

      if (patientId != null) {
        query = query.where('patientId', isEqualTo: patientId);
      }

      final querySnapshot = await query.get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return RecordingSession(
          id: doc.id,
          patientId: data['patientId'] ?? '',
          patientName: data['patientName'] ?? '',
          userId: data['userId'] ?? '',
          startTime:
              (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
          endTime: (data['endTime'] as Timestamp?)?.toDate(),
          status: RecordingStatus.values.firstWhere(
            (status) => status.name == data['status'],
            orElse: () => RecordingStatus.completed,
          ),
          totalChunks: data['totalChunks'] ?? 0,
        );
      }).toList();
    } catch (e) {
      // print('Error getting recording sessions from Firebase: $e');
      return [];
    }
  }

  static Future<void> deleteRecordingSession({
    required String sessionId,
  }) async {
    try {
      await _firestore
          .collection(_recordingSessionsCollection)
          .doc(sessionId)
          .delete();
    } catch (e) {
      // print('Error deleting recording session from Firebase: $e');
      throw Exception('Failed to delete recording session: $e');
    }
  }
}
