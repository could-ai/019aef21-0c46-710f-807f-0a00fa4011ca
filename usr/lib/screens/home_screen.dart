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
  realistic('Realistic', 'photorealistic, realistic, 8k, cinematic lighting, high detail, photography'),
  animeScreencap('Anime Screencap', 'anime screencap, retro anime, 90s anime style, blur effect, tv aesthetic'),
  cinema('Cinema', 'cinematic shot, movie scene, dramatic lighting, 35mm, film grain, masterpiece'),
  veryCuteAnime('Very Cute Anime', 'super cute, adorable, moe, pastel colors, soft lighting, masterpiece, high quality');

  final String label;
  final String promptSuffix;
  const ImageStyle(this.label, this.promptSuffix);
}

class GeneratedImage {
  final Uint8List bytes;
  final String url;
  final String prompt;
  final ImageStyle style;
  final int seed;

  GeneratedImage({
    required this.bytes,
    required this.url,
    required this.prompt,
    required this.style,
    required this.seed,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  ImageStyle _selectedStyle = ImageStyle.anime;
  double _numberOfImages = 1;
  bool _isLoading = false;
  
  List<GeneratedImage> _generatedImages = [];
  int? _selectedImageIndex;

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _generateImages() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _generatedImages = [];
      _selectedImageIndex = null;
    });

    try {
      // Create a list of futures to run in parallel
      List<Future<GeneratedImage?>> futures = [];
      
      for (int i = 0; i < _numberOfImages.toInt(); i++) {
        futures.add(_fetchSingleImage(prompt, _selectedStyle));
      }

      final results = await Future.wait(futures);
      
      // Filter out nulls (failed requests)
      final successfulImages = results.whereType<GeneratedImage>().toList();

      setState(() {
        _generatedImages = successfulImages;
        if (_generatedImages.isNotEmpty) {
          // Auto-select the first image if only 1 is generated
          if (_generatedImages.length == 1) {
            _selectedImageIndex = 0;
          }
        }
      });
      
      // Scroll to results
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating images: $e')),
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

  Future<GeneratedImage?> _fetchSingleImage(String prompt, ImageStyle style) async {
    try {
      final seed = Random().nextInt(1000000000); // Larger seed range
      // Construct prompt to follow user exactly, then add style
      final fullPrompt = '$prompt . ${style.promptSuffix}';
      final encodedPrompt = Uri.encodeComponent(fullPrompt);
      
      // Using flux model for better quality
      final url = 'https://image.pollinations.ai/prompt/$encodedPrompt?width=1024&height=1024&seed=$seed&nologo=true&model=flux';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return GeneratedImage(
          bytes: response.bodyBytes,
          url: url,
          prompt: prompt,
          style: style,
          seed: seed,
        );
      }
    } catch (e) {
      debugPrint('Error fetching image: $e');
    }
    return null;
  }

  Future<void> _saveImage(GeneratedImage image) async {
    try {
      if (kIsWeb) {
        final blob = html.Blob([image.bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = 'ai_image_${image.seed}.jpg';
        html.document.body!.children.add(anchor);
        anchor.click();
        html.document.body!.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image downloading...')),
        );
      } else {
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

  void _editSelectedImage() {
    if (_selectedImageIndex == null) return;
    
    final image = _generatedImages[_selectedImageIndex!];
    
    setState(() {
      _promptController.text = image.prompt;
      _selectedStyle = image.style;
    });

    // Scroll back to top to edit
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt loaded for editing. Tweak it and generate again!')),
    );
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
        controller: _scrollController,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    
                    // Style Selection
                    const Text(
                      'Select Style',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
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
                    
                    // Image Count Slider
                    Row(
                      children: [
                        const Text(
                          'Number of Images:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Slider(
                            value: _numberOfImages,
                            min: 1,
                            max: 7,
                            divisions: 6,
                            label: _numberOfImages.round().toString(),
                            onChanged: (value) {
                              setState(() {
                                _numberOfImages = value;
                              });
                            },
                          ),
                        ),
                        Text(
                          _numberOfImages.round().toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    
                    // Generate Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _generateImages,
                        icon: _isLoading 
                            ? const SizedBox(
                                width: 24, 
                                height: 24, 
                                child: CircularProgressIndicator(strokeWidth: 2)
                              ) 
                            : const Icon(Icons.auto_awesome),
                        label: Text(
                          _isLoading ? 'Generating...' : 'Generate Images',
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
            
            // Results Section
            if (_generatedImages.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Results (${_generatedImages.length})',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (_selectedImageIndex != null)
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _editSelectedImage,
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit/Remix'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _saveImage(_generatedImages[_selectedImageIndex!]),
                          icon: const Icon(Icons.download),
                          label: const Text('Save'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 16),
              
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // 2 columns
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: _generatedImages.length,
                itemBuilder: (context, index) {
                  final image = _generatedImages[index];
                  final isSelected = _selectedImageIndex == index;
                  
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedImageIndex = index;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected 
                            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 4)
                            : Border.all(color: Colors.transparent, width: 4),
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              image.bytes,
                              fit: BoxFit.cover,
                            ),
                            if (isSelected)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, color: Colors.white, size: 20),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
                        'Enter a prompt, select a style and count to start creating!',
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
