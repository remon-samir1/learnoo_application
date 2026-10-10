import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/notes/presentation/widgets/note_attachment_preview.dart';

void main() {
  test('generic binary MIME does not hide an image extension', () {
    expect(NoteAttachment.parse({'url': '/storage/photo.jpg', 'mime_type': 'application/octet-stream'})!.kind, NoteAttachmentKind.image);
    expect(NoteAttachment.parse({'url': '/storage/opaque', 'name': 'photo.PNG', 'mime_type': 'application/octet-stream'})!.kind, NoteAttachmentKind.image);
  });
  test('extensionless binary attachments are probed as images', () {
    expect(NoteAttachment.parse({'url': '/storage/opaque', 'mime_type': 'application/octet-stream'})!.kind, NoteAttachmentKind.unknown);
  });
  test('JSON API attachment relations retain image metadata', () {
    expect(NoteAttachment.parse({'data': {'attributes': {'url': '/storage/photo', 'extension': '.JFIF'}}})!.kind, NoteAttachmentKind.image);
  });
  test('specific video and PDF types remain correct', () {
    expect(NoteAttachment.parse({'url': '/storage/opaque', 'name': 'IMG_0592.mov'})!.kind, NoteAttachmentKind.video);
    expect(NoteAttachment.parse({'url': '/storage/opaque', 'mime_type': 'application/pdf'})!.kind, NoteAttachmentKind.pdf);
  });
}
