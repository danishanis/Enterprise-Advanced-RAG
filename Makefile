.PHONY: help install install-mac-intel sync sync-mac-intel seed seed-data api streamlit eval eval-baseline eval-hybrid eval-rerank eval-hyde eval-crag eval-all eval-diff test lint format

# --no-sync: `uv run` auto-syncs the project before running, which fails on
# Intel Mac because uv alone can't resolve a valid torch (see sync-mac-intel
# below). Skipping the auto-sync is safe everywhere — it just means "use
# .venv as it already is," which is what `make sync`/`make sync-mac-intel`
# are for.
UV_RUN := uv run --no-sync


help:
	@echo "ADV RAG — Available commands"
	@echo ""
	@echo "  make install          — create enterprise-adv-rag & install all deps (one-time, Linux/Apple Silicon)"
	@echo "  make install-mac-intel — create .venv + conda-forge torch env (one-time, Intel Mac)"
	@echo "  make sync             — sync deps with pyproject.toml"
	@echo "  make sync-mac-intel   — sync deps into .venv, linking in conda's torch/torchvision"
	@echo "  make seed             — seed DB + ingest docs into Qdrant"
	@echo "  make seed-data        — download + generate the 95/5 noise corpus (~130-200 MB)"
	@echo "  make api              — start FastAPI backend (:8000)"
	@echo "  make streamlit        — start Streamlit UI (:8501)"
	@echo "  make eval             — run baseline + all + diff"
	@echo "  make test             — run pytest"
	@echo "  make lint             — run ruff check"
	@echo "  make format           — run ruff format"


install:
	uv python pin 3.12
	uv sync --extra dev

sync:
	uv sync --extra dev

# Intel Mac: PyPI's torch dropped macOS x86_64 wheels after v2.2.2, and llm-guard
# requires torch>=2.4.0, so uv alone can't resolve a compatible version.
#
# Fix: a conda-forge env hosts torch/torchvision only (conda-forge still builds
# osx-64 wheels), and uv manages everything else in its own .venv, excluded from
# torch/torchvision. A .pth file in .venv points Python at the conda env's
# site-packages so it can still `import torch`.
#
# NOTE: do not point `uv sync --python` directly at the conda env, and don't
# alias VIRTUAL_ENV to CONDA_PREFIX to make `uv sync --active` target it either
# — both were tried and both corrupted the conda torch install. `uv sync`
# reconciles the *entire* site-packages tree (not just the packages it's
# installing), and conda's symlink-based package layout doesn't survive that.
# Keeping the two environments physically separate, linked only via .pth, is
# what actually works.
install-mac-intel:
	@command -v conda >/dev/null 2>&1 || { echo "conda not found — install miniconda/miniforge first"; exit 1; }
	conda create -y -n enterprise-adv-rag-torch -c conda-forge python=3.12 pytorch torchvision
	uv python pin 3.12
	uv venv --python 3.12
	@echo ""
	@echo "Now run: make sync-mac-intel"

sync-mac-intel:
	uv sync --extra dev --no-install-package torch --no-install-package torchvision
	@CONDA_BASE="$$(conda info --base 2>/dev/null)"; \
	test -n "$$CONDA_BASE" || { echo "conda not found on PATH"; exit 1; }; \
	CONDA_SITE="$$CONDA_BASE/envs/enterprise-adv-rag-torch/lib/python3.12/site-packages"; \
	test -d "$$CONDA_SITE" || { echo "conda env 'enterprise-adv-rag-torch' not found — run make install-mac-intel first"; exit 1; }; \
	echo "$$CONDA_SITE" > .venv/lib/python3.12/site-packages/conda_torch.pth; \
	echo "Linked conda-forge torch/torchvision into .venv"

seed:
	$(UV_RUN) python scripts/seed_db.py

seed-docs:
	$(UV_RUN) python -c "from scripts.seed_db import seed_docs; seed_docs()"

seed-data:
	bash scripts/data_pipeline/run_all.sh

api:
	$(UV_RUN) uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

streamlit:
	$(UV_RUN) streamlit run scripts/streamlit_app.py


eval-baseline:
	$(UV_RUN) python -m eval.run_ragas --profile naive

eval-hybrid:
	$(UV_RUN) python -m eval.run_ragas --profile hybrid

eval-rerank:
	$(UV_RUN) python -m eval.run_ragas --profile hybrid+rerank

eval-hyde:
	$(UV_RUN) python -m eval.run_ragas --profile hybrid+rerank+hyde --filter hyde

eval-crag:
	$(UV_RUN) python -m eval.run_ragas --profile hybrid+rerank+crag --filter crag

eval-all:
	$(UV_RUN) python -m eval.run_ragas --profile all

eval: eval-baseline eval-all
	$(MAKE) eval-diff

eval-diff:
	@latest_naive=$$(ls -t eval/results/*_naive.json 2>/dev/null | head -1); \
	latest_all=$$(ls -t eval/results/*_all.json 2>/dev/null | head -1); \
	test -n "$$latest_naive" && test -n "$$latest_all" && \
	  $(UV_RUN) python -m eval.diff $$latest_naive $$latest_all || \
	  echo "Need at least one _naive.json and one _all.json in eval/results/"

validate:
	$(UV_RUN) python scripts/validate_goldens.py


test:
	$(UV_RUN) pytest tests/ -v

lint:
	$(UV_RUN) ruff check .

format:
	$(UV_RUN) ruff format .


eval-legacy:
	@echo "Use: make eval-baseline"