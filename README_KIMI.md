# Kimi-K2.5 RunPod Serverless Deployment Guide

This guide covers deploying Kimi-K2.5 on RunPod Serverless using vLLM 0.14.1.

## Model Information

- **Model**: `moonshotai/Kimi-K2.5`
- **Architecture**: Mixture of Experts (MoE)
- **Context Length**: 131,072 tokens
- **Recommended Setup**: 8x H100 GPUs with FP8 quantization

## Build Instructions

### Option 1: Build Without Model Baked In (Recommended for Large Models)

```bash
docker build -t your-dockerhub/kimi-k2.5-vllm:latest .
docker push your-dockerhub/kimi-k2.5-vllm:latest
```

The model will be downloaded at runtime to the network storage.

### Option 2: Build With Model Baked In

```bash
export DOCKER_BUILDKIT=1
export HF_TOKEN="your_huggingface_token"

docker build \
  --secret id=HF_TOKEN \
  --build-arg MODEL_NAME="moonshotai/Kimi-K2.5" \
  --build-arg BASE_PATH="/models" \
  --build-arg QUANTIZATION="fp8" \
  -t your-dockerhub/kimi-k2.5-vllm:baked .

docker push your-dockerhub/kimi-k2.5-vllm:baked
```

## RunPod Serverless Deployment

### Step 1: Create a Serverless Endpoint

1. Go to [RunPod Console](https://www.runpod.io/console/serverless)
2. Click "New Endpoint"
3. Select your Docker image: `your-dockerhub/kimi-k2.5-vllm:latest`

### Step 2: Configure Environment Variables

Set the following environment variables in the RunPod endpoint configuration:

| Variable | Value | Description |
|----------|-------|-------------|
| `MODEL_NAME` | `moonshotai/Kimi-K2.5` | The Kimi-K2.5 model |
| `HF_TOKEN` | `hf_xxxxx` | Your Hugging Face token |
| `TENSOR_PARALLEL_SIZE` | `8` | Distribute across 8 GPUs |
| `QUANTIZATION` | `fp8` | FP8 quantization for memory efficiency |
| `MAX_MODEL_LEN` | `131072` | Full 128K context window |
| `ENABLE_AUTO_TOOL_CHOICE` | `true` | Enable tool/function calling |
| `TOOL_CALL_PARSER` | `kimi_k2` | Kimi-specific tool parser |
| `ENABLE_EXPERT_PARALLEL` | `true` | Enable MoE expert parallelism |
| `GPU_MEMORY_UTILIZATION` | `0.95` | Maximize GPU memory usage |
| `TRUST_REMOTE_CODE` | `true` | Required for Kimi model |

### Step 3: Configure GPU Settings

- **GPU Type**: H100 80GB (recommended) or A100 80GB
- **GPU Count**: 8
- **Active Workers**: Start with 1, scale as needed
- **Max Workers**: Based on your budget

### Step 4: Attach Network Storage (Optional but Recommended)

For Option 1 builds, attach a network volume to cache the model:
- Mount path: `/runpod-volume`
- Size: At least 500GB for model weights

## API Usage

### Endpoint URL Format

```
https://api.runpod.ai/v2/{YOUR_ENDPOINT_ID}/openai/v1
```

### Python Example

```python
from openai import OpenAI
import os

client = OpenAI(
    api_key=os.environ.get("RUNPOD_API_KEY"),
    base_url="https://api.runpod.ai/v2/{YOUR_ENDPOINT_ID}/openai/v1",
)

# Basic chat completion
response = client.chat.completions.create(
    model="moonshotai/Kimi-K2.5",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Explain quantum computing in simple terms."}
    ],
    temperature=0.7,
    max_tokens=2048,
)
print(response.choices[0].message.content)
```

### Tool Calling Example

```python
tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get the current weather in a given location",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "The city and state, e.g. San Francisco, CA"
                    }
                },
                "required": ["location"]
            }
        }
    }
]

response = client.chat.completions.create(
    model="moonshotai/Kimi-K2.5",
    messages=[{"role": "user", "content": "What's the weather in Tokyo?"}],
    tools=tools,
    tool_choice="auto",
)
print(response.choices[0].message.tool_calls)
```

### Streaming Example

```python
stream = client.chat.completions.create(
    model="moonshotai/Kimi-K2.5",
    messages=[{"role": "user", "content": "Write a short story about AI."}],
    stream=True,
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

## OpenCode Integration

To use this endpoint with OpenCode or other OpenAI-compatible tools:

### Environment Setup

```bash
export OPENAI_API_KEY="your_runpod_api_key"
export OPENAI_BASE_URL="https://api.runpod.ai/v2/{YOUR_ENDPOINT_ID}/openai/v1"
export OPENAI_MODEL="moonshotai/Kimi-K2.5"
```

### OpenCode Configuration

Add to your OpenCode config:

```json
{
  "provider": "openai",
  "model": "moonshotai/Kimi-K2.5",
  "apiKey": "your_runpod_api_key",
  "baseUrl": "https://api.runpod.ai/v2/{YOUR_ENDPOINT_ID}/openai/v1"
}
```

## Troubleshooting

### Out of Memory Errors

- Reduce `MAX_MODEL_LEN` to `65536` or lower
- Ensure `QUANTIZATION=fp8` is set
- Verify you have 8 GPUs with `TENSOR_PARALLEL_SIZE=8`

### Slow Cold Starts

- Use Option 2 (baked model) for faster cold starts
- Ensure `HF_HUB_ENABLE_HF_TRANSFER=1` is set (default in this image)
- Attach network storage to cache the model

### Tool Calling Not Working

- Verify `ENABLE_AUTO_TOOL_CHOICE=true`
- Verify `TOOL_CALL_PARSER=kimi_k2`
- Check that your tool definitions follow OpenAI format

### Model Not Loading

- Ensure `TRUST_REMOTE_CODE=true` is set
- Verify your `HF_TOKEN` has access to the model
- Check RunPod logs for detailed error messages

## Performance Tips

1. **Enable Expert Parallelism**: Set `ENABLE_EXPERT_PARALLEL=true` for MoE models
2. **Use FP8 Quantization**: Reduces memory by ~50% with minimal quality loss
3. **Prefix Caching**: Set `ENABLE_PREFIX_CACHING=true` for repeated prompts
4. **Batch Processing**: Use the batch API for high-throughput scenarios

## Cost Estimation

With 8x H100 GPUs on RunPod Serverless:
- Cold start: ~2-5 minutes (first request after scale-down)
- Warm inference: 50-100 tokens/second depending on context length
- Cost: ~$0.0025/second while active (varies by region)
