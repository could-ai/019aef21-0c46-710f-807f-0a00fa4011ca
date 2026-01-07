import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
// Conditional import for web downloading
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum ImageStyle {
  raw('Raw (Exact Prompt)', ''), // New style for exact prompt adherence
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

enum ModelType {
  normal('Normal', 'flux'),
  medri('Medri', 'flux'), // Specialized in backgrounds, using flux model
  misdo('Misdo.ai', 'flux-dev'); // Advanced model with high accuracy, using flux-dev

  final String label;
  final String modelParam;
  const ModelType(this.label, this.modelParam);
}

enum AgeRating {
  kid('9-13 (Safe)', 'safe, child-friendly, no adult content, appropriate for children, family-friendly, wholesome'),
  teen('14-17 (Bold)', 'teen-appropriate, some boldness, no explicit adult content, tasteful, moderate'),
  adult('18+ (Adult)', 'adult content, explicit, sensual, erotic, may include nudity, mature themes');

  final String label;
  final String promptModifier;
  const AgeRating(this.label, this.promptModifier);
}

enum AspectRatioOption {
  square('Square (1:1)', 1024, 1024),
  portrait('Portrait (3:4)', 768, 1024),
  landscape('Landscape (4:3)', 1024, 768);

  final String label;
  final int width;
  final int height;
  const AspectRatioOption(this.label, this.width, this.height);
}

class GeneratedImage {
  final Uint8List? bytes; // Can be null if loaded from history without bytes
  final String url;
  final String prompt;
  final ImageStyle style;
  final ModelType model;
  final AgeRating ageRating;
  final int seed;
  final DateTime timestamp;

  GeneratedImage({
    this.bytes,
    required this.url,
    required this.prompt,
    required this.style,
    required this.model,
    required this.ageRating,
    required this.seed,
    required this.timestamp,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  ImageStyle _selectedStyle = ImageStyle.raw; // Default to Raw for exact adherence
  ModelType _selectedModel = ModelType.normal; // Default model
  AgeRating _selectedAgeRating = AgeRating.kid; // Default to safe
  AspectRatioOption _selectedRatio = AspectRatioOption.square;
  double _numberOfImages = 1;
  bool _isLoading = false;
  
  // Current session results
  List<GeneratedImage> _generatedImages = [];
  int? _selectedImageIndex;

  // Saved images
  List<GeneratedImage> _savedImages = [];

  @override
  void initState() {
    super.initState();
    _loadSavedImages();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getStringList('saved_images') ?? [];
      
      final List<GeneratedImage> loadedImages = [];
      for (var jsonStr in savedData) {
        // Parse JSON and recreate GeneratedImage
        // For simplicity, we'll store minimal data
        final parts = jsonStr.split('|');
        if (parts.length >= 4) {
          final url = parts[0];
          final prompt = parts[1];
          final style = ImageStyle.values.firstWhere(
            (s) => s.label == parts[2],
            orElse: () => ImageStyle.raw,
          );
          final model = ModelType.values.firstWhere(
            (m) => m.label == parts[3],
            orElse: () => ModelType.normal,
          );
          final ageRating = parts.length > 4 ? AgeRating.values.firstWhere(
            (a) => a.label == parts[4],
            orElse: () => AgeRating.kid,
          ) : AgeRating.kid;
          final seed = int.tryParse(parts[5] ?? '0') ?? 0;
          
          loadedImages.add(GeneratedImage(
            url: url,
            prompt: prompt,
            style: style,
            model: model,
            ageRating: ageRating,
            seed: seed,
            timestamp: DateTime.now(), // Approximate timestamp
            bytes: null,
          ));
        }
      }
      
      if (mounted) {
        setState(() {
          _savedImages = loadedImages;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved images: $e');
    }
  }

  Future<void> _saveImageToStorage(GeneratedImage image) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getStringList('saved_images') ?? [];
      
      // Create a simple string representation
      final dataStr = '${image.url}|${image.prompt}|${image.style.label}|${image.model.label}|${image.ageRating.label}|${image.seed}';
      savedData.add(dataStr);
      
      await prefs.setStringList('saved_images', savedData);
      
      setState(() {
        _savedImages.add(image);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image saved successfully!')),
      );
    } catch (e) {
      debugPrint('Error saving image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save image')),
      );
    }
  }

  String _processPrompt(String rawPrompt, AgeRating ageRating) {
    // Rule: if user write around a word 'example' the ai fouces on this more.
    final regex = RegExp(r"'([^']*)'");
    
    String processed = rawPrompt.replaceAllMapped(regex, (match) {
      final word = match.group(1);
      return '($word:1.5)'; // Increased boost weight for better adherence
    });
    
    // Add age rating specific content
    if (ageRating == AgeRating.adult) {
      // For 18+, add explicit content even if not specified
      if (!processed.toLowerCase().contains('naked') && 
          !processed.toLowerCase().contains('nude') &&
          !processed.toLowerCase().contains('erotic') &&
          !processed.toLowerCase().contains('sensual')) {
        processed += ', sensual, alluring, seductive';
      }
    } else if (ageRating == AgeRating.teen) {
      // For teens, ensure moderate boldness
      processed += ', tasteful, appealing';
    } else {
      // For kids, ensure completely safe
      processed += ', wholesome, innocent, pure';
    }
    
    return processed;
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
      List<Future<GeneratedImage?>> futures = [];
      
      final processedPrompt = _processPrompt(prompt, _selectedAgeRating);

      for (int i = 0; i < _numberOfImages.toInt(); i++) {
        futures.add(_fetchSingleImage(processedPrompt, _selectedStyle, _selectedModel, _selectedAgeRating));
      }

      final results = await Future.wait(futures);
      final successfulImages = results.whereType<GeneratedImage>().toList();

      setState(() {
        _generatedImages = successfulImages;
        if (_generatedImages.isNotEmpty) {
          if (_generatedImages.length == 1) {
            _selectedImageIndex = 0;
          }
        }
      });

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

  Future<GeneratedImage?> _fetchSingleImage(String prompt, ImageStyle style, ModelType model, AgeRating ageRating) async {
    try {
      final seed = Random().nextInt(1000000000);
      
      // Construct prompt based on style
      String fullPrompt = prompt;
      if (style != ImageStyle.raw) {
        fullPrompt = '$prompt . ${style.promptSuffix}';
      }
      
      // Add age rating modifier
      fullPrompt += ', ${ageRating.promptModifier}';
      
      final encodedPrompt = Uri.encodeComponent(fullPrompt);
      
      // Age-specific negative prompts
      String negativePrompt = 'blur, low quality, distortion, ugly, pixelated, bad anatomy, extra limbs, watermark, text';
      if (ageRating == AgeRating.kid) {
        negativePrompt += ', adult, sexual, violence, scary, inappropriate';
      } else if (ageRating == AgeRating.teen) {
        negativePrompt += ', explicit nudity, pornography, extreme violence';
      }
      // For adult, allow more content
      
      final encodedNegative = Uri.encodeComponent(negativePrompt);
      
      // Use selected model parameter
      // enhance=false ensures exact prompt adherence
      // nologo=true removes watermarks
      String url = 'https://image.pollinations.ai/prompt/$encodedPrompt?width=${_selectedRatio.width}&height=${_selectedRatio.height}&seed=$seed&nologo=true&model=${model.modelParam}&enhance=false&negative_prompt=$encodedNegative';
      
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return GeneratedImage(
          bytes: response.bodyBytes,
          url: url,
          prompt: _promptController.text, // Store original prompt
          style: style,
          model: model,
          ageRating: ageRating,
          seed: seed,
          timestamp: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('Error fetching image: $e');
    }
    return null;
  }

  Future<void> _downloadImage(GeneratedImage image) async {
    try {
      if (kIsWeb) {
        // If we have bytes, use them. If not (history item), fetch them first.
        Uint8List? bytes = image.bytes;
        if (bytes == null) {
           final response = await http.get(Uri.parse(image.url));
           if (response.statusCode == 200) {
             bytes = response.bodyBytes;
           } else {
             throw Exception('Failed to download image data');
           }
        }

        final blob = html.Blob([bytes]);
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
          const SnackBar(content: Text('Downloading is optimized for Web in this demo')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download image: $e')),
      );
    }
  }

  void _editSelectedImage() {
    if (_selectedImageIndex == null) return;
    
    final image = _generatedImages[_selectedImageIndex!];
    
    setState(() {
      _promptController.text = image.prompt;
      _selectedStyle = image.style;
      _selectedModel = image.model;
      _selectedAgeRating = image.ageRating;
    });

    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt loaded for editing. Tweak it and generate again!')),
    );
  }

  void _showSavedImages() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Saved Images (${_savedImages.length})',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Expanded(
                child: _savedImages.isEmpty
                    ? const Center(child: Text('No saved images yet'))
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _savedImages.length,
                        itemBuilder: (context, index) {
                          final image = _savedImages[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _showSavedImageActionDialog(image);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  image.bytes != null 
                                    ? Image.memory(image.bytes!, fit: BoxFit.cover)
                                    : Image.network(image.url, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Center(child: Icon(Icons.error))),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      color: Colors.black54,
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        image.prompt,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSavedImageActionDialog(GeneratedImage image) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saved Image'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: image.bytes != null 
                  ? Image.memory(image.bytes!, fit: BoxFit.cover)
                  : Image.network(image.url, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 16),
            Text('Prompt: ${image.prompt}'),
            Text('Style: ${image.style.label}'),
            Text('Model: ${image.model.label}'),
            Text('Age Rating: ${image.ageRating.label}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _promptController.text = image.prompt;
                _selectedStyle = image.style;
                _selectedModel = image.model;
                _selectedAgeRating = image.ageRating;
              });
            },
            child: const Text('Reuse Prompt'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadImage(image);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Image Generator'),
        centerTitle: true,
        elevation: 2,
        shadowColor: Theme.of(context).colorScheme.shadow,
        leading: IconButton(
          icon: const Icon(Icons.logout),
          onPressed: _signOut,
          tooltip: 'Sign Out',
        ),
        actions: [
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              themeProvider.toggleTheme();
            },
            tooltip: 'Toggle Theme',
          ),
          IconButton(
            icon: const Icon(Icons.bookmark),
            onPressed: _showSavedImages,
            tooltip: 'Saved Images',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Input Section
              Card(
                elevation: 8,
                shadowColor: Theme.of(context).colorScheme.shadow.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create Your Image',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _promptController,
                          decoration: InputDecoration(
                            hintText: "Describe your image (use 'quotes' to emphasize)",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            prefixIcon: const Icon(Icons.edit),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _promptController.clear,
                            ),
                          ),
                          maxLines: 3,
                          minLines: 1,
                        ),
                        const SizedBox(height: 20),
                        
                        // Age Rating Selection - NEW FEATURE
                        const Text(
                          'Age Rating',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.error.withOpacity(0.3),
                            ),
                          ),
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: AgeRating.values.map((rating) {
                              final isSelected = _selectedAgeRating == rating;
                              return ChoiceChip(
                                label: Text(rating.label),
                                selected: isSelected,
                                selectedColor: rating == AgeRating.adult 
                                  ? Theme.of(context).colorScheme.error.withOpacity(0.8)
                                  : rating == AgeRating.teen
                                    ? Theme.of(context).colorScheme.secondary.withOpacity(0.8)
                                    : Theme.of(context).colorScheme.primary.withOpacity(0.8),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedAgeRating = rating;
                                    });
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Style Selection
                        const Text(
                          'Art Style',
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

                        // Model Selection
                        const Text(
                          'AI Model',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: ModelType.values.map((model) {
                            return ChoiceChip(
                              label: Text(model.label),
                              selected: _selectedModel == model,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedModel = model;
                                  });
                                }
                              },
                            );
                          }).toList(),
                        ),
                        
                        const SizedBox(height: 16),

                        // Aspect Ratio Selection
                        const Text(
                          'Aspect Ratio',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: AspectRatioOption.values.map((ratio) {
                            return ChoiceChip(
                              label: Text(ratio.label),
                              selected: _selectedRatio == ratio,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedRatio = ratio;
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
                              'Count:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Slider(
                                value: _numberOfImages,
                                min: 1,
                                max: 4, // Limit to 4
                                divisions: 3,
                                label: _numberOfImages.round().toString(),
                                onChanged: (value) {
                                  setState(() {
                                    _numberOfImages = value;
                                  });
                                },
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _numberOfImages.round().toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        
                        // Generate Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
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
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              elevation: 4,
                              shadowColor: Theme.of(context).colorScheme.shadow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                      'Generated Images (${_generatedImages.length})',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_selectedImageIndex != null)
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _editSelectedImage,
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _downloadImage(_generatedImages[_selectedImageIndex!]),
                            icon: const Icon(Icons.download),
                            label: const Text('Download'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: _selectedRatio.width / _selectedRatio.height,
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
                          borderRadius: BorderRadius.circular(16),
                          border: isSelected 
                              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 4)
                              : Border.all(color: Colors.transparent, width: 4),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              image.bytes != null 
                                ? Image.memory(image.bytes!, fit: BoxFit.cover)
                                : Image.network(image.url, fit: BoxFit.cover),
                              if (isSelected)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.check,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              // Save button for each image
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: FloatingActionButton.small(
                                  onPressed: () => _saveImageToStorage(image),
                                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                  foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                                  elevation: 4,
                                  child: const Icon(Icons.bookmark_add),
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
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.image_search, 
                          size: 80, 
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Enter a prompt, select options and generate!',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}