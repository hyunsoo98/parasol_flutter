@echo off
echo 🚀 Lambda Layer 생성을 시작합니다...

:: 임시 디렉토리 생성
set LAYER_DIR=lambda_layer
if exist %LAYER_DIR% rmdir /s /q %LAYER_DIR%
mkdir %LAYER_DIR%\python

echo 📦 Python 패키지 설치 중...

:: Python 패키지 설치
pip install --target %LAYER_DIR%\python ^
    opencv-python-headless==4.8.1.78 ^
    mediapipe==0.10.7 ^
    numpy==1.24.4 ^
    pandas==2.0.3 ^
    --no-deps

echo 🧹 불필요한 파일 정리 중...

:: __pycache__ 디렉토리 제거
for /d /r %LAYER_DIR%\python %%d in (__pycache__) do @if exist "%%d" rd /s /q "%%d" 2>nul

:: .pyc, .pyo 파일 제거
del /s /q "%LAYER_DIR%\python\*.pyc" 2>nul
del /s /q "%LAYER_DIR%\python\*.pyo" 2>nul

echo 📁 ZIP 파일 생성 중...

:: PowerShell을 사용하여 ZIP 파일 생성
powershell -command "Compress-Archive -Path '%LAYER_DIR%\*' -DestinationPath 'eye_tracking_layer.zip' -Force"

:: 정리
rmdir /s /q %LAYER_DIR%

echo ✅ Layer 생성 완료: eye_tracking_layer.zip

:: 파일 크기 확인
for %%I in (eye_tracking_layer.zip) do echo 📏 파일 크기: %%~zI bytes

echo.
echo 다음 단계:
echo 1. AWS Lambda 콘솔에서 Layer 생성
echo 2. eye_tracking_layer.zip 업로드
echo 3. Runtime: Python 3.9+ 선택

pause