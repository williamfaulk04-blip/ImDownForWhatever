import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/poll_model.dart';
import '../models/wheel_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

typedef ChoicesState = ({RoomState? room, bool connected});

class ChoicesScreen extends StatefulWidget {
  const ChoicesScreen({
    required this.session,
    required this.state,
    this.api,
    super.key,
  });
  final RoomSession session;
  final ValueListenable<ChoicesState> state;
  final ApiService? api;
  @override
  State<ChoicesScreen> createState() => _ChoicesScreenState();
}

class _ChoicesScreenState extends State<ChoicesScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  bool _deleting = false;
  bool get _enabled =>
      widget.state.value.connected &&
      widget.state.value.room?.isHost == true &&
      !_deleting;

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _edit({
    WheelCategory? category,
    WheelActivity? activity,
    bool addActivity = false,
  }) async {
    final isActivity = activity != null || addActivity;
    final initial = activity?.name ?? (isActivity ? '' : category?.name ?? '');
    final title =
        '${initial.isEmpty ? 'Add' : 'Rename'} ${isActivity ? 'activity' : 'category'}';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChoiceFormScreen(
          title: title,
          initial: initial,
          subtitle: isActivity
              ? 'An idea for ${category!.name}. Keep it specific so everyone knows the plan.'
              : 'Group similar ideas together, like games, food, or a night out.',
          onSave: (name) async {
            if (!_enabled) {
              throw ApiFailure('Reconnect to the room before saving.', 409);
            }
            final room = widget.state.value.room!;
            WheelCategory? current;
            for (final item in room.categories) {
              if (item.id == category?.id) current = item;
            }
            if (category != null && current == null) {
              throw ApiFailure(
                'This category was removed. Go back to your choices.',
                404,
              );
            }
            final names = isActivity
                ? current!.activities
                      .where((item) => item.id != activity?.id)
                      .map((item) => item.name)
                : room.categories
                      .where((item) => item.id != category?.id)
                      .map((item) => item.name);
            if (names.any((item) => item.toLowerCase() == name.toLowerCase())) {
              throw ApiFailure(
                'That name is already in this list. Try another.',
                409,
              );
            }
            if (isActivity) {
              if (activity == null) {
                await _api.addActivity(widget.session, category!.id, name);
              } else {
                await _api.renameActivity(
                  widget.session,
                  category!.id,
                  activity.id,
                  name,
                );
              }
            } else if (category == null) {
              await _api.addCategory(widget.session, name);
            } else {
              await _api.renameCategory(widget.session, category.id, name);
            }
          },
        ),
      ),
    );
  }

  Future<void> _remove(
    WheelCategory category, [
    WheelActivity? activity,
  ]) async {
    final name = activity?.name ?? category.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text(
          activity == null
              ? 'This also removes the activities in this category.'
              : 'This idea will be removed from the wheel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_enabled) return;
    setState(() => _deleting = true);
    try {
      if (activity == null) {
        await _api.removeCategory(widget.session, category.id);
      } else {
        await _api.removeActivity(widget.session, category.id, activity.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiFailure
                  ? error.message
                  : 'Could not remove this choice. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ChoicesState>(
    valueListenable: widget.state,
    builder: (context, state, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Your choices'),
        actions: const [AppearanceButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Make room for good ideas.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Organize your categories and activities here. Head back to the lobby when you’re ready to spin.',
              ),
              const SizedBox(height: 20),
              if (!state.connected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Reconnecting… Your draft is safe. Editing resumes when connected.',
                  ),
                ),
              if (_deleting) const LinearProgressIndicator(),
              if (state.room?.categories.isEmpty ?? true)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'Start with a category, then fill it with things you’d like to do.',
                  ),
                ),
              for (final category
                  in state.room?.categories ?? <WheelCategory>[])
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                category.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Rename ${category.name}',
                              onPressed: _enabled
                                  ? () => _edit(category: category)
                                  : null,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Remove ${category.name}',
                              onPressed: _enabled
                                  ? () => _remove(category)
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        if (category.activities.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No activities yet. Add your first idea.',
                            ),
                          ),
                        for (final activity in category.activities)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(activity.name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Rename ${activity.name}',
                                  onPressed: _enabled
                                      ? () => _edit(
                                          category: category,
                                          activity: activity,
                                        )
                                      : null,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove ${activity.name}',
                                  onPressed: _enabled
                                      ? () => _remove(category, activity)
                                      : null,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        TextButton.icon(
                          onPressed: _enabled
                              ? () =>
                                    _edit(category: category, addActivity: true)
                              : null,
                          icon: const Icon(Icons.add),
                          label: const Text('Add activity'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _enabled ? () => _edit() : null,
                icon: const Icon(Icons.add),
                label: const Text('Add category'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ChoiceFormScreen extends StatefulWidget {
  const ChoiceFormScreen({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.onSave,
    super.key,
  });
  final String title;
  final String subtitle;
  final String initial;
  final Future<void> Function(String) onSave;
  @override
  State<ChoiceFormScreen> createState() => _ChoiceFormScreenState();
}

class _ChoiceFormScreenState extends State<ChoiceFormScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim());
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiFailure
              ? error.message
              : 'Could not save. Your text is still here—try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: const [AppearanceButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  widget.title.contains('activity')
                      ? Icons.emoji_objects_outlined
                      : Icons.category_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(widget.subtitle),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _name,
                  maxLength: 100,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a name to continue.'
                      : null,
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: Icon(_saving ? Icons.hourglass_top : Icons.check),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
