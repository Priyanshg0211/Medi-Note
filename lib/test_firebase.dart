import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// Test Firebase connection
class FirebaseTest {
  static Future<void> testConnection() async {
    try {
      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      print('✅ Firebase initialized successfully');

      // Test Firestore connection
      final firestore = FirebaseFirestore.instance;

      // Try to write a test document
      await firestore.collection('test').doc('connection').set({
        'message': 'Hello Firebase!',
        'timestamp': FieldValue.serverTimestamp(),
      });

      print('✅ Firestore write test successful');

      // Try to read the test document
      final doc = await firestore.collection('test').doc('connection').get();
      if (doc.exists) {
        print('✅ Firestore read test successful');
        print('📄 Document data: ${doc.data()}');
      }

      // Clean up test document
      await firestore.collection('test').doc('connection').delete();
      print('✅ Test cleanup completed');

      print('🎉 All Firebase tests passed! Your connection is working.');
    } catch (e) {
      print('❌ Firebase test failed: $e');
      print('Please check your Firebase configuration and try again.');
    }
  }
}
