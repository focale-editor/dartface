import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Downloads the public-domain detection corpus used by the package tests.
///
/// The images live outside the published package, so a fresh checkout needs to
/// fetch them once before `dart test` can run the corpus suite.
Future<void> main(List<String> arguments) async {
  final Directory directory = Directory('test/corpus/images');
  await directory.create(recursive: true);
  final HttpClient client = HttpClient()..userAgent = _userAgent;
  int failures = 0;
  try {
    for (final CorpusSource source in corpusSources) {
      final File file = File('${directory.path}/${source.fileName}');
      if (await file.exists() && _digestOf(await file.readAsBytes()) == source.sha256) {
        stdout.writeln('up to date  ${source.fileName}');
        continue;
      }
      final List<int> bytes = await _download(client, source.url);
      final String digest = _digestOf(bytes);
      if (digest != source.sha256) {
        stderr.writeln('digest mismatch for ${source.fileName}: expected ${source.sha256}, got $digest');
        failures++;
        continue;
      }
      await file.writeAsBytes(bytes);
      stdout.writeln('downloaded  ${source.fileName} (${bytes.length} bytes)');
    }
  } finally {
    client.close();
  }
  if (failures > 0) {
    stderr.writeln('$failures file(s) could not be verified');
    exitCode = 1;
  }
}

/// Identifies this tool to the Wikimedia servers, as their policy requires.
const String _userAgent = 'DartfaceCorpusBuilder/1.0 (https://github.com/focale-editor/dartface)';

/// One corpus file and the bytes it must contain.
final class CorpusSource {
  /// Describes a downloadable corpus file.
  const CorpusSource({
    required this.fileName,
    required this.url,
    required this.sha256,
  });

  /// Name the file receives inside `test/corpus/images`.
  final String fileName;

  /// Wikimedia Commons thumbnail address.
  final String url;

  /// Lowercase hexadecimal SHA-256 digest of the expected bytes.
  final String sha256;
}

