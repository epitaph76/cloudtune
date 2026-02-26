part of '../screens/server_music_screen.dart';

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientHeaderButton extends StatelessWidget {
  const _GradientHeaderButton({
    required this.width,
    required this.height,
    required this.label,
    required this.onTap,
  });

  final double width;
  final double height;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.tertiary],
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatefulWidget {
  const _PlaylistCard({
    required this.playlistName,
    required this.trackCount,
    this.selected = false,
    this.isTransferring = false,
    this.onTap,
    this.menuActions,
  });

  final String playlistName;
  final int trackCount;
  final bool selected;
  final bool isTransferring;
  final VoidCallback? onTap;
  final List<_PlaylistMenuAction>? menuActions;

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 150,
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.selected
                ? colorScheme.secondary
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.selected || _hovered
                  ? colorScheme.primary
                  : colorScheme.outline,
            ),
          ),
          child: Stack(
            children: [
              if (widget.isTransferring)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: _PlaylistTransferWaveFill(
                        primaryColor: colorScheme.primary,
                        secondaryColor: colorScheme.tertiary,
                      ),
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.tertiary],
                      ),
                    ),
                    child: Icon(
                      Icons.queue_music_rounded,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.playlistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.trackCount} ${AppLocalizations.text(context, 'tracks')}',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              if (widget.menuActions != null && widget.menuActions!.isNotEmpty)
                Positioned(
                  right: -6,
                  top: -6,
                  child: PopupMenuButton<int>(
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    onSelected: (index) => widget.menuActions![index].onTap(),
                    itemBuilder: (context) {
                      return List.generate(widget.menuActions!.length, (index) {
                        final action = widget.menuActions![index];
                        return PopupMenuItem<int>(
                          value: index,
                          child: Row(
                            children: [
                              Icon(action.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(action.label),
                            ],
                          ),
                        );
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistMenuAction {
  const _PlaylistMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _CreatePlaylistCard extends StatefulWidget {
  const _CreatePlaylistCard({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  State<_CreatePlaylistCard> createState() => _CreatePlaylistCardState();
}

class _CreatePlaylistCardState extends State<_CreatePlaylistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hovered ? colorScheme.primary : colorScheme.outline,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.secondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.add_rounded, color: colorScheme.primary),
              ),
              const SizedBox(height: 10),
              Text(widget.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTransferWaveFill extends StatefulWidget {
  const _PlaylistTransferWaveFill({
    required this.primaryColor,
    required this.secondaryColor,
  });

  final Color primaryColor;
  final Color secondaryColor;

  @override
  State<_PlaylistTransferWaveFill> createState() =>
      _PlaylistTransferWaveFillState();
}

class _PlaylistTransferWaveFillState extends State<_PlaylistTransferWaveFill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final wavePhase = _controller.value * 2 * math.pi;
        final fillLevel =
            0.15 + Curves.easeInOut.transform(_controller.value) * 0.85;

        return FractionallySizedBox(
          alignment: Alignment.bottomCenter,
          heightFactor: fillLevel.clamp(0.0, 1.0),
          child: CustomPaint(
            painter: _PlaylistTransferWavePainter(
              phase: wavePhase,
              baseColor: widget.primaryColor.withValues(alpha: 0.14),
              waveColor: widget.primaryColor.withValues(alpha: 0.22),
              crestColor: widget.secondaryColor.withValues(alpha: 0.30),
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _PlaylistTransferWavePainter extends CustomPainter {
  const _PlaylistTransferWavePainter({
    required this.phase,
    required this.baseColor,
    required this.waveColor,
    required this.crestColor,
  });

  final double phase;
  final Color baseColor;
  final Color waveColor;
  final Color crestColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);

    final crestY = size.height * 0.16;
    final firstAmplitude = math.max(2.0, size.height * 0.08);
    final secondAmplitude = math.max(1.6, size.height * 0.055);

    Path buildWave(double phaseShift, double amplitude) {
      final path = Path();
      final startY = crestY + math.sin(phaseShift) * amplitude;
      path.moveTo(0, startY);

      final width = size.width;
      for (double x = 0; x <= width; x += 4) {
        final normalized = width == 0 ? 0.0 : x / width;
        final y =
            crestY +
            math.sin((normalized * 2 * math.pi) + phaseShift) * amplitude;
        path.lineTo(x, y);
      }
      path.lineTo(width, size.height);
      path.lineTo(0, size.height);
      path.close();
      return path;
    }

    canvas.drawPath(
      buildWave(phase, firstAmplitude),
      Paint()..color = waveColor,
    );
    canvas.drawPath(
      buildWave(phase + (math.pi / 1.8), secondAmplitude),
      Paint()..color = crestColor,
    );

    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.16), Colors.transparent],
        stops: const [0.0, 0.55],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _PlaylistTransferWavePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.waveColor != waveColor ||
        oldDelegate.crestColor != crestColor;
  }
}

class _SelectablePlaylistCard extends StatefulWidget {
  const _SelectablePlaylistCard({
    required this.playlistName,
    required this.trackCount,
    this.trackCounterText,
    required this.selected,
    this.isTransferring = false,
    required this.onTap,
    this.menuActions,
  });

  final String playlistName;
  final int trackCount;
  final String? trackCounterText;
  final bool selected;
  final bool isTransferring;
  final VoidCallback onTap;
  final List<_PlaylistMenuAction>? menuActions;

  @override
  State<_SelectablePlaylistCard> createState() =>
      _SelectablePlaylistCardState();
}

class _SelectablePlaylistCardState extends State<_SelectablePlaylistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.selected
                ? colorScheme.secondary
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.selected || _hovered
                  ? colorScheme.primary
                  : colorScheme.outline,
            ),
          ),
          child: Stack(
            children: [
              if (widget.isTransferring)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: _PlaylistTransferWaveFill(
                        primaryColor: colorScheme.primary,
                        secondaryColor: colorScheme.tertiary,
                      ),
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.tertiary],
                      ),
                    ),
                    child: Icon(
                      Icons.queue_music_rounded,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.playlistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.trackCounterText ??
                        '${widget.trackCount} ${AppLocalizations.text(context, 'tracks')}',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              if (widget.menuActions != null && widget.menuActions!.isNotEmpty)
                Positioned(
                  right: -6,
                  top: -6,
                  child: PopupMenuButton<int>(
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    onSelected: (index) => widget.menuActions![index].onTap(),
                    itemBuilder: (context) {
                      return List.generate(widget.menuActions!.length, (index) {
                        final action = widget.menuActions![index];
                        return PopupMenuItem<int>(
                          value: index,
                          child: Row(
                            children: [
                              Icon(action.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(action.label),
                            ],
                          ),
                        );
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackMenuAction {
  const _TrackMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
}

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.title,
    required this.subtitle,
    required this.menuItems,
    this.selected = false,
    this.batchSelected = false,
    this.isUploading = false,
    this.isPlaying = false,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final List<_TrackMenuAction> menuItems;
  final bool selected;
  final bool batchSelected;
  final bool isUploading;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.batchSelected
                ? colorScheme.primary.withValues(alpha: 0.14)
                : widget.selected
                ? colorScheme.secondary
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.batchSelected
                  ? colorScheme.primary
                  : widget.selected || _hovered
                  ? colorScheme.primary
                  : colorScheme.outline,
            ),
          ),
          child: Stack(
            children: [
              if (widget.isUploading)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: _TrackUploadWaveFill(
                        primaryColor: colorScheme.primary,
                        secondaryColor: colorScheme.tertiary,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.tertiary],
                      ),
                    ),
                    child: widget.isPlaying
                        ? _AnimatedPlayingBars(color: colorScheme.onPrimary)
                        : Icon(
                            Icons.music_note_rounded,
                            color: colorScheme.onPrimary,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.batchSelected)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                  PopupMenuButton<int>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (index) => widget.menuItems[index].onTap(),
                    itemBuilder: (context) {
                      return List.generate(widget.menuItems.length, (index) {
                        final item = widget.menuItems[index];
                        return PopupMenuItem<int>(
                          value: index,
                          enabled: item.enabled,
                          child: Row(
                            children: [
                              Icon(item.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(item.label),
                            ],
                          ),
                        );
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackUploadWaveFill extends StatefulWidget {
  const _TrackUploadWaveFill({
    required this.primaryColor,
    required this.secondaryColor,
  });

  final Color primaryColor;
  final Color secondaryColor;

  @override
  State<_TrackUploadWaveFill> createState() => _TrackUploadWaveFillState();
}

class _TrackUploadWaveFillState extends State<_TrackUploadWaveFill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final widthFactor = 0.2 + (t * 0.8);
        final phase = _controller.value * 2 * math.pi;
        return FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor.clamp(0.0, 1.0),
          child: CustomPaint(
            painter: _TrackUploadWavePainter(
              phase: phase,
              baseColor: widget.primaryColor.withValues(alpha: 0.1),
              waveColor: widget.primaryColor.withValues(alpha: 0.17),
              crestColor: widget.secondaryColor.withValues(alpha: 0.24),
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _TrackUploadWavePainter extends CustomPainter {
  const _TrackUploadWavePainter({
    required this.phase,
    required this.baseColor,
    required this.waveColor,
    required this.crestColor,
  });

  final double phase;
  final Color baseColor;
  final Color waveColor;
  final Color crestColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);

    Path buildVerticalWave(double localPhase, double baseX, double amp) {
      final path = Path();
      final startX = baseX + (math.sin(localPhase) * amp);
      path.moveTo(startX, 0);

      final height = size.height;
      for (double y = 0; y <= height; y += 3) {
        final normalized = height == 0 ? 0.0 : y / height;
        final x =
            baseX + (math.sin((normalized * 2 * math.pi) + localPhase) * amp);
        path.lineTo(x, y);
      }
      path.lineTo(0, size.height);
      path.lineTo(0, 0);
      path.close();
      return path;
    }

    canvas.drawPath(
      buildVerticalWave(
        phase,
        size.width * 0.78,
        math.max(1.3, size.width * 0.06),
      ),
      Paint()..color = waveColor,
    );
    canvas.drawPath(
      buildVerticalWave(
        phase + (math.pi / 1.5),
        size.width * 0.62,
        math.max(1.0, size.width * 0.045),
      ),
      Paint()..color = crestColor,
    );
  }

  @override
  bool shouldRepaint(covariant _TrackUploadWavePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.waveColor != waveColor ||
        oldDelegate.crestColor != crestColor;
  }
}

class _AnimatedPlayingBars extends StatefulWidget {
  const _AnimatedPlayingBars({required this.color});

  final Color color;

  @override
  State<_AnimatedPlayingBars> createState() => _AnimatedPlayingBarsState();
}

class _AnimatedPlayingBarsState extends State<_AnimatedPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _barHeight(int index, double t) {
    final phase = (t * 2 * math.pi) + (index * 0.9);
    final normalized = (math.sin(phase) + 1) / 2;
    return 8 + (normalized * 12);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 18,
        height: 22,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(3, (index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    width: 4,
                    height: _barHeight(index, _controller.value),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _CloudLoginCard extends StatelessWidget {
  const _CloudLoginCard({
    required this.emailController,
    required this.usernameController,
    required this.passwordController,
    required this.loading,
    required this.isRegisterMode,
    required this.onSubmit,
    required this.onToggleMode,
  });

  final TextEditingController emailController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool loading;
  final bool isRegisterMode;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppLocalizations.text(context, key);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isRegisterMode ? t('cloud_register') : t('cloud_login'),
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            isRegisterMode ? t('cloud_register_hint') : t('cloud_login_hint'),
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          if (isRegisterMode) ...[
            const SizedBox(height: 10),
            TextField(
              controller: usernameController,
              decoration: InputDecoration(
                labelText: t('username'),
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t('password'),
              prefixIcon: Icon(Icons.lock_rounded),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : onSubmit,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isRegisterMode ? t('create_account') : t('sign_in')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: loading ? null : onToggleMode,
              child: Text(
                isRegisterMode
                    ? t('already_have_account')
                    : t('no_account_register'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  const _EmptyInlineState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Text(
        message,
        style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.65)),
      ),
    );
  }
}
