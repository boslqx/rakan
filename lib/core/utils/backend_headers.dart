import 'package:firebase_auth/firebase_auth.dart';

/// Headers for every call to the Rakan backend. Each endpoint checks the
/// signed-in user's Firebase ID token and takes the uid from it, not from
/// the request body (D-15 / V-07). `getIdToken()` returns the cached token
/// and only refreshes it when it has expired.
Future<Map<String, String>> backendHeaders() async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}
