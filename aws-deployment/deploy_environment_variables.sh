#!/bin/bash

# AWS 환경변수 통합 배포 스크립트
# 모든 Lambda 함수에 통일된 환경변수를 설정합니다.

set -e

echo "🚀 AWS 환경변수 통합 배포 시작..."

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# AWS 리전 설정
AWS_REGION=${AWS_REGION:-us-west-1}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-730335212232}

echo -e "${BLUE}AWS Region: $AWS_REGION${NC}"
echo -e "${BLUE}AWS Account ID: $AWS_ACCOUNT_ID${NC}"

# 공통 환경변수 정의
declare -A COMMON_ENV_VARS=(
    ["S3_BUCKET"]="seoul-ht-09"
    ["S3_MAIN_PREFIX"]="parasol"
    ["S3_UPLOAD_PREFIX"]="parasol/uploads"
    ["S3_RESULTS_PREFIX"]="parasol/results"
    ["EYE_TRACKING_RESULTS_TABLE"]="parasol-eye-tracking-results"
    ["FINGER_TAPPING_RESULTS_TABLE"]="parasol-finger-tapping-results"
    ["VOICE_ANALYSIS_RESULTS_TABLE"]="parasol-voice-analysis-results"
    ["FINGER_TAPPING_QUEUE_URL"]="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_ID/finger-tapping-processing.fifo"
    ["VOICE_ANALYSIS_QUEUE_URL"]="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_ID/voice-analysis-processing.fifo"
    ["PRESIGNED_URL_EXPIRATION_SECONDS"]="3600"
    ["MAX_HISTORY_RECORDS"]="100"
)

# Lambda 함수별 추가 환경변수
declare -A UPLOAD_ENV_VARS=(
    ["MAX_FILE_SIZE_MB"]="100"
    ["UPLOAD_TIMEOUT_SECONDS"]="300"
)

declare -A STATUS_ENV_VARS=()

declare -A FINGER_PROCESS_ENV_VARS=(
    ["MODEL_PATH"]="/opt/models/best_pipeline_recall_AdaBoost.joblib"
    ["MAX_PROCESSING_TIME_SECONDS"]="600"
    ["DEFAULT_THRESHOLD"]="0.5"
)

declare -A VOICE_PROCESS_ENV_VARS=(
    ["VOICE_MODEL_PATH"]="/opt/models/voice_analysis_model.joblib"
    ["AUDIO_SAMPLE_RATE"]="16000"
    ["MAX_AUDIO_DURATION_SECONDS"]="300"
)

# Lambda 함수 목록
LAMBDA_FUNCTIONS=(
    "parasol-unified-upload"
    "parasol-unified-status"
    "parasol-finger-process"
    "parasol-voice-process"
)

# 환경변수 업데이트 함수
update_lambda_env_vars() {
    local function_name=$1
    local -n env_vars_ref=$2

    echo -e "${YELLOW}📝 $function_name 환경변수 업데이트 중...${NC}"

    # 기존 환경변수 가져오기
    local current_env=$(aws lambda get-function-configuration \
        --function-name "$function_name" \
        --region "$AWS_REGION" \
        --query 'Environment.Variables' \
        --output json 2>/dev/null || echo '{}')

    if [ "$current_env" = "null" ] || [ "$current_env" = "" ]; then
        current_env='{}'
    fi

    # 새로운 환경변수 병합
    local merged_env="$current_env"
    for key in "${!env_vars_ref[@]}"; do
        local value="${env_vars_ref[$key]}"
        merged_env=$(echo "$merged_env" | jq --arg key "$key" --arg value "$value" '. + {($key): $value}')
    done

    # 환경변수 업데이트
    aws lambda update-function-configuration \
        --function-name "$function_name" \
        --environment "Variables=$merged_env" \
        --region "$AWS_REGION" > /dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $function_name 환경변수 업데이트 완료${NC}"
    else
        echo -e "${RED}❌ $function_name 환경변수 업데이트 실패${NC}"
        return 1
    fi
}

# 함수 존재 여부 확인
check_function_exists() {
    local function_name=$1
    aws lambda get-function --function-name "$function_name" --region "$AWS_REGION" > /dev/null 2>&1
    return $?
}

