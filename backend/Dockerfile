FROM codercom/code-server:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip \
    openssh-client git curl rsync build-essential \
    && rm -rf /var/lib/apt/lists/*

USER coder
WORKDIR /home/coder

# Python + PyTorch con CUDA (las wheels cu124 incluyen el runtime de CUDA,
# el host solo necesita el driver NVIDIA + Container Toolkit)
RUN python3 -m venv /home/coder/.venvs/ml && \
    /home/coder/.venvs/ml/bin/pip install --no-cache-dir --upgrade pip && \
    /home/coder/.venvs/ml/bin/pip install --no-cache-dir \
        torch torchvision --index-url https://download.pytorch.org/whl/cu124 && \
    /home/coder/.venvs/ml/bin/pip install --no-cache-dir \
        jupyterlab ipykernel ipywidgets numpy pandas scipy matplotlib polars pyarrow && \
    /home/coder/.venvs/ml/bin/python -m ipykernel install --user \
        --name ml --display-name "Python (ML)"

# Julia vía juliaup + kernel IJulia + CUDA.jl
RUN curl -fsSL https://install.julialang.org | sh -s -- --yes && \
    /home/coder/.juliaup/bin/julia -e \
        'using Pkg; Pkg.add(["IJulia","CUDA","DataFrames","Plots"]); using IJulia'

# El venv y julia en el PATH de la terminal integrada
RUN echo 'export PATH="$HOME/.venvs/ml/bin:$HOME/.juliaup/bin:$PATH"' >> /home/coder/.bashrc

# Extensiones (Open VSX): Jupyter, Python, Julia, basedpyright (equivalente
# libre de Pylance) y Open Remote SSH (equivalente de Remote-SSH)
RUN code-server \
    --install-extension ms-toolsai.jupyter \
    --install-extension ms-python.python \
    --install-extension julialang.language-julia \
    --install-extension detachhead.basedpyright \
    --install-extension jeanp413.open-remote-ssh
