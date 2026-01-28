# Use CUDA 12.9 runtime image (includes CUDA runtime libraries needed by PyTorch)
FROM nvidia/cuda:12.9.0-runtime-ubuntu22.04

RUN apt-get update -y \
    && apt-get install -y python3-pip python3-venv curl

# Install uv (faster package manager, recommended by vLLM)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Install vLLM from prebuilt wheel at commit with Kimi-K2.5 support (PR #33131)
# Wheel: vllm-0.14.0rc2.dev375+gb539f988e-cp38-abi3-manylinux_2_31_x86_64.whl
ENV VLLM_COMMIT=b539f988e1eeffe1c39bebbeaba892dc529eefaf
RUN uv pip install --system vllm \
    --prerelease=allow \
    --index-strategy unsafe-best-match \
    --extra-index-url https://wheels.vllm.ai/${VLLM_COMMIT} \
    --extra-index-url https://download.pytorch.org/whl/cu129

# Install additional dependencies (after vLLM to avoid torch conflicts)
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