/// Public-domain images making up the corpus.
///
/// Attribution and licensing are recorded in `test/corpus/README.md`.
const List<CorpusSource> corpusSources = <CorpusSource>[
  CorpusSource(
    fileName: 'group_apollo11_crew.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3d/Apollo_11_Crew.jpg/960px-Apollo_11_Crew.jpg',
    sha256: '3eed8f82e006f2accb05cefb0e3f300bbafcff4b516373ae0f94a9defc9e9f65',
  ),
  CorpusSource(
    fileName: 'group_obama_family.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/be/Obama_Family.jpg/960px-Obama_Family.jpg',
    sha256: '7fa64ea98a46bd3507cee1fcfc86717b8f6c4fab6a755900c75ed7c554be8a24',
  ),
  CorpusSource(
    fileName: 'group_solvay_1927.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6e/Solvay_conference_1927.jpg/960px-Solvay_conference_1927.jpg',
    sha256: '0dd9f7ec4af0e0e96f9bf7a53cb6300a3876d0b03cf65142f978c2bf28df385a',
  ),
  CorpusSource(
    fileName: 'negative_big_bend.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e7/Big_Bend_National_Park_PB112573.jpg/500px-Big_Bend_National_Park_PB112573.jpg',
    sha256: '689c3164fc11aa7bbe0f6a9f0e5604b5e9d934ea112979cf0247aa35da0a566d',
  ),
  CorpusSource(
    fileName: 'negative_blue_marble.png',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/23/Blue_Marble_2002.png/500px-Blue_Marble_2002.png',
    sha256: 'f58c04e912885923c83823bd2052f4c35efab60b8811a8fffa65c8a14f2e339f',
  ),
  CorpusSource(
    fileName: 'negative_usda_lab_cat.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/16/USDA_lab_cat.jpg/500px-USDA_lab_cat.jpg',
    sha256: 'fe558bafd3cef1a819495b06a278be4852d6cfb4e8df955451fda8898caa70f6',
  ),
  CorpusSource(
    fileName: 'negative_statue_of_liberty_face.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/93/Face_of_Statue_of_Liberty.jpg/500px-Face_of_Statue_of_Liberty.jpg',
    sha256: 'dfe5332717b30c5a76266a6bdeab31c122c0c1e82914b701d9801ef433c7b880',
  ),
  CorpusSource(
    fileName: 'portrait_albert_einstein.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d3/Albert_Einstein_Head.jpg/500px-Albert_Einstein_Head.jpg',
    sha256: '7411d4bb232192cbf14840f284130a8175c1b07a6a13b00ac2cfbb1a70482652',
  ),
  CorpusSource(
    fileName: 'portrait_buzz_aldrin.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/dc/Buzz_Aldrin.jpg/500px-Buzz_Aldrin.jpg',
    sha256: '4197a7bee2aa13b26ac3eadab962d3be170e5465ff4960d8608d8abaf8fbe9bf',
  ),
  CorpusSource(
    fileName: 'portrait_katherine_johnson.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6d/Katherine_Johnson_1983.jpg/500px-Katherine_Johnson_1983.jpg',
    sha256: 'bab82534bcbe54eb9641baa12978722d51d2bf98774dfbb61b1205fa2fd559a5',
  ),
  CorpusSource(
    fileName: 'portrait_mae_jemison.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/55/Mae_Carol_Jemison.jpg/500px-Mae_Carol_Jemison.jpg',
    sha256: '661245f6400caecb783fbe637192602ab45d987209b561e9db43197ca5cc4dbb',
  ),
  CorpusSource(
    fileName: 'portrait_marie_curie.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/7/7e/Marie_Curie_c1920.jpg/500px-Marie_Curie_c1920.jpg',
    sha256: '3f5c5957f26c007c09a396c7bca04c7d6a9f2821f9d76ad9890b70404b0c048d',
  ),
  CorpusSource(
    fileName: 'portrait_michelle_obama.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/4b/Michelle_Obama_2013_official_portrait.jpg/500px-Michelle_Obama_2013_official_portrait.jpg',
    sha256: '05af74f71144e7485bef551e6cdc5665445c679a00ba2ccde36bb6dc98cbeacb',
  ),
  CorpusSource(
    fileName: 'portrait_neil_armstrong.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0d/Neil_Armstrong_pose.jpg/500px-Neil_Armstrong_pose.jpg',
    sha256: 'ca8e77b433e6d2c865c0b7323229bde07f9cfe8ee2cbb783d79460d5962a53c6',
  ),
  CorpusSource(
    fileName: 'portrait_ruth_bader_ginsburg.jpg',
    url: 'https://upload.wikimedia.org/wikipedia/commons/d/d5/Ruth_Bader_Ginsburg_official_portrait.jpg',
    sha256: 'f5a954d304de50266fe1b277e20dbfa0578fe66dffe728242b54245b788ce377',
  ),
  CorpusSource(
    fileName: 'portrait_sally_ride.jpg',
    url: 'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0c/Sally_Ride_%281984%29.jpg/500px-Sally_Ride_%281984%29.jpg',
    sha256: '9226b628f91279203c1568029535c6a84f3988b1ebc5af3606ebe001adade53d',
  ),
];

/// Fetches [url], following redirects and rejecting error responses.
Future<List<int>> _download(HttpClient client, String url) async {
  final HttpClientRequest request = await client.getUrl(Uri.parse(url));
  final HttpClientResponse response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('Unexpected status ${response.statusCode}', uri: Uri.parse(url));
  }
  final BytesBuilder builder = BytesBuilder(copy: false);
  await response.forEach(builder.add);
  return builder.takeBytes();
}

/// Returns the lowercase hexadecimal SHA-256 digest of [bytes].
String _digestOf(List<int> bytes) => sha256.convert(bytes).toString();
