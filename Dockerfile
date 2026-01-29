# CUDA 12.9 for B200 GPUs
FROM nvidia/cuda:12.9.0-runtime-ubuntu22.04

RUN apt-get update -y \
    && apt-get install -y python3-pip python3-venv git

# CRITICAL: Make CUDA libraries discoverable
RUN ldconfig /usr/local/cuda-12.9/compat/

# Install PyTorch FIRST with CUDA 12.8 (forward compatible with 12.9)
RUN pip install torch==2.6.0 --index-url https://download.pytorch.org/whl/cu128

# Install vLLM from cu129 wheel (Kimi-K2.5 support commit)
ENV VLLM_COMMIT=b539f988e1eeffe1c39bebbeaba892dc529eefaf
RUN pip install vllm --extra-index-url https://wheels.vllm.ai/${VLLM_COMMIT}/cu129/

# Install additional dependencies (torch already installed above)
COPY builder/requirements.txt /requirements.txt
RUN pip install --upgrade -r /requirements.txt

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
