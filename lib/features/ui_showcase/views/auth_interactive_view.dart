import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

/// Vista interactiva para probar el flujo de Autenticación sin SIM y Doble Factor (MFA)
/// utilizando [AuthProvider] y diseño Material 3.
class AuthInteractiveView extends StatefulWidget {
  const AuthInteractiveView({super.key});

  @override
  State<AuthInteractiveView> createState() => _AuthInteractiveViewState();
}

class _AuthInteractiveViewState extends State<AuthInteractiveView> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: 'usuario1');
  final _emailController = TextEditingController(text: 'usuario1@finchat.app');
  final _passwordController = TextEditingController(text: 'password123');
  final _fullNameController = TextEditingController(text: 'Carlos Santana');
  final _mfaCodeController = TextEditingController(text: '123456');

  bool _isRegistering = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleAuthSubmit(AuthProvider authProvider) async {
    if (!_formKey.currentState!.validate()) return;

    if (_isRegistering) {
      await authProvider.register(
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        fullName: _fullNameController.text,
      );
    } else {
      await authProvider.login(
        identifier: _usernameController.text,
        password: _passwordController.text,
      );
    }

    if (mounted && authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage!),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _handleMfaSubmit(AuthProvider authProvider) async {
    final success = await authProvider.verifyMfa(_mfaCodeController.text);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ ¡Autenticación MFA Exitosa! Acceso concedido a FinChat.'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage!),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final session = authProvider.session;
    final isAwaitingMfa = authProvider.isAwaitingMfa;
    final isFullyAuth = authProvider.isAuthenticated;
    final isLoading = authProvider.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Autenticación & MFA (Fase 2)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner de Requerimiento MoSCoW
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
                        'Must Have (10 pts): Registro sin SIM/teléfono + Autenticación MFA con código de 6 dígitos antes del chat.',
                        style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (isFullyAuth) ...[
              // ==============================================================
              // ESTADO 1: USUARIO AUTENTICADO Y VERIFICADO CON MFA
              // ==============================================================
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.verified_user, color: Colors.green, size: 64),
                    const SizedBox(height: 12),
                    const Text(
                      '¡Sesión Segura y Verificada!',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'MFA superado exitosamente. Acceso completo a FinChat habilitado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.green.shade900, fontSize: 13),
                    ),
                    const Divider(height: 28),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryColor,
                        child: Text(
                          session.username.isNotEmpty ? session.username[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        session.fullName ?? session.username,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('@${session.username} • ${session.email}'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => authProvider.logout(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar Sesión'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
                    ),
                  ],
                ),
              ),
            ] else if (isAwaitingMfa) ...[
              // ==============================================================
              // ESTADO 2: RETO MFA ACTIVO (ENTRADA OTP DE 6 DÍGITOS)
              // ==============================================================
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_clock, size: 52, color: AppTheme.primaryColor),
                      const SizedBox(height: 12),
                      const Text(
                        'Verificación de Doble Factor (MFA)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ingresa el código temporal de 6 dígitos enviado para @${session.username} (${session.email}):',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _mfaCodeController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          letterSpacing: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: '123456',
                          counterText: '',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: isLoading ? null : () => _handleMfaSubmit(authProvider),
                        child: isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Confirmar Código MFA'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('¿No recibiste el código? ', style: TextStyle(fontSize: 13)),
                          if (authProvider.canResendMfa)
                            TextButton(
                              onPressed: authProvider.resendMfaCode,
                              child: const Text('Reenviar'),
                            )
                          else
                            Text(
                              'Reintentar en ${authProvider.mfaResendSeconds}s',
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => authProvider.logout(),
                        child: const Text('Cancelar / Usar otra cuenta'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // ==============================================================
              // ESTADO 3: FORMULARIO DE INICIO DE SESIÓN O REGISTRO
              // ==============================================================
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: !_isRegistering
                            ? AppTheme.primaryColor.withValues(alpha: 0.1)
                            : null,
                      ),
                      onPressed: () {
                        setState(() => _isRegistering = false);
                        authProvider.clearError();
                      },
                      child: const Text('Iniciar Sesión'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _isRegistering
                            ? AppTheme.primaryColor.withValues(alpha: 0.1)
                            : null,
                      ),
                      onPressed: () {
                        setState(() => _isRegistering = true);
                        authProvider.clearError();
                      },
                      child: const Text('Crear Cuenta'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de Usuario (@único, sin SIM)',
                        prefixIcon: Icon(Icons.alternate_email),
                        hintText: 'ej. usuario1',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa un nombre de usuario';
                        }
                        if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value.trim())) {
                          return 'Debe tener entre 3 y 20 caracteres alfanuméricos';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    if (_isRegistering) ...[
                      TextFormField(
                        controller: _fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Completo (opcional)',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo Electrónico',
                          prefixIcon: Icon(Icons.email_outlined),
                          hintText: 'ejemplo@finchat.app',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa un correo electrónico';
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Ingresa un formato de correo válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                    ],

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa una contraseña';
                        }
                        if (value.length < 6) {
                          return 'Mínimo 6 caracteres requeridos';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),

                    ElevatedButton(
                      onPressed: isLoading ? null : () => _handleAuthSubmit(authProvider),
                      child: isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(_isRegistering ? 'Registrarse con MFA' : 'Iniciar Sesión'),
                    ),
                  ],
                ),
              ),
            ],

            // Mensajes de error en caso de fallo
            if (authProvider.errorMessage != null && !isFullyAuth) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        authProvider.errorMessage!,
                        style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: authProvider.clearError,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
