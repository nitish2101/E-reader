String validPdf() {
  var result = '%PDF-1.4\n';
  final offsets = <int>[0];
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents 4 0 R >>',
    '<< /Length 0 >>\nstream\n\nendstream',
  ];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(result.length);
    result += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final xref = result.length;
  result += 'xref\n0 5\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    result += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  return '${result}trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
}
