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
from decimal import Decimal

class DecimalEncoder(json.JSONEncoder):
    """DynamoDB Decimal 타입을 JSON으로 직렬화하기 위한 커스텀 인코더"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

# AWS 클라이언트 초기화
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

# 통합 환경 변수 설정 (API 문서 기준 정정)
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')
S3_EYE_TRACKING_PREFIX = os.environ.get('S3_EYE_TRACKING_PREFIX', 'eye-tracking/results')  # JSON 결과만
S3_FINGER_TAPPING_PREFIX = os.environ.get('S3_FINGER_TAPPING_PREFIX', 'finger-tapping')
S3_VOICE_ANALYSIS_PREFIX = os.environ.get('S3_VOICE_ANALYSIS_PREFIX', 'voice-analysis')

# DynamoDB 테이블 (API 문서 기준 - 모든 분석은 analyses 테이블 사용)
ANALYSES_TABLE = os.environ.get('ANALYSES_TABLE', 'analyses')
DIAGNOSIS_SESSIONS_TABLE = os.environ.get('DIAGNOSIS_SESSIONS_TABLE', 'diagnosis_sessions')

# Presigned URL 설정
PRESIGNED_URL_EXPIRATION_SECONDS = int(os.environ.get('PRESIGNED_URL_EXPIRATION_SECONDS', '3600'))
MAX_HISTORY_RECORDS = int(os.environ.get('MAX_HISTORY_RECORDS', '100'))

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
        
        # Path Parameter에서 analysis_id 추출 (API Gateway 구조에 맞춤)
        path_parameters = event.get('pathParameters') or {}
        analysis_id = path_parameters.get('analysis_id')

        # 쿼리 파라미터 추출 (추가 옵션용)
        query_parameters = event.get('queryStringParameters') or {}
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

    try:
        # API 문서 기준: 단일 analyses 테이블 사용
        table = dynamodb.Table(ANALYSES_TABLE)
        response = table.get_item(Key={'analysis_id': analysis_id})  # API 문서 기준 필드명
            
        if 'Item' in response:
            item = response['Item']
            detected_type = item.get('analysis_type', 'unknown')

            # 기본 응답 구성 (API 문서 기준 필드명)
            result = {
                'analysis_id': analysis_id,  # API 문서 기준
                'user_id': item.get('user_id', 'unknown'),
                'analysis_type': detected_type,
                'status': item.get('status', 'unknown'),
                'created_at': item.get('created_at'),
                'updated_at': item.get('updated_at'),
                'progress': item.get('progress', 0),
                'progress_message': item.get('progress_message', '')
            }
                
            # 상태별 추가 정보
            if item.get('status') == 'processing':
                result['estimated_completion'] = estimate_completion_time(item)

            elif item.get('status') == 'completed':
                if include_result and 'results' in item:
                    analysis_result = item['results']
                    result['results'] = analysis_result

                    # 분석 유형별 결과 요약
                    if detected_type == 'eye-tracking':
                        result['summary'] = create_eye_tracking_summary(analysis_result)
                    elif detected_type == 'finger-tapping':
                        result['summary'] = create_finger_tapping_summary(analysis_result)

                # S3 다운로드 URL 생성 (API 문서 기준)
                if generate_download_url and 's3_paths' in item:
                    s3_paths = item['s3_paths']
                    result['download_urls'] = {}

                    # 각 타입별 결과 파일 URL
                    if 'results' in s3_paths:
                        result['download_urls']['results'] = generate_presigned_url(
                            s3_paths['results'],
                            'application/json' if detected_type == 'eye-tracking' else 'text/csv'
                        )
                    if 'processed' in s3_paths:
                        result['download_urls']['processed'] = generate_presigned_url(
                            s3_paths['processed'], 'application/json'
                        )

            elif item.get('status') == 'failed':
                result['error_message'] = item.get('error_message', '알 수 없는 오류')
                
            # S3 경로 정보
            if 's3_paths' in item:
                result['s3_paths'] = item['s3_paths']

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
                        'results': result.get('results'),
                        'summary': result.get('summary'),
                        'download_urls': result.get('download_urls')
                    }, cls=DecimalEncoder)
                }

            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    'success': True,
                    'data': result
                }, cls=DecimalEncoder)
            }
        else:
            # 분석을 찾을 수 없는 경우
            return create_error_response(404, "분석을 찾을 수 없습니다", headers)

    except ClientError as e:
        print(f"DynamoDB 조회 실패: {str(e)}")
        return create_error_response(500, f"데이터베이스 조회 실패: {str(e)}", headers)

def get_user_analyses(user_id: str, analysis_type: str, headers: Dict[str, str]) -> Dict[str, Any]:
    """사용자별 분석 목록 조회"""

    try:
        # API 문서 기준: 단일 analyses 테이블에서 user-id-index 사용
        table = dynamodb.Table(ANALYSES_TABLE)

        # GSI를 사용한 쿼리 (user_id + created_at)
        query_kwargs = {
            'IndexName': 'user-id-index',
            'KeyConditionExpression': boto3.dynamodb.conditions.Key('user_id').eq(user_id),
            'ProjectionExpression': 'analysis_id, analysis_type, #status, created_at, updated_at, progress',
            'ExpressionAttributeNames': {'#status': 'status'},
            'ScanIndexForward': False,  # 최신순 정렬
            'Limit': MAX_HISTORY_RECORDS
        }

        # analysis_type 필터 추가
        if analysis_type:
            query_kwargs['FilterExpression'] = boto3.dynamodb.conditions.Attr('analysis_type').eq(analysis_type)

        response = table.query(**query_kwargs)
        items = response.get('Items', [])

        # 응답 형식 변환
        all_analyses = []
        for item in items:
            analysis_info = {
                'analysis_id': item['analysis_id'],  # API 문서 기준
                'analysis_type': item.get('analysis_type', 'unknown'),
                'status': item.get('status', 'unknown'),
                'created_at': item.get('created_at'),
                'updated_at': item.get('updated_at'),
                'progress': item.get('progress', 0)
            }
            all_analyses.append(analysis_info)

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'success': True,
                'user_id': user_id,
                'analysis_type': analysis_type or 'all',
                'total_count': len(all_analyses),
                'analyses': all_analyses
            }, cls=DecimalEncoder)
        }

    except ClientError as e:
        print(f"사용자 분석 목록 조회 실패: {str(e)}")
        return create_error_response(500, f"분석 목록 조회 실패: {str(e)}", headers)

def create_eye_tracking_summary(result: Dict[str, Any]) -> Dict[str, Any]:
    """Eye Tracking 결과 요약 생성 (클라이언트 분석 결과 포함)"""
    summary = {
        'analysis_type': 'eye-tracking',
        'diagnosis': '분석불가',
        'confidence': 'unknown',
        'source': 'client'  # 클라이언트에서 분석됨
    }

    # 클라이언트 실시간 분석 결과 처리
    if 'psp_detected' in result:
        psp_detected = result.get('psp_detected', False)
        vertical_range = result.get('vertical_range', 0.0)

        if psp_detected:
            summary['diagnosis'] = '파킨슨병 의심 (PSP 징후)'
            summary['confidence'] = 'high' if vertical_range < 0.03 else 'medium'
        else:
            summary['diagnosis'] = '정상 범위'
            summary['confidence'] = 'medium'

        summary['vertical_range'] = vertical_range
        summary['test_duration'] = result.get('test_duration', 0)
        summary['total_frames'] = result.get('total_frames', 0)
        summary['blink_count'] = result.get('blink_count', 0)

    # 기존 서버 분석 결과 처리 (호환성)
    elif 'psp_screening' in result:
        psp = result['psp_screening']
        if psp.get('suspected', False):
            summary['diagnosis'] = '파킨슨병 의심 (PSP 징후)'
            summary['confidence'] = 'high' if psp.get('vertical_ptp_measured', 0) < 0.03 else 'medium'
        else:
            summary['diagnosis'] = '정상 범위'
            summary['confidence'] = 'medium'
        summary['source'] = 'server'  # 서버에서 분석됨

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
        # API 문서 기준: created_at 사용
        created_at_str = item.get('created_at', '')
        if not created_at_str:
            return 300  # 기본 5분

        # ISO 8601 형식 파싱
        from datetime import datetime
        created_at = datetime.fromisoformat(created_at_str.replace('Z', '+00:00'))
        elapsed = (datetime.utcnow() - created_at.replace(tzinfo=None)).total_seconds()

        progress = item.get('progress', 0)

        if progress <= 0:
            return 300  # 기본 5분

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
        }, cls=DecimalEncoder)
    }