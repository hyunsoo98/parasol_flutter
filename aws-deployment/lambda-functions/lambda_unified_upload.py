"""
AWS Lambda: 통합 업로드 및 SQS 큐 전송 (Eye Tracking + Finger Tapping)
- API Gateway에서 비디오 파일 받기
- 분석 타입에 따라 적절한 S3 경로에 업로드
- 해당 타입의 SQS 큐에 처리 요청 전송
- 해당 타입의 DynamoDB 테이블에 초기 상태 저장
"""

import json
import boto3
import base64
import uuid
import time
import os
from decimal import Decimal
from typing import Dict, Any

# AWS 클라이언트 초기화
s3_client = boto3.client('s3')
sqs_client = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')

# 환경 변수
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')

# 표준화된 S3 경로 설정 (시선추적은 클라이언트 분석으로 제거)
ANALYSIS_CONFIGS = {
    # 'eye-tracking': 클라이언트에서 실시간 분석하므로 AWS 업로드 불필요
    'finger-tapping': {
        's3_prefix': 'videos/finger-tapping/',
        'sqs_queue_url': os.environ.get('FINGER_TAPPING_QUEUE', 'https://sqs.us-west-1.amazonaws.com/730335212232/finger-tapping-processing.fifo'),
        'dynamodb_table': 'finger-tapping-results',
        'content_type': 'video/mp4',
        'file_extension': '.mp4'
    },
    'voice-analysis': {
        's3_prefix': 'audio/voice-analysis/',
        'sqs_queue_url': os.environ.get('VOICE_ANALYSIS_QUEUE', 'https://sqs.us-west-1.amazonaws.com/730335212232/voice-analysis-processing.fifo'),
        'dynamodb_table': 'voice-analysis-results',
        'content_type': 'audio/wav',
        'file_extension': '.wav'
    },
    # 시선추적 결과 저장용 (비디오 없이 분석 결과만 저장)
    'eye-tracking-results': {
        's3_prefix': 'results/eye-tracking/',
        'sqs_queue_url': None,  # SQS 처리 불필요
        'dynamodb_table': 'eye-tracking-results',
        'content_type': 'application/json',
        'file_extension': '.json'
    }
}

