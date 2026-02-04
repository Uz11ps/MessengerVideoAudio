import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:messenger_app/data/models/user_model.dart';
import 'package:messenger_app/data/models/chat_model.dart';
import 'package:messenger_app/data/repositories/chat_repository.dart';
import 'package:messenger_app/logic/blocs/auth_bloc.dart';
import 'package:messenger_app/logic/blocs/chat_bloc.dart';
import 'package:messenger_app/presentation/screens/chat_screen.dart';
import 'package:messenger_app/presentation/screens/profile_screen.dart';
import 'package:messenger_app/presentation/screens/call_screen.dart';
import 'package:messenger_app/core/encryption_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        leading: IconButton(
          icon: const Icon(Icons.account_circle),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfileScreen()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Выходим из аккаунта - это автоматически закроет все ресурсы и вернет на экран авторизации
              context.read<AuthBloc>().add(AuthLoggedOut());
            },
          ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: context.read<ChatRepository>().onIncomingCall,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showIncomingCallDialog(context, snapshot.data!);
            });
          }
          return BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              if (state is ChatInitial) {
                context.read<ChatBloc>().add(ChatListStarted());
              }
              if (state is ChatListLoaded) {
                return FutureBuilder<Map<String, UserModel>>(
                  future: _loadUsersForChats(context, state.chats),
                  builder: (context, usersSnapshot) {
                    if (!usersSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final usersMap = usersSnapshot.data!;
                    
                    return ListView.builder(
                      itemCount: state.chats.length,
                      itemBuilder: (context, index) {
                        final chat = state.chats[index];
                        final authState = context.read<AuthBloc>().state;
                        if (authState is! AuthAuthenticated) {
                          return const SizedBox.shrink();
                        }
                        final currentUserId = authState.user.id;
                        final chatRepo = context.read<ChatRepository>();
                        final authBloc = context.read<AuthBloc>();

                        String chatTitle;
                        if (chat.isGroup && chat.groupName != null) {
                          chatTitle = chat.groupName!;
                        } else {
                          final otherUserId = chat.participants.firstWhere(
                            (id) => id != currentUserId,
                            orElse: () => '',
                          );
                          final otherUser = usersMap[otherUserId];
                          chatTitle = otherUser?.displayName ?? 
                                     otherUser?.email ?? 
                                     otherUser?.phoneNumber ?? 
                                     otherUserId;
                        }

                        final otherUserId = chat.participants.firstWhere(
                          (id) => id != currentUserId,
                          orElse: () => '',
                        );
                        final otherUser = usersMap[otherUserId];
                        final userPhotoUrl = otherUser?.photoUrl;

                        return ListTile(
                          leading: chat.isGroup
                              ? CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  child: const Icon(Icons.group, color: Colors.white),
                                )
                              : CircleAvatar(
                                  backgroundImage: userPhotoUrl != null
                                      ? CachedNetworkImageProvider(
                                          'http://83.166.246.225:3000$userPhotoUrl')
                                      : null,
                                  child: userPhotoUrl == null
                                      ? Text(
                                          chatTitle.substring(0, 1).toUpperCase(),
                                          style: const TextStyle(color: Colors.white),
                                        )
                                      : null,
                                ),
                          title: Text(chatTitle),
                          subtitle: Text(_getDecryptedLastMessage(chat.lastMessage)),
                          trailing: Text(chat.lastMessageTimestamp != null
                              ? DateFormat('HH:mm').format(chat.lastMessageTimestamp!)
                              : ''),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MultiRepositoryProvider(
                                providers: [
                                  RepositoryProvider.value(value: chatRepo),
                                ],
                                child: MultiBlocProvider(
                                  providers: [
                                    BlocProvider.value(value: authBloc),
                                    BlocProvider(
                                      create: (context) => ChatBloc(chatRepository: chatRepo),
                                    ),
                                  ],
                                  child: ChatDetailScreen(chatId: chat.id, chat: chat),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              }
              return const Center(child: CircularProgressIndicator());
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'group',
            onPressed: () => _showCreateGroupDialog(context),
            child: const Icon(Icons.group_add),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'search',
            onPressed: () => _showSearchDialog(context),
            child: const Icon(Icons.search),
          ),
        ],
      ),
    );
  }

  void _showIncomingCallDialog(BuildContext context, Map<String, dynamic> callData) {
    final type = callData['type'] ?? 'video';
    final isGroup = callData['isGroup'] == true;
    final typeText = type == 'video' ? 'Видеозвонок' : 'Аудиозвонок';
    final callTitle = isGroup ? 'Входящий групповой $typeText' : 'Входящий $typeText';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(callTitle),
        content: Text(isGroup 
          ? 'Групповой звонок в ${callData['channelName']}'
          : 'Звонок от пользователя ${callData['from']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отклонить', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              // Отправляем событие call_accepted на сервер
              final chatRepo = context.read<ChatRepository>();
              final channelName = callData['channelName'] as String;
              chatRepo.acceptCall(channelName);

              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CallScreen(
                    channelName: callData['channelName'],
                    appId: '9f3bf11c90364991926390fae2a67c92', 
                    callType: type,
                    isGroupCall: isGroup,
                    participantIds: callData['participants'] ?? [],
                  ),
                ),
              );
            },
            child: const Text('Принять'),
          ),
        ],
      ),
    );
  }

  String _getDecryptedLastMessage(String? encryptedMessage) {
    if (encryptedMessage == null || encryptedMessage.isEmpty) {
      return 'Нет сообщений';
    }
    // Пытаемся расшифровать сообщение
    final decrypted = EncryptionService.decrypt(encryptedMessage);
    // Если расшифровка не удалась (вернулась та же строка), значит это не зашифрованное сообщение
    // или это тип сообщения (audio, image, file)
    if (decrypted == encryptedMessage && !encryptedMessage.contains('=')) {
      // Это не зашифрованное сообщение, возможно тип сообщения
      return encryptedMessage;
    }
    return decrypted;
  }

  Future<Map<String, UserModel>> _loadUsersForChats(BuildContext context, List<ChatModel> chats) async {
    final chatRepo = context.read<ChatRepository>();
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return {};
    final currentUserId = authState.user.id;
    final Set<String> userIds = {};
    
    for (final chat in chats) {
      for (final participantId in chat.participants) {
        if (participantId != currentUserId) {
          userIds.add(participantId);
        }
      }
    }
    
    return await chatRepo.getUsersByIds(userIds.toList());
  }

  void _showSearchDialog(BuildContext context) {
    final controller = TextEditingController();
    final chatRepo = context.read<ChatRepository>();
    final authBloc = context.read<AuthBloc>();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Поиск по номеру или имени',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => setSheetState(() {}),
                  ),
                ),
                onSubmitted: (_) => setSheetState(() {}),
              ),
              Expanded(
                child: FutureBuilder<List<UserModel>>(
                  future: controller.text.isEmpty 
                      ? Future.value([]) 
                      : chatRepo.searchUsers(controller.text),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final users = snapshot.data ?? [];
                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(user.displayName ?? user.email ?? user.phoneNumber ?? 'Пользователь'),
                          subtitle: Text(user.phoneNumber ?? user.email ?? ''),
                          onTap: () async {
                            final chat = await chatRepo.createChat(user.id);
                            if (context.mounted) {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MultiRepositoryProvider(
                                    providers: [
                                      RepositoryProvider.value(value: chatRepo),
                                    ],
                                    child: MultiBlocProvider(
                                      providers: [
                                        BlocProvider.value(value: authBloc),
                                        BlocProvider(
                                          create: (context) => ChatBloc(chatRepository: chatRepo),
                                        ),
                                      ],
                                      child: ChatDetailScreen(chatId: chat.id, chat: chat),
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    final nameController = TextEditingController();
    final searchController = TextEditingController();
    final chatRepo = context.read<ChatRepository>();
    final authBloc = context.read<AuthBloc>();
    final selectedUsers = <String>{};
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Создать групповой чат'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Название группы',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Поиск пользователей',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                const Text('Выберите участников:'),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<UserModel>>(
                    future: chatRepo.searchUsers(searchController.text),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final users = snapshot.data ?? [];
                      final authState = authBloc.state;
                      if (authState is! AuthAuthenticated) {
                        return const Center(child: Text('Ошибка авторизации'));
                      }
                      final currentUserId = authState.user.id;
                      final availableUsers = users.where((u) => u.id != currentUserId).toList();
                      
                      if (availableUsers.isEmpty) {
                        return const Center(child: Text('Пользователи не найдены'));
                      }
                      
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: availableUsers.length,
                        itemBuilder: (context, index) {
                          final user = availableUsers[index];
                          final isSelected = selectedUsers.contains(user.id);
                          return CheckboxListTile(
                            title: Text(user.displayName ?? user.email ?? user.phoneNumber ?? 'Пользователь'),
                            subtitle: Text(user.phoneNumber ?? user.email ?? ''),
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  selectedUsers.add(user.id);
                                } else {
                                  selectedUsers.remove(user.id);
                                }
                              });
                            },
                          );
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
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Введите название группы')),
                  );
                  return;
                }
                if (selectedUsers.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Выберите хотя бы одного участника')),
                  );
                  return;
                }
                
                final authState = authBloc.state;
                if (authState is! AuthAuthenticated) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ошибка авторизации')),
                  );
                  return;
                }
                final currentUserId = authState.user.id;
                final participants = [currentUserId, ...selectedUsers];
                final chat = await chatRepo.createGroupChat(participants, nameController.text.trim());
                
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MultiRepositoryProvider(
                        providers: [
                          RepositoryProvider.value(value: chatRepo),
                        ],
                        child: MultiBlocProvider(
                          providers: [
                            BlocProvider.value(value: authBloc),
                            BlocProvider(
                              create: (context) => ChatBloc(chatRepository: chatRepo),
                            ),
                          ],
                          child: ChatDetailScreen(chatId: chat.id, chat: chat),
                        ),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }
}
