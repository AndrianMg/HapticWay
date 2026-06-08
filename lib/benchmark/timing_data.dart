class TimingData {
  final int preprocessMs;
  final int inferMs;
  int get totalMs => preprocessMs + inferMs;

  const TimingData({required this.preprocessMs, required this.inferMs});
}
