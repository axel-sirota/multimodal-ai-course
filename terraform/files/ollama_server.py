#!/usr/bin/env python3
import os
import json
import time
import subprocess
import threading
import logging
from datetime import datetime
from flask import Flask, request, jsonify
import requests
import boto3
import psutil

# Configuration
TOKEN = os.environ.get('API_TOKEN', '4cbd67c87dd9080c464f0427547942eee4b1a9b76ddf6eec241f0ca60fbea2db')
OLLAMA_URL = "http://localhost:11434"
LOG_GROUP = os.environ.get('LOG_GROUP', '/aws/ec2/ollama-course')
REGION = os.environ.get('AWS_REGION', 'us-east-1')
DEFAULT_MODEL = "qwen3:8b"
PORT = 8080

os.environ['HOME'] = '/home/ubuntu'

app = Flask(__name__)
pulled_models = set()

try:
    INSTANCE_ID = requests.get("http://169.254.169.254/latest/meta-data/instance-id", timeout=2).text
except:
    INSTANCE_ID = "local"

class CloudWatchHandler(logging.Handler):
    def __init__(self):
        super().__init__()
        try:
            self.logs_client = boto3.client('logs', region_name=REGION)
            self.sequence_token = None
        except:
            self.logs_client = None
        
    def emit(self, record):
        if not self.logs_client:
            return
        try:
            log_message = self.format(record)
            timestamp = int(time.time() * 1000)
            params = {
                'logGroupName': LOG_GROUP,
                'logStreamName': 'main',
                'logEvents': [{'timestamp': timestamp, 'message': log_message}]
            }
            if self.sequence_token:
                params['sequenceToken'] = self.sequence_token
            response = self.logs_client.put_log_events(**params)
            self.sequence_token = response.get('nextSequenceToken')
        except Exception as e:
            print(f"CloudWatch error: {e}")

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)
logger.addHandler(CloudWatchHandler())

gpu_metrics = {"utilization": 0, "memory_used": 0, "memory_total": 0, "temperature": 0}
gpu_metrics_lock = threading.Lock()
models_loaded = {}

def collect_gpu_metrics():
    while True:
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu', 
                 '--format=csv,noheader,nounits'],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                stats = result.stdout.strip().split(', ')
                with gpu_metrics_lock:
                    gpu_metrics['utilization'] = float(stats[0])
                    gpu_metrics['memory_used'] = float(stats[1])
                    gpu_metrics['memory_total'] = float(stats[2])
                    gpu_metrics['temperature'] = float(stats[3])
                if gpu_metrics['utilization'] > 20 or time.time() % 30 < 2:
                    memory_percent = (gpu_metrics['memory_used'] / gpu_metrics['memory_total']) * 100 if gpu_metrics['memory_total'] > 0 else 0
                    logger.info(f"GPU_METRICS: util={gpu_metrics['utilization']:.1f}% | mem={gpu_metrics['memory_used']:.0f}/{gpu_metrics['memory_total']:.0f}MB ({memory_percent:.1f}%) | temp={gpu_metrics['temperature']:.0f}C")
        except:
            pass
        time.sleep(2)

gpu_thread = threading.Thread(target=collect_gpu_metrics, daemon=True)
gpu_thread.start()

def check_auth():
    auth = request.headers.get('Authorization')
    if not auth or auth != f"Bearer {TOKEN}":
        return False
    return True

def get_ollama_models():
    try:
        response = requests.get(f"{OLLAMA_URL}/api/tags")
        if response.status_code == 200:
            models = response.json().get('models', [])
            return [model['name'] for model in models]
    except:
        pass
    return []

@app.route('/health', methods=['GET'])
def health():
    try:
        response = requests.get(f"{OLLAMA_URL}/api/tags")
        models = response.json().get('models', [])
        model_list = [
            {
                "name": model['name'],
                "size": f"{model.get('size', 0) / 1e9:.1f}GB",
                "is_default": model['name'] in ['qwen3:8b', 'qwen3:4b-instruct']
            }
            for model in models
        ]
        for model in models:
            pulled_models.add(model['name'])
        return jsonify({
            "status": "healthy",
            "instance": INSTANCE_ID,
            "models_available": model_list,
            "models_count": len(models),
            "default_model": DEFAULT_MODEL,
            "timestamp": datetime.utcnow().isoformat()
        })
    except Exception as e:
        logger.error(f"Health check error: {e}")
        return jsonify({"status": "unhealthy", "error": str(e)}), 500

