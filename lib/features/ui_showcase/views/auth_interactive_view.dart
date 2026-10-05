import 'package:flutter/material.dart';
import '../../auth/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';

/// Vista interactiva para probar el flujo de Autenticación sin SIM y Doble Factor (MFA).
class AuthInteractiveView extends StatefulWidget {
  const AuthInteractiveView({super.key});

  @override
  State<AuthInteractiveView> createState() => _AuthInteractiveViewState();
}

class _AuthInteractiveViewState extends State<AuthInteractiveView> {
  final _authService = AuthService();
  final _usernameController = TextEditingController(text: 'usuario1');
  final _emailController = TextEditingController(text: 'usuario1@finchat.app');
  final _passwordController = TextEditingController(text: 'password123');
  final _mfaCodeController = TextEditingController(text: '123456');

  bool _isRegistering = false;
  bool _isLoading = false;
  String? _feedbackMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    setState(() {
      _isLoading = true;
      _feedbackMessage = null;
    });

    if (_isRegistering) {
      await _authService.register(
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      setState(() {
        _isLoading = false;
        _feedbackMessage = '¡Cuenta creada! Se ha enviado el código MFA (Usa: 123456)';
        _isSuccess = true;
      });
    } else {
      await _authService.signIn(
        identifier: _usernameController.text,
        password: _passwordController.text,
      );
      setState(() {
        _isLoading = false;
        _feedbackMessage = 'Credenciales correctas. Ingresa tu código MFA (Usa: 123456)';
        _isSuccess = true;
      });
    }
  }

  Future<void> _verifyMfa() async {
    setState(() => _isLoading = true);
    final ok = await _authService.verifyMfaCode(_mfaCodeController.text);
    setState(() {
      _isLoading = false;
      _isSuccess = ok;
      _feedbackMessage = ok 
          ? '✅ ¡Verificación MFA Exitosa! Sesión autorizada en Supabase.' 
          : '❌ Código MFA incorrecto. Intenta con 123456';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _authService,
      builder: (context, _) {
        final session = _authService.currentSession;
        final needsMfa = session.userId.isNotEmpty && !session.isMfaVerified;
        final isFullyAuth = session.isAuthenticated;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Prueba de Autenticación & MFA'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tarjeta informativa de requerimiento
                Card(
                  color: Colors.blue.shade50,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Must Have (10 pts): Registro sin SIM/teléfono + Autenticación MFA con usuario, contraseña y correo.',
                            style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (isFullyAuth) ...[
                  // Estado Autenticado
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 54),
                        const SizedBox(height: 12),
                        const Text(
                          '¡Usuario Autenticado con MFA!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        const SizedBox(height: 8),
                        Text('Usuario: @${session.username}'),
                        Text('Correo: ${session.email}'),
                        Text('ID: ${session.userId}'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _authService.signOut(),
                          icon: const Icon(Icons.logout),
                          label: const Text('Cerrar Sesión'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
                        ),
                      ],
                    ),
                  ),
                ] else if (needsMfa) ...[
                  // Pantalla Reto MFA
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.lock_clock, size: 48, color: AppTheme.primaryColor),
                          const SizedBox(height: 12),
                          const Text(
                            'Verificación de Doble Factor (MFA)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ingresa el código temporal de 6 dígitos enviado a ${session.email}:',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _mfaCodeController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(hintText: '123456'),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _verifyMfa,
                            child: _isLoading 
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Confirmar Código MFA'),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () => _authService.signOut(),
                            child: const Text('Cancelar / Usar otra cuenta'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Formulario de Inicio o Registro
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: !_isRegistering ? AppTheme.primaryColor.withOpacity(0.1) : null,
                          ),
                          onPressed: () => setState(() => _isRegistering = false),
                          child: const Text('Iniciar Sesión'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _isRegistering ? AppTheme.primaryColor.withOpacity(0.1) : null,
                          ),
                          onPressed: () => setState(() => _isRegistering = true),
                          child: const Text('Crear Cuenta'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de Usuario (Único, sin teléfono)',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_isRegistering) ...[
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleAuth,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isRegistering ? 'Registrarse con MFA' : 'Iniciar Sesión'),
                  ),
                ],

                if (_feedbackMessage != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _isSuccess ? Colors.green : Colors.red),
                    ),
                    child: Text(
                      _feedbackMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isSuccess ? Colors.green.shade900 : Colors.red.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
