enum CaptionStyle {
  readable('Readable', 'Complete phrases, easy to read.'),
  cue('Cue', 'Words rise in. Your marked emphasis stands out.'),
  punch('Punch', 'A few bold words at a time.'),
  karaoke('Karaoke', 'Words light up as you say them.');

  const CaptionStyle(this.label, this.description);
  final String label, description;
}
