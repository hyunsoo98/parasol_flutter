"""
간단한 자체 회원가입/로그인 Lambda 함수
"""

import json
import boto3
import hashlib
import uuid
import os
from datetime import datetime, timedelta

# 환경변수에서 테이블명 가져오기
USERS_TABLE_NAME = os.environ.get('DYNAMODB_TABLE', 'parasol-users')

dynamodb = boto3.resource('dynamodb')
users_table = dynamodb.Table(USERS_TABLE_NAME)

def lambda_handler(event, context):
    """
    통합 인증 Lambda
    /auth/register - 회원가입
    /auth/login - 로그인
    """

    path = event.get('path', '')
    method = event.get('httpMethod', '')

    try:
        if path.endswith('/register') and method == 'POST':
            return handle_register(event)
        elif path.endswith('/login') and method == 'POST':
            return handle_login(event)
        else:
            return {
                'statusCode': 404,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': '지원하지 않는 경로입니다.'})
            }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': str(e)})
        }

def handle_register(event):
    """회원가입 처리"""
    body = json.loads(event['body'])

    email = body.get('email', '').strip()
    phone = body.get('phone', '').strip()
    password = body.get('password', '')
    name = body.get('name', '').strip()

    # 필수 필드 검증
    if not email or not password:
        return {
            'statusCode': 400,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': '이메일과 비밀번호는 필수입니다.'})
        }

    # 중복 확인
    existing_user = check_existing_user(email, phone)
    if existing_user:
        return {
            'statusCode': 400,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': '이미 존재하는 사용자입니다.'})
        }

    # 사용자 ID 생성
    user_id = f"user_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{str(uuid.uuid4())[:8]}"

    # 비밀번호 해싱
    password_hash = hashlib.sha256(password.encode()).hexdigest()

    # DynamoDB에 저장
    timestamp = int(datetime.utcnow().timestamp())

    users_table.put_item(Item={
        'userId': user_id,
        'email': email,
        'phone': phone or '',
        'name': name or '',
        'passwordHash': password_hash,
        'status': 'active',
        'timestamp': timestamp,
        'createdAt': datetime.utcnow().isoformat(),
        'lastLoginAt': ''
    })

    # 세션 토큰 생성
    session_token = str(uuid.uuid4())

    return {
        'statusCode': 200,
        'headers': get_cors_headers(),
        'body': json.dumps({
            'userId': user_id,
            'email': email,
            'name': name,
            'sessionToken': session_token,
            'message': '회원가입이 완료되었습니다.'
        })
    }

def handle_login(event):
    """로그인 처리"""
    body = json.loads(event['body'])

    email = body.get('email', '').strip()
    password = body.get('password', '')

    if not email or not password:
        return {
            'statusCode': 400,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': '이메일과 비밀번호를 입력해주세요.'})
        }

    # 사용자 조회
    response = users_table.scan(
        FilterExpression='email = :email',
        ExpressionAttributeValues={':email': email}
    )

    if not response['Items']:
        return {
            'statusCode': 401,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': '사용자를 찾을 수 없습니다.'})
        }

    user = response['Items'][0]

    # 비밀번호 확인
    password_hash = hashlib.sha256(password.encode()).hexdigest()
    if user['passwordHash'] != password_hash:
        return {
            'statusCode': 401,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': '비밀번호가 일치하지 않습니다.'})
        }

    # 로그인 시간 업데이트
    users_table.update_item(
        Key={'userId': user['userId']},
        UpdateExpression='SET lastLoginAt = :login_time',
        ExpressionAttributeValues={
            ':login_time': datetime.utcnow().isoformat()
        }
    )

    # 세션 토큰 생성
    session_token = str(uuid.uuid4())

    return {
        'statusCode': 200,
        'headers': get_cors_headers(),
        'body': json.dumps({
            'userId': user['userId'],
            'email': user['email'],
            'name': user.get('name', ''),
            'sessionToken': session_token,
            'message': '로그인 성공'
        })
    }

def check_existing_user(email, phone):
    """기존 사용자 존재 확인"""
    # 이메일로 확인
    response = users_table.scan(
        FilterExpression='email = :email',
        ExpressionAttributeValues={':email': email}
    )

    if response['Items']:
        return True

    # 전화번호로 확인 (있는 경우)
    if phone:
        response = users_table.scan(
            FilterExpression='phone = :phone',
            ExpressionAttributeValues={':phone': phone}
        )
        if response['Items']:
            return True

    return False

def get_cors_headers():
    """CORS 헤더 반환"""
    return {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }