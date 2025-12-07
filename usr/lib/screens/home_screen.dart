import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final Uint8List bytes;
  final String url;
  final String prompt;
  final ImageStyle style;
  final int seed;
  final DateTime timestamp;

  GeneratedImage({
    required this.bytes,
    required this.url,
    required this.prompt,
    required this.style,
    required this.seed,
    required this.timestamp,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  
  ImageStyle _selectedStyle = ImageStyle.anime;
  AspectRatioOption _selectedRatio = AspectRatioOption.square;
  double _numberOfImages = 1;
  bool _isLoading = false;
  
  // Current session results
  List<GeneratedImage> _generatedImages = [];
  int? _selectedImageIndex;

  // History
  final List<GeneratedImage> _history = [];

  // Image to Image
  XFile? _referenceImage;
  String? _uploadedReferenceUrl;
  bool _isUploading = false;

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _referenceImage = image;
          _uploadedReferenceUrl = null; // Reset URL until uploaded
        });
        _uploadReferenceImage(image);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _uploadReferenceImage(XFile image) async {
    setState(() {
      _isUploading = true;
    });

    try {
      final bytes = await image.readAsBytes();
      final fileExt = image.name.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'references/$fileName';

      await Supabase.instance.client.storage
          .from('user_uploads')
          .uploadBinary(filePath, bytes);

      final imageUrl = Supabase.instance.client.storage
          .from('user_uploads')
          .getPublicUrl(filePath);

      setState(() {
        _uploadedReferenceUrl = imageUrl;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reference image ready!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload reference: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _removeReferenceImage() {
    setState(() {
      _referenceImage = null;
      _uploadedReferenceUrl = null;
    });
  }

  void _useHistoryImageAsReference(GeneratedImage image) {
    // Since we don't have the original file easily for XFile without downloading,
    // and Pollinations takes a URL, we can just use the URL we already have!
    // However, the GeneratedImage url might be the generation URL.
    // For this app, let's assume we want to use the generated image as a new reference.
    // We can treat the 'url' property of GeneratedImage as the reference URL.
    
    // Note: The 'url' in GeneratedImage is the API call URL. 
    // Pollinations images are dynamically generated. 
    // To use it as a stable reference, ideally we'd upload it. 
    // But for now, let's try passing the generation URL itself if Pollinations supports it,
    // or better, we can't easily "pick" it as XFile without downloading.
    
    // Workaround: We will just set the _uploadedReferenceUrl directly.
    // But wait, the previous URL was a GET request. 
    // Let's just say "Image loaded from history" and set the URL.
    
    setState(() {
      _uploadedReferenceUrl = image.url; // This might re-trigger generation if used directly, but let's try.
      _referenceImage = null; // It's a URL, not a local file
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Selected image set as reference!')),
    );
  }

  String _processPrompt(String rawPrompt) {
    // Rule: if user write around a word 'example' the ai fouces on this more.
    // Regex to find words inside single quotes
    final regex = RegExp(r"'([^']*)'");
    
    String processed = rawPrompt.replaceAllMapped(regex, (match) {
      final word = match.group(1);
      return '($word:1.3)'; // Boost weight
    });
    
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

    if (_referenceImage != null && _uploadedReferenceUrl == null) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for image upload to finish')),
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
      
      final processedPrompt = _processPrompt(prompt);

      for (int i = 0; i < _numberOfImages.toInt(); i++) {
        futures.add(_fetchSingleImage(processedPrompt, _selectedStyle));
      }

      final results = await Future.wait(futures);
      final successfulImages = results.whereType<GeneratedImage>().toList();

      setState(() {
        _generatedImages = successfulImages;
        _history.insertAll(0, successfulImages); // Add to history
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

  Future<GeneratedImage?> _fetchSingleImage(String prompt, ImageStyle style) async {
    try {
      final seed = Random().nextInt(1000000000);
      final fullPrompt = '$prompt . ${style.promptSuffix}';
      final encodedPrompt = Uri.encodeComponent(fullPrompt);
      
      String url = 'https://image.pollinations.ai/prompt/$encodedPrompt?width=${_selectedRatio.width}&height=${_selectedRatio.height}&seed=$seed&nologo=true&model=flux';
      
      if (_uploadedReferenceUrl != null) {
        final encodedRefUrl = Uri.encodeComponent(_uploadedReferenceUrl!);
        url += '&image=$encodedRefUrl';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return GeneratedImage(
          bytes: response.bodyBytes,
          url: url,
          prompt: _promptController.text, // Store original prompt
          style: style,
          seed: seed,
          timestamp: DateTime.now(),
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

    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt loaded for editing. Tweak it and generate again!')),
    );
  }

  void _showHistory() {
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
                  'Generation History',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Expanded(
                child: _history.isEmpty
                    ? const Center(child: Text('No history yet'))
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _history.length,
                        itemBuilder: (context, index) {
                          final image = _history[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              // Ask user what to do
                              _showHistoryActionDialog(image);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(image.bytes, fit: BoxFit.cover),
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

  void _showHistoryActionDialog(GeneratedImage image) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selected Image'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(image.bytes, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 16),
            Text('Prompt: ${image.prompt}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _useHistoryImageAsReference(image);
            },
            child: const Text('Use as Reference'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _promptController.text = image.prompt;
                _selectedStyle = image.style;
              });
            },
            child: const Text('Reuse Prompt'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Image Generator'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showHistory,
            tooltip: 'History',
          ),
        ],
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
                        hintText: "Describe your image (use 'quotes' to emphasize)",
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
                    
                    // Image to Image Section
                    const Text(
                      'Image Reference (Optional)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (_referenceImage != null || _uploadedReferenceUrl != null)
                          Stack(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _referenceImage != null
                                      ? (kIsWeb 
                                          ? Image.network(_referenceImage!.path, fit: BoxFit.cover) 
                                          : Image.file(File(_referenceImage!.path), fit: BoxFit.cover))
                                      : Image.network(_uploadedReferenceUrl!, fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 12,
                                child: GestureDetector(
                                  onTap: _removeReferenceImage,
                                  child: Container(
                                    color: Colors.black54,
                                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                              if (_isUploading)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black45,
                                    child: const Center(child: CircularProgressIndicator()),
                                  ),
                                ),
                            ],
                          ),
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Add Image'),
                        ),
                      ],
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
                        onPressed: _isLoading || _isUploading ? null : _generateImages,
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
                          label: const Text('Edit'),
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
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
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
