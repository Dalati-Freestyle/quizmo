import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../l10n/app_localizations.dart';
import 'media_upload.dart';

class ImageOptimizationDialog extends StatefulWidget {
  const ImageOptimizationDialog({required this.original, super.key});

  final MediaAsset original;

  @override
  State<ImageOptimizationDialog> createState() =>
      _ImageOptimizationDialogState();
}

class _ImageOptimizationDialogState extends State<ImageOptimizationDialog> {
  int maxDimension = 2560;
  OptimizedMediaImage? optimized;
  bool working = false;
  String? error;

  Future<void> optimize() async {
    setState(() {
      working = true;
      error = null;
      optimized = null;
    });
    try {
      final result = await optimizeMediaImage(
        widget.original.bytes!,
        maxDimension: maxDimension,
      );
      if (mounted) setState(() => optimized = result);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => error = e is JsonContractException
              ? context.tr('$e')
              : context.tr('Image optimization failed.'),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Widget preview(MediaAsset asset) => SizedBox(
    height: 160,
    width: double.infinity,
    child: Image.memory(
      asset.bytes!,
      fit: BoxFit.contain,
      cacheWidth: 640,
      errorBuilder: (_, _, _) =>
          Center(child: Text(context.tr('Image preview unavailable.'))),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final result = optimized;
    final smaller =
        result != null &&
        result.asset.bytes!.length < widget.original.bytes!.length;
    return AlertDialog(
      title: Text(context.tr('Keep original or optimize image')),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(
                  'The original is preserved by default. Optional resizing keeps the aspect ratio and never enlarges images. PNG encoding is lossless, but resizing removes detail and metadata; the copy may be larger.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('Original: {0} KiB', [
                  (widget.original.bytes!.length / 1024).toStringAsFixed(1),
                ]),
              ),
              preview(widget.original),
              DropdownButtonFormField<int>(
                initialValue: maxDimension,
                decoration: InputDecoration(
                  labelText: context.tr('Maximum edge length (pixels)'),
                ),
                items: [
                  for (final dimension in [3840, 2560, 1920, 1280])
                    DropdownMenuItem(
                      value: dimension,
                      child: Text('$dimension'),
                    ),
                ],
                onChanged: working
                    ? null
                    : (value) => setState(() {
                        maxDimension = value!;
                        optimized = null;
                      }),
              ),
              TextButton(
                onPressed: working ? null : optimize,
                child: Text(context.tr('Preview optimized PNG copy')),
              ),
              if (working) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              if (result != null) ...[
                Text(
                  context.tr(
                    'Optimized: {0} × {1} → {2} × {3} pixels, {4} KiB',
                    [
                      result.originalWidth,
                      result.originalHeight,
                      result.width,
                      result.height,
                      (result.asset.bytes!.length / 1024).toStringAsFixed(1),
                    ],
                  ),
                ),
                preview(result.asset),
                if (!smaller)
                  Text(
                    context.tr(
                      'This PNG copy is not smaller. Keep the original or try a smaller edge length.',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Abbrechen')),
        ),
        if (result != null)
          OutlinedButton(
            onPressed: smaller && !working
                ? () => Navigator.pop(context, result.asset)
                : null,
            child: Text(context.tr('Use optimized copy')),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, widget.original),
          child: Text(context.tr('Keep original')),
        ),
      ],
    );
  }
}