@app.route('/startup', methods=['POST'])
def startup():
    """Initialize the server by pulling default models"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    logger.info("Starting model initialization...")
    results = []
    
    # Pull default models
    default_models = ["qwen3:8b", "qwen3:4b-instruct"]
    
    for model_name in default_models:
        logger.info(f"Pulling model: {model_name}")
        try:
            response = requests.post(f"{OLLAMA_URL}/api/pull", json={"name": model_name}, stream=True)
            last_status = ""
            for line in response.iter_lines():
                if line:
                    data = json.loads(line)
                    if 'status' in data:
                        status = data['status']
                        if 'completed' in data and 'total' in data:
                            percent = (data['completed'] / data['total']) * 100
                            last_status = f"{status} - {percent:.1f}%"
                            logger.info(f"Model {model_name}: {last_status}")
                        else:
                            last_status = status
                            logger.info(f"Model {model_name}: {status}")
            
            pulled_models.add(model_name)
            results.append({"model": model_name, "status": "success", "message": last_status})
        except Exception as e:
            logger.error(f"Failed to pull {model_name}: {str(e)}")
            results.append({"model": model_name, "status": "error", "message": str(e)})
    
    # Test models by loading them
    for model_name in default_models:
        if model_name in pulled_models:
            logger.info(f"Testing model: {model_name}")
            try:
                response = requests.post(f"{OLLAMA_URL}/api/generate", 
                                       json={"model": model_name, "prompt": "test", "stream": False})
                if response.status_code == 200:
                    models_loaded[model_name] = datetime.utcnow().isoformat()
                    logger.info(f"Model {model_name} tested successfully")
            except Exception as e:
                logger.error(f"Failed to test {model_name}: {str(e)}")
    
    return jsonify({
        "message": "Startup initialization complete",
        "results": results,
        "models_loaded": list(models_loaded.keys()),
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/pull_model', methods=['POST'])
def pull_model():
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    data = request.json
    if not data or 'model' not in data:
        return jsonify({"error": "Missing 'model' in request body"}), 400
    model_name = data['model']
    logger.info(f"Pulling model: {model_name}")
    try:
        response = requests.post(f"{OLLAMA_URL}/api/pull", json={"name": model_name}, stream=True)
        for line in response.iter_lines():
            if line:
                data = json.loads(line)
                if 'status' in data:
                    status = data['status']
                    if 'completed' in data and 'total' in data:
                        percent = (data['completed'] / data['total']) * 100
                        logger.info(f"Model {model_name}: {status} - {percent:.1f}%")
                    else:
                        logger.info(f"Model {model_name}: {status}")
        pulled_models.add(model_name)
        return jsonify({"success": True, "model": model_name, "message": f"Model {model_name} pulled successfully"})
    except Exception as e:
        logger.error(f"Error pulling model {model_name}: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/serve_model', methods=['POST'])
def serve_model():
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    data = request.json
    if not data or 'model' not in data:
        return jsonify({"error": "Missing 'model' in request body"}), 400
    model_name = data['model']
    available_models = get_ollama_models()
    if model_name not in available_models and model_name not in pulled_models:
        return jsonify({"error": f"Model {model_name} not found", "available_models": list(available_models)}), 404
    logger.info(f"Loading model: {model_name}")
    try:
        response = requests.post(f"{OLLAMA_URL}/api/generate", json={"model": model_name, "prompt": "test", "stream": False})
        if response.status_code == 200:
            models_loaded[model_name] = datetime.utcnow().isoformat()
            logger.info(f"Model {model_name} loaded")
            return jsonify({"success": True, "model": model_name, "message": f"Model {model_name} loaded"})
        else:
            return jsonify({"error": f"Failed to load: {response.text}"}), 500
    except Exception as e:
        logger.error(f"Error loading model {model_name}: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    with gpu_metrics_lock:
        current_gpu = gpu_metrics.copy()
    if current_gpu['memory_total'] > 0:
        current_gpu['memory_percent'] = (current_gpu['memory_used'] / current_gpu['memory_total']) * 100
    else:
        current_gpu['memory_percent'] = 0
    return jsonify({
        "gpu": current_gpu,
        "system": {
            "cpu_percent": psutil.cpu_percent(interval=1),
            "memory_percent": psutil.virtual_memory().percent,
            "disk_percent": psutil.disk_usage('/').percent,
        },
        "models_loaded": models_loaded,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/think', methods=['POST'])
def think():
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    data = request.json
    if not data or 'prompt' not in data:
        return jsonify({"error": "Missing 'prompt' in request body"}), 400
    model_name = data.get('model', DEFAULT_MODEL)
    prompt = data['prompt']
    stream = data.get('stream', False)
    logger.info(f"Inference: model={model_name}, prompt_length={len(prompt)}")
    start_time = time.time()
    try:
        response = requests.post(f"{OLLAMA_URL}/api/generate", json={
            "model": model_name, "prompt": prompt, "stream": stream, "options": data.get('options', {})
        })
        if response.status_code == 200:
            result = response.json()
            duration = time.time() - start_time
            with gpu_metrics_lock:
                post_gpu = gpu_metrics.copy()
            logger.info(f"Inference done in {duration:.2f}s | GPU: {post_gpu['utilization']}% ({post_gpu['memory_used']}MB)")
            return jsonify({
                "model": model_name,
                "response": result.get('response', ''),
                "done": result.get('done', True),
                "total_duration": result.get('total_duration', 0),
                "gpu_utilization": post_gpu['utilization'],
                "inference_time": duration
            })
        else:
            return jsonify({"error": f"Ollama error: {response.text}"}), response.status_code
    except Exception as e:
        logger.error(f"Inference error: {str(e)}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    logger.info(f"Starting Ollama API on {INSTANCE_ID}")
    logger.info(f"CloudWatch: {LOG_GROUP}")
    logger.info("Endpoints: /health, /startup, /pull_model, /serve_model, /metrics, /think")
    logger.info(f"Default model: {DEFAULT_MODEL}")
    logger.info(f"Running on port: {PORT}")
    app.run(host='0.0.0.0', port=PORT, threaded=True)