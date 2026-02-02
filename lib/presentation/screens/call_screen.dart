import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class CallScreen extends StatefulWidget {
  final String channelName;
  final String appId;
  final String callType; // 'audio' or 'video'
  final bool isGroupCall;
  final List<String> participantIds;

  const CallScreen({
    super.key,
    required this.channelName,
    required this.appId,
    this.callType = 'video',
    this.isGroupCall = false,
    this.participantIds = const [],
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final Map<int, bool> _remoteUids = {}; // Для групповых звонков
  int? _remoteUid; // Для обычных звонков (обратная совместимость)
  bool _localUserJoined = false;
  bool _isMuted = false;
  late RtcEngine _engine;

  @override
  void initState() {
    super.initState();
    initAgora();
  }

  Future<void> initAgora() async {
    try {
      // 1. Проверка прав (только не для Web)
      if (!kIsWeb) {
        final permissions = [Permission.microphone];
        if (widget.callType == 'video') {
          permissions.add(Permission.camera);
        }
        await permissions.request();
      }

      // 2. Инициализация движка
      _engine = createAgoraRtcEngine();
      await _engine.initialize(RtcEngineContext(
        appId: widget.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint("Agora: Local user ${connection.localUid} joined channel: ${widget.channelName}");
            if (mounted) {
              setState(() {
                _localUserJoined = true;
              });
            }
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint("Agora: Remote user $remoteUid joined");
            if (mounted) {
              setState(() {
                if (widget.isGroupCall) {
                  _remoteUids[remoteUid] = true;
                } else {
                  _remoteUid = remoteUid;
                }
              });
            }
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint("Agora: Remote user $remoteUid left");
            if (mounted) {
              setState(() {
                if (widget.isGroupCall) {
                  _remoteUids.remove(remoteUid);
                  // Не закрываем экран для групповых звонков, если остались участники
                } else {
                  _remoteUid = null;
                  Navigator.pop(context);
                }
              });
            }
          },
          onError: (err, msg) {
            debugPrint("Agora Error: $err, $msg");
          },
        ),
      );

      // 3. Настройка аудио/видео
      await _engine.enableAudio();
      
      if (!kIsWeb) {
        try {
          if (Platform.isAndroid || Platform.isIOS) {
            await _engine.setEnableSpeakerphone(true);
          }
        } catch (e) {
          debugPrint("Agora: Speakerphone not supported on this platform");
        }
      }
      
      if (widget.callType == 'video') {
        await _engine.enableVideo();
        await _engine.startPreview();
      } else {
        await _engine.disableVideo();
      }

      // 4. Вход в канал
      await _engine.joinChannel(
        token: '', 
        channelId: widget.channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (e) {
      debugPrint("Agora Setup Error: $e");
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  Future<void> _dispose() async {
    try {
      await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      debugPrint("Agora Release Error: $e");
    }
  }

  void _onToggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _engine.muteLocalAudioStream(_isMuted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.callType == 'video' ? 'Видео звонок' : 'Аудио звонок'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: widget.callType == 'video' 
              ? (widget.isGroupCall ? _buildGroupVideoCall() : _remoteVideo())
              : (widget.isGroupCall ? _buildGroupAudioCallUI() : _buildAudioCallUI()),
          ),
          if (widget.callType == 'video' && _localUserJoined) _buildLocalPreview(),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildAudioCallUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircleAvatar(
          radius: 60, 
          backgroundColor: Colors.blueAccent,
          child: Icon(Icons.person, size: 60, color: Colors.white)
        ),
        const SizedBox(height: 20),
        Text(
          _remoteUid != null ? 'Связь установлена' : 'Ожидание собеседника...',
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
      ],
    );
  }

  Widget _buildLocalPreview() {
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        width: 120,
        height: 180,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: _engine,
              canvas: const VideoCanvas(uid: 0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 50),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FloatingActionButton(
              heroTag: 'mute',
              onPressed: _onToggleMute,
              backgroundColor: _isMuted ? Colors.white : Colors.white24,
              child: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: _isMuted ? Colors.black : Colors.white),
            ),
            const SizedBox(width: 20),
            FloatingActionButton(
              heroTag: 'endCall',
              onPressed: () => Navigator.pop(context),
              backgroundColor: Colors.red,
              child: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    );
  }

  Widget _remoteVideo() {
    if (_remoteUid != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: widget.channelName),
        ),
      );
    } else {
      return const Text(
        'Ожидание собеседника...',
        style: TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      );
    }
  }

  Widget _buildGroupVideoCall() {
    if (_remoteUids.isEmpty) {
      return const Text(
        'Ожидание участников...',
        style: TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _remoteUids.length,
      itemBuilder: (context, index) {
        final uid = _remoteUids.keys.elementAt(index);
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _engine,
                canvas: VideoCanvas(uid: uid),
                connection: RtcConnection(channelId: widget.channelName),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupAudioCallUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircleAvatar(
          radius: 60, 
          backgroundColor: Colors.blueAccent,
          child: Icon(Icons.group, size: 60, color: Colors.white)
        ),
        const SizedBox(height: 20),
        Text(
          'Участников: ${_remoteUids.length + 1}',
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
        const SizedBox(height: 10),
        const Text(
          'Групповой аудиозвонок',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
  }
}
