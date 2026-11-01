import 'package:flutter/material.dart';

import 'route_recommendations.dart';
import 'trail_catalogue.dart';

const _forest = Color(0xFF3E8967);
const _ink = Color(0xFF292D2B);
const _paper = Color(0xFFF0F7F2);

class TrailCataloguePage extends StatefulWidget {
  const TrailCataloguePage({
    super.key,
    this.ability = HikingAbility.beginner,
    this.conditions = TrailConditions.dry,
    this.trails = sampleTrailCatalogue,
  });

  final HikingAbility ability;
  final TrailConditions conditions;
  final List<Trail> trails;

  @override
  State<TrailCataloguePage> createState() => _TrailCataloguePageState();
}

class _TrailCataloguePageState extends State<TrailCataloguePage> {
  late HikingAbility _ability = widget.ability;
  late TrailConditions _conditions = widget.conditions;

  @override
  Widget build(BuildContext context) {
    final suggestions = suggestTrails(
      trails: widget.trails,
      ability: _ability,
      conditions: _conditions,
    );
    final suitable = suggestions
        .where((suggestion) => suggestion.fit != TrailFit.tooDemanding)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover trails'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        titleTextStyle: const TextStyle(
          color: _ink,
          fontFamily: 'Georgia',
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const Text(
            'Routes near Luchon',
            style: TextStyle(
              color: _ink,
              fontFamily: 'Georgia',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sample catalogue · ${widget.trails.length} routes',
            style: const TextStyle(color: Color(0xFF777E79), fontSize: 11),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<HikingAbility>(
                  key: const Key('catalogue-ability'),
                  initialValue: _ability,
                  decoration: const InputDecoration(
                    labelText: 'Ability',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  items: HikingAbility.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _ability = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<TrailConditions>(
                  key: const Key('catalogue-conditions'),
                  initialValue: _conditions,
                  decoration: const InputDecoration(
                    labelText: 'Conditions',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  items: TrailConditions.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _conditions = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$suitable of ${widget.trails.length} routes fit your level in '
            '${_conditions.label.toLowerCase()} conditions.',
            style: const TextStyle(
              color: Color(0xFF68716B),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          for (final suggestion in suggestions)
            _TrailTile(
              suggestion: suggestion,
              onTap: () => _showDetails(suggestion),
            ),
          const SizedBox(height: 4),
          const Text(
            'Sample catalogue bundled with TrailOff. Distances, access and '
            'current conditions must be checked with local sources before you '
            'rely on them.',
            style: TextStyle(color: Color(0xFF858B86), fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _showDetails(TrailSuggestion suggestion) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFAFBF9),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _TrailDetails(
        suggestion: suggestion,
        conditions: _conditions,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _TrailTile extends StatelessWidget {
  const _TrailTile({required this.suggestion, required this.onTap});

  final TrailSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trail = suggestion.trail;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B24352C),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('trail-${trail.id}'),
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trail.name,
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trail.area,
                            style: const TextStyle(
                              color: Color(0xFF777E79),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FitBadge(fit: suggestion.fit),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  '${trail.distanceLabel} · ${trail.ascentLabel} ascent · '
                  '${trail.durationLabel}',
                  style: const TextStyle(
                    color: Color(0xFF5F6862),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  trail.summary,
                  style: const TextStyle(
                    color: Color(0xFF68716B),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FitBadge extends StatelessWidget {
  const _FitBadge({required this.fit});

  final TrailFit fit;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (fit) {
      TrailFit.comfortable => (
        const Color(0xFFE7F3EC),
        const Color(0xFF2F7154),
      ),
      TrailFit.stretch => (const Color(0xFFFBF1DF), const Color(0xFF8A5D1F)),
      TrailFit.tooDemanding => (
        const Color(0xFFF8EAE7),
        const Color(0xFF95493D),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        fit.label,
        style: TextStyle(
          color: foreground,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _TrailDetails extends StatelessWidget {
  const _TrailDetails({
    required this.suggestion,
    required this.conditions,
    required this.onClose,
  });

  final TrailSuggestion suggestion;
  final TrailConditions conditions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final trail = suggestion.trail;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DEDA),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    trail.name,
                    style: const TextStyle(
                      color: _ink,
                      fontFamily: 'Georgia',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _FitBadge(fit: suggestion.fit),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              trail.area,
              style: const TextStyle(color: Color(0xFF777E79), fontSize: 11),
            ),
            const SizedBox(height: 12),
            Text(
              trail.summary,
              style: const TextStyle(
                color: Color(0xFF3F4742),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _DetailStat(label: 'Distance', value: trail.distanceLabel),
                _DetailStat(label: 'Ascent', value: trail.ascentLabel),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _DetailStat(label: 'Time', value: trail.durationLabel),
                _DetailStat(
                  label: 'High point',
                  value: '${trail.highestPointMeters} m',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              trailFitReason(suggestion.fit),
              key: const Key('trail-fit-reason'),
              style: const TextStyle(
                color: Color(0xFF5F6862),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'GOOD TO KNOW',
              style: TextStyle(
                color: _forest,
                fontWeight: FontWeight.w800,
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            for (final note in trail.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: SizedBox(
                        width: 5,
                        height: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _forest,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note,
                        style: const TextStyle(
                          color: Color(0xFF68716B),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Fit judged from your ability and ${conditions.label.toLowerCase()} '
              'conditions. The app does not know about closures or the weather '
              'on the day.',
              style: const TextStyle(color: Color(0xFF858B86), fontSize: 10),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(foregroundColor: _forest),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF858B86),
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