def convert_floats_to_decimals(obj):
    """
    DynamoDB에서 사용할 수 있도록 float을 Decimal로 변환
    """
    if isinstance(obj, float):
        return Decimal(str(obj))
    elif isinstance(obj, dict):
        return {k: convert_floats_to_decimals(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_floats_to_decimals(item) for item in obj]
    else:
        return obj

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    통합 업로드 핸들러 함수

    입력 예시:
    {
        "body": {
            "analysis_type": "eye-tracking" | "finger-tapping",
            "video_data": "base64_encoded_video",
            "user_id": "user123",
            "parameters": {
                // eye-tracking parameters
                "step": 1,
                "vpp_thresh": 0.06,
                "blink_thresh": 0.18,
                "max_frames": 12000

                // OR finger-tapping parameters
                "target_taps": 10,
                "max_duration": 30,
                "hand_preference": "both"
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
        # 요청 파싱
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})

        # 필수 필드 검증 (시선추적 결과는 video_data 대신 results_data 사용)
        analysis_type = body.get('analysis_type')

        if analysis_type == 'eye-tracking-results':
            required_fields = ['analysis_type', 'results_data', 'user_id']
            data_field = 'results_data'
        else:
            required_fields = ['analysis_type', 'video_data', 'user_id']
            data_field = 'video_data'

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

        analysis_type = body['analysis_type']
        file_data = body.get(data_field)  # video_data 또는 results_data
        user_id = body['user_id']
        parameters = body.get('parameters', {})

        # 분석 타입 검증
        if analysis_type not in ANALYSIS_CONFIGS:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': f'Invalid analysis_type: {analysis_type}',
                    'supported_types': list(ANALYSIS_CONFIGS.keys())
                })
            }

        config = ANALYSIS_CONFIGS[analysis_type]

        # 분석 ID 생성
        analysis_id = str(uuid.uuid4())
        timestamp = int(time.time())

        # S3 키 생성
        s3_key = f"{config['s3_prefix']}{user_id}/{analysis_id}_{timestamp}{config['file_extension']}"

        try:
            # 데이터 처리 (시선추적 결과는 JSON, 나머지는 Base64 디코딩)
            if analysis_type == 'eye-tracking-results':
                # JSON 데이터를 문자열로 변환
                if isinstance(file_data, dict):
                    file_bytes = json.dumps(file_data).encode('utf-8')
                else:
                    file_bytes = str(file_data).encode('utf-8')
            else:
                # Base64 데이터 디코딩 (비디오 또는 오디오)
                file_bytes = base64.b64decode(file_data)
        except Exception as e:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'Invalid data format',
                    'details': str(e)
                })
            }

        # S3 업로드
        try:
            s3_client.put_object(
                Bucket=S3_BUCKET,
                Key=s3_key,
                Body=file_bytes,
                ContentType=config['content_type']
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

        # DynamoDB에 초기 상태 저장 (skip_db_save 파라미터 체크)
        skip_db = parameters.get('skip_db_save', False)

        if not skip_db:
            try:
                table = dynamodb.Table(config['dynamodb_table'])

                # parameters 처리: 문자열로 받은 float 값들을 Decimal로 변환
                processed_parameters = {}
                for key, value in parameters.items():
                    if key == 'skip_db_save':
                        continue  # 이 파라미터는 저장하지 않음
                    elif key in ['vpp_thresh', 'blink_thresh'] and isinstance(value, str):
                        # 문자열로 받은 float 값을 Decimal로 변환
                        processed_parameters[key] = Decimal(value)
                    else:
                        # 다른 값들은 기본 변환 함수 사용
                        processed_parameters[key] = convert_floats_to_decimals(value)

                safe_parameters = processed_parameters

                table.put_item(Item={
                    'analysisId': analysis_id,
                    'user_id': user_id,
                    'status': 'uploaded',
                    'timestamp': timestamp,
                    's3_key': s3_key,
                    'analysis_type': analysis_type,
                    'parameters': safe_parameters,
                    'created_at': time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(timestamp))
                })
            except Exception as e:
                # DynamoDB 저장 실패시 S3에서 업로드된 파일 삭제 (롤백)
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
        else:
            print(f"DynamoDB 저장 건너뛰기 - skip_db_save=True, analysis_id: {analysis_id}")

        # SQS에 처리 요청 전송 (시선추적 결과는 SQS 건너뛰기)
        if config['sqs_queue_url']:  # SQS URL이 있는 경우만 전송
            try:
                sqs_message = {
                    'analysis_id': analysis_id,  # 스네이크케이스로 수정
                    'user_id': user_id,
                    's3_bucket': S3_BUCKET,
                    's3_key': s3_key,
                    'analysis_type': analysis_type,
                    'parameters': parameters,
                    'timestamp': timestamp
                }

                sqs_client.send_message(
                    QueueUrl=config['sqs_queue_url'],
                    MessageBody=json.dumps(sqs_message),
                    MessageGroupId=analysis_type,  # FIFO 큐용
                    MessageDeduplicationId=analysis_id
                )
            except Exception as e:
                # 실패시 DynamoDB 상태 업데이트
                try:
                    table = dynamodb.Table(config['dynamodb_table'])
                    table.update_item(
                        Key={'analysisId': analysis_id},
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
                        'analysis_id': analysis_id  # 클라이언트가 상태 확인할 수 있도록
                    })
                }
        else:
            # SQS 처리 없는 경우 (시선추적 결과) 상태를 completed로 설정
            if not skip_db:
                try:
                    table = dynamodb.Table(config['dynamodb_table'])
                    table.update_item(
                        Key={'analysisId': analysis_id},
                        UpdateExpression='SET #status = :status',
                        ExpressionAttributeNames={'#status': 'status'},
                        ExpressionAttributeValues={':status': 'completed'}
                    )
                except Exception as e:
                    print(f"DynamoDB 상태 업데이트 실패: {e}")

        # 성공 응답
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': 'Upload successful',
                'analysisId': analysis_id,
                'analysis_type': analysis_type,
                'status': 'uploaded',
                's3_key': s3_key,
                'timestamp': timestamp,
                'estimated_processing_time': get_estimated_time(analysis_type)
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

def get_estimated_time(analysis_type: str) -> str:
    """분석 타입별 예상 처리 시간 반환"""
    times = {
        'eye-tracking-results': 'completed',  # 클라이언트에서 이미 분석됨
        'finger-tapping': '1-3 minutes',
        'voice-analysis': '1-2 minutes'
    }
    return times.get(analysis_type, '1-3 minutes')