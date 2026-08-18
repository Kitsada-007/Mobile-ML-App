class CountdownReadingStabilizer {
  CountdownReadingStabilizer({
    this.requiredMatches = 2,
    this.maximumStepDown = 3,
  }) {
    assert(requiredMatches > 0);
    assert(maximumStepDown > 0);
  }

  final int requiredMatches;
  final int maximumStepDown;

  String? _candidate;
  int _candidateMatches = 0;
  int? _acceptedValue;

  String? get acceptedReading => _acceptedValue?.toString();

  String? add(String? reading) {
    final normalized = reading?.trim();
    final int? value;
    if (normalized == null) {
      value = null;
    } else {
      value = int.tryParse(normalized);
    }
    if (value == null || value < 0 || value > 99) {
      _clearCandidate();
      return null;
    }

    final canonical = value.toString();
    final previous = _acceptedValue;

    // หากเป็นการนับถอยหลังปกติ (ลดลง 1) หรือตัวเลขเดิมในช่วงวินาทีเดิม (ลดลง 0)
    // ให้ยอมรับค่านั้นทันทีเพื่อขจัดดีเลย์ในแอป Realtime
    if (previous != null) {
      final stepDown = previous - value;
      if (stepDown == 0 || stepDown == 1) {
        _acceptedValue = value;
        _clearCandidate();
        return canonical;
      }
    }

    if (_candidate == canonical) {
      _candidateMatches += 1;
    } else {
      _candidate = canonical;
      _candidateMatches = 1;
    }

    if (_candidateMatches < requiredMatches) return null;

    if (previous != null) {
      final stepDown = previous - value;
      if (stepDown < 0) {
        if (_candidateMatches < requiredMatches + 2) return null;
      } else if (stepDown > maximumStepDown &&
          _candidateMatches < requiredMatches + 1) {
        return null;
      }
    }

    _acceptedValue = value;
    return canonical;
  }

  void reset() {
    _acceptedValue = null;
    _clearCandidate();
  }

  void _clearCandidate() {
    _candidate = null;
    _candidateMatches = 0;
  }
}