# DynamoDB 테이블 생성 (존재하지 않는 경우)
create_dynamodb_tables() {
    echo -e "${YELLOW}🗃️ DynamoDB 테이블 확인 및 생성...${NC}"

    local tables=(
        "parasol-eye-tracking-results"
        "parasol-finger-tapping-results"
        "parasol-voice-analysis-results"
    )

    for table in "${tables[@]}"; do
        aws dynamodb describe-table --table-name "$table" --region "$AWS_REGION" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}📋 $table 테이블 생성 중...${NC}"
            aws dynamodb create-table \
                --table-name "$table" \
                --attribute-definitions \
                    AttributeName=analysisId,AttributeType=S \
                    AttributeName=user_id,AttributeType=S \
                    AttributeName=timestamp,AttributeType=N \
                --key-schema \
                    AttributeName=analysisId,KeyType=HASH \
                --global-secondary-indexes \
                    IndexName=user-id-timestamp-index,KeySchema=[{AttributeName=user_id,KeyType=HASH},{AttributeName=timestamp,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
                --provisioned-throughput \
                    ReadCapacityUnits=5,WriteCapacityUnits=5 \
                --region "$AWS_REGION" > /dev/null

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ $table 테이블 생성 완료${NC}"
            else
                echo -e "${RED}❌ $table 테이블 생성 실패${NC}"
            fi
        else
            echo -e "${GREEN}✅ $table 테이블 이미 존재${NC}"
        fi
    done
}

# SQS 큐 생성 (존재하지 않는 경우)
create_sqs_queues() {
    echo -e "${YELLOW}📫 SQS 큐 확인 및 생성...${NC}"

    local queues=(
        "finger-tapping-processing.fifo"
        "voice-analysis-processing.fifo"
    )

    for queue in "${queues[@]}"; do
        aws sqs get-queue-url --queue-name "$queue" --region "$AWS_REGION" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}📮 $queue 큐 생성 중...${NC}"

            local attributes='{
                "FifoQueue": "true",
                "ContentBasedDeduplication": "true",
                "VisibilityTimeoutSeconds": "900",
                "MessageRetentionPeriod": "1209600"
            }'

            aws sqs create-queue \
                --queue-name "$queue" \
                --attributes "$attributes" \
                --region "$AWS_REGION" > /dev/null

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ $queue 큐 생성 완료${NC}"
            else
                echo -e "${RED}❌ $queue 큐 생성 실패${NC}"
            fi
        else
            echo -e "${GREEN}✅ $queue 큐 이미 존재${NC}"
        fi
    done
}

# S3 버킷 구조 생성
create_s3_structure() {
    echo -e "${YELLOW}🪣 S3 버킷 구조 확인 및 생성...${NC}"

    local s3_bucket="seoul-ht-09"
    local prefixes=(
        "parasol/uploads/videos/finger-tapping/"
        "parasol/uploads/audio/voice-analysis/"
        "parasol/uploads/data/eye-tracking/"
        "parasol/results/finger-tapping/"
        "parasol/results/voice-analysis/"
        "parasol/results/eye-tracking/"
    )

    for prefix in "${prefixes[@]}"; do
        aws s3api head-object --bucket "$s3_bucket" --key "${prefix}.keep" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}📁 s3://$s3_bucket/$prefix 구조 생성 중...${NC}"
            echo "" | aws s3 cp - "s3://$s3_bucket/${prefix}.keep"

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ s3://$s3_bucket/$prefix 구조 생성 완료${NC}"
            else
                echo -e "${RED}❌ s3://$s3_bucket/$prefix 구조 생성 실패${NC}"
            fi
        else
            echo -e "${GREEN}✅ s3://$s3_bucket/$prefix 구조 이미 존재${NC}"
        fi
    done
}

