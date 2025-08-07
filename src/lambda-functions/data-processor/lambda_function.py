import json
import base64
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# Environment variables
S3_BUCKET = os.environ.get('S3_BUCKET')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process incoming Kinesis records and store them in S3.
    
    Args:
        event: Kinesis event containing records
        context: Lambda context object
        
    Returns:
        Dict containing processing results
    """
    try:
        logger.info(f"Processing {len(event['Records'])} records")
        
        processed_records = []
        failed_records = []
        
        for record in event['Records']:
            try:
                # Decode Kinesis record
                kinesis_data = record['kinesis']
                payload = base64.b64decode(kinesis_data['data']).decode('utf-8')
                data = json.loads(payload)
                
                # Validate and enrich data
                enriched_data = validate_and_enrich_record(data)
                
                # Store in S3
                s3_key = generate_s3_key(enriched_data)
                store_in_s3(enriched_data, s3_key)
                
                processed_records.append({
                    'recordId': record['recordId'],
                    's3_key': s3_key,
                    'status': 'success'
                })
                
                logger.debug(f"Successfully processed record: {record['recordId']}")
                
            except Exception as e:
                logger.error(f"Failed to process record {record.get('recordId', 'unknown')}: {str(e)}")
                failed_records.append({
                    'recordId': record.get('recordId', 'unknown'),
                    'error': str(e),
                    'status': 'failed'
                })
        
        # Log processing summary
        logger.info(f"Processing complete. Success: {len(processed_records)}, Failed: {len(failed_records)}")
        
        return {
            'statusCode': 200,
            'processed_count': len(processed_records),
            'failed_count': len(failed_records),
            'processed_records': processed_records,
            'failed_records': failed_records
        }
        
    except Exception as e:
        logger.error(f"Lambda function failed: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }

def validate_and_enrich_record(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate incoming data and add enrichment fields.
    
    Args:
        data: Raw data from Kinesis record
        
    Returns:
        Dict containing validated and enriched data
    """
    # Validate required fields
    required_fields = ['sensor_id', 'temperature', 'humidity']
    for field in required_fields:
        if field not in data:
            raise ValueError(f"Missing required field: {field}")
    
    # Validate data types and ranges
    if not isinstance(data['temperature'], (int, float)):
        raise ValueError("Temperature must be a number")
    
    if not isinstance(data['humidity'], (int, float)):
        raise ValueError("Humidity must be a number")
        
    if not (0 <= data['humidity'] <= 100):
        raise ValueError("Humidity must be between 0 and 100")
    
    # Add enrichment fields
    enriched_data = data.copy()
    enriched_data.update({
        'processed_timestamp': datetime.utcnow().isoformat(),
        'temperature_celsius': data['temperature'],
        'temperature_fahrenheit': (data['temperature'] * 9/5) + 32,
        'data_quality_score': calculate_quality_score(data),
        'partition_date': datetime.utcnow().strftime('%Y/%m/%d'),
        'partition_hour': datetime.utcnow().strftime('%H')
    })
    
    return enriched_data

def calculate_quality_score(data: Dict[str, Any]) -> float:
    """
    Calculate a data quality score based on various factors.
    
    Args:
        data: Data record to score
        
    Returns:
        Quality score between 0 and 1
    """
    score = 1.0
    
    # Check for realistic temperature ranges
    temp = data['temperature']
    if temp < -50 or temp > 70:  # Extreme temperatures
        score -= 0.3
    elif temp < -20 or temp > 50:  # Unusual temperatures
        score -= 0.1
    
    # Check for realistic humidity
    humidity = data['humidity']
    if humidity < 0 or humidity > 100:
        score -= 0.4
    
    # Check if timestamp is present and recent
    if 'timestamp' in data:
        try:
            record_time = datetime.fromisoformat(data['timestamp'].replace('Z', '+00:00'))
            time_diff = datetime.utcnow() - record_time.replace(tzinfo=None)
            if time_diff.total_seconds() > 3600:  # Older than 1 hour
                score -= 0.2
        except:
            score -= 0.1
    
    return max(0.0, score)

def generate_s3_key(data: Dict[str, Any]) -> str:
    """
    Generate S3 key for storing the record.
    
    Args:
        data: Processed data record
        
    Returns:
        S3 key string
    """
    partition_date = data['partition_date']
    partition_hour = data['partition_hour']
    sensor_id = data['sensor_id']
    timestamp = data['processed_timestamp'].replace(':', '-').replace('.', '-')
    
    return f"sensor-data/{partition_date}/hour={partition_hour}/sensor_id={sensor_id}/{timestamp}.json"

def store_in_s3(data: Dict[str, Any], s3_key: str) -> None:
    """
    Store processed data in S3.
    
    Args:
        data: Data to store
        s3_key: S3 key for the object
    """
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(data, indent=2),
            ContentType='application/json',
            Metadata={
                'sensor_id': data['sensor_id'],
                'quality_score': str(data['data_quality_score']),
                'processed_timestamp': data['processed_timestamp']
            }
        )
        logger.debug(f"Stored data in S3: s3://{S3_BUCKET}/{s3_key}")
        
    except Exception as e:
        logger.error(f"Failed to store data in S3: {str(e)}")
        raise
