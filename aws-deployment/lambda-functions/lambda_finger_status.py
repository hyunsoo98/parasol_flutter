"""
AWS Lambda: Finger Tapping 분석 상태 및 결과 조회
- API Gateway에서 analysis_id로 상태 조회 요청 받기
- DynamoDB에서 분석 상태 및 결과 조회
- S3에서 CSV 다운로드 URL 생성 (선택사항)
"""

import json
import boto3
import os
import time
from typing import Dict, Any
from botocore.exceptions import ClientError

# AWS 클라이언트 초기화
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

# 환경 변수
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')
S3_PREFIX = os.environ.get('S3_PREFIX', 'parasol/')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'finger-tapping-results')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    메인 핸들러 함수
    
    GET /finger-tapping/status/{analysis_id}
    또는
    GET /finger-tapping/status?user_id=xxx (사용자별 분석 목록)
    """
    
    # CORS 헤더
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
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
        
        # 경로 파라미터에서 analysis_id 추출
        path_parameters = event.get('pathParameters') or {}
        analysis_id = path_parameters.get('analysis_id')
        
        # 쿼리 파라미터 추출
        query_parameters = event.get('queryStringParameters') or {}
        user_id = query_parameters.get('user_id')
        include_result = query_parameters.get('include_result', 'true').lower() == 'true'
        generate_download_url = query_parameters.get('download_url', 'false').lower() == 'true'
        
        if analysis_id:
            # 특정 분석 결과 조회
            return get_analysis_status(analysis_id, include_result, generate_download_url, headers)
        elif user_id:
            # 사용자별 분석 목록 조회
            return get_user_analyses(user_id, headers)
        else:
            return create_error_response(400, "analysis_id 또는 user_id가 필요합니다", headers)
            
    except Exception as e:
        print(f"Finger Tapping Status Lambda 오류: {str(e)}")
        return create_error_response(500, f"내부 서버 오류: {str(e)}", headers)

def get_analysis_status(analysis_id: str, include_result: bool, generate_download_url: bool, headers: Dict[str, str]) -> Dict[str, Any]:
    """특정 분석의 상태 및 결과 조회"""
    
    try:
        # DynamoDB에서 분석 정보 조회
        response = table.get_item(Key={'analysis_id': analysis_id})
        
        if 'Item' not in response:
            return create_error_response(404, "분석을 찾을 수 없습니다", headers)
        
        item = response['Item']
        
        # 기본 응답 구성
        result = {
            'analysis_id': analysis_id,
            'user_id': item.get('user_id', 'unknown'),
            'analysis_type': item.get('analysis_type', 'finger-tapping'),
            'status': item.get('status', 'unknown'),
            'timestamp': item.get('timestamp'),
            'progress': item.get('progress', 0),
            'progress_message': item.get('progress_message', '')
        }
        
        # 상태별 추가 정보
        if item.get('status') == 'processing':
            result['estimated_completion'] = estimate_completion_time(item)
            
        elif item.get('status') == 'completed':
            result['completed_at'] = item.get('completed_at')
            
            if include_result and 'result' in item:
                analysis_result = item['result']
                result['result'] = analysis_result
                
                # 분석 결과 요약 추가
                if 'combined_result' in analysis_result:
                    combined = analysis_result['combined_result']
                    result['summary'] = {
                        'diagnosis': combined.get('label', '분석불가'),
                        'probability': combined.get('probability', 0.0),
                        'confidence_level': get_confidence_level(combined.get('probability', 0.0))
                    }
                
                # 손별 결과 요약
                if 'hand_predictions' in analysis_result:
                    result['hand_summary'] = []
                    for hand_pred in analysis_result['hand_predictions']:
                        result['hand_summary'].append({
                            'hand': hand_pred.get('hand', 'unknown'),
                            'tap_count': hand_pred.get('tap_count', 0),
                            'diagnosis': hand_pred.get('label', '분석불가'),
                            'probability': hand_pred.get('probability', 0.0)
                        })
                
            # CSV 다운로드 URL 생성
            if generate_download_url and 'csv_s3_key' in item.get('result', {}):
                csv_s3_key = item['result']['csv_s3_key']
                result['download_urls'] = {
                    'csv': generate_presigned_url(csv_s3_key, 'text/csv')
                }
                
        elif item.get('status') == 'failed':
            result['failed_at'] = item.get('failed_at')
            result['error'] = item.get('error', '알 수 없는 오류')
        
        # 파일 정보
        if 'file_size' in item:
            result['file_info'] = {
                'size': item['file_size'],
                's3_key': item.get('s3_key')
            }
        
        # 분석 파라미터
        if 'parameters' in item:
            result['parameters'] = item['parameters']
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'success': True,
                'data': result
            })
        }
        
    except ClientError as e:
        return create_error_response(500, f"DynamoDB 조회 실패: {str(e)}", headers)

def get_user_analyses(user_id: str, headers: Dict[str, str]) -> Dict[str, Any]:
    """사용자별 Finger Tapping 분석 목록 조회"""
    
    try:
        # DynamoDB 스캔 (finger-tapping만 필터링)
        response = table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr('user_id').eq(user_id) & 
                           boto3.dynamodb.conditions.Attr('analysis_type').eq('finger-tapping'),
            ProjectionExpression='analysis_id, #status, #timestamp, progress, file_size, analysis_type',
            ExpressionAttributeNames={'#status': 'status', '#timestamp': 'timestamp'}
        )
        
        items = response.get('Items', [])
        
        # 타임스탬프로 정렬 (최신순)
        items.sort(key=lambda x: x.get('timestamp', 0), reverse=True)
        
        # 응답 형식 변환
        analyses = []
        for item in items:
            analysis_info = {
                'analysis_id': item['analysis_id'],
                'analysis_type': item.get('analysis_type', 'finger-tapping'),
                'status': item.get('status', 'unknown'),
                'timestamp': item.get('timestamp'),
                'progress': item.get('progress', 0),
                'file_size': item.get('file_size', 0)
            }
            analyses.append(analysis_info)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'success': True,
                'user_id': user_id,
                'analysis_type': 'finger-tapping',
                'total_count': len(analyses),
                'analyses': analyses
            })
        }
        
    except ClientError as e:
        return create_error_response(500, f"사용자 분석 목록 조회 실패: {str(e)}", headers)

def generate_presigned_url(s3_key: str, content_type: str, expiration: int = 3600) -> str:
    """S3 presigned URL 생성"""
    try:
        url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': S3_BUCKET,
                'Key': s3_key,
                'ResponseContentType': content_type
            },
            ExpiresIn=expiration
        )
        return url
    except ClientError as e:
        print(f"Presigned URL 생성 실패: {str(e)}")
        return ""

def estimate_completion_time(item: Dict[str, Any]) -> int:
    """예상 완료 시간 계산 (초)"""
    try:
        timestamp = item.get('timestamp', 0)
        file_size = item.get('file_size', 0)
        progress = item.get('progress', 0)
        
        if progress <= 0:
            return 300  # 기본 5분
        
        elapsed = int(time.time()) - timestamp
        estimated_total = elapsed * (100 / progress)
        remaining = max(0, estimated_total - elapsed)
        
        return int(remaining)
    except:
        return 180  # 기본 3분

def get_confidence_level(probability: float) -> str:
    """확률을 신뢰도 레벨로 변환"""
    if probability >= 0.8:
        return "높음"
    elif probability >= 0.6:
        return "중간"
    elif probability >= 0.4:
        return "낮음"
    else:
        return "매우 낮음"

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

# 추가: 분석 결과 삭제 함수
def delete_analysis(analysis_id: str, user_id: str) -> Dict[str, Any]:
    """분석 결과 삭제 (선택사항)"""
    try:
        # DynamoDB에서 삭제
        table.delete_item(Key={'analysis_id': analysis_id})
        
        # S3에서 관련 파일들 삭제
        s3_prefix = f"videos/{user_id}/finger-tapping/{analysis_id}/"
        objects_to_delete = s3_client.list_objects_v2(
            Bucket=S3_BUCKET,
            Prefix=s3_prefix
        )
        
        if 'Contents' in objects_to_delete:
            delete_objects = [{'Key': obj['Key']} for obj in objects_to_delete['Contents']]
            s3_client.delete_objects(
                Bucket=S3_BUCKET,
                Delete={'Objects': delete_objects}
            )
        
        return {'success': True, 'message': 'Finger Tapping 분석 결과가 삭제되었습니다'}
        
    except Exception as e:
        return {'success': False, 'error': f'삭제 실패: {str(e)}'}