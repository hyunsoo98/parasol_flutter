"""
AWS Lambda: Finger Tapping 비디오 업로드 및 SQS 큐 전송
- API Gateway에서 비디오 파일 받기
- S3에 업로드
- SQS에 처리 요청 전송
- DynamoDB에 초기 상태 저장
"""

import json
import boto3
import base64
import uuid
import time
import os
from typing import Dict, Any

# AWS 클라이언트 초기화
s3_client = boto3.client('s3')
sqs_client = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')

# 환경 변수
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')
S3_PREFIX = os.environ.get('S3_PREFIX', 'parasol/')
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'finger-tapping-results')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    메인 핸들러 함수
    
    입력 예시:
    {
        "body": {
            "video_data": "base64_encoded_video",
            "user_id": "user123",
            "parameters": {
                "target_taps": 10,
                "max_duration": 30,
                "hand_preference": "both"
            }
        }
    }
    """
    
    # CORS 헤더
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }
    
    try:
        # OPTIONS 요청 처리
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'OK'})
            }
        
        # 요청 본문 파싱
        if 'body' in event:
            if event.get('isBase64Encoded', False):
                body = base64.b64decode(event['body']).decode('utf-8')
            else:
                body = event['body']
            request_data = json.loads(body) if isinstance(body, str) else body
        else:
            request_data = event
        
        # 필수 파라미터 확인
        video_data = request_data.get('video_data')
        if not video_data:
            return create_error_response(400, "video_data가 필요합니다", headers)
        
        user_id = request_data.get('user_id', 'anonymous')
        parameters = request_data.get('parameters', {})
        
        # 기본 파라미터 설정
        default_params = {
            'target_taps': 10,
            'max_duration': 30,
            'hand_preference': 'both',  # 'left', 'right', 'both'
            'threshold': 0.50,
            'delta': 0.05
        }
        default_params.update(parameters)
        
        # 분석 ID 생성
        analysis_id = str(uuid.uuid4())
        timestamp = int(time.time())
        
        # Base64 디코딩
        try:
            video_bytes = base64.b64decode(video_data)
        except Exception as e:
            return create_error_response(400, f"잘못된 base64 데이터: {str(e)}", headers)
        
        # 파일 크기 확인 (100MB 제한)
        file_size = len(video_bytes)
        if file_size > 100 * 1024 * 1024:
            return create_error_response(400, "파일 크기가 100MB를 초과합니다", headers)
        
        if file_size == 0:
            return create_error_response(400, "빈 파일입니다", headers)
        
        # S3에 비디오 업로드
        s3_key = f"{S3_PREFIX}videos/{user_id}/finger-tapping/{analysis_id}/input.mp4"
        try:
            s3_client.put_object(
                Bucket=S3_BUCKET,
                Key=s3_key,
                Body=video_bytes,
                ContentType='video/mp4',
                Metadata={
                    'user_id': user_id,
                    'analysis_id': analysis_id,
                    'analysis_type': 'finger-tapping',
                    'upload_timestamp': str(timestamp)
                }
            )
        except Exception as e:
            return create_error_response(500, f"S3 업로드 실패: {str(e)}", headers)
        
        # DynamoDB에 초기 상태 저장
        try:
            table.put_item(Item={
                'analysis_id': analysis_id,
                'user_id': user_id,
                'analysis_type': 'finger-tapping',
                'status': 'processing',
                'timestamp': timestamp,
                's3_key': s3_key,
                'file_size': file_size,
                'parameters': default_params,
                'progress': 0
            })
        except Exception as e:
            return create_error_response(500, f"DynamoDB 저장 실패: {str(e)}", headers)
        
        # SQS에 처리 요청 전송
        message_body = {
            'analysis_id': analysis_id,
            'user_id': user_id,
            'analysis_type': 'finger-tapping',
            's3_bucket': S3_BUCKET,
            's3_key': s3_key,
            'file_size': file_size,
            'parameters': default_params,
            'timestamp': timestamp
        }
        
        try:
            sqs_response = sqs_client.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps(message_body),
                MessageAttributes={
                    'analysis_id': {
                        'StringValue': analysis_id,
                        'DataType': 'String'
                    },
                    'analysis_type': {
                        'StringValue': 'finger-tapping',
                        'DataType': 'String'
                    },
                    'user_id': {
                        'StringValue': user_id,
                        'DataType': 'String'
                    }
                }
            )
        except Exception as e:
            # SQS 전송 실패시 상태 업데이트
            table.update_item(
                Key={'analysis_id': analysis_id},
                UpdateExpression='SET #status = :status, #error = :error',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#error': 'error'
                },
                ExpressionAttributeValues={
                    ':status': 'failed',
                    ':error': f"SQS 전송 실패: {str(e)}"
                }
            )
            return create_error_response(500, f"처리 요청 전송 실패: {str(e)}", headers)
        
        # 성공 응답
        return {
            'statusCode': 202,  # Accepted
            'headers': headers,
            'body': json.dumps({
                'success': True,
                'analysis_id': analysis_id,
                'analysis_type': 'finger-tapping',
                'status': 'processing',
                'message': 'Finger Tapping 분석이 시작되었습니다. 상태를 확인하여 결과를 받아보세요.',
                'file_size': file_size,
                'estimated_time': estimate_processing_time(file_size),
                'status_check_url': f"/status/{analysis_id}"
            })
        }
        
    except Exception as e:
        print(f"Finger Tapping Upload Lambda 오류: {str(e)}")
        return create_error_response(500, f"내부 서버 오류: {str(e)}", headers)

def create_error_response(status_code: int, message: str, headers: Dict[str, str]) -> Dict[str, Any]:
    """에러 응답 생성"""
    return {
        'statusCode': status_code,
        'headers': headers,
        'body': json.dumps({
            'success': False,
            'error': message
        })
    }

def estimate_processing_time(file_size: int) -> int:
    """파일 크기 기반 예상 처리 시간 (초)"""
    # Finger Tapping은 Eye Tracking보다 빠름 (1MB당 약 5초)
    estimated_seconds = (file_size / (1024 * 1024)) * 5
    return max(15, min(300, int(estimated_seconds)))  # 15초~5분 범위