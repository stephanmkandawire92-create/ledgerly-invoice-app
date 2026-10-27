import 'package:flutter/material.dart';

import '../services/cloud_storage_service.dart';
import '../services/document_store.dart';

class CloudStorageScreen extends StatefulWidget {
  const CloudStorageScreen({
    super.key,
    required this.onWorkspaceChanged,
  });

  final VoidCallback onWorkspaceChanged;

  @override
  State<CloudStorageScreen> createState() => _CloudStorageScreenState();
}

class _CloudStorageScreenState extends State<CloudStorageScreen> {
  final CloudStorageService _cloud = CloudStorageService.instance;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _busy = false;
  bool _createAccount = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    bool chooseMigrationAfter = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (chooseMigrationAfter && _cloud.isSignedIn && mounted) {
        await _chooseMigration();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _friendlyError(error);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _message = 'Enter a valid email address.';
        _messageIsError = true;
      });
      return;
    }
    if (password.length < 8) {
      setState(() {
        _message = 'Use a password with at least 8 characters.';
        _messageIsError = true;
      });
      return;
    }

    await _runAction(() async {
      if (_createAccount) {
        final response = await _cloud.signUp(email, password);
        if (response.session == null) {
          if (!mounted) return;
          setState(() {
            _message = 'Account created. Check your email to confirm it, then sign in here. Your local records have not been changed.';
            _messageIsError = false;
            _createAccount = false;
          });
        }
      } else {
        await _cloud.signIn(email, password);
      }
    }, chooseMigrationAfter: true);
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _message = 'Enter your account email first.';
        _messageIsError = true;
      });
      return;
    }
    await _runAction(() => _cloud.sendPasswordReset(email));
    if (mounted) {
      setState(() {
        _message = 'If that email belongs to an account, a password-reset message will be sent.';
        _messageIsError = false;
      });
    }
  }

  Future<void> _chooseMigration() async {
    final localBackup = await DocumentStore().exportLocalBackup();
    final localHasData = CloudStorageService.backupHasData(localBackup);
    final cloudHasData = await _cloud.hasCloudData();
    if (!mounted) return;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose where to keep your information'),
        content: Text(
          'This device: ${localHasData ? 'contains local records' : 'has no saved business records'}\n'
          'Cloud account: ${cloudHasData ? 'contains saved records' : 'has no saved cloud records'}\n\n'
          'Choose what to keep. Ledgerly will ask again before replacing any existing copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, 'restore'),
            child: const Text('Restore cloud records'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'upload'),
            child: const Text('Upload local records'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel' || !mounted) {
      setState(() {
        _message = 'No records were moved. Your existing copies remain unchanged.';
        _messageIsError = false;
      });
      return;
    }

    if (choice == 'upload') {
      if (cloudHasData) {
        final confirmed = await _confirmReplace(
          title: 'Replace cloud records?',
          message: 'The cloud account already contains records. Uploading this device will replace those cloud sections. The local copy will not be deleted. Continue only if the local copy is the one you want to keep.',
          confirmLabel: 'Replace cloud records',
        );
        if (confirmed != true || !mounted) return;
      }
      await _cloud.uploadBackup(localBackup, allowOverwrite: cloudHasData);
      await _cloud.setCloudMode(true);
    } else {
      if (localHasData) {
        final confirmed = await _confirmReplace(
          title: 'Replace records on this device?',
          message: 'Restoring the cloud copy will replace the records currently stored on this device. The cloud copy will not be deleted. Continue only if the cloud copy is the one you want to keep.',
          confirmLabel: 'Replace local records',
        );
        if (confirmed != true || !mounted) return;
      }
      final cloudBackup = await _cloud.exportCloudBackup();
      if (!cloudHasData) {
        // Seed the empty workspace so future cloud reads do not confuse a
        // missing section with a partially migrated workspace.
        await _cloud.uploadBackup(cloudBackup, allowOverwrite: false);
      }
      await DocumentStore().importBackup(cloudBackup);
      await _cloud.setCloudMode(true);
    }

    widget.onWorkspaceChanged();
    if (!mounted) return;
    setState(() {
      _message = choice == 'upload'
          ? 'Local records were uploaded. Cloud storage is now enabled.'
          : 'Cloud records were restored to this device. Cloud storage is now enabled.';
      _messageIsError = false;
    });
  }

  Future<bool?> _confirmReplace({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _switchToLocal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Use this device only?'),
        content: const Text(
          'Ledgerly will stop syncing changes to the cloud. The cloud copy will remain in your account and the local copy will stay on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep cloud storage'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Use local storage'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _cloud.setCloudMode(false);
    widget.onWorkspaceChanged();
    setState(() {
      _message = 'Local-only mode is enabled. Cloud records remain in your account and are not being deleted.';
      _messageIsError = false;
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out of Ledgerly cloud?'),
        content: const Text(
          'Cloud mode will be disabled on this device. The cloud records stay in your account, and the local copy on this device is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(() async {
      await _cloud.signOut();
      widget.onWorkspaceChanged();
      if (mounted) {
        setState(() {
          _message = 'Signed out. Ledgerly is using local storage on this device.';
          _messageIsError = false;
        });
      }
    });
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.toLowerCase().contains('invalid login credentials')) {
      return 'Email or password is incorrect. If you just registered, confirm your email first.';
    }
    if (message.toLowerCase().contains('email not confirmed')) {
      return 'Confirm your email before signing in.';
    }
    if (message.toLowerCase().contains('not configured')) {
      return 'Cloud storage is not configured in this app build. Local storage remains available.';
    }
    return message.length > 240 ? '${message.substring(0, 240)}…' : message;
  }

  @override
  Widget build(BuildContext context) {
    final configured = _cloud.isConfigured;
    final user = _cloud.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Cloud backup & sync')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.cloud_sync_outlined, size: 56, color: Color(0xFF4F46E5)),
              const SizedBox(height: 12),
              Text('Your data, your choice', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'Local mode works without an account. Cloud mode stores your business records in your private Supabase workspace and lets supported devices access the same records when online.',
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _cloud.isSignedIn ? Icons.verified_user_outlined : Icons.phonelink_lock_outlined,
                        color: _cloud.isSignedIn ? Colors.green : Colors.blueGrey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _cloud.isSignedIn ? 'Signed in as ${user?.email ?? 'Ledgerly user'}' : 'Local storage is always available',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _cloud.isSignedIn
                                  ? 'Choose below whether this device should sync with your cloud workspace.'
                                  : 'No account is needed to create quotes and invoices.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!configured) ...[
                const SizedBox(height: 12),
                const Text(
                  'Cloud is not configured for this build. Provide the Supabase project URL and publishable key through the existing build-time configuration. Do not put a service-role key in the app.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              ] else if (user == null) ...[
                const SizedBox(height: 18),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: _createAccount ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password (at least 8 characters)', prefixIcon: Icon(Icons.lock_outline)),
                  onSubmitted: (_) => _submitAuth(),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _submitAuth,
                  child: Text(_busy ? 'Please wait…' : _createAccount ? 'Create account' : 'Sign in and continue'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() {
                    _createAccount = !_createAccount;
                    _message = null;
                  }),
                  child: Text(_createAccount ? 'Already have an account? Sign in' : 'New to Ledgerly cloud? Create an account'),
                ),
                TextButton(
                  onPressed: _busy ? null : _sendPasswordReset,
                  child: const Text('Forgot password?'),
                ),
              ] else ...[
                const SizedBox(height: 18),
                FutureBuilder<bool>(
                  future: _cloud.isCloudMode,
                  builder: (context, snapshot) => ListTile(
                    leading: Icon(snapshot.data == true ? Icons.cloud_done_outlined : Icons.cloud_outlined),
                    title: Text(snapshot.data == true ? 'Cloud storage is enabled' : 'Cloud storage is not enabled'),
                    subtitle: const Text('Choose a migration option before changing which copy is used.'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _runAction(_chooseMigration),
                  icon: const Icon(Icons.sync),
                  label: const Text('Choose migration / sync records'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _switchToLocal,
                  icon: const Icon(Icons.phone_android),
                  label: const Text('Use local storage only'),
                ),
                TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('Sign out'),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _messageIsError ? const Color(0xFFFFF1F0) : const Color(0xFFEFFAF3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_message!, style: TextStyle(color: _messageIsError ? const Color(0xFFB42318) : const Color(0xFF027A48))),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Before replacing a destination that already contains records, Ledgerly asks for confirmation. Cancelling migration leaves both copies unchanged.',
                style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
