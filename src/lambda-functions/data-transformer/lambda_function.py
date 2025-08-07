import json
import boto3
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any
import pandas as pd

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
s3_client = boto3.client('s3')
athena_client = boto3.client('athena')

# Environment variables
S3_BUCKET = os.environ.get('S3_BUCKET')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Transform and aggregate data from S3.
    
    Args:
        event: Lambda event (could be scheduled or triggered)
        context: Lambda context object
        
    Returns:
        Dict containing transformation results
    """
    try:
        logger.info("Starting data transformation process")
        
        # Get the time window for processing
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)  # Process last hour
        
        # Process aggregations
        aggregation_results = perform_aggregations(start_time, end_time)
        
        # Create summary statistics
        summary_stats = create_summary_statistics(start_time, end_time)
        
        # Store results
        store_aggregation_results(aggregation_results, summary_stats, end_time)
        
        logger.info("Data transformation completed successfully")
        
        return {
            'statusCode': 200,
            'message': 'Data transformation completed',
            'processed_window': {
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat()
            },
            'aggregation_count': len(aggregation_results),
            'summary_stats': summary_stats
        }
        
    except Exception as e:
        logger.error(f"Data transformation failed: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }

def perform_aggregations(start_time: datetime, end_time: datetime) -> List[Dict[str, Any]]:
    """
    Perform data aggregations for the specified time window.
    
    Args:
        start_time: Start of the time window
        end_time: End of the time window
        
    Returns:
        List of aggregation results
    """
    logger.info(f"Performing aggregations for window: {start_time} to {end_time}")
    
    # List objects in S3 for the time window
    objects = list_s3_objects_for_window(start_time, end_time)
    
    if not objects:
        logger.warning("No objects found for the specified time window")
        return []
    
    # Group data by sensor_id
    sensor_data = {}
    
    for obj_key in objects:
        try:
            # Get object from S3
            response = s3_client.get_object(Bucket=S3_BUCKET, Key=obj_key)
            data = json.loads(response['Body'].read().decode('utf-8'))
            
            sensor_id = data['sensor_id']
            if sensor_id not in sensor_data:
                sensor_data[sensor_id] = []
            
            sensor_data[sensor_id].append(data)
            
        except Exception as e:
            logger.warning(f"Failed to process object {obj_key}: {str(e)}")
            continue
    
    # Perform aggregations for each sensor
    aggregation_results = []
    
    for sensor_id, readings in sensor_data.items():
        try:
            aggregated = aggregate_sensor_data(sensor_id, readings, start_time, end_time)
            aggregation_results.append(aggregated)
        except Exception as e:
            logger.error(f"Failed to aggregate data for sensor {sensor_id}: {str(e)}")
    
    return aggregation_results

def list_s3_objects_for_window(start_time: datetime, end_time: datetime) -> List[str]:
    """
    List S3 objects within the specified time window.
    
    Args:
        start_time: Start of the time window
        end_time: End of the time window
        
    Returns:
        List of S3 object keys
    """
    objects = []
    
    # Generate prefixes for the time window
    current_time = start_time
    while current_time <= end_time:
        prefix = f"sensor-data/{current_time.strftime('%Y/%m/%d')}/hour={current_time.strftime('%H')}/"
        
        try:
            response = s3_client.list_objects_v2(
                Bucket=S3_BUCKET,
                Prefix=prefix
            )
            
            if 'Contents' in response:
                for obj in response['Contents']:
                    objects.append(obj['Key'])
                    
        except Exception as e:
            logger.warning(f"Failed to list objects with prefix {prefix}: {str(e)}")
        
        current_time += timedelta(hours=1)
    
    return objects

def aggregate_sensor_data(sensor_id: str, readings: List[Dict[str, Any]], 
                         start_time: datetime, end_time: datetime) -> Dict[str, Any]:
    """
    Aggregate data for a single sensor.
    
    Args:
        sensor_id: ID of the sensor
        readings: List of sensor readings
        start_time: Start of the aggregation window
        end_time: End of the aggregation window
        
    Returns:
        Aggregated sensor data
    """
    if not readings:
        return {}
    
    # Extract numeric values
    temperatures = [r['temperature'] for r in readings if 'temperature' in r]
    humidities = [r['humidity'] for r in readings if 'humidity' in r]
    quality_scores = [r.get('data_quality_score', 0) for r in readings]
    
    # Calculate aggregations
    aggregated = {
        'sensor_id': sensor_id,
        'aggregation_window': {
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat()
        },
        'record_count': len(readings),
        'temperature': {
            'avg': sum(temperatures) / len(temperatures) if temperatures else 0,
            'min': min(temperatures) if temperatures else 0,
            'max': max(temperatures) if temperatures else 0,
            'std': calculate_std_dev(temperatures) if len(temperatures) > 1 else 0
        },
        'humidity': {
            'avg': sum(humidities) / len(humidities) if humidities else 0,
            'min': min(humidities) if humidities else 0,
            'max': max(humidities) if humidities else 0,
            'std': calculate_std_dev(humidities) if len(humidities) > 1 else 0
        },
        'data_quality': {
            'avg_score': sum(quality_scores) / len(quality_scores) if quality_scores else 0,
            'high_quality_count': sum(1 for score in quality_scores if score > 0.8),
            'low_quality_count': sum(1 for score in quality_scores if score < 0.5)
        },
        'anomaly_detection': detect_anomalies(temperatures, humidities),
        'processed_timestamp': datetime.utcnow().isoformat()
    }
    
    return aggregated

def calculate_std_dev(values: List[float]) -> float:
    """Calculate standard deviation."""
    if len(values) < 2:
        return 0.0
    
    mean = sum(values) / len(values)
    variance = sum((x - mean) ** 2 for x in values) / len(values)
    return variance ** 0.5

def detect_anomalies(temperatures: List[float], humidities: List[float]) -> Dict[str, Any]:
    """
    Simple anomaly detection based on statistical thresholds.
    
    Args:
        temperatures: List of temperature readings
        humidities: List of humidity readings
        
    Returns:
        Anomaly detection results
    """
    anomalies = {
        'temperature_anomalies': 0,
        'humidity_anomalies': 0,
        'total_anomalies': 0
    }
    
    if temperatures:
        temp_mean = sum(temperatures) / len(temperatures)
        temp_std = calculate_std_dev(temperatures)
        
        # Flag values outside 2 standard deviations
        for temp in temperatures:
            if abs(temp - temp_mean) > 2 * temp_std:
                anomalies['temperature_anomalies'] += 1
    
    if humidities:
        humidity_mean = sum(humidities) / len(humidities)
        humidity_std = calculate_std_dev(humidities)
        
        # Flag values outside 2 standard deviations
        for humidity in humidities:
            if abs(humidity - humidity_mean) > 2 * humidity_std:
                anomalies['humidity_anomalies'] += 1
    
    anomalies['total_anomalies'] = anomalies['temperature_anomalies'] + anomalies['humidity_anomalies']
    
    return anomalies

def create_summary_statistics(start_time: datetime, end_time: datetime) -> Dict[str, Any]:
    """
    Create summary statistics for the processing window.
    
    Args:
        start_time: Start of the processing window
        end_time: End of the processing window
        
    Returns:
        Summary statistics
    """
    return {
        'processing_window': {
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'duration_hours': (end_time - start_time).total_seconds() / 3600
        },
        'processed_timestamp': datetime.utcnow().isoformat()
    }

def store_aggregation_results(aggregation_results: List[Dict[str, Any]], 
                            summary_stats: Dict[str, Any], 
                            end_time: datetime) -> None:
    """
    Store aggregation results in S3.
    
    Args:
        aggregation_results: List of aggregation results
        summary_stats: Summary statistics
        end_time: End time of the processing window
    """
    try:
        # Store aggregated data
        aggregated_data = {
            'aggregations': aggregation_results,
            'summary_stats': summary_stats,
            'metadata': {
                'total_sensors': len(aggregation_results),
                'processing_timestamp': datetime.utcnow().isoformat()
            }
        }
        
        # Generate S3 key for aggregated data
        s3_key = f"aggregated-data/{end_time.strftime('%Y/%m/%d')}/hour={end_time.strftime('%H')}/aggregated-{end_time.strftime('%Y%m%d-%H%M%S')}.json"
        
        # Store in S3
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(aggregated_data, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Stored aggregation results in S3: s3://{S3_BUCKET}/{s3_key}")
        
    except Exception as e:
        logger.error(f"Failed to store aggregation results: {str(e)}")
        raise
