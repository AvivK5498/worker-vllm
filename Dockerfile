# CUDA 12.9 for B200 GPUs (matching vLLM's approach)
FROM nvidia/cuda:12.9.0-base-ubuntu22.04

ARG CUDA_VERSION=12.9

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
        python3-pip \
        python3-venv \
        git \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv (vLLM's recommended package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# uv environment settings (from vLLM Dockerfile)
ENV UV_HTTP_TIMEOUT=500
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_LINK_MODE=copy

# CUDA compatibility (vLLM's approach - write to ld.so.conf.d)
RUN echo "/usr/local/cuda-12.9/compat/" > /etc/ld.so.conf.d/00-cuda-compat.conf && ldconfig

# LD_LIBRARY_PATH setup (from vLLM Dockerfile)
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib64:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Install PyTorch 2.9.1 first (exact version required by vLLM commit)
RUN uv pip install --system torch==2.9.1 \
    --index-url https://download.pytorch.org/whl/cu129

# Install vLLM from cu129 wheel with Kimi-K2.5 support
ENV VLLM_COMMIT=b539f988e1eeffe1c39bebbeaba892dc529eefaf
RUN uv pip install --system vllm \
    --extra-index-url https://wheels.vllm.ai/${VLLM_COMMIT}/cu129/

# Install additional dependencies
COPY builder/requirements.txt /requirements.txt
RUN uv pip install --system --upgrade -r /requirements.txt

# Setup for Option 2: Building the Image with the Model included
ARG MODEL_NAME=""
ARG TOKENIZER_NAME=""
ARG BASE_PATH="/runpod-volume"
ARG QUANTIZATION=""
ARG MODEL_REVISION=""
ARG TOKENIZER_REVISION=""

ENV MODEL_NAME=$MODEL_NAME \
    MODEL_REVISION=$MODEL_REVISION \
    TOKENIZER_NAME=$TOKENIZER_NAME \
    TOKENIZER_REVISION=$TOKENIZER_REVISION \
    BASE_PATH=$BASE_PATH \
    QUANTIZATION=$QUANTIZATION \
    HF_DATASETS_CACHE="${BASE_PATH}/huggingface-cache/datasets" \
    HUGGINGFACE_HUB_CACHE="${BASE_PATH}/huggingface-cache/hub" \
    HF_HOME="${BASE_PATH}/huggingface-cache/hub" \
    HF_HUB_ENABLE_HF_TRANSFER=1

ENV PYTHONPATH="/:/vllm-workspace"

COPY src /src
RUN --mount=type=secret,id=HF_TOKEN,required=false \
    if [ -f /run/secrets/HF_TOKEN ]; then \
    export HF_TOKEN=$(cat /run/secrets/HF_TOKEN); \
    fi && \
    if [ -n "$MODEL_NAME" ]; then \
    python3 /src/download_model.py; \
    fi

# Start the handler
CMD ["python3", "/src/handler.py"]
