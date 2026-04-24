import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';

// Defines each tappable body region as a rectangle zone
// Coordinates are normalized (0.0 to 1.0) relative to the widget size
class BodyRegionZone {
  final BodyRegion region;
  final String label;
  final Rect normalizedRect; 

  const BodyRegionZone({
    required this.region,
    required this.label,
    required this.normalizedRect,
  });
}

// All tappable zones on the body map
// Tuned for a standing front-facing human silhouette
const List<BodyRegionZone> bodyZones = [
  BodyRegionZone(
    region: BodyRegion.head,
    label: 'Head',
    normalizedRect: Rect.fromLTWH(0.35, 0.01, 0.30, 0.12),
  ),
  BodyRegionZone(
    region: BodyRegion.neck,
    label: 'Neck',
    normalizedRect: Rect.fromLTWH(0.40, 0.13, 0.20, 0.06),
  ),
  BodyRegionZone(
    region: BodyRegion.leftShoulder,
    label: 'Left Shoulder',
    normalizedRect: Rect.fromLTWH(0.18, 0.18, 0.18, 0.10),
  ),
  BodyRegionZone(
    region: BodyRegion.rightShoulder,
    label: 'Right Shoulder',
    normalizedRect: Rect.fromLTWH(0.64, 0.18, 0.18, 0.10),
  ),
  BodyRegionZone(
    region: BodyRegion.chest,
    label: 'Chest',
    normalizedRect: Rect.fromLTWH(0.32, 0.19, 0.36, 0.12),
  ),
  BodyRegionZone(
    region: BodyRegion.upperBack,
    label: 'Upper Back',
    normalizedRect: Rect.fromLTWH(0.32, 0.19, 0.36, 0.10),
  ),
  BodyRegionZone(
    region: BodyRegion.leftArm,
    label: 'Left Arm',
    normalizedRect: Rect.fromLTWH(0.12, 0.28, 0.16, 0.22),
  ),
  BodyRegionZone(
    region: BodyRegion.rightArm,
    label: 'Right Arm',
    normalizedRect: Rect.fromLTWH(0.72, 0.28, 0.16, 0.22),
  ),
  BodyRegionZone(
    region: BodyRegion.core,
    label: 'Core',
    normalizedRect: Rect.fromLTWH(0.32, 0.31, 0.36, 0.12),
  ),
  BodyRegionZone(
    region: BodyRegion.lowerBack,
    label: 'Lower Back',
    normalizedRect: Rect.fromLTWH(0.32, 0.43, 0.36, 0.08),
  ),
  BodyRegionZone(
    region: BodyRegion.leftHip,
    label: 'Left Hip',
    normalizedRect: Rect.fromLTWH(0.28, 0.51, 0.20, 0.10),
  ),
  BodyRegionZone(
    region: BodyRegion.rightHip,
    label: 'Right Hip',
    normalizedRect: Rect.fromLTWH(0.52, 0.51, 0.20, 0.10),
  ),
  BodyRegionZone(
    region: BodyRegion.leftKnee,
    label: 'Left Knee',
    normalizedRect: Rect.fromLTWH(0.28, 0.72, 0.18, 0.08),
  ),
  BodyRegionZone(
    region: BodyRegion.rightKnee,
    label: 'Right Knee',
    normalizedRect: Rect.fromLTWH(0.54, 0.72, 0.18, 0.08),
  ),
  BodyRegionZone(
    region: BodyRegion.leftAnkle,
    label: 'Left Ankle',
    normalizedRect: Rect.fromLTWH(0.28, 0.90, 0.18, 0.08),
  ),
  BodyRegionZone(
    region: BodyRegion.rightAnkle,
    label: 'Right Ankle',
    normalizedRect: Rect.fromLTWH(0.54, 0.90, 0.18, 0.08),
  ),
];

// Predefined injuries per body region
const Map<BodyRegion, List<String>> regionInjuries = {
  BodyRegion.head: ['Concussion', 'Migraine', 'Vertigo'],
  BodyRegion.neck: ['Neck Strain', 'Cervical Disc Issue', 'Whiplash'],
  BodyRegion.leftShoulder: [
    'Rotator Cuff Tear',
    'Shoulder Impingement',
    'AC Joint Sprain',
    'Frozen Shoulder',
  ],
  BodyRegion.rightShoulder: [
    'Rotator Cuff Tear',
    'Shoulder Impingement',
    'AC Joint Sprain',
    'Frozen Shoulder',
  ],
  BodyRegion.chest: ['Pec Strain', 'Costochondritis', 'Rib Stress'],
  BodyRegion.upperBack: [
    'Upper Back Strain',
    'Thoracic Disc Issue',
    'Muscle Knots',
  ],
  BodyRegion.leftArm: [
    'Bicep Tendinitis',
    'Tennis Elbow',
    'Golfer\'s Elbow',
    'Wrist Sprain',
  ],
  BodyRegion.rightArm: [
    'Bicep Tendinitis',
    'Tennis Elbow',
    'Golfer\'s Elbow',
    'Wrist Sprain',
  ],
  BodyRegion.core: ['Abdominal Strain', 'Hernia', 'Hip Flexor Strain'],
  BodyRegion.lowerBack: [
    'Lower Back Pain',
    'Lumbar Disc Herniation',
    'Sciatica',
    'SI Joint Dysfunction',
  ],
  BodyRegion.leftHip: ['Hip Flexor Strain', 'IT Band Syndrome', 'Hip Bursitis'],
  BodyRegion.rightHip: [
    'Hip Flexor Strain',
    'IT Band Syndrome',
    'Hip Bursitis',
  ],
  BodyRegion.leftKnee: [
    'ACL/MCL Sprain',
    'Patellar Tendinitis',
    'Runner\'s Knee',
    'Meniscus Issue',
  ],
  BodyRegion.rightKnee: [
    'ACL/MCL Sprain',
    'Patellar Tendinitis',
    'Runner\'s Knee',
    'Meniscus Issue',
  ],
  BodyRegion.leftAnkle: ['Ankle Sprain', 'Achilles Tendinitis', 'Plantar Fasciitis'],
  BodyRegion.rightAnkle: [
    'Ankle Sprain',
    'Achilles Tendinitis',
    'Plantar Fasciitis',
  ],
};

