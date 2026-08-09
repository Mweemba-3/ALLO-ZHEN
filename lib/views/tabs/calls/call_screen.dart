import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';
import 'package:allo_zhen/data/repositories/call_repository.dart';
import 'package:allo_zhen/data/models/call_model.dart';
import 'package:permission_handler/permission_handler.dart';

class CallScreen extends StatefulWidget {
  final String recipientId;
  final String recipientName;
  final String? avatarUrl;
  final bool isVideoCall;
  final bool isIncoming;
  final String? callId; // ✅ Added

  const CallScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
    this.avatarUrl,
    this.isVideoCall = false,
    this.isIncoming = false,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallRepository _callRepo = CallRepository();
  
  // WebRTC
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  
  // Call state
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;
  bool _isConnected = false;
  bool _isCallEnded = false;
  bool _isCameraReady = false;
  Timer? _callTimer;
  int _callDuration = 0;

  // Signaling
  final _signalingChannel = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _signalingSubscription;

  // Unique call ID
  late String _callId;

  @override
  void initState() {
    super.initState();
    _callId = widget.callId ?? DateTime.now().millisecondsSinceEpoch.toString();
    _initRenderer();
    _requestPermissionsAndStart();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _requestPermissionsAndStart() async {
    final status = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (status[Permission.camera]!.isGranted && 
        status[Permission.microphone]!.isGranted) {
      _startCall();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera and microphone permissions are required for calls.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _startCall() async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': widget.isVideoCall,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      setState(() => _isCameraReady = true);

      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      });

      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (event) {
        _remoteRenderer.srcObject = event.streams[0];
        setState(() => _isConnected = true);
        _startCallTimer();
      };

      _peerConnection?.onIceCandidate = (candidate) {
        _sendSignalingMessage({
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };

      if (widget.isIncoming) {
        // ✅ Listen for the offer from the signaling channel using callId
        _signalingSubscription = _callRepo.listenForSignaling(_callId).listen((signal) async {
          if (signal['type'] == 'offer') {
            final offer = RTCSessionDescription(signal['sdp'], 'offer');
            await _peerConnection?.setRemoteDescription(offer);
            
            final answer = await _peerConnection?.createAnswer();
            await _peerConnection?.setLocalDescription(answer!);
            _sendSignalingMessage({
              'type': 'answer',
              'sdp': answer!.sdp,
              'recipient_id': widget.recipientId,
              'call_id': _callId,
            });
          } else if (signal['type'] == 'candidate') {
            final candidate = RTCIceCandidate(
              signal['candidate'],
              signal['sdpMid'],
              signal['sdpMLineIndex'],
            );
            await _peerConnection?.addCandidate(candidate);
          }
        });
      } else {
        // ✅ Outgoing call: create and send offer
        final offer = await _peerConnection?.createOffer();
        await _peerConnection?.setLocalDescription(offer!);
        
        // Send the offer + notification
        _sendSignalingMessage({
          'type': 'offer',
          'sdp': offer!.sdp,
          'recipient_id': widget.recipientId,
          'caller_id': _callRepo.currentUserId,
          'is_video': widget.isVideoCall,
          'call_id': _callId,
        });

        // Send the popup notification
        await _callRepo.sendCallNotification(
          callerId: _callRepo.currentUserId ?? '',
          callerName: widget.recipientName,
          recipientId: widget.recipientId,
          isVideo: widget.isVideoCall,
          callId: _callId, // ✅ Pass callId
        );
      }

      setState(() => _isVideoEnabled = widget.isVideoCall);
    } catch (e) {
      debugPrint('Error starting call: $e');
      _endCall();
    }
  }

  void _sendSignalingMessage(Map<String, dynamic> payload) {
    _callRepo.sendSignalingMessage(payload);
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDuration++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleMute() async {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !track.enabled;
    });
    setState(() => _isMuted = !_isMuted);
  }

  Future<void> _toggleVideo() async {
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !track.enabled;
    });
    setState(() => _isVideoEnabled = !_isVideoEnabled);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
  }

  Future<void> _endCall() async {
    if (_isCallEnded) return;
    setState(() => _isCallEnded = true);

    _callTimer?.cancel();
    _signalingSubscription?.cancel();
    
    if (_callDuration > 0) {
      await _callRepo.logCall(
        callerId: _callRepo.currentUserId ?? '',
        callerName: widget.recipientName,
        receiverId: widget.recipientId,
        type: widget.isVideoCall ? CallType.video : CallType.audio,
        status: _isConnected ? CallStatus.outgoing : CallStatus.missed,
        durationSeconds: _callDuration,
      );
    }

    _peerConnection?.close();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _signalingSubscription?.cancel();
    _peerConnection?.close();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // --- Remote Video ---
            if (_isVideoEnabled && _isConnected && _remoteRenderer.srcObject != null)
              Positioned.fill(
                child: RTCVideoView(_remoteRenderer, mirror: false),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: AppColors.surface,
                      backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                          ? NetworkImage(widget.avatarUrl!)
                          : null,
                      child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                          ? Text(
                              widget.recipientName[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.recipientName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isConnected
                          ? _formatDuration(_callDuration)
                          : (widget.isIncoming ? 'Incoming call...' : 'Calling...'),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // --- Local Video (PIP) ---
            if (_isVideoEnabled && _isCameraReady)
              Positioned(
                top: 20,
                right: 20,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(_localRenderer, mirror: true),
                ),
              ),

            // --- Top-left Back Button ---
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                  onPressed: _endCall,
                ),
              ),
            ),

            // --- Bottom Control Bar ---
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      isActive: _isMuted,
                      onTap: _toggleMute,
                    ),
                    _CallActionButton(
                      icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                      isActive: _isSpeakerOn,
                      onTap: _toggleSpeaker,
                    ),
                    _CallActionButton(
                      icon: _isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                      isActive: _isVideoEnabled,
                      onTap: _toggleVideo,
                    ),
                    FloatingActionButton(
                      heroTag: 'endCallBtn',
                      backgroundColor: Colors.redAccent,
                      elevation: 2,
                      onPressed: _endCall,
                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 26),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.white60,
          size: 22,
        ),
      ),
    );
  }
}