# 메인 실행 로직
main() {
    echo -e "${BLUE}🔍 AWS CLI 설정 확인...${NC}"

    # AWS CLI 설치 확인
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI가 설치되지 않았습니다.${NC}"
        exit 1
    fi

    # jq 설치 확인
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ jq가 설치되지 않았습니다.${NC}"
        exit 1
    fi

    # AWS 자격 증명 확인
    aws sts get-caller-identity --region "$AWS_REGION" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ AWS 자격 증명이 설정되지 않았습니다.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ AWS CLI 설정 확인 완료${NC}"

    # 리소스 생성
    create_dynamodb_tables
    create_sqs_queues
    create_s3_structure

    # Lambda 함수별 환경변수 업데이트
    echo -e "${BLUE}🔧 Lambda 함수 환경변수 업데이트...${NC}"

    # parasol-unified-upload
    if check_function_exists "parasol-unified-upload"; then
        declare -A upload_env
        for key in "${!COMMON_ENV_VARS[@]}"; do
            upload_env["$key"]="${COMMON_ENV_VARS[$key]}"
        done
        for key in "${!UPLOAD_ENV_VARS[@]}"; do
            upload_env["$key"]="${UPLOAD_ENV_VARS[$key]}"
        done
        update_lambda_env_vars "parasol-unified-upload" upload_env
    else
        echo -e "${YELLOW}⚠️ parasol-unified-upload 함수가 존재하지 않습니다.${NC}"
    fi

    # parasol-unified-status
    if check_function_exists "parasol-unified-status"; then
        declare -A status_env
        for key in "${!COMMON_ENV_VARS[@]}"; do
            status_env["$key"]="${COMMON_ENV_VARS[$key]}"
        done
        for key in "${!STATUS_ENV_VARS[@]}"; do
            status_env["$key"]="${STATUS_ENV_VARS[$key]}"
        done
        update_lambda_env_vars "parasol-unified-status" status_env
    else
        echo -e "${YELLOW}⚠️ parasol-unified-status 함수가 존재하지 않습니다.${NC}"
    fi

    # parasol-finger-process
    if check_function_exists "parasol-finger-process"; then
        declare -A finger_env
        for key in "${!COMMON_ENV_VARS[@]}"; do
            finger_env["$key"]="${COMMON_ENV_VARS[$key]}"
        done
        for key in "${!FINGER_PROCESS_ENV_VARS[@]}"; do
            finger_env["$key"]="${FINGER_PROCESS_ENV_VARS[$key]}"
        done
        update_lambda_env_vars "parasol-finger-process" finger_env
    else
        echo -e "${YELLOW}⚠️ parasol-finger-process 함수가 존재하지 않습니다.${NC}"
    fi

    # parasol-voice-process (향후 구현)
    if check_function_exists "parasol-voice-process"; then
        declare -A voice_env
        for key in "${!COMMON_ENV_VARS[@]}"; do
            voice_env["$key"]="${COMMON_ENV_VARS[$key]}"
        done
        for key in "${!VOICE_PROCESS_ENV_VARS[@]}"; do
            voice_env["$key"]="${VOICE_PROCESS_ENV_VARS[$key]}"
        done
        update_lambda_env_vars "parasol-voice-process" voice_env
    else
        echo -e "${YELLOW}⚠️ parasol-voice-process 함수가 존재하지 않습니다 (향후 구현 예정).${NC}"
    fi

    echo -e "${GREEN}🎉 AWS 환경변수 통합 배포 완료!${NC}"
    echo ""
    echo -e "${BLUE}📋 배포된 설정 요약:${NC}"
    echo -e "  • S3 Bucket: ${COMMON_ENV_VARS[S3_BUCKET]}"
    echo -e "  • Main Prefix: ${COMMON_ENV_VARS[S3_MAIN_PREFIX]}"
    echo -e "  • DynamoDB Tables: 3개 테이블"
    echo -e "  • SQS Queues: 2개 FIFO 큐"
    echo -e "  • Lambda Functions: $(echo "${LAMBDA_FUNCTIONS[@]}" | wc -w)개 함수 환경변수 업데이트"
    echo ""
    echo -e "${YELLOW}💡 다음 단계:${NC}"
    echo -e "  1. Flutter 앱에서 새로운 AwsConfig 사용"
    echo -e "  2. Lambda 함수 재배포 (필요시)"
    echo -e "  3. 전체 시스템 테스트"
}

# 스크립트 실행
main "$@"