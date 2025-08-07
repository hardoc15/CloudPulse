"""

This application generates realistic IoT sensor data and sends it to the CloudPulse
data pipeline via API Gateway or directly to Kinesis.
"""

import json
import time
import random
import argparse
import logging
import requests
import boto3
from datetime import datetime, timezone
from typing import Dict, List, Any
from concurrent.futures import ThreadPoolExecutor
import threading
from dataclasses import dataclass

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class SensorConfig:
    """Configuration for a sensor"""
    sensor_id: str
    location: str
    base_temperature: float = 20.0
    base_humidity: float = 50.0
    temp_variance: float = 5.0
    humidity_variance: float = 15.0
    anomaly_probability: float = 0.02

class IoTDataGenerator:
    """IoT sensor data generator"""
    
    def __init__(self, config_file: str = None):
        """Initialize the data generator"""
        self.sensors = self._load_sensor_config(config_file)
        self.running = False
        self.stats = {
            'total_sent': 0,
            'total_errors': 0,
            'start_time': None
        }
        self.stats_lock = threading.Lock()
        
    def _load_sensor_config(self, config_file: str) -> List[SensorConfig]:
        """Load sensor configuration"""
        if config_file:
            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)
                return [SensorConfig(**sensor) for sensor in config['sensors']]
            except Exception as e:
                logger.warning(f"Failed to load config file: {e}. Using default sensors.")
        
        return [
            SensorConfig("temp_001", "Building_A_Floor_1", 22.0, 45.0),
            SensorConfig("temp_002", "Building_A_Floor_2", 21.0, 48.0),
            SensorConfig("temp_003", "Building_B_Floor_1", 23.0, 42.0),
            SensorConfig("temp_004", "Building_B_Floor_2", 20.0, 50.0),
            SensorConfig("temp_005", "Warehouse_North", 18.0, 55.0),
            SensorConfig("temp_006", "Warehouse_South", 19.0, 52.0),
            SensorConfig("temp_007", "Data_Center", 16.0, 30.0, anomaly_probability=0.01),
            SensorConfig("temp_008", "Server_Room", 15.0, 25.0, anomaly_probability=0.01),
        ]
    
    def generate_sensor_reading(self, sensor: SensorConfig) -> Dict[str, Any]:
        """Generate a realistic sensor reading"""
        
        temperature = sensor.base_temperature + random.gauss(0, sensor.temp_variance)
        humidity = sensor.base_humidity + random.gauss(0, sensor.humidity_variance)
        
        humidity = max(0, min(100, humidity))
        
        hour = datetime.now().hour
        temp_adjustment = 3 * math.sin((hour - 14) * math.pi / 12)  # Peak at 2 PM
        temperature += temp_adjustment
        
        if random.random() < sensor.anomaly_probability:
            if random.choice([True, False]):
                temperature += random.uniform(15, 25)
            else:
                temperature -= random.uniform(10, 20)
            logger.debug(f"Generated anomaly for {sensor.sensor_id}: temp={temperature:.2f}")
        
        return {
            'sensor_id': sensor.sensor_id,
            'temperature': round(temperature, 2),
            'humidity': round(humidity, 2),
            'location': sensor.location,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
    
    def send_to_api_gateway(self, data: Dict[str, Any], endpoint: str) -> bool:
        try:
            response = requests.post(
                endpoint,
                json=data,
                timeout=10,
                headers={'Content-Type': 'application/json'}
            )
            response.raise_for_status()
            return True
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to send data to API Gateway: {e}")
            return False
    
    def send_to_kinesis(self, data: Dict[str, Any], stream_name: str) -> bool:
        try:
            kinesis_client = boto3.client('kinesis')
            response = kinesis_client.put_record(
                StreamName=stream_name,
                Data=json.dumps(data),
                PartitionKey=data['sensor_id']
            )
            return True
        except Exception as e:
            logger.error(f"Failed to send data to Kinesis: {e}")
            return False
    
    def send_data_batch(self, batch_data: List[Dict[str, Any]], endpoint: str = None, 
                       stream_name: str = None) -> int:
        success_count = 0
        
        for data in batch_data:
            success = False
            if endpoint:
                success = self.send_to_api_gateway(data, endpoint)
            elif stream_name:
                success = self.send_to_kinesis(data, stream_name)
            
            with self.stats_lock:
                if success:
                    self.stats['total_sent'] += 1
                    success_count += 1
                else:
                    self.stats['total_errors'] += 1
        
        return success_count
    
    def generate_batch(self, batch_size: int) -> List[Dict[str, Any]]:
        """Generate a batch of sensor readings"""
        batch = []
        for _ in range(batch_size):
            sensor = random.choice(self.sensors)
            reading = self.generate_sensor_reading(sensor)
            batch.append(reading)
        return batch
    
    def run_continuous(self, endpoint: str = None, stream_name: str = None,
                      rate: float = 10.0, batch_size: int = 10, 
                      duration: int = None, num_threads: int = 4):
        """Run continuous data generation"""
        
        logger.info(f"Starting continuous data generation...")
        logger.info(f"Rate: {rate} records/second, Batch size: {batch_size}")
        logger.info(f"Threads: {num_threads}, Duration: {duration or 'unlimited'} seconds")
        
        if endpoint:
            logger.info(f"Sending to API Gateway: {endpoint}")
        elif stream_name:
            logger.info(f"Sending to Kinesis stream: {stream_name}")
        
        self.running = True
        self.stats['start_time'] = time.time()
        
        interval = batch_size / rate
        
        with ThreadPoolExecutor(max_workers=num_threads) as executor:
            
            while self.running:
                start_time = time.time()
                
                batch = self.generate_batch(batch_size)
                
                future = executor.submit(
                    self.send_data_batch, batch, endpoint, stream_name
                )
                
                elapsed = time.time() - start_time
                sleep_time = max(0, interval - elapsed)
                
                if sleep_time > 0:
                    time.sleep(sleep_time)
                
                # Check duration limit
                if duration and (time.time() - self.stats['start_time']) >= duration:
                    logger.info("Duration limit reached, stopping...")
                    break
        
        self.running = False
        logger.info("Data generation stopped.")
    
    def print_stats(self):
        """Print current statistics"""
        with self.stats_lock:
            elapsed = time.time() - (self.stats['start_time'] or time.time())
            rate = self.stats['total_sent'] / max(elapsed, 1)
            error_rate = self.stats['total_errors'] / max(self.stats['total_sent'] + self.stats['total_errors'], 1)
            
            print(f"\n=== CloudPulse Data Generator Stats ===")
            print(f"Running time: {elapsed:.1f} seconds")
            print(f"Records sent: {self.stats['total_sent']}")
            print(f"Errors: {self.stats['total_errors']}")
            print(f"Success rate: {(1-error_rate)*100:.1f}%")
            print(f"Average rate: {rate:.2f} records/second")
            print("=" * 40)

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='CloudPulse IoT Data Generator')
    
    dest_group = parser.add_mutually_exclusive_group(required=False)
    dest_group.add_argument('--api-endpoint', help='API Gateway endpoint URL')
    dest_group.add_argument('--kinesis-stream', help='Kinesis stream name')
    
    parser.add_argument('--rate', type=float, default=10.0,
                       help='Records per second (default: 10)')
    parser.add_argument('--batch-size', type=int, default=10,
                       help='Batch size (default: 10)')
    parser.add_argument('--duration', type=int,
                       help='Duration in seconds (unlimited if not specified)')
    parser.add_argument('--threads', type=int, default=4,
                       help='Number of threads (default: 4)')
    parser.add_argument('--config', help='Sensor configuration file')
    
    parser.add_argument('--single', action='store_true',
                       help='Generate single record and exit')
    parser.add_argument('--test', action='store_true',
                       help='Test mode - generate sample data without sending')
    
    args = parser.parse_args()
    
    if not args.test and not args.api_endpoint and not args.kinesis_stream:
        parser.error("Either --api-endpoint or --kinesis-stream is required for non-test modes")
    
    generator = IoTDataGenerator(args.config)
    
    if args.test:
        batch = generator.generate_batch(5)
        print("Sample sensor data:")
        for reading in batch:
            print(json.dumps(reading, indent=2))
        return
    
    if args.single:
        reading = generator.generate_sensor_reading(generator.sensors[0])
        
        if args.api_endpoint:
            success = generator.send_to_api_gateway(reading, args.api_endpoint)
        else:
            success = generator.send_to_kinesis(reading, args.kinesis_stream)
        
        print(f"Single record {'sent successfully' if success else 'failed'}")
        print(json.dumps(reading, indent=2))
        return
    
    try:
        import threading
        stats_thread = threading.Thread(
            target=lambda: [
                time.sleep(10), generator.print_stats()
            ] * (args.duration // 10 + 1) if args.duration else [time.sleep(10), generator.print_stats()]
        )
        stats_thread.daemon = True
        stats_thread.start()
        
        generator.run_continuous(
            endpoint=args.api_endpoint,
            stream_name=args.kinesis_stream,
            rate=args.rate,
            batch_size=args.batch_size,
            duration=args.duration,
            num_threads=args.threads
        )
        
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        generator.running = False
    
    finally:
        generator.print_stats()

if __name__ == '__main__':
    import math
    main()
