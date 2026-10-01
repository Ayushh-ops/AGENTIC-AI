import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Primary Research button replicating `.btn` from reference prototype:
/// Background `--acc`, text `--onacc`, border-radius 12px, font-weight 600,
/// hover translateY(-2px) and shadow with `--at`.
class PrimaryResearchButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  const PrimaryResearchButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.label = 'Research',
  });

  @override
  State<PrimaryResearchButton> createState() => _PrimaryResearchButtonState();
}

class _PrimaryResearchButtonState extends State<PrimaryResearchButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;

    final bgColor = isEnabled ? acc : line;
    final fgColor = isEnabled ? onAcc : mute;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(
              0,
              _isHovered && isEnabled ? -2.0 : 0,
              0,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              boxShadow: _isHovered && isEnabled
                  ? [
                      BoxShadow(
                        color: at.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: FilledButton(
              onPressed: widget.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: fgColor,
                disabledBackgroundColor: Colors.transparent,
                disabledForegroundColor: mute,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                textStyle: AppTheme.bodyFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: widget.isLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                      ),
                    )
                  : Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width "New research" button replicating `.btn` from reference prototype.
class NewResearchButton extends StatefulWidget {
  final VoidCallback onPressed;

  const NewResearchButton({super.key, required this.onPressed});

  @override
  State<NewResearchButton> createState() => _NewResearchButtonState();
}

class _NewResearchButtonState extends State<NewResearchButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(
              0,
              _isHovered ? -2.0 : 0,
              0,
            ),
            decoration: BoxDecoration(
              color: acc,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: at.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                onTap: widget.onPressed,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '+ New research',
                        style: AppTheme.bodyFont(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: onAcc,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
