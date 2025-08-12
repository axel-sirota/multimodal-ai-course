output "ollama_endpoint" {
  value = "http://${aws_instance.ollama_server.public_dns}"
}

output "ollama_endpoint_ip" {
  value = "http://${aws_eip.ollama_ip.public_ip}"
}

output "api_token" {
  value     = var.api_token
  sensitive = true
}

output "python_usage" {
  value = <<-EOT
    # Python usage in Colab:
    import requests
    
    OLLAMA_URL = "http://${aws_instance.ollama_server.public_dns}"
    TOKEN = "${var.api_token}"
    
    # Example using /think endpoint (defaults to qwen3:8b)
    response = requests.post(
        f"{OLLAMA_URL}/think",
        headers={"Authorization": f"Bearer {TOKEN}"},
        json={
            "prompt": "What is an invoice?"
        }
    )
    print(response.json())
    
    # Example with specific model (qwen3:4b-instruct)
    response = requests.post(
        f"{OLLAMA_URL}/think",
        headers={"Authorization": f"Bearer {TOKEN}"},
        json={
            "model": "qwen3:4b-instruct",
            "prompt": "Explain machine learning in simple terms"
        }
    )
    print(response.json())
  EOT
}

output "available_models" {
  value = <<-EOT
    Default models on this instance:
    - qwen3:8b - Dense thinking model (default for /think)
    - qwen3:4b-instruct - Smaller instruct model
    
    Check available models:
    curl http://${aws_instance.ollama_server.public_dns}/health
  EOT
}

output "monitoring_commands" {
  value = <<-EOT
    SSH into instance and run:
    - sudo journalctl -u ollama-app -f      # Check Python app logs
    - sudo journalctl -u ollama -f          # Check Ollama logs
    - nvidia-smi -l 1                       # Monitor GPU usage
    - curl http://localhost:8080/health     # Test Python app
    - curl http://localhost:11434/api/tags  # Test Ollama directly
  EOT
}

output "cloudwatch_logs" {
  value = <<-EOT
    CloudWatch Log Group: ${aws_cloudwatch_log_group.ollama_logs.name}
    
    View logs in AWS Console:
    https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${aws_cloudwatch_log_group.ollama_logs.name}
    
    Stream logs via CLI:
    aws logs tail ${aws_cloudwatch_log_group.ollama_logs.name} --follow --region ${var.aws_region}
  EOT
}

output "api_endpoints" {
  value = <<-EOT
    Base URL: http://${aws_instance.ollama_server.public_dns}
    
    Educational API Endpoints:
    - GET  /health       - Health check & model list (no auth)
    - GET  /metrics      - GPU and system metrics (no auth)
    - POST /startup      - Initialize and pull default models (requires auth)
    - POST /pull_model   - Pull a new model (requires auth)
    - POST /serve_model  - Load model into memory (requires auth)
    - POST /think        - Run inference (requires auth, defaults to qwen3:8b)
    
    Examples:
    # Check health & models
    curl http://${aws_instance.ollama_server.public_dns}/health
    
    # Initialize server with default models
    curl -X POST -H "Authorization: Bearer ${var.api_token}" \
         http://${aws_instance.ollama_server.public_dns}/startup
    
    # Pull a new model
    curl -X POST -H "Authorization: Bearer ${var.api_token}" \
         -H "Content-Type: application/json" \
         -d '{"model": "llama2:7b"}' \
         http://${aws_instance.ollama_server.public_dns}/pull_model
    
    # Think with default model (qwen3:8b)
    curl -X POST -H "Authorization: Bearer ${var.api_token}" \
         -H "Content-Type: application/json" \
         -d '{"prompt": "What is machine learning?"}' \
         http://${aws_instance.ollama_server.public_dns}/think
    
    # Check GPU metrics
    curl http://${aws_instance.ollama_server.public_dns}/metrics
  EOT
}