"""
AWS Lambda: Voice Analysis 상태 및 결과 조회
- DynamoDB에서 음성 분석 상태 조회
- 완료된 분석의 결과 반환
- 사용자별 분석 목록 조회
"""

import json
import boto3
import os
from typing import Dict, Any, List
from boto3.dynamodb.conditions import Key

# AWS 클라이언트 초기화
dynamodb = boto3.resource('dynamodb')

# 환경 변수
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'voice-analysis-results')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    음성 분석 상태 조회 핸들러

    URL 패턴:
    - GET /status/{analysis_id} : 특정 분석 조회
    - GET /status?user_id=xxx : 사용자별 목록 조회
    """

    # CORS 헤더
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS',
        'Content-Type': 'application/json'
    }

    try:
        # HTTP 메서드 확인
        http_method = event.get('httpMethod', 'GET')
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'CORS preflight'})
            }

        # 경로 파라미터 확인
        path_parameters = event.get('pathParameters', {}) or {}
        query_parameters = event.get('queryStringParameters', {}) or {}

        analysis_id = path_parameters.get('analysis_id')
        user_id = query_parameters.get('user_id')

        if analysis_id:
            # 특정 분석 ID 조회
            return get_analysis_by_id(analysis_id, headers)
        elif user_id:
            # 사용자별 목록 조회
            return get_analyses_by_user(user_id, headers)
        else:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'Either analysis_id or user_id is required',
                    'usage': {
                        'single_analysis': '/status/{analysis_id}',
                        'user_analyses': '/status?user_id=xxx'
                    }
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

def get_analysis_by_id(analysis_id: str, headers: Dict[str, str]) -> Dict[str, Any]:
    """특정 분석 ID로 결과 조회"""

    try:
        response = table.get_item(Key={'analysis_id': analysis_id})

        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({
                    'error': 'Analysis not found',
                    'analysis_id': analysis_id
                })
            }

        item = response['Item']

        # 결과 데이터 정리
        result = {
            'analysis_id': item['analysis_id'],
            'user_id': item['user_id'],
            'analysis_type': 'voice-analysis',
            'status': item['status'],
            'timestamp': item['timestamp'],
            'created_at': item.get('created_at'),
            's3_key': item.get('s3_key'),
            'parameters': item.get('parameters', {}),
            'progress': item.get('progress', 0),
            'processing_time': item.get('processing_time'),
            'error_message': item.get('error_message')
        }

        # 완료된 경우 결과 포함
        if item['status'] == 'completed' and 'results' in item:
            analysis_results = item['results']
            result['results'] = analysis_results

            # 결과 요약 생성
            result['summary'] = create_voice_analysis_summary(analysis_results)

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(result)
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to retrieve analysis',
                'details': str(e)
            })
        }

def get_analyses_by_user(user_id: str, headers: Dict[str, str]) -> Dict[str, Any]:
    """사용자별 분석 목록 조회"""

    try:
        # user_id-timestamp-index 사용해서 조회
        response = table.query(
            IndexName='user_id-timestamp-index',
            KeyConditionExpression=Key('user_id').eq(user_id),
            ScanIndexForward=False  # 최신순 정렬
        )

        results = []
        for item in response['Items']:
            result = {
                'analysis_id': item['analysis_id'],
                'status': item['status'],
                'timestamp': item['timestamp'],
                'created_at': item.get('created_at'),
                'progress': item.get('progress', 0),
                'processing_time': item.get('processing_time'),
                'error_message': item.get('error_message')
            }

            # 완료된 경우 결과 요약 포함
            if item['status'] == 'completed' and 'results' in item:
                analysis_results = item['results']
                result['results_summary'] = create_voice_analysis_summary(analysis_results)

            results.append(result)

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'user_id': user_id,
                'analysis_type': 'voice-analysis',
                'total_count': len(results),
                'analyses': results
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to retrieve user analyses',
                'details': str(e)
            })
        }

def create_voice_analysis_summary(analysis_results: Dict[str, Any]) -> Dict[str, Any]:
    """음성 분석 결과 요약 생성"""

    summary = {
        'analysis_type': 'voice-analysis',
        'overall_assessment': 'unknown',
        'parkinson_probability': 0.0,
        'confidence': 'unknown',
        'key_findings': []
    }

    try:
        if 'overall_assessment' in analysis_results:
            overall = analysis_results['overall_assessment']
            summary['overall_assessment'] = overall.get('assessment', 'unknown')
            summary['parkinson_probability'] = overall.get('parkinson_probability', 0.0)
            summary['confidence'] = overall.get('confidence', 'unknown')

        # 주요 소견 추출
        key_findings = []

        if 'voice_quality' in analysis_results:
            voice_quality = analysis_results['voice_quality']

            jitter = voice_quality.get('jitter_percent', 0)
            if jitter > 1.0:
                key_findings.append(f"음성 떨림 증가 ({jitter:.2f}%)")

            shimmer = voice_quality.get('shimmer_percent', 0)
            if shimmer > 5.0:
                key_findings.append(f"음성 강도 변동 증가 ({shimmer:.2f}%)")

            hnr = voice_quality.get('harmonic_to_noise_ratio', 20)
            if hnr < 15:
                key_findings.append(f"음성 기식성 증가 (HNR: {hnr:.1f}dB)")

        if 'parkinson_indicators' in analysis_results:
            parkinson_indicators = analysis_results['parkinson_indicators']

            if parkinson_indicators.get('voice_tremor_detected', False):
                key_findings.append("음성 떨림 감지")

            breathiness = parkinson_indicators.get('breathiness_level', 0)
            if breathiness > 0.5:
                key_findings.append("기식성 목소리")

            monotonicity = parkinson_indicators.get('monotonicity_score', 0)
            if monotonicity > 0.7:
                key_findings.append("단조로운 말투")

        if len(key_findings) == 0:
            key_findings.append("특이사항 없음")

        summary['key_findings'] = key_findings

        # 권장사항
        if 'overall_assessment' in analysis_results:
            recommendations = analysis_results['overall_assessment'].get('recommendations', [])
            summary['recommendations'] = recommendations

        return summary

    except Exception as e:
        print(f"Summary creation error: {str(e)}")
        return summary