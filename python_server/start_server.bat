@echo off
echo ===================================
echo   파킨슨병 Eye Tracking API 서버 시작
echo ===================================
echo.

cd /d "%~dp0"

echo Python 가상환경 확인...
if not exist "venv" (
    echo 가상환경을 생성합니다...
    python -m venv venv
    call venv\Scripts\activate.bat
    echo 패키지를 설치합니다...
    pip install -r requirements.txt
) else (
    echo 가상환경 활성화...
    call venv\Scripts\activate.bat
)

echo.
echo 🚀 서버 시작...
echo 📊 MediaPipe 기반 눈 추적 분석
echo 🌐 서버 주소: http://localhost:8000
echo 📖 API 문서: http://localhost:8000/docs
echo.
echo 서버를 중지하려면 Ctrl+C를 누르세요
echo.

python main.py

pause