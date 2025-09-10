import sys
import os

# eyetrack.py 파일이 있는 경로를 Python 경로에 추가
sys.path.append(r'c:\Users\asia\Desktop\vscode')

# eyetrack 모듈에서 FastAPI app 가져오기
from eyetrack import app

if __name__ == "__main__":
    import uvicorn
    
    # 서버 실행 설정
    uvicorn.run(
        "main:app",  # app 객체 참조
        host="0.0.0.0",  # 모든 IP에서 접근 가능
        port=8000,       # 포트 번호
        reload=True      # 코드 변경시 자동 재시작
    )