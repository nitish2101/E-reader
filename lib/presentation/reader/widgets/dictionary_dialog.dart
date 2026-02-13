
import 'package:flutter/material.dart';
import '../../../data/models/dictionary_entry.dart';
import '../../../data/repositories/dictionary_repository.dart';

class DictionaryDialog extends StatefulWidget {
  final String word;

  const DictionaryDialog({super.key, required this.word});

  @override
  State<DictionaryDialog> createState() => _DictionaryDialogState();
}

class _DictionaryDialogState extends State<DictionaryDialog> {
  final DictionaryRepository _repository = DictionaryRepository();
  late Future<List<DictionaryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.getDefinition(widget.word.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.word,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<DictionaryEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No definition found.'));
                }

                final entries = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.phonetic != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              entry.phonetic!,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ),
                        ...entry.meanings.map((meaning) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  meaning.partOfSpeech,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                ...meaning.definitions.map((def) {
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('• ${def.definition}'),
                                        if (def.example != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2.0, left: 8.0),
                                            child: Text(
                                              '"${def.example}"',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                        const Divider(),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
