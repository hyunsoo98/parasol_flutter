// Web용 flutter_sound 스텁 파일
// Web 빌드에서 flutter_sound 호환성 문제를 해결하기 위한 더미 구현

class FlutterSoundRecorder {
  Future<void> openRecorder() async {
    // Web에서는 아무것도 하지 않음
  }

  Future<void> startRecorder({
    String? toFile,
    dynamic codec,
    int? bitRate,
    int? sampleRate,
  }) async {
    // Web에서는 아무것도 하지 않음
  }

  Future<void> stopRecorder() async {
    // Web에서는 아무것도 하지 않음
  }

  Future<void> closeRecorder() async {
    // Web에서는 아무것도 하지 않음
  }

  bool get isRecording => false;
}

class FlutterSoundPlayer {
  Future<void> openPlayer() async {
    // Web에서는 아무것도 하지 않음
  }

  Future<void> closePlayer() async {
    // Web에서는 아무것도 하지 않음
  }
}

// flutter_sound에서 사용하는 Codec enum 더미
enum Codec {
  aacADTS,
  opusOGG,
  opusCAF,
  mp3,
  vorbisOGG,
  pcm16,
  pcm16WAV,
  pcm16AIFF,
  pcm16CAF,
  flac,
  aacMP4,
  amrNB,
  amrWB,
  pcm8,
  pcmFloat32,
  pcmWebM,
  opusWebM,
  vorbisWebM,
}