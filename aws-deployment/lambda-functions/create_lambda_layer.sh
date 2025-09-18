#!/bin/bash

# AWS Lambda Eye Tracking Layer 생성 스크립트
# OpenCV + MediaPipe + NumPy + Pandas 포함

echo "🚀 Lambda Layer 생성을 시작합니다..."

# 임시 디렉토리 생성
LAYER_DIR="lambda_layer"
rm -rf $LAYER_DIR
mkdir -p $LAYER_DIR/python

echo "📦 Python 패키지 설치 중..."

# Python 3.9 사용 (Lambda Runtime 호환)
pip install --target $LAYER_DIR/python \
    opencv-python-headless==4.8.1.78 \
    mediapipe==0.10.7 \
    numpy==1.24.4 \
    pandas==2.0.3 \
    --no-deps

# 불필요한 파일 제거
echo "🧹 불필요한 파일 정리 중..."
find $LAYER_DIR/python -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find $LAYER_DIR/python -name "*.pyc" -delete
find $LAYER_DIR/python -name "*.pyo" -delete
find $LAYER_DIR/python -name "*.so" -exec strip {} \; 2>/dev/null || true

# ZIP 파일 생성
echo "📁 ZIP 파일 생성 중..."
cd $LAYER_DIR
zip -r9 ../eye_tracking_layer.zip .
cd ..

# 정리
rm -rf $LAYER_DIR

echo "✅ Layer 생성 완료: eye_tracking_layer.zip"
echo "📏 파일 크기: $(du -h eye_tracking_layer.zip | cut -f1)"

# AWS CLI로 Layer 업로드 (선택사항)
read -p "AWS에 Layer를 업로드하시겠습니까? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "⬆️ AWS Lambda Layer 업로드 중..."
    aws lambda publish-layer-version \
        --layer-name eye-tracking-dependencies \
        --description "OpenCV, MediaPipe, NumPy, Pandas for Eye Tracking" \
        --zip-file fileb://eye_tracking_layer.zip \
        --compatible-runtimes python3.9 python3.10 python3.11
    echo "✅ Layer 업로드 완료!"
fi