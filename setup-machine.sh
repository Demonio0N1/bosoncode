#!/usr/bin/env bash
# setup-machine — configura esta máquina iVsCode como un entorno de desarrollo
# completo: git, compiladores, Python con kernel de Jupyter y libs científicas.
#
# Uso (dentro de la máquina):
#   setup-machine          # base: git, build tools, python3 + ipykernel + numpy/pandas/matplotlib
#   setup-machine --ml     # además PyTorch con CUDA (usa la GPU del host; ~3 GB)

set -euo pipefail
ML=0
[ "${1:-}" = "--ml" ] && ML=1

echo "══ setup-machine: configurando $(hostname) ══"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    git curl wget nano htop unzip zip ca-certificates openssh-client \
    build-essential python3 python3-pip python3-venv
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y git curl wget nano htop unzip zip openssh-clients \
    gcc gcc-c++ make python3 python3-pip
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --noconfirm git curl wget nano htop unzip zip openssh \
    base-devel python python-pip
else
  echo "✗ Gestor de paquetes no soportado"; exit 1
fi

echo "── Python: kernel de Jupyter + libs científicas ──"
python3 -m pip install --break-system-packages --upgrade \
  ipykernel ipywidgets numpy pandas matplotlib 2>/dev/null \
  || python3 -m pip install --upgrade ipykernel ipywidgets numpy pandas matplotlib
python3 -m ipykernel install --name python3 --display-name "Python 3 ($(hostname))"

if [ "$ML" = 1 ]; then
  echo "── PyTorch (CUDA) ──"
  python3 -m pip install --break-system-packages torch torchvision 2>/dev/null \
    || python3 -m pip install torch torchvision
  python3 -c "import torch; print('PyTorch:', torch.__version__, '| CUDA disponible:', torch.cuda.is_available())"
fi

echo ""
echo "✔ Máquina configurada. En VS Code: recarga la ventana (o cierra y abre"
echo "  el notebook) y elige el kernel \"Python 3 ($(hostname))\"."
