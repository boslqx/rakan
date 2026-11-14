import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Particle data for the workout transition: every dot has a spot on the
/// logo, a spot on one of two 3D "panels", and a spot on a flat square ring.
/// The painter moves each dot between those spots over the timeline.
class LogoParticles {
  LogoParticles._({
    required this.image,
    required this.aspect,
    required this.logo,
    required this.panels,
    required this.ring,
    required this.delay,
  });

  /// Full-resolution logo, drawn solid at the start and the end.
  final ui.Image image;

  /// Logo width / height.
  final double aspect;

  /// Interleaved positions, in "logo units": the logo's longest side spans -1..1.
  final Float32List logo; // x, y
  final Float32List panels; // x, y, z
  final Float32List ring; // x, y

  /// Per-dot stagger (0..1) so the dots don't move in lockstep.
  final Float32List delay;

  int get count => delay.length;

  static Future<LogoParticles> load(
    String asset, {
    int count = 9000,
    int seed = 7,
  }) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();

    final fullCodec = await ui.instantiateImageCodec(bytes);
    final image = (await fullCodec.getNextFrame()).image;

    // A small copy is enough to find where the logo is opaque.
    const sampleWidth = 220;
    final smallCodec =
        await ui.instantiateImageCodec(bytes, targetWidth: sampleWidth);
    final small = (await smallCodec.getNextFrame()).image;
    final rgba = (await small.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final w = small.width, h = small.height;
    small.dispose();

    final opaque = <int>[];
    for (var i = 0; i < w * h; i++) {
      if (rgba.getUint8(i * 4 + 3) > 140) opaque.add(i);
    }

    final rnd = math.Random(seed);
    final half = math.max(w, h) / 2;
    final logo = Float32List(count * 2);
    final panels = Float32List(count * 3);
    final ring = Float32List(count * 2);
    final delay = Float32List(count);

    for (var i = 0; i < count; i++) {
      // ── Logo spot: a random opaque pixel with sub-pixel jitter.
      final p = opaque.isEmpty ? 0 : opaque[rnd.nextInt(opaque.length)];
      logo[i * 2] = ((p % w) + rnd.nextDouble() - w / 2) / half;
      logo[i * 2 + 1] = ((p ~/ w) + rnd.nextDouble() - h / 2) / half;

      // ── Panel spot: two see-through cards at different depths,
      // with dots bunched along the edges like the reference.
      final big = i.isEven;
      final side = big ? 1.55 : 1.1;
      final cx = big ? -0.35 : 0.6;
      final cy = big ? -0.05 : 0.2;
      final cz = big ? -0.35 : 0.45;
      // uv follows the dot's place in the logo, so the shape stretches onto
      // the card instead of scattering randomly.
      final lx = logo[i * 2], ly = logo[i * 2 + 1];
      double u = (lx / 0.72).clamp(-1.0, 1.0);
      double v = ly.clamp(-1.0, 1.0);
      if (rnd.nextDouble() < 0.4) {
        // Edge: snap to the nearest side, pulled slightly inward.
        final inset = 1 - rnd.nextDouble() * rnd.nextDouble() * 0.12;
        if (u.abs() > v.abs()) {
          u = u.sign * inset;
        } else {
          v = v.sign * inset;
        }
      }
      // Card faces are turned 0.5 rad around Y so they read as 3D.
      const cardTurn = 0.5;
      final px = u * side / 2, py = v * side / 2;
      panels[i * 3] = cx + px * math.cos(cardTurn);
      panels[i * 3 + 1] = cy + py;
      panels[i * 3 + 2] = cz + px * math.sin(cardTurn);

      // ── Ring spot: push the dot outward along its angle from the centre
      // onto a thick square band, so the ring pinches back into the logo.
      final angle = (lx.abs() + ly.abs() < 1e-3)
          ? rnd.nextDouble() * math.pi * 2
          : math.atan2(ly, lx);
      final band = 0.66 +
          (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble()) / 3 * 0.2;
      final ca = math.cos(angle), sa = math.sin(angle);
      final r = band / math.max(ca.abs(), sa.abs());
      ring[i * 2] = ca * r;
      ring[i * 2 + 1] = sa * r;

      delay[i] = rnd.nextDouble();
    }

    return LogoParticles._(
      image: image,
      aspect: image.width / image.height,
      logo: logo,
      panels: panels,
      ring: ring,
      delay: delay,
    );
  }
}

/// Timeline in seconds. Kept here so the screen and painter agree.
class ParticleTimeline {
  static const double logoIn = 0.4; // solid logo scales in
  static const double dissolveEnd = 0.8; // solid → dots
  static const double cloudEnd = 1.9; // dots → turning 3D panels
  static const double ringEnd = 2.4; // panels → flat square ring
  static const double reformEnd = 3.3; // ring → logo
  static const double solidEnd = 3.6; // dots → solid logo
}

class LogoParticlePainter extends CustomPainter {
  LogoParticlePainter({
    required this.particles,
    required this.seconds,
    required this.color,
  });

  final LogoParticles particles;
  final double seconds;
  final Color color;

  static double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  static double _ease(double v) => Curves.easeInOutCubic.transform(_clamp01(v));
  static double _phase(double t, double a, double b) => _clamp01((t - a) / (b - a));

