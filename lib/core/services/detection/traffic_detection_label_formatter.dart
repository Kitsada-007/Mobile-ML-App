/// แปลง className จากโมเดลเป็นชื่อไทยทางการสำหรับ UI และเสียง
String videoFormalThaiName(String className) {
  return switch (className) {
    'dont_go_straight_arrow' => 'ป้ายห้ามตรงไป',
    'dont_turn_left' => 'ป้ายห้ามเลี้ยวซ้าย',
    'dont_turn_right' => 'ป้ายห้ามเลี้ยวขวา',
    'go_straight_arrow' => 'ป้ายบังคับให้ตรงไป',
    'green_light_circle' => 'สัญญาณไฟจราจรสีเขียว',
    'off_light' => 'สัญญาณไฟจราจรขัดข้อง',
    'red_light_circle' => 'สัญญาณไฟจราจรสีแดง',
    'sign_number' => 'สัญญาณไฟนับถอยหลัง',
    'turn_left' => 'สัญญาณไฟเลี้ยวซ้าย',
    'turn_right' => 'สัญญาณไฟเลี้ยวขวา',
    'yellow_light' => 'สัญญาณไฟจราจรสีเหลือง',
    _ => className,
  };
}
