/// One Mithen app listed on the Tools page.
final class const MithenAppInfo({
  required final String name,
  required final String description,
  required final String url,

  /// `.extension` -> ProgId pairs the MithenOS playbook applies for this app.
  final List<(String, String)> associations = const [],
});

const List<String> _viewExtensions = [
  'jpg',
  'jpeg',
  'jfif',
  'jpe',
  'png',
  'gif',
  'bmp',
  'dib',
  'webp',
  'ico',
  'tif',
  'tiff',
  'svg',
  'avif',
  'heic',
  'heif',
  'jxl',
  'jxr',
  'wdp',
  'tga',
  'jp2',
];

const List<String> _pdfExtensions = [
  'pdf',
  'xps',
  'oxps',
  'epub',
  'mobi',
  'cbz',
  'cbr',
  'cb7',
  'cbt',
  'djvu',
  'chm',
  'fb2',
  'azw',
  'azw3',
  'md',
  'markdown',
];

const List<String> _playerExtensions = [
  'mkv',
  'mp4',
  'avi',
  'mov',
  'wmv',
  'webm',
  'm4v',
  'flv',
  'ts',
  'm2ts',
  'mpg',
  'mpeg',
  'vob',
  'rmvb',
  '3gp',
  'ogv',
  'divx',
  'asf',
  'mts',
  'm2t',
];

const List<String> _musicExtensions = [
  'mp3',
  'flac',
  'm4a',
  'm4b',
  'aac',
  'ogg',
  'oga',
  'opus',
  'wav',
  'wma',
  'aiff',
  'aif',
  'ape',
  'wv',
  'mka',
];

const List<String> _zipExtensions = [
  'zip',
  '7z',
  'rar',
  'tar',
  'gz',
  'bz2',
  'xz',
  'iso',
  'cab',
  'lzma',
  'zst',
  'tgz',
];

List<(String, String)> _pairs(
  List<String> extensions,
  String Function(String extension) progIdFor,
) => [for (final String extension in extensions) ('.$extension', progIdFor(extension))];

/// The Mithen apps shown on the Tools page, in playbook install order.
final List<MithenAppInfo> mithenApps = [
  MithenAppInfo(
    name: 'MithenView',
    description: 'Lightweight image viewer & basic editor with OCR & QR code scanner',
    url: 'https://github.com/catchem88/mithen-view',
    associations: _pairs(_viewExtensions, (_) => 'MithenView.Image'),
  ),
  MithenAppInfo(
    name: 'MithenPDF',
    description:
        'Lightweight PDF, ebook reader with OCR, basic edit, signing & form filling support',
    url: 'https://github.com/catchem88/mithen-pdf',
    associations: _pairs(_pdfExtensions, (extension) => 'MithenPDF.$extension'),
  ),
  MithenAppInfo(
    name: 'MithenPlayer',
    description: 'Lightweight video player',
    url: 'https://github.com/catchem88/mithen-player',
    associations: _pairs(_playerExtensions, (extension) => 'mpc-be64.$extension'),
  ),
  MithenAppInfo(
    name: 'MithenMusic',
    description: 'Lightweight music player for local files and support for YouTube Music',
    url: 'https://github.com/catchem88/mithen-music',
    associations: _pairs(_musicExtensions, (_) => 'MithenMusic.Audio'),
  ),
  MithenAppInfo(
    name: 'MithenZip',
    description: 'Lightweight archive reader and maker',
    url: 'https://github.com/catchem88/mithen-zip',
    associations: _pairs(_zipExtensions, (_) => 'MithenZip.Archive'),
  ),
];