  @override
  void paint(Canvas canvas, Size size) {
    final t = seconds;
    final center = size.center(Offset.zero);
    final unit = size.shortestSide / 2; // px per logo unit

    // ── Solid logo: scale in, fade out into dots, fade back at the end.
    final scaleIn = Curves.easeOutBack.transform(_phase(t, 0, ParticleTimeline.logoIn));
    final solidOut = 1 - _phase(t, ParticleTimeline.logoIn, ParticleTimeline.dissolveEnd);
    final solidBack = _ease(_phase(t, ParticleTimeline.reformEnd - 0.15, ParticleTimeline.solidEnd));
    final solidAlpha = math.max(t < ParticleTimeline.dissolveEnd ? solidOut : 0.0, solidBack);
    final solidScale = t < ParticleTimeline.logoIn ? scaleIn : 1.0;

    // ── Dots: fade in while the solid fades out, fade away under the solid.
    final dotsIn = _phase(t, ParticleTimeline.logoIn, ParticleTimeline.dissolveEnd - 0.1);
    final dotsOut = 1 - _phase(t, ParticleTimeline.reformEnd, ParticleTimeline.solidEnd);
    final dotAlpha = math.min(dotsIn, dotsOut);

    if (dotAlpha > 0.001) {
      _paintDots(canvas, center, unit, t, dotAlpha);
    }

    if (solidAlpha > 0.001 && solidScale > 0.001) {
      final img = particles.image;
      final h = particles.aspect >= 1 ? 2 * unit / particles.aspect : 2 * unit;
      final w = h * particles.aspect;
      final rect = Rect.fromCenter(
        center: center,
        width: w * solidScale,
        height: h * solidScale,
      );
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        rect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.mode(
            color.withValues(alpha: _clamp01(solidAlpha)),
            BlendMode.modulate,
          ),
      );
    }
  }

  void _paintDots(Canvas canvas, Offset c, double unit, double t, double alpha) {
    final p = particles;
    final n = p.count;
    final out = Float32List(n * 2);

    // Global 3D turn: ramps in as dots leave the logo, out as they flatten.
    final turnIn = _ease(_phase(t, ParticleTimeline.dissolveEnd, ParticleTimeline.dissolveEnd + 0.6));
    final turnOut = 1 - _ease(_phase(t, ParticleTimeline.cloudEnd, ParticleTimeline.ringEnd));
    final amp = math.min(turnIn, turnOut);
    final sweep = -0.7 + 1.5 * _phase(t, ParticleTimeline.dissolveEnd, ParticleTimeline.ringEnd);
    final ay = sweep * amp;
    final ax = 0.28 * amp;
    final cy = math.cos(ay), sy = math.sin(ay);
    final cx = math.cos(ax), sx = math.sin(ax);
    const focal = 3.2;

    // Grain while dissolving: dots drift slightly off the logo.
    final drift = _phase(t, ParticleTimeline.logoIn, ParticleTimeline.dissolveEnd);

    for (var i = 0; i < n; i++) {
      final d = p.delay[i] * 0.35; // stagger as a share of each phase
      final lx = p.logo[i * 2], ly = p.logo[i * 2 + 1];
      double x, y, z = 0;

      if (t < ParticleTimeline.cloudEnd) {
        final e = _ease((_phase(t, ParticleTimeline.dissolveEnd, ParticleTimeline.cloudEnd - 0.15) - d) / (1 - d));
        final jx = (p.delay[(i * 7) % n] - 0.5) * 0.05 * drift;
        final jy = (p.delay[(i * 13) % n] - 0.5) * 0.05 * drift;
        x = lx + jx + (p.panels[i * 3] - lx) * e;
        y = ly + jy + (p.panels[i * 3 + 1] - ly) * e;
        z = p.panels[i * 3 + 2] * e;
      } else if (t < ParticleTimeline.ringEnd) {
        final e = _ease((_phase(t, ParticleTimeline.cloudEnd, ParticleTimeline.ringEnd) - d) / (1 - d));
        x = p.panels[i * 3] + (p.ring[i * 2] - p.panels[i * 3]) * e;
        y = p.panels[i * 3 + 1] + (p.ring[i * 2 + 1] - p.panels[i * 3 + 1]) * e;
        z = p.panels[i * 3 + 2] * (1 - e);
      } else {
        final e = _ease((_phase(t, ParticleTimeline.ringEnd, ParticleTimeline.reformEnd) - d) / (1 - d));
        x = p.ring[i * 2] + (lx - p.ring[i * 2]) * e;
        y = p.ring[i * 2 + 1] + (ly - p.ring[i * 2 + 1]) * e;
      }

      // Rotate (Y then X), then perspective-project.
      if (amp > 0) {
        final rx = x * cy + z * sy;
        final rz = -x * sy + z * cy;
        final ry = y * cx - rz * sx;
        final rz2 = y * sx + rz * cx;
        final k = focal / (focal + rz2);
        x = rx * k;
        y = ry * k;
      }

      out[i * 2] = c.dx + x * unit;
      out[i * 2 + 1] = c.dy + y * unit;
    }

    canvas.drawRawPoints(
      ui.PointMode.points,
      out,
      Paint()
        ..color = color.withValues(alpha: 0.8 * alpha)
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(LogoParticlePainter old) =>
      old.seconds != seconds || old.particles != particles || old.color != color;
}
