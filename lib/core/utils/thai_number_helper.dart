/// Converts integers (0-99) to Thai words.
String convertToThaiWords(int val) {
  if (val == 0) return 'ศูนย์';

  final units = [
    '',
    'หนึ่ง',
    'สอง',
    'สาม',
    'สี่',
    'ห้า',
    'หก',
    'เจ็ด',
    'แปด',
    'เก้า',
  ];

  if (val < 10) {
    return units[val];
  }

  if (val < 100) {
    final tens = val ~/ 10;
    final ones = val % 10;

    String tensStr = '';
    if (tens == 1) {
      tensStr = 'สิบ';
    } else if (tens == 2) {
      tensStr = 'ยี่สิบ';
    } else {
      tensStr = '${units[tens]}สิบ';
    }

    String onesStr = '';
    if (ones == 1) {
      onesStr = 'เอ็ด';
    } else if (ones > 1) {
      onesStr = units[ones];
    }

    return '$tensStr$onesStr';
  }

  return val.toString(); // Fallback for 100+
}

bool shouldPrepareToGo(int countdown) => countdown >= 1 && countdown <= 5;
