import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Map<String, dynamic>? get currentUserData {
    final user = _auth.currentUser;
    if (user == null) return null;
    return {
      'id': user.uid,
      'name': user.displayName,
      'email': user.email,
    };
  }

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw Exception('Erro ao fazer login: ${e.toString()}');
    }
  }

  Future<void> register(String name, String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user?.updateDisplayName(name);

      await _firestore.collection('users').doc(userCredential.user?.uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Erro ao criar conta: ${e.toString()}');
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Erro ao fazer logout: ${e.toString()}');
    }
  }

  Future<void> updateProfile({String? displayName}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      if (displayName != null) {
        await user.updateDisplayName(displayName);
        await _firestore.collection('users').doc(user.uid).update({
          'name': displayName,
        });
      }
    } catch (e) {
      throw Exception('Erro ao atualizar perfil: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getServiceHistory() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final snapshot = await _firestore
          .collection('services')
          .where('userId', isEqualTo: user.uid)
          .orderBy('date', descending: true)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      throw Exception('Erro ao carregar histórico: ${e.toString()}');
    }
  }

  Future<UserCredential> signUp(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        throw 'A senha é muito fraca.';
      } else if (e.code == 'email-already-in-use') {
        throw 'Este email já está em uso.';
      } else if (e.code == 'invalid-email') {
        throw 'Email inválido.';
      } else {
        throw 'Erro ao criar conta: ${e.message}';
      }
    }
  }

  Future<UserCredential> registerWithEmailAndPassword(
      String email, String password, String name) async {
    try {
      debugPrint('Iniciando registro de usuário: $email');

      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      debugPrint('Usuário criado com sucesso. UID: ${result.user?.uid}');

      if (result.user == null) {
        throw 'Erro ao criar usuário: usuário nulo após criação';
      }

      await result.user!.getIdToken(true);
      await Future.delayed(const Duration(seconds: 1));

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw 'Erro ao criar usuário: usuário não está mais autenticado';
      }

      int retryCount = 0;
      while (retryCount < 3) {
        try {
          await _firestore.collection('users').doc(currentUser.uid).set({
            'name': name,
            'email': email,
            'createdAt': FieldValue.serverTimestamp(),
          });
          debugPrint('Documento do usuário criado no Firestore com sucesso');
          break;
        } catch (e) {
          debugPrint(
              'Tentativa ${retryCount + 1} - Erro ao criar documento no Firestore: $e');
          retryCount++;
          if (retryCount >= 3) {
            rethrow;
          }
          await currentUser.reload();
          await currentUser.getIdToken(true);
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      return result;
    } on FirebaseAuthException catch (e) {
      debugPrint('Erro de autenticação no registro: ${e.code} - ${e.message}');
      throw _handleAuthError(e);
    } catch (e) {
      debugPrint('Erro inesperado no registro: $e');
      try {
        final user = _auth.currentUser;
        if (user != null) {
          await user.delete();
        }
      } catch (deleteError) {
        debugPrint('Erro ao tentar excluir usuário após falha: $deleteError');
      }
      throw Exception('Failed to create user: $e');
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      debugPrint('Erro ao enviar email de reset: ${e.code} - ${e.message}');
      throw _handleAuthError(e);
    } catch (e) {
      debugPrint('Erro inesperado ao enviar email de reset: $e');
      throw Exception('Failed to reset password: $e');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.updatePassword(newPassword);
      } else {
        throw Exception('No user is currently signed in');
      }
    } catch (e) {
      throw Exception('Failed to update password: $e');
    }
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não está logado');
    }

    // Reauthenticate user with current password
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);

    // Change password
    await user.updatePassword(newPassword);
  }

  String _handleAuthError(FirebaseAuthException e) {
    debugPrint('Código do erro: ${e.code}');
    debugPrint('Mensagem do erro: ${e.message}');

    switch (e.code) {
      case 'invalid-email':
        return 'Email inválido.';
      case 'user-disabled':
        return 'Esta conta foi desativada.';
      case 'user-not-found':
        return 'Usuário não encontrado.';
      case 'wrong-password':
        return 'Senha incorreta.';
      case 'email-already-in-use':
        return 'Este email já está em uso.';
      case 'operation-not-allowed':
        return 'Método de autenticação não habilitado. Entre em contato com o suporte.';
      case 'weak-password':
        return 'A senha é muito fraca. Use pelo menos 6 caracteres.';
      case 'invalid-credential':
        return 'Credenciais inválidas. Verifique seu email e senha.';
      case 'invalid-verification-code':
        return 'Código de verificação inválido.';
      case 'invalid-verification-id':
        return 'ID de verificação inválido.';
      case 'network-request-failed':
        return 'Erro de conexão. Verifique sua internet.';
      default:
        return 'Ocorreu um erro: ${e.message ?? "Erro desconhecido"}';
    }
  }
}
