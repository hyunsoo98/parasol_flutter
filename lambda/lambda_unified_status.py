"""
AWS Lambda: 통합 분석 상태 확인
- DynamoDB에서 분석 상태 조회
- 분석 타입에 관계없이 통합 상태 반환
"""

import json
import boto3
import os
from typing import Dict, Any

# AWS 클라이언트 초기화
dynamodb = boto3.resource('dynamodb')

# DynamoDB 테이블 매핑
TABLE_MAPPING = {
    'finger-tapping': 'finger-tapping-results',
    'voice-analysis': 'voice-analysis-results',
    'eye-tracking-results': 'eye-tracking-results'
}

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    통합 상태 확인 핸들러

    GET /status/{analysis_id} 요청 처리
    """

    # CORS 헤더
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS',
        'Content-Type': 'application/json'
    }

    try:
        # OPTIONS 요청 처리
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': ''
            }

        # Path에서 analysis_id 추출
        path_parameters = event.get('pathParameters', {})
        analysis_id = path_parameters.get('analysisId') or path_parameters.get('analysis_id')

        if not analysis_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'Missing analysis_id in path parameters'
                })
            }

        # 모든 테이블에서 analysis_id 검색
        found_record = None
        found_table = None

        for analysis_type, table_name in TABLE_MAPPING.items():
            try:
                table = dynamodb.Table(table_name)
                response = table.get_item(Key={'analysis_id': analysis_id})

                if 'Item' in response:
                    found_record = response['Item']
                    found_table = table_name
                    break

            except Exception as e:
                print(f"Error querying {table_name}: {e}")
                continue

        if not found_record:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({
                    'error': 'Analysis not found',
                    'analysis_id': analysis_id
                })
            }

        # Decimal 타입을 float로 변환하여 JSON 직렬화 가능하게 만들기
        def convert_decimals_to_floats(obj):
            if hasattr(obj, 'items'):
                return {k: convert_decimals_to_floats(v) for k, v in obj.items()}
            elif hasattr(obj, '__iter__') and not isinstance(obj, (str, bytes)):
                return [convert_decimals_to_floats(item) for item in obj]
            elif hasattr(obj, '__float__'):
                return float(obj)
            else:
                return obj

        clean_record = convert_decimals_to_floats(found_record)

        # 성공 응답
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'analysis_id': analysis_id,
                'status': clean_record.get('status', 'unknown'),
                'analysis_type': clean_record.get('analysis_type'),
                'user_id': clean_record.get('user_id'),
                'created_at': clean_record.get('created_at'),
                'timestamp': clean_record.get('timestamp'),
                's3_key': clean_record.get('s3_key'),
                'parameters': clean_record.get('parameters', {}),
                'results': clean_record.get('results'),
                'error_message': clean_record.get('error_message'),
                'table_source': found_table
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