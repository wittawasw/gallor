part of '../../../main.dart';

class MediaPreviewTile extends StatelessWidget {
  final MediaPreview? preview;
  final double size;

  const MediaPreviewTile({super.key, required this.preview, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final thumbPath = p?.thumbPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: size,
        height: size,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: p == null
            ? const Icon(Icons.image, size: 20)
            : thumbPath == null
            ? Icon(p.isPdf ? Icons.picture_as_pdf : Icons.movie, size: 20)
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(thumbPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                  ),
                  if (p.isVideo)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  if (p.isPdf)
                    const Positioned(
                      right: 4,
                      bottom: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.all(Radius.circular(3)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            'PDF',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
