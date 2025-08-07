# DynamoDB table for metadata and configuration
resource "aws_dynamodb_table" "metadata" {
  name           = "${var.project_name}-metadata-${var.name_suffix}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pk"
  range_key      = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "gsi1_pk"
    type = "S"
  }

  attribute {
    name = "gsi1_sk"
    type = "S"
  }

  global_secondary_index {
    name               = "GSI1"
    hash_key           = "gsi1_pk"
    range_key          = "gsi1_sk"
    projection_type    = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

# DynamoDB table for sensor configuration
resource "aws_dynamodb_table" "sensors" {
  name           = "${var.project_name}-sensors-${var.name_suffix}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "sensor_id"

  attribute {
    name = "sensor_id"
    type = "S"
  }

  attribute {
    name = "location"
    type = "S"
  }

  global_secondary_index {
    name               = "LocationIndex"
    hash_key           = "location"
    projection_type    = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

# DynamoDB table for aggregated metrics
resource "aws_dynamodb_table" "metrics" {
  name           = "${var.project_name}-metrics-${var.name_suffix}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "metric_id"
  range_key      = "timestamp"

  attribute {
    name = "metric_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "sensor_id"
    type = "S"
  }

  global_secondary_index {
    name               = "SensorIndex"
    hash_key           = "sensor_id"
    range_key          = "timestamp"
    projection_type    = "ALL"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

# Populate initial sensor data
resource "aws_dynamodb_table_item" "sensor_configs" {
  for_each = local.default_sensors
  
  table_name = aws_dynamodb_table.sensors.name
  hash_key   = aws_dynamodb_table.sensors.hash_key
  
  item = jsonencode({
    sensor_id = {
      S = each.key
    }
    location = {
      S = each.value.location
    }
    base_temperature = {
      N = tostring(each.value.base_temperature)
    }
    base_humidity = {
      N = tostring(each.value.base_humidity)
    }
    temp_variance = {
      N = tostring(each.value.temp_variance)
    }
    humidity_variance = {
      N = tostring(each.value.humidity_variance)
    }
    anomaly_probability = {
      N = tostring(each.value.anomaly_probability)
    }
    created_at = {
      S = timestamp()
    }
    active = {
      BOOL = true
    }
  })
}

locals {
  default_sensors = {
    "temp_001" = {
      location = "Building_A_Floor_1"
      base_temperature = 22.0
      base_humidity = 45.0
      temp_variance = 5.0
      humidity_variance = 15.0
      anomaly_probability = 0.02
    }
    "temp_002" = {
      location = "Building_A_Floor_2"
      base_temperature = 21.0
      base_humidity = 48.0
      temp_variance = 5.0
      humidity_variance = 15.0
      anomaly_probability = 0.02
    }
    "temp_003" = {
      location = "Building_B_Floor_1"
      base_temperature = 23.0
      base_humidity = 42.0
      temp_variance = 5.0
      humidity_variance = 15.0
      anomaly_probability = 0.02
    }
    "temp_004" = {
      location = "Building_B_Floor_2"
      base_temperature = 20.0
      base_humidity = 50.0
      temp_variance = 5.0
      humidity_variance = 15.0
      anomaly_probability = 0.02
    }
    "temp_005" = {
      location = "Warehouse_North"
      base_temperature = 18.0
      base_humidity = 55.0
      temp_variance = 5.0
      humidity_variance = 15.0
      anomaly_probability = 0.02
    }
    "temp_006" = {
      location = "Warehouse_South"
      base_temperature = 19.0
      base_humidity = 52.0
      temp_variance = 5.0
      humidity_variance = 15.0
      anomaly_probability = 0.02
    }
    "temp_007" = {
      location = "Data_Center"
      base_temperature = 16.0
      base_humidity = 30.0
      temp_variance = 3.0
      humidity_variance = 10.0
      anomaly_probability = 0.01
    }
    "temp_008" = {
      location = "Server_Room"
      base_temperature = 15.0
      base_humidity = 25.0
      temp_variance = 3.0
      humidity_variance = 10.0
      anomaly_probability = 0.01
    }
  }
}
