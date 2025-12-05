import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
// Conditional import for web downloading
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum ImageStyle {
  cuteAnime('Cute Anime', 'cute anime style, chibi, vibrant colors, kawaii'),
  anime('Anime', 'anime style, manga, high quality, detailed, studio ghibli'),
  realistic('Realistic', 'photorealistic, realistic, 8k, cinematic lighting, high detail, photography');

  final String label;
  final String promptSuffix;
  const ImageStyle(this.label, this.promptSuffix);
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _promptController = TextEditingController();
  ImageStyle _selectedStyle = ImageStyle.anime;
  String? _generatedImageUrl;
  bool _isLoading = false;
  Uint8List? _imageBytes;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generateImage() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _generatedImageUrl = null;
      _imageBytes = null;
    });

    try {
      // Using Pollinations.ai for unlimited free generation
      // Format: https://image.pollinations.ai/prompt/{prompt}?width={w}&height={h}&seed={seed}&nologo=true
      final seed = Random().nextInt(1000000);
      final fullPrompt = '$prompt, ${_selectedStyle.promptSuffix}';
      final encodedPrompt = Uri.encodeComponent(fullPrompt);
      final url = 'https://image.pollinations.ai/prompt/$encodedPrompt?width=1024&height=1024&seed=$seed&nologo=true&model=flux';

      // We fetch the image bytes immediately to ensure it loads and to have data ready for saving
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        setState(() {
          _imageBytes = response.bodyBytes;
          _generatedImageUrl = url;
        });
      } else {
        throw Exception('Failed to load image');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveImage() async {
    if (_imageBytes == null) return;

    try {
      if (kIsWeb) {
        // Web download logic
        final blob = html.Blob([_imageBytes!]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = 'generated_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        html.document.body!.children.add(anchor);
        anchor.click();
        html.document.body!.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image downloading...')),
        );
      } else {
        // Mobile/Desktop logic would go here (omitted for web-first preview simplicity)
        // Typically involves path_provider and writing to file
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saving is optimized for Web in this demo')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save image: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Image Generator'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Input Section
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _promptController,
                      decoration: InputDecoration(
                        hintText: 'Describe your image (e.g., "A futuristic city")',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _promptController.clear,
                        ),
                      ),
                      maxLines: 3,
                      minLines: 1,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select Style',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      alignment: WrapAlignment.center,
                      children: ImageStyle.values.map((style) {
                        return ChoiceChip(
                          label: Text(style.label),
                          selected: _selectedStyle == style,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedStyle = style;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _generateImage,
                        icon: _isLoading 
                            ? const SizedBox(
                                width: 24, 
                                height: 24, 
                                child: CircularProgressIndicator(strokeWidth: 2)
                              ) 
                            : const Icon(Icons.auto_awesome),
                        label: Text(
                          _isLoading ? 'Generating...' : 'Generate Image',
                          style: const TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Result Section
            if (_imageBytes != null) ...[
              Card(
                elevation: 8,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Image.memory(
                      _imageBytes!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(seconds: 1),
                          curve: Curves.easeOut,
                          child: child,
                        );
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              // Share functionality could go here
                            },
                            icon: const Icon(Icons.share),
                            label: const Text('Share'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _saveImage,
                            icon: const Icon(Icons.download),
                            label: const Text('Save JPEG'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!_isLoading) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(Icons.image_search, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Enter a prompt and select a style to start creating!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
