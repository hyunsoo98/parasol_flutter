"""
AWS Lambda: 종합 진단 결과 생성 및 관리
- 3가지 분석 결과를 통합하여 종합 진단 제공
- 진단 세션 관리
- AI 기반 종합 분석
"""

import json
import boto3
import time
import numpy as np
from typing import Dict, Any, List, Optional
from boto3.dynamodb.conditions import Key

# AWS 클라이언트 초기화
dynamodb = boto3.resource('dynamodb')

# DynamoDB 테이블들
comprehensive_table = dynamodb.Table('comprehensive-diagnosis')
eye_table = dynamodb.Table('eye-tracking-results')
finger_table = dynamodb.Table('finger-tapping-results')
voice_table = dynamodb.Table('voice-analysis-results')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    종합 진단 Lambda 핸들러

    엔드포인트:
    - POST /diagnosis/start : 진단 세션 시작
    - GET /diagnosis/{session_id} : 세션 상태 조회
    - POST /diagnosis/{session_id}/complete : 종합 결과 생성
    - GET /diagnosis/user/{user_id} : 사용자별 진단 이력
    """

    # CORS 헤더
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Content-Type': 'application/json'
    }

    try:
        http_method = event.get('httpMethod', 'GET')
        path = event.get('path', '')

        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'CORS preflight'})
            }

        # 라우팅
        if 'start' in path and http_method == 'POST':
            return start_diagnosis_session(event, headers)
        elif 'complete' in path and http_method == 'POST':
            return complete_diagnosis_session(event, headers)
        elif '/user/' in path:
            return get_user_diagnosis_history(event, headers)
        else:
            return get_diagnosis_status(event, headers)

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Internal server error',
                'details': str(e)
            })
        }

def start_diagnosis_session(event: Dict[str, Any], headers: Dict[str, str]) -> Dict[str, Any]:
    """새로운 진단 세션 시작"""

    try:
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})

        user_id = body.get('user_id')
        session_name = body.get('session_name', f'진단_{int(time.time())}')

        if not user_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'user_id is required'})
            }

        # 진단 세션 ID 생성
        import uuid
        session_id = str(uuid.uuid4())
        timestamp = int(time.time())

        # 진단 세션 초기화
        session_data = {
            'diagnosis_session_id': session_id,
            'user_id': user_id,
            'session_name': session_name,
            'status': 'in_progress',
            'timestamp': timestamp,
            'created_at': time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(timestamp)),
            'required_analyses': ['eye-tracking', 'finger-tapping', 'voice-analysis'],
            'completed_analyses': [],
            'analyses': {
                'eye-tracking': {'status': 'pending', 'analysis_id': None},
                'finger-tapping': {'status': 'pending', 'analysis_id': None},
                'voice-analysis': {'status': 'pending', 'analysis_id': None}
            },
            'comprehensive_result': None
        }

        comprehensive_table.put_item(Item=session_data)

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'diagnosis_session_id': session_id,
                'status': 'in_progress',
                'required_analyses': session_data['required_analyses'],
                'message': 'Diagnosis session started successfully'
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to start diagnosis session',
                'details': str(e)
            })
        }

def get_diagnosis_status(event: Dict[str, Any], headers: Dict[str, str]) -> Dict[str, Any]:
    """진단 세션 상태 조회"""

    try:
        path_parameters = event.get('pathParameters', {}) or {}
        session_id = path_parameters.get('session_id')

        if not session_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'session_id is required'})
            }

        # 세션 데이터 조회
        response = comprehensive_table.get_item(Key={'diagnosis_session_id': session_id})

        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({'error': 'Diagnosis session not found'})
            }

        session_data = response['Item']

        # 개별 분석 상태 업데이트
        updated_session = update_analysis_status(session_data)

        # 모든 분석 완료 확인
        if check_all_analyses_completed(updated_session):
            comprehensive_result = generate_comprehensive_result(updated_session)
            updated_session['comprehensive_result'] = comprehensive_result
            updated_session['status'] = 'completed'

            # DynamoDB 업데이트
            comprehensive_table.put_item(Item=updated_session)

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(updated_session)
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to get diagnosis status',
                'details': str(e)
            })
        }

def update_analysis_status(session_data: Dict[str, Any]) -> Dict[str, Any]:
    """개별 분석 상태를 실시간으로 업데이트"""

    analyses = session_data.get('analyses', {})

    for analysis_type, analysis_info in analyses.items():
        if analysis_info.get('status') == 'pending':
            continue

        analysis_id = analysis_info.get('analysis_id')
        if not analysis_id:
            continue

        # 해당 테이블에서 상태 조회
        table_map = {
            'eye-tracking': eye_table,
            'finger-tapping': finger_table,
            'voice-analysis': voice_table
        }

        table = table_map.get(analysis_type)
        if not table:
            continue

        try:
            response = table.get_item(Key={'analysis_id': analysis_id})
            if 'Item' in response:
                item = response['Item']
                analyses[analysis_type].update({
                    'status': item.get('status', 'unknown'),
                    'progress': item.get('progress', 0),
                    'completion_time': item.get('completed_at'),
                    'parkinson_probability': extract_parkinson_probability(item, analysis_type)
                })
        except Exception as e:
            print(f"Error updating {analysis_type} status: {str(e)}")

    session_data['analyses'] = analyses
    session_data['completed_analyses'] = [
        analysis_type for analysis_type, info in analyses.items()
        if info.get('status') == 'completed'
    ]

    return session_data

def extract_parkinson_probability(analysis_result: Dict[str, Any], analysis_type: str) -> Optional[float]:
    """분석 결과에서 파킨슨병 확률 추출"""

    try:
        results = analysis_result.get('results') or analysis_result.get('result')
        if not results:
            return None

        if analysis_type == 'eye-tracking':
            # PSP screening 결과에서 추출
            psp = results.get('psp_screening', {})
            if psp.get('suspected', False):
                return 0.8  # 높은 확률
            else:
                return 0.2  # 낮은 확률

        elif analysis_type == 'finger-tapping':
            # Combined result에서 추출
            combined = results.get('combined_result', {})
            return combined.get('probability', 0.5)

        elif analysis_type == 'voice-analysis':
            # Ensemble result에서 추출
            ensemble = results.get('ensemble_result', {})
            return ensemble.get('ensemble_probability', 0.5)

        return 0.5  # 기본값

    except Exception as e:
        print(f"Error extracting probability for {analysis_type}: {str(e)}")
        return None

def check_all_analyses_completed(session_data: Dict[str, Any]) -> bool:
    """모든 분석이 완료되었는지 확인"""

    analyses = session_data.get('analyses', {})
    required_analyses = session_data.get('required_analyses', [])

    for analysis_type in required_analyses:
        if analysis_type not in analyses:
            return False
        if analyses[analysis_type].get('status') != 'completed':
            return False

    return True

def generate_comprehensive_result(session_data: Dict[str, Any]) -> Dict[str, Any]:
    """종합 진단 결과 생성"""

    try:
        analyses = session_data.get('analyses', {})

        # 개별 확률들 수집
        probabilities = []
        individual_scores = {}

        for analysis_type, analysis_info in analyses.items():
            prob = analysis_info.get('parkinson_probability')
            if prob is not None:
                probabilities.append(prob)
                individual_scores[analysis_type] = prob

        if not probabilities:
            return {'error': 'No valid analysis results found'}

        # 가중 평균 계산 (음성 분석에 더 높은 가중치)
        weights = {
            'eye-tracking': 0.25,
            'finger-tapping': 0.35,
            'voice-analysis': 0.40
        }

        weighted_sum = 0
        total_weight = 0

        for analysis_type, prob in individual_scores.items():
            weight = weights.get(analysis_type, 0.33)
            weighted_sum += prob * weight
            total_weight += weight

        overall_probability = weighted_sum / total_weight if total_weight > 0 else np.mean(probabilities)

        # 평가 등급 결정
        if overall_probability > 0.8:
            assessment = "파킨슨병 징후 매우 강하게 의심"
            confidence = "very_high"
        elif overall_probability > 0.65:
            assessment = "파킨슨병 징후 강하게 의심"
            confidence = "high"
        elif overall_probability > 0.4:
            assessment = "파킨슨병 징후 중등도 의심"
            confidence = "medium"
        elif overall_probability > 0.25:
            assessment = "파킨슨병 징후 경미하게 의심"
            confidence = "low"
        else:
            assessment = "정상 범위"
            confidence = "medium"

        # 주요 지표 생성
        dominant_indicators = generate_dominant_indicators(individual_scores)
        recommendations = generate_recommendations(overall_probability, individual_scores)

        return {
            'overall_parkinson_probability': round(overall_probability, 3),
            'confidence_level': confidence,
            'assessment': assessment,
            'individual_scores': individual_scores,
            'dominant_indicators': dominant_indicators,
            'recommendations': recommendations,
            'analysis_summary': {
                'highest_risk_factor': max(individual_scores.items(), key=lambda x: x[1]),
                'lowest_risk_factor': min(individual_scores.items(), key=lambda x: x[1]),
                'risk_distribution': calculate_risk_distribution(individual_scores)
            },
            'generated_at': int(time.time())
        }

    except Exception as e:
        return {'error': f'Failed to generate comprehensive result: {str(e)}'}

def generate_dominant_indicators(scores: Dict[str, float]) -> List[str]:
    """주요 지표 생성"""

    indicators = []

    for analysis_type, score in scores.items():
        if score > 0.7:
            if analysis_type == 'eye-tracking':
                indicators.append("안구 운동에서 현저한 이상 감지")
            elif analysis_type == 'finger-tapping':
                indicators.append("손가락 탭핑에서 심각한 리듬 불규칙성")
            elif analysis_type == 'voice-analysis':
                indicators.append("음성 분석에서 강한 파킨슨병 징후")
        elif score > 0.5:
            if analysis_type == 'eye-tracking':
                indicators.append("안구 운동에서 경미한 이상")
            elif analysis_type == 'finger-tapping':
                indicators.append("손가락 탭핑에서 리듬 불규칙성")
            elif analysis_type == 'voice-analysis':
                indicators.append("음성 떨림 및 단조로운 말투 감지")

    if not indicators:
        indicators.append("모든 분석에서 정상 범위 내 결과")

    return indicators

def generate_recommendations(overall_prob: float, scores: Dict[str, float]) -> List[str]:
    """권장사항 생성"""

    recommendations = []

    if overall_prob > 0.7:
        recommendations.append("신경과 전문의 상담을 즉시 권장합니다")
        recommendations.append("MRI 및 DAT 스캔 검사를 고려해보세요")
    elif overall_prob > 0.5:
        recommendations.append("신경과 전문의 상담을 권장합니다")
        recommendations.append("3개월 후 재검사를 권장합니다")
    elif overall_prob > 0.3:
        recommendations.append("6개월 후 재검사를 권장합니다")
        recommendations.append("규칙적인 운동을 통한 예방 관리")
    else:
        recommendations.append("현재 상태는 양호합니다")
        recommendations.append("1년 후 정기 검진을 권장합니다")

    # 개별 분석 기반 권장사항
    if scores.get('voice-analysis', 0) > 0.6:
        recommendations.append("음성 치료를 고려해보세요")
    if scores.get('finger-tapping', 0) > 0.6:
        recommendations.append("손가락 운동 및 물리치료를 권장합니다")

    return recommendations

def calculate_risk_distribution(scores: Dict[str, float]) -> Dict[str, str]:
    """위험도 분포 계산"""

    distribution = {}

    for analysis_type, score in scores.items():
        if score > 0.7:
            level = "높음"
        elif score > 0.5:
            level = "중간"
        elif score > 0.3:
            level = "낮음"
        else:
            level = "정상"

        distribution[analysis_type] = level

    return distribution

def get_user_diagnosis_history(event: Dict[str, Any], headers: Dict[str, str]) -> Dict[str, Any]:
    """사용자별 진단 이력 조회"""

    try:
        path_parameters = event.get('pathParameters', {}) or {}
        user_id = path_parameters.get('user_id')

        if not user_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'user_id is required'})
            }

        # user_id-timestamp-index로 조회
        response = comprehensive_table.query(
            IndexName='user_id-timestamp-index',
            KeyConditionExpression=Key('user_id').eq(user_id),
            ScanIndexForward=False  # 최신순
        )

        sessions = response.get('Items', [])

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'user_id': user_id,
                'total_sessions': len(sessions),
                'diagnosis_history': sessions
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to get diagnosis history',
                'details': str(e)
            })
        }

def complete_diagnosis_session(event: Dict[str, Any], headers: Dict[str, str]) -> Dict[str, Any]:
    """진단 세션 강제 완료 (수동 트리거용)"""

    try:
        path_parameters = event.get('pathParameters', {}) or {}
        session_id = path_parameters.get('session_id')

        if not session_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'session_id is required'})
            }

        # 세션 조회 및 강제 완료
        response = comprehensive_table.get_item(Key={'diagnosis_session_id': session_id})

        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({'error': 'Session not found'})
            }

        session_data = response['Item']
        updated_session = update_analysis_status(session_data)

        # 완료된 분석들로만 종합 결과 생성
        comprehensive_result = generate_comprehensive_result(updated_session)
        updated_session['comprehensive_result'] = comprehensive_result
        updated_session['status'] = 'completed'

        comprehensive_table.put_item(Item=updated_session)

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': 'Diagnosis session completed',
                'comprehensive_result': comprehensive_result
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to complete diagnosis session',
                'details': str(e)
            })
        }