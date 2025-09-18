# 🌐 S3 버킷 CORS 설정 (AWS Console)

## 🎯 **seoul-ht-09 버킷 CORS 설정**

### **Step 1: S3 콘솔 접속**
1. AWS Console → **S3** 서비스 이동
2. **seoul-ht-09** 버킷 클릭

### **Step 2: Permissions 탭 이동**
1. 버킷 상세 페이지에서 **Permissions** 탭 클릭
2. 페이지 하단의 **Cross-origin resource sharing (CORS)** 섹션 찾기

### **Step 3: CORS 설정 편집**
1. **Cross-origin resource sharing (CORS)** 섹션에서 **Edit** 버튼 클릭
2. 기존 설정이 있다면 모두 삭제
3. 아래 CORS 설정 입력:

```json
[
    {
        "AllowedHeaders": [
            "*"
        ],
        "AllowedMethods": [
            "GET",
            "PUT",
            "POST",
            "DELETE",
            "HEAD"
        ],
        "AllowedOrigins": [
            "*"
        ],
        "ExposeHeaders": [
            "ETag",
            "x-amz-request-id"
        ],
        "MaxAgeSeconds": 3000
    }
]
```

### **Step 4: 설정 저장**
1. **Save changes** 버튼 클릭
2. 설정이 저장되었는지 확인

## ✅ **설정 확인**

### **CORS 규칙 확인**
- **AllowedOrigins**: `*` (모든 도메인에서 접근 허용)
- **AllowedMethods**: `GET, PUT, POST, DELETE, HEAD` (모든 HTTP 메서드)
- **AllowedHeaders**: `*` (모든 헤더 허용)
- **ExposeHeaders**: `ETag, x-amz-request-id` (응답에서 노출할 헤더)
- **MaxAgeSeconds**: `3000` (프리플라이트 요청 캐시 시간)

### **테스트**
이제 Flutter 앱에서 다음과 같은 요청이 가능합니다:
- S3에 파일 업로드 (PUT)
- S3에서 파일 다운로드 (GET)
- 파일 삭제 (DELETE)
- 메타데이터 조회 (HEAD)

## 🚨 **보안 주의사항**

### **Production 환경에서는**
```json
{
    "AllowedOrigins": [
        "https://your-app-domain.com",
        "https://parasol-app.com"
    ]
}
```
실제 앱 도메인만 허용하도록 변경하세요.

### **개발 환경에서는**
```json
{
    "AllowedOrigins": [
        "*",
        "http://localhost:*",
        "https://localhost:*"
    ]
}
```
개발용으로는 현재 설정이 적합합니다.

## 📱 **Flutter에서 사용 예시**

```dart
// S3 업로드 URL (presigned URL 사용)
final uploadUrl = 'https://seoul-ht-09.s3.us-west-1.amazonaws.com/...';

// HTTP 요청시 CORS가 자동으로 처리됩니다
final response = await http.put(
  Uri.parse(uploadUrl),
  headers: {
    'Content-Type': 'video/mp4',
  },
  body: videoBytes,
);
```

**CORS 설정 완료!** 🎯