"""
AWS Lambda: 통합 분석 상태 및 결과 조회 
- Eye Tracking과 Finger Tapping 결과를 모두 처리
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
EYE_TRACKING_TABLE = os.environ.get('EYE_TRACKING_TABLE', 'eye-tracking-results')
FINGER_TAPPING_TABLE = os.environ.get('FINGER_TAPPING_TABLE', 'finger-tapping-results')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    메인 핸들러 함수
    
    GET /api/v1/status?analysis_id=xxx
    GET /api/v1/status?user_id=xxx
    GET /api/v1/results?analysis_id=xxx
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
        
        # 쿼리 파라미터 추출
        query_parameters = event.get('queryStringParameters') or {}
        analysis_id = query_parameters.get('analysis_id')
        user_id = query_parameters.get('user_id')
        analysis_type = query_parameters.get('analysis_type')  # 'eye-tracking' 또는 'finger-tapping'
        include_result = query_parameters.get('include_result', 'true').lower() == 'true'
        generate_download_url = query_parameters.get('download_url', 'false').lower() == 'true'
        
        # 경로로 결과 요청인지 확인
        path = event.get('path', '')
        is_results_endpoint = '/results' in path
        
        if analysis_id:
            # 특정 분석 결과 조회
            return get_analysis_status(analysis_id, analysis_type, include_result, generate_download_url, is_results_endpoint, headers)
        elif user_id:
            # 사용자별 분석 목록 조회
            return get_user_analyses(user_id, analysis_type, headers)
        else:
            return create_error_response(400, "analysis_id 또는 user_id가 필요합니다", headers)
            
    except Exception as e:
        print(f"Unified Status Lambda 오류: {str(e)}")
        return create_error_response(500, f"내부 서버 오류: {str(e)}", headers)

def get_analysis_status(analysis_id: str, analysis_type: str, include_result: bool, generate_download_url: bool, is_results_endpoint: bool, headers: Dict[str, str]) -> Dict[str, Any]:
    """특정 분석의 상태 및 결과 조회"""
    
    # analysis_type이 명시되지 않은 경우 두 테이블에서 모두 검색
    tables_to_check = []
    if analysis_type == 'eye-tracking':
        tables_to_check = [(EYE_TRACKING_TABLE, 'eye-tracking')]
    elif analysis_type == 'finger-tapping':
        tables_to_check = [(FINGER_TAPPING_TABLE, 'finger-tapping')]
    else:
        # 타입이 명시되지 않은 경우 두 테이블 모두 확인
        tables_to_check = [
            (EYE_TRACKING_TABLE, 'eye-tracking'),
            (FINGER_TAPPING_TABLE, 'finger-tapping')
        ]
    
    for table_name, detected_type in tables_to_check:
        try:
            table = dynamodb.Table(table_name)
            response = table.get_item(Key={'analysis_id': analysis_id})
            
            if 'Item' in response:
                item = response['Item']
                
                # 기본 응답 구성
                result = {
                    'analysis_id': analysis_id,
                    'user_id': item.get('user_id', 'unknown'),
                    'analysis_type': item.get('analysis_type', detected_type),
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
                        
                        # 분석 유형별 결과 요약
                        if detected_type == 'eye-tracking':
                            result['summary'] = create_eye_tracking_summary(analysis_result)
                        elif detected_type == 'finger-tapping':
                            result['summary'] = create_finger_tapping_summary(analysis_result)
                    
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
                
                # results 엔드포인트인 경우 결과만 반환
                if is_results_endpoint and item.get('status') == 'completed':
                    return {
                        'statusCode': 200,
                        'headers': headers,
                        'body': json.dumps({
                            'success': True,
                            'analysis_id': analysis_id,
                            'analysis_type': detected_type,
                            'result': result.get('result'),
                            'summary': result.get('summary'),
                            'download_urls': result.get('download_urls')
                        })
                    }
                
                return {
                    'statusCode': 200,
                    'headers': headers,
                    'body': json.dumps({
                        'success': True,
                        'data': result
                    })
                }
                
        except ClientError as e:
            print(f"DynamoDB 조회 실패 ({table_name}): {str(e)}")
            continue
    
    # 어떤 테이블에서도 찾지 못한 경우
    return create_error_response(404, "분석을 찾을 수 없습니다", headers)

def get_user_analyses(user_id: str, analysis_type: str, headers: Dict[str, str]) -> Dict[str, Any]:
    """사용자별 분석 목록 조회"""
    
    all_analyses = []
    
    # 검색할 테이블 결정
    tables_to_check = []
    if analysis_type == 'eye-tracking':
        tables_to_check = [(EYE_TRACKING_TABLE, 'eye-tracking')]
    elif analysis_type == 'finger-tapping':
        tables_to_check = [(FINGER_TAPPING_TABLE, 'finger-tapping')]
    else:
        # 타입이 명시되지 않은 경우 두 테이블 모두 확인
        tables_to_check = [
            (EYE_TRACKING_TABLE, 'eye-tracking'),
            (FINGER_TAPPING_TABLE, 'finger-tapping')
        ]
    
    for table_name, detected_type in tables_to_check:
        try:
            table = dynamodb.Table(table_name)
            
            # 기본 필터: user_id
            filter_expression = boto3.dynamodb.conditions.Attr('user_id').eq(user_id)
            
            # analysis_type 필터 추가 (해당 타입의 테이블인 경우)
            if analysis_type:
                filter_expression = filter_expression & boto3.dynamodb.conditions.Attr('analysis_type').eq(detected_type)
            
            response = table.scan(
                FilterExpression=filter_expression,
                ProjectionExpression='analysis_id, #status, #timestamp, progress, file_size, analysis_type',
                ExpressionAttributeNames={'#status': 'status', '#timestamp': 'timestamp'}
            )
            
            items = response.get('Items', [])
            
            # 응답 형식 변환
            for item in items:
                analysis_info = {
                    'analysis_id': item['analysis_id'],
                    'analysis_type': item.get('analysis_type', detected_type),
                    'status': item.get('status', 'unknown'),
                    'timestamp': item.get('timestamp'),
                    'progress': item.get('progress', 0),
                    'file_size': item.get('file_size', 0)
                }
                all_analyses.append(analysis_info)
                
        except ClientError as e:
            print(f"사용자 분석 목록 조회 실패 ({table_name}): {str(e)}")
            continue
    
    # 타임스탬프로 정렬 (최신순)
    all_analyses.sort(key=lambda x: x.get('timestamp', 0), reverse=True)
    
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({
            'success': True,
            'user_id': user_id,
            'analysis_type': analysis_type or 'all',
            'total_count': len(all_analyses),
            'analyses': all_analyses
        })
    }

def create_eye_tracking_summary(result: Dict[str, Any]) -> Dict[str, Any]:
    """Eye Tracking 결과 요약 생성"""
    summary = {
        'analysis_type': 'eye-tracking',
        'diagnosis': '분석불가',
        'confidence': 'unknown'
    }
    
    if 'psp_screening' in result:
        psp = result['psp_screening']
        if psp.get('suspected', False):
            summary['diagnosis'] = '파킨슨병 의심 (PSP 징후)'
            summary['confidence'] = 'high' if psp.get('vertical_ptp_measured', 0) < 0.03 else 'medium'
        else:
            summary['diagnosis'] = '정상 범위'
            summary['confidence'] = 'medium'
    
    if 'blink_analysis' in result:
        blink = result['blink_analysis']
        summary['blink_rate'] = blink.get('rate_per_minute', 0)
        summary['blink_count'] = blink.get('count', 0)
    
    return summary

def create_finger_tapping_summary(result: Dict[str, Any]) -> Dict[str, Any]:
    """Finger Tapping 결과 요약 생성"""
    summary = {
        'analysis_type': 'finger-tapping',
        'diagnosis': '분석불가',
        'confidence': 'unknown'
    }
    
    if 'combined_result' in result:
        combined = result['combined_result']
        summary['diagnosis'] = combined.get('label', '분석불가')
        probability = combined.get('probability', 0.0)
        
        if probability >= 0.8:
            summary['confidence'] = 'high'
        elif probability >= 0.6:
            summary['confidence'] = 'medium'  
        elif probability >= 0.4:
            summary['confidence'] = 'low'
        else:
            summary['confidence'] = 'very_low'
        
        summary['probability'] = probability
    
    if 'tap_counts' in result:
        summary['tap_counts'] = result['tap_counts']
    
    if 'hand_predictions' in result:
        summary['hand_results'] = []
        for hand_pred in result['hand_predictions']:
            summary['hand_results'].append({
                'hand': hand_pred.get('hand', 'unknown'),
                'diagnosis': hand_pred.get('label', '분석불가'),
                'tap_count': hand_pred.get('tap_count', 0)
            })
    
    return summary

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