import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../models/poll_model.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({required this.session, super.key});

  final RoomSession session;

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  int _duration = 60;
  bool _submitting = false;

  @override
  void dispose() {
    _topicController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final api = ApiService();
    try {
      await api.createPoll(
        widget.session,
        topic: _topicController.text.trim(),
        options: _optionControllers
            .map((controller) => controller.text.trim())
            .toList(),
        duration: _duration,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiFailure
                  ? error.message
                  : 'Could not reach the server. Please try again.',
            ),
          ),
        );
      }
    } finally {
      api.close();
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create a poll')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _topicController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Topic',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a topic'
                  : null,
            ),
            const SizedBox(height: 20),
            ..._optionControllers.indexed.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: entry.$2,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Option ${entry.$1 + 1}',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter an option'
                      : null,
                ),
              ),
            ),
            if (_optionControllers.length < 5)
              TextButton.icon(
                onPressed: _submitting
                    ? null
                    : () => setState(
                        () => _optionControllers.add(TextEditingController()),
                      ),
                icon: const Icon(Icons.add),
                label: const Text('Add option'),
              ),
            if (_optionControllers.length > 2)
              TextButton.icon(
                onPressed: _submitting
                    ? null
                    : () => setState(
                        () => _optionControllers.removeLast().dispose(),
                      ),
                icon: const Icon(Icons.remove),
                label: const Text('Remove last option'),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _duration,
              decoration: const InputDecoration(
                labelText: 'Duration',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 30, child: Text('30 seconds')),
                DropdownMenuItem(value: 60, child: Text('1 minute')),
                DropdownMenuItem(value: 300, child: Text('5 minutes')),
                DropdownMenuItem(value: 600, child: Text('10 minutes')),
              ],
              onChanged: (value) => setState(() => _duration = value ?? 60),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Creating…' : 'Start poll'),
            ),
          ],
        ),
      ),
    );
  }
}
