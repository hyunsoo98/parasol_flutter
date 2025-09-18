"""
AWS Lambda: Voice Analysis 오디오 업로드 및 SQS 큐 전송
- API Gateway에서 오디오 파일 받기
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
S3_PREFIX = os.environ.get('S3_PREFIX', 'voice-analysis/')
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'voice-analysis-results')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    메인 핸들러 함수

    입력 예시:
    {
        "body": {
            "audio_data": "base64_encoded_audio",
            "user_id": "user123",
            "parameters": {
                "language": "ko",
                "task_type": "syllable_repetition",
                "duration": 30
            }
        }
    }
    """

    # CORS 헤더
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Content-Type': 'application/json'
    }

    try:
        # OPTIONS 요청 처리
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'CORS preflight'})
            }

        # 요청 파싱
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})

        # 필수 필드 검증
        required_fields = ['audio_data', 'user_id']
        for field in required_fields:
            if field not in body:
                return {
                    'statusCode': 400,
                    'headers': headers,
                    'body': json.dumps({
                        'error': f'Missing required field: {field}',
                        'required_fields': required_fields
                    })
                }

        audio_data = body['audio_data']
        user_id = body['user_id']
        parameters = body.get('parameters', {})

        # 분석 ID 생성
        analysis_id = str(uuid.uuid4())
        timestamp = int(time.time())

        # S3 키 생성
        s3_key = f"{S3_PREFIX}{user_id}/{analysis_id}_{timestamp}.wav"

        try:
            # Base64 오디오 데이터 디코딩
            audio_bytes = base64.b64decode(audio_data)
        except Exception as e:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'Invalid base64 audio data',
                    'details': str(e)
                })
            }

        # S3 업로드
        try:
            s3_client.put_object(
                Bucket=S3_BUCKET,
                Key=s3_key,
                Body=audio_bytes,
                ContentType='audio/wav'
            )
        except Exception as e:
            return {
                'statusCode': 500,
                'headers': headers,
                'body': json.dumps({
                    'error': 'S3 upload failed',
                    'details': str(e)
                })
            }

        # DynamoDB에 초기 상태 저장
        try:
            table.put_item(Item={
                'analysis_id': analysis_id,
                'user_id': user_id,
                'status': 'uploaded',
                'timestamp': timestamp,
                's3_key': s3_key,
                'analysis_type': 'voice-analysis',
                'parameters': parameters,
                'created_at': time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(timestamp))
            })
        except Exception as e:
            # S3에서 업로드된 파일 삭제 (롤백)
            try:
                s3_client.delete_object(Bucket=S3_BUCKET, Key=s3_key)
            except:
                pass

            return {
                'statusCode': 500,
                'headers': headers,
                'body': json.dumps({
                    'error': 'DynamoDB save failed',
                    'details': str(e)
                })
            }

        # SQS에 처리 요청 전송
        try:
            sqs_message = {
                'analysis_id': analysis_id,
                'user_id': user_id,
                's3_bucket': S3_BUCKET,
                's3_key': s3_key,
                'analysis_type': 'voice-analysis',
                'parameters': parameters,
                'timestamp': timestamp
            }

            sqs_client.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps(sqs_message),
                MessageGroupId='voice-analysis',  # FIFO 큐용
                MessageDeduplicationId=analysis_id
            )
        except Exception as e:
            # 실패시 DynamoDB 상태 업데이트
            try:
                table.update_item(
                    Key={'analysis_id': analysis_id},
                    UpdateExpression='SET #status = :status, error_message = :error',
                    ExpressionAttributeNames={'#status': 'status'},
                    ExpressionAttributeValues={
                        ':status': 'failed',
                        ':error': f'SQS send failed: {str(e)}'
                    }
                )
            except:
                pass

            return {
                'statusCode': 500,
                'headers': headers,
                'body': json.dumps({
                    'error': 'SQS message send failed',
                    'details': str(e),
                    'analysis_id': analysis_id
                })
            }

        # 성공 응답
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': 'Upload successful',
                'analysis_id': analysis_id,
                'analysis_type': 'voice-analysis',
                'status': 'uploaded',
                's3_key': s3_key,
                'timestamp': timestamp,
                'estimated_processing_time': '1-2 minutes'
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Internal server error',
                'details': str(e)
            })
        }