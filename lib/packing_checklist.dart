import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'route_recommendations.dart';
import 'trail_catalogue.dart';
import 'units.dart';

class PackingItem {
  const PackingItem({
    required this.id,
    required this.label,
    required this.reason,
  });

  final String id;
  final String label;
  final String reason;
}

/// Litres to carry for a route, from its walking time and the day's
/// conditions, rounded up to the nearest half litre.
double waterLitresFor({
  required Trail trail,
  required TrailConditions conditions,
}) {
  final litresPerHour = 0.5;
  final conditionFactor = switch (conditions) {
    TrailConditions.dry => 1.15,
    TrailConditions.wet => 1.0,
    TrailConditions.snowy => 0.9,
    TrailConditions.hot => 1.4,
  };
  final raw =
      math.max(0.75, trail.durationMinutes / 60 * litresPerHour) *
      conditionFactor;
  return (raw / 0.5).ceilToDouble() * 0.5;
}

String litreLabel(double litres) => litres == litres.roundToDouble()
    ? litres.toStringAsFixed(0)
    : litres.toStringAsFixed(1);

List<PackingItem> packingChecklistFor({
  required HikingAbility ability,
  required TrailConditions conditions,
  Trail? trail,
  Units units = Units.metric,
}) {
  final items = <PackingItem>[
    if (trail == null)
      PackingItem(
        id: 'water',
        label: 'Water',
        reason: switch (ability) {
          HikingAbility.beginner => 'At least 1.5 L for a shorter hike',
          HikingAbility.intermediate => 'At least 2 L for a longer day out',
          HikingAbility.advanced => 'Plan extra water for a full-day route',
        },
      )
    else
      PackingItem(
        id: 'water',
        label: 'Water',
        reason:
            'About ${litreLabel(waterLitresFor(trail: trail, conditions: conditions))} L '
            'for ${trail.durationLabel} on the trail',
      ),
    if (trail != null &&
        (trail.durationMinutes >= 180 ||
            (trail.elevationKnown && trail.ascentMeters >= 500)))
      PackingItem(
        id: 'extra-food',
        label: 'Extra food',
        reason: trail.elevationKnown
            ? '${trail.distanceLabel(units)} and ${trail.ascentLabel(units)} '
                  'needs more than a snack'
            : '${trail.distanceLabel(units)} is a long day out',
      ),
    const PackingItem(
      id: 'navigation',
      label: 'Navigation',
      reason: 'Carry a map and know your route before setting out',
    ),
    const PackingItem(
      id: 'first-aid',
      label: 'First-aid kit',
      reason: 'Bring basic first aid and any personal medication',
    ),
    const PackingItem(
      id: 'light',
      label: 'Headlamp',
      reason: 'Keep a light available if your hike takes longer than planned',
    ),
    if (trail != null && trail.elevationKnown && trail.ascentMeters >= 500)
      const PackingItem(
        id: 'poles',
        label: 'Trekking poles',
        reason: 'Long descents are easier on the knees with poles',
      ),
    if (trail != null && trail.elevationKnown && trail.highestPointMeters >= 1800)
      PackingItem(
        id: 'insulation',
        label: 'Insulating layer',
        reason:
            'It can be much colder at '
            '${units.height(trail.highestPointMeters)} than in the valley',
      ),
  ];

  switch (conditions) {
    case TrailConditions.dry:
      items.add(
        const PackingItem(
          id: 'sun-protection',
          label: 'Sun protection',
          reason: 'Pack sunscreen, sunglasses, and a hat',
        ),
      );
    case TrailConditions.wet:
      items.add(
        const PackingItem(
          id: 'waterproof-shell',
          label: 'Waterproof shell',
          reason: 'Wet rocks and roots can be slippery',
        ),
      );
    case TrailConditions.snowy:
      items
        ..add(
          const PackingItem(
            id: 'traction',
            label: 'Traction devices',
            reason: 'Check snow and ice reports before you go',
          ),
        )
        ..add(
          const PackingItem(
            id: 'warm-layers',
            label: 'Warm layers',
            reason: 'Bring insulating layers for cold conditions',
          ),
        );
    case TrailConditions.hot:
      items
        ..add(
          const PackingItem(
            id: 'extra-water',
            label: 'Extra water',
            reason: 'Carry more water and plan shaded breaks',
          ),
        )
        ..add(
          const PackingItem(
            id: 'sun-protection',
            label: 'Sun protection',
            reason: 'Pack sunscreen, sunglasses, and a hat',
          ),
        );
  }
  return List.unmodifiable(items);
}

class PackingChecklist extends StatefulWidget {
  const PackingChecklist({
    super.key,
    required this.ability,
    required this.conditions,
    this.trail,
  });

  final HikingAbility ability;
  final TrailConditions conditions;

  /// The planned route, when there is one. Its distance, ascent, walking time
  /// and high point change what the list recommends.
  final Trail? trail;

  @override
  State<PackingChecklist> createState() => _PackingChecklistState();
}

class _PackingChecklistState extends State<PackingChecklist> {
  final Set<String> _checkedItems = {};

  @override
  void didUpdateWidget(covariant PackingChecklist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ability != widget.ability ||
        oldWidget.conditions != widget.conditions ||
        oldWidget.trail?.id != widget.trail?.id) {
      _checkedItems.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trail = widget.trail;
    final units = UnitsScope.of(context);
    final items = packingChecklistFor(
      ability: widget.ability,
      conditions: widget.conditions,
      trail: trail,
      units: units,
    );
    final checkedCount = items
        .where((item) => _checkedItems.contains(item.id))
        .length;
    return Container(
      key: const Key('packing-checklist'),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.backpack_outlined, color: Color(0xFF3E8967)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Packing checklist',
                  style: TextStyle(
                    color: Color(0xFF292D2B),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '$checkedCount/${items.length}',
                key: const Key('packing-progress'),
                style: const TextStyle(
                  color: Color(0xFF3E8967),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            trail == null
                ? 'Suggested essentials · check off what you have packed'
                : 'Tailored to ${trail.name} · '
                      '${trail.distanceLabel(units)}'
                      '${trail.elevationKnown ? ' · ${trail.ascentLabel(units)}' : ''}',
            style: const TextStyle(color: Color(0xFF777E79), fontSize: 11),
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final checked = _checkedItems.contains(item.id);
            return Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                key: Key('packing-${item.id}'),
                value: checked,
                onChanged: (value) => setState(() {
                  if (value ?? false) {
                    _checkedItems.add(item.id);
                  } else {
                    _checkedItems.remove(item.id);
                  }
                }),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: const Color(0xFF3E8967),
                title: Text(
                  item.label,
                  style: const TextStyle(
                    color: Color(0xFF292D2B),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  item.reason,
                  style: const TextStyle(
                    color: Color(0xFF777E79),
                    fontSize: 10,
                  ),
                ),
              ),
            );
          }),
          const Padding(
            padding: EdgeInsets.only(top: 5, bottom: 3),
            child: Text(
              'General guidance only. Review local conditions and bring gear appropriate to your trip.',
              style: TextStyle(color: Color(0xFF858B86), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