// The actual painter — draws the silhouette and region highlights
class BodyMapPainter extends CustomPainter {
  final Set<BodyRegion> highlightedRegions;
  final BodyRegion? hoveredRegion;

  const BodyMapPainter({
    required this.highlightedRegions,
    this.hoveredRegion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw body silhouette as simplified shapes
    _drawSilhouette(canvas, size);

    // Draw region highlights for injured areas
    for (final zone in bodyZones) {
      if (highlightedRegions.contains(zone.region)) {
        _drawZoneHighlight(canvas, size, zone, isActive: true);
      } else if (hoveredRegion == zone.region) {
        _drawZoneHighlight(canvas, size, zone, isActive: false);
      }
    }

    // Draw region labels
    _drawRegionLabels(canvas, size);
  }

  void _drawSilhouette(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.surfaceContainerHigh
      ..style = PaintingStyle.fill;

    final outlinePaint = Paint()
      ..color = AppColors.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Head
    final headRect = Rect.fromLTWH(
      size.width * 0.35,
      size.height * 0.01,
      size.width * 0.30,
      size.height * 0.12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(headRect, const Radius.circular(20)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(headRect, const Radius.circular(20)),
      outlinePaint,
    );

    // Neck
    final neckRect = Rect.fromLTWH(
      size.width * 0.42,
      size.height * 0.13,
      size.width * 0.16,
      size.height * 0.06,
    );
    canvas.drawRect(neckRect, paint);

    // Torso
    final torsoRect = Rect.fromLTWH(
      size.width * 0.28,
      size.height * 0.19,
      size.width * 0.44,
      size.height * 0.35,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(torsoRect, const Radius.circular(12)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(torsoRect, const Radius.circular(12)),
      outlinePaint,
    );

    // Left arm
    final leftArmRect = Rect.fromLTWH(
      size.width * 0.12,
      size.height * 0.19,
      size.width * 0.16,
      size.height * 0.32,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(leftArmRect, const Radius.circular(10)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(leftArmRect, const Radius.circular(10)),
      outlinePaint,
    );

    // Right arm
    final rightArmRect = Rect.fromLTWH(
      size.width * 0.72,
      size.height * 0.19,
      size.width * 0.16,
      size.height * 0.32,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rightArmRect, const Radius.circular(10)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rightArmRect, const Radius.circular(10)),
      outlinePaint,
    );

    // Left leg
    final leftLegRect = Rect.fromLTWH(
      size.width * 0.28,
      size.height * 0.54,
      size.width * 0.20,
      size.height * 0.44,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(leftLegRect, const Radius.circular(10)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(leftLegRect, const Radius.circular(10)),
      outlinePaint,
    );

    // Right leg
    final rightLegRect = Rect.fromLTWH(
      size.width * 0.52,
      size.height * 0.54,
      size.width * 0.20,
      size.height * 0.44,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rightLegRect, const Radius.circular(10)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rightLegRect, const Radius.circular(10)),
      outlinePaint,
    );
  }

  void _drawZoneHighlight(
    Canvas canvas,
    Size size,
    BodyRegionZone zone, {
    required bool isActive,
  }) {
    final rect = Rect.fromLTWH(
      zone.normalizedRect.left * size.width,
      zone.normalizedRect.top * size.height,
      zone.normalizedRect.width * size.width,
      zone.normalizedRect.height * size.height,
    );

    final paint = Paint()
      ..color = isActive
          ? AppColors.error.withOpacity(0.35)
          : AppColors.primary.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );

    if (isActive) {
      final borderPaint = Paint()
        ..color = AppColors.error.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        borderPaint,
      );
    }
  }

  void _drawRegionLabels(Canvas canvas, Size size) {
    // Draw small dot indicators on each zone
    for (final zone in bodyZones) {
      final centerX =
          (zone.normalizedRect.left + zone.normalizedRect.width / 2) *
              size.width;
      final centerY =
          (zone.normalizedRect.top + zone.normalizedRect.height / 2) *
              size.height;

      final dotPaint = Paint()
        ..color = highlightedRegions.contains(zone.region)
            ? AppColors.error
            : AppColors.outlineVariant.withOpacity(0.5)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(centerX, centerY), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(BodyMapPainter oldDelegate) {
    return oldDelegate.highlightedRegions != highlightedRegions ||
        oldDelegate.hoveredRegion != hoveredRegion;
  }
}