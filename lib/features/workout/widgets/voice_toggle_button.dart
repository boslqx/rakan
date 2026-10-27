import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/voice_coach.dart';
import '../../../shared/widgets/pressable.dart';

/// Mutes or unmutes [coach]; the choice is remembered for later sessions.
/// Sized to sit beside the camera screens' close button.
class VoiceToggleButton extends StatefulWidget {
  final VoiceCoach coach;

  const VoiceToggleButton({super.key, required this.coach});

  @override
  State<VoiceToggleButton> createState() => _VoiceToggleButtonState();
}

class _VoiceToggleButtonState extends State<VoiceToggleButton> {
  void _toggle() {
    HapticFeedback.selectionClick();
    final on = !widget.coach.enabled;
    widget.coach.setEnabled(on);
    setState(() {});
    if (on) widget.coach.say('Voice on.');
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.coach.enabled;
    return Semantics(
      button: true,
      label: on ? 'Mute voice coach' : 'Unmute voice coach',
      child: Pressable(
        onTap: _toggle,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: on ? Colors.white : Colors.white38,
            size: 18,
          ),
        ),
      ),
    );
  }
}
