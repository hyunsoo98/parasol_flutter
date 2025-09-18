# 📁 S3 버킷 구조 (단순화)

## 🏪 **seoul-ht-09 버킷 구조**

```
seoul-ht-09/
├── eye-tracking/
│   └── {analysis_id}/
│       ├── video.mp4           # 업로드된 원본 비디오
│       └── result.json         # 분석 결과
│
├── finger-tapping/
│   └── {analysis_id}/
│       ├── video.mp4           # 업로드된 원본 비디오
│       └── result.json         # 분석 결과
│
├── voice-analysis/
│   └── {analysis_id}/
│       ├── audio.wav           # 업로드된 원본 오디오
│       └── result.json         # 분석 결과
│
└── diagnosis/
    └── {session_id}/
        └── comprehensive.json  # 종합 진단 결과
```

## 🔧 **Lambda에서 사용할 S3 경로**

```python
# 업로드 시
upload_key = f"{analysis_type}/{analysis_id}/{filename}"

# 결과 저장 시
result_key = f"{analysis_type}/{analysis_id}/result.json"

# 종합 진단
diagnosis_key = f"diagnosis/{session_id}/comprehensive.json"
```

## 📊 **분석 ID 규칙**
```
eye_20240917_abc123
finger_20240917_def456
voice_20240917_ghi789
```

**끝!** 이게 전부입니다. 🎯