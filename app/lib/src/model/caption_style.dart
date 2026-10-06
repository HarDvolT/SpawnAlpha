enum CaptionStyle {
  readable('Readable', 'Complete phrases, easy to read.'),
  karaoke('Karaoke', 'Words light up as you say them.');

  const CaptionStyle(this.label, this.description);
  final String label, description;
}
