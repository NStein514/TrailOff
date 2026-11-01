import 'package:flutter/material.dart';

import 'trail_guide.dart';

const _forest = Color(0xFF3E8967);
const _ink = Color(0xFF292D2B);
const _paper = Color(0xFFF0F7F2);

/// Asks questions of trail information the user has downloaded for offline
/// use. Answers always quote one section of the guide and name their source.
class TrailAnswers extends StatefulWidget {
  const TrailAnswers({super.key, this.store, this.guide = tourTrailGuide});

  final TrailGuideStore? store;
  final TrailGuide guide;

  @override
  State<TrailAnswers> createState() => _TrailAnswersState();
}

class _TrailAnswersState extends State<TrailAnswers> {
  late final TrailGuideStore _store;
  final _questionController = TextEditingController();
  TrailGuide? _saved;
  TrailAnswer? _answer;
  String? _asked;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? SharedPreferencesTrailGuideStore();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await _store.load(widget.guide.id);
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Saved trail info could not be read. Download it again.';
      });
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _store.save(widget.guide);
      if (!mounted) return;
      setState(() {
        _saved = widget.guide;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Trail info could not be saved on this device.';
      });
    }
  }

  void _ask(String value) {
    final question = value.trim();
    final guide = _saved;
    if (question.isEmpty || guide == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _asked = question;
      _answer = answerTrailQuestion(guide: guide, question: question);
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('trail-answers'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B24352C),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.menu_book_rounded, color: _forest, size: 19),
              SizedBox(width: 8),
              Text(
                'Trail answers',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ask the ${widget.guide.name} notes you keep offline.',
            style: const TextStyle(color: Color(0xFF777E79), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Text(
              'Looking for saved trail info…',
              style: TextStyle(color: Color(0xFF777E79), fontSize: 12),
            )
          else if (_saved == null)
            _downloadPrompt()
          else
            ..._questionFlow(_saved!),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFF9B4B3F), fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Sample guide bundled with TrailOff. Answers are quoted from the '
            'downloaded text only — no live weather or closure data. Verify '
            'access, rules and hazards with local sources.',
            style: TextStyle(color: Color(0xFF858B86), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _downloadPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Download the ${widget.guide.sections.length}-section guide '
          '(${widget.guide.region}) to ask questions with no signal.',
          style: const TextStyle(color: Color(0xFF68716B), fontSize: 12),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          key: const Key('trail-download'),
          onPressed: _busy ? null : _download,
          icon: const Icon(Icons.download_for_offline_outlined, size: 18),
          label: Text(_busy ? 'Saving…' : 'Download trail info'),
          style: FilledButton.styleFrom(
            backgroundColor: _paper,
            foregroundColor: _forest,
          ),
        ),
      ],
    );
  }

  List<Widget> _questionFlow(TrailGuide guide) {
    return [
      Row(
        children: [
          const Icon(Icons.offline_pin_outlined, color: _forest, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Saved offline · ${guide.sections.length} sections',
              style: const TextStyle(
                color: _forest,
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        key: const Key('trail-question'),
        controller: _questionController,
        textInputAction: TextInputAction.send,
        onSubmitted: _ask,
        decoration: InputDecoration(
          labelText: 'Ask your guide',
          hintText: 'Is there water on the route?',
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          suffixIcon: IconButton(
            key: const Key('trail-ask'),
            tooltip: 'Ask your guide',
            onPressed: () => _ask(_questionController.text),
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          ),
        ),
      ),
      if (_asked != null) ...[
        const SizedBox(height: 12),
        Container(
          key: const Key('trail-answer'),
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.circular(15),
          ),
          child: _answer == null
              ? Text(
                  'Your downloaded guide does not cover that. It has notes '
                  'on: ${guide.sections.map((section) => section.title).join(', ')}.',
                  style: const TextStyle(
                    color: Color(0xFF68716B),
                    fontSize: 11,
                    height: 1.35,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FROM YOUR DOWNLOADED GUIDE',
                      style: TextStyle(
                        color: _forest,
                        fontWeight: FontWeight.w800,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _answer!.quote,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'From ${_answer!.attribution}',
                      style: const TextStyle(
                        color: Color(0xFF68716B),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    ];
  }
}
