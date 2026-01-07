FROM apache/superset:latest

USER root


RUN pip install psycopg2-binary --target=$(/app/.venv/bin/python -c "import site; print(site.getsitepackages()[0])")

USER superset
