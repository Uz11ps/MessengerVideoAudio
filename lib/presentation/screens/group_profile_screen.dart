import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:messenger_app/data/models/chat_model.dart';
import 'package:messenger_app/data/models/user_model.dart';
import 'package:messenger_app/data/repositories/chat_repository.dart';
import 'package:messenger_app/logic/blocs/auth_bloc.dart';
import 'package:messenger_app/presentation/screens/home_screen.dart';

class GroupProfileScreen extends StatefulWidget {
  final ChatModel chat;

  const GroupProfileScreen({super.key, required this.chat});

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  Map<String, UserModel> _participants = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    final chatRepo = context.read<ChatRepository>();
    final users = await chatRepo.getUsersByIds(widget.chat.participants);
    setState(() {
      _participants = users;
      _isLoading = false;
    });
  }

  bool get _isAdmin {
    final currentUserId = (context.read<AuthBloc>().state as AuthAuthenticated).user.id;
    return widget.chat.groupAdminId == currentUserId;
  }

  void _showAddParticipantsDialog() async {
    final chatRepo = context.read<ChatRepository>();
    final currentUserId = (context.read<AuthBloc>().state as AuthAuthenticated).user.id;
    
    String searchQuery = '';
    List<UserModel> searchResults = [];
    bool isSearching = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Добавить участников'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Поиск пользователей...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) async {
                    setDialogState(() {
                      searchQuery = value;
                      isSearching = true;
                    });
                    if (value.isNotEmpty) {
                      final results = await chatRepo.searchUsers(value);
                      setDialogState(() {
                        searchResults = results.where((u) => 
                          u.id != currentUserId && 
                          !widget.chat.participants.contains(u.id)
                        ).toList();
                        isSearching = false;
                      });
                    } else {
                      setDialogState(() {
                        searchResults = [];
                        isSearching = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                if (isSearching)
                  const CircularProgressIndicator()
                else if (searchResults.isEmpty && searchQuery.isNotEmpty)
                  const Text('Пользователи не найдены')
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        final user = searchResults[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: user.photoUrl != null
                                ? CachedNetworkImageProvider('http://83.166.246.225:3000${user.photoUrl}')
                                : null,
                            child: user.photoUrl == null
                                ? Text(user.displayName?.substring(0, 1).toUpperCase() ?? 'U')
                                : null,
                          ),
                          title: Text(user.displayName ?? user.email ?? user.phoneNumber ?? 'Пользователь'),
                          trailing: const Icon(Icons.add),
                          onTap: () async {
                            Navigator.pop(context);
                            await _addParticipant(user.id);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addParticipant(String userId) async {
    final chatRepo = context.read<ChatRepository>();
    final success = await chatRepo.addParticipantToGroup(widget.chat.id, userId);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Участник добавлен'), backgroundColor: Colors.green),
      );
      _loadParticipants(); // Обновляем список участников
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при добавлении участника'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _removeParticipant(String userId) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Только администратор может удалять участников')),
      );
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: const Text('Вы уверены, что хотите удалить этого участника из группы?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final chatRepo = context.read<ChatRepository>();
      final success = await chatRepo.removeParticipantFromGroup(widget.chat.id, userId);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Участник удален'), backgroundColor: Colors.green),
        );
        _loadParticipants(); // Обновляем список участников
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при удалении участника'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteGroup() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Только администратор может удалить группу')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text('Вы уверены, что хотите удалить эту группу? Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final chatRepo = context.read<ChatRepository>();
      final success = await chatRepo.deleteGroup(widget.chat.id);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Группа удалена'), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // Закрываем профиль группы
        Navigator.pop(context); // Закрываем чат
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при удалении группы'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = (context.read<AuthBloc>().state as AuthAuthenticated).user.id;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль группы'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Аватар группы
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.blue,
                    child: const Icon(Icons.group, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  // Название группы
                  Text(
                    widget.chat.groupName ?? 'Групповой чат',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  // Участники
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Участники (${widget.chat.participants.length})',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            if (_isAdmin)
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: _showAddParticipantsDialog,
                                tooltip: 'Добавить участника',
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...widget.chat.participants.map((participantId) {
                          final user = _participants[participantId];
                          final isAdmin = widget.chat.groupAdminId == participantId;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user?.photoUrl != null
                                    ? CachedNetworkImageProvider('http://83.166.246.225:3000${user!.photoUrl}')
                                    : null,
                                child: user?.photoUrl == null
                                    ? Text(user?.displayName?.substring(0, 1).toUpperCase() ?? 'U')
                                    : null,
                              ),
                              title: Text(user?.displayName ?? user?.email ?? user?.phoneNumber ?? 'Пользователь'),
                              subtitle: isAdmin ? const Text('Администратор', style: TextStyle(color: Colors.blue)) : null,
                              trailing: _isAdmin && participantId != currentUserId && !isAdmin
                                  ? IconButton(
                                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                                      onPressed: () => _removeParticipant(participantId),
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Действия администратора
                  if (_isAdmin) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.delete, color: Colors.red),
                      title: const Text('Удалить группу', style: TextStyle(color: Colors.red)),
                      onTap: _deleteGroup,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